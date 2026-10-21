// McFly article: a news story read in full, for whoever can read the feeds.
//
//   POST /functions/v1/article   Authorization: Bearer <the caller's JWT>
//   body:  { item_id }
//   200    { article: { item_id, status, title, byline, site_name, published_at,
//                       lead_image, blocks[], word_count, summary, points[],
//                       summary_model, illustration_url, illustration_model,
//                       fetched_at, pending } }
//
// The first open of a story fetches its page (the item's own URL, never one
// the caller sends), reads the article out of it (extract.ts) and keeps it in
// news_articles; every later open, from any display or the app, gets that
// copy. A page that can't be read is a normal answer (status "unavailable").
// The summary (summary.ts) is the assistant's from the page's text, or, for
// a page that turned McFly away, Grok's from reading the story with its web
// search. Grok also draws a picture of the story (illustration.ts), kept in
// the private news-illustrations bucket and sent as a signed link. Those can
// take a while: the answer comes within ANSWER_BY_MS with what is ready and
// `pending: true`, the rest is stored when it lands, and clients ask again.
// A summary or picture that fails is tried again on a later open.
//
// Errors: 400 bad body, 401 no session, 403 not a reader, 404 no such story.

import Anthropic from "npm:@anthropic-ai/sdk@^0.133.0";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { authenticate, bearerToken, isUuid, json, preflight, readJson } from "../_shared/http.ts";
import { chooseProvider, grokModelName, modelName } from "../assistant/helpers.ts";
import { readResponse, XAI_RESPONSES_URL } from "../bots/run.ts";
import { type Article, extractArticle, videoArticle } from "./extract.ts";
import { BUCKET, IMAGES_URL, illustrationPath, illustrationPrompt, illustrationRequest, imageModelName, LINK_SECONDS, needsIllustration, readIllustration } from "./illustration.ts";
import { fetchPage } from "./page.ts";
import {
  isPending,
  needsPage,
  needsSummary,
  parseSummary,
  READ_SYSTEM,
  readRequest,
  type Summary,
  SUMMARY_SCHEMA,
  SUMMARY_SYSTEM,
  summaryRequest,
  summarySource,
} from "./summary.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const XAI_URL = "https://api.x.ai/v1/chat/completions";
const SUMMARY_TIMEOUT_MS = 45_000;
const IMAGE_TIMEOUT_MS = 45_000;
// Grok reading a story on the web searches first.
const READ_TIMEOUT_MS = 90_000;
// A model that answers without reasoning first: reading one story is quick work.
const DEFAULT_READ_MODEL = "grok-4.20-0309-non-reasoning";
// The answer goes by then with what is ready: the display gives up on a
// request after 15 s.
const ANSWER_BY_MS = 11_000;

const COLUMNS = "item_id, status, title, byline, site_name, published_at, lead_image, blocks, word_count, summary, points, summary_model, " +
  "summary_tried_at, illustration, illustration_model, illustration_tried_at, fetched_at";

type Row = Article & {
  item_id: string;
  summary: string | null;
  points: string[];
  summary_model: string | null;
  summary_tried_at: string | null;
  illustration: string | null;
  illustration_model: string | null;
  illustration_tried_at: string | null;
  fetched_at: string;
};

type Story = { id: string; url: string; headline: string; takeaway: string | null; section_name: string | null; source_domain: string | null };

const service = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

let client: Anthropic | null = null;
function claude(): Anthropic | null {
  if (client) return client;
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")?.trim();
  if (!apiKey) return null;
  client = new Anthropic({ apiKey, timeout: SUMMARY_TIMEOUT_MS, maxRetries: 1 });
  return client;
}

// ───────────────────────────── Summary ─────────────────────────────

async function summarizeWithClaude(sdk: Anthropic, model: string, request: string): Promise<{ summary: Summary; model: string } | null> {
  const message = await sdk.beta.messages.create({
    model,
    max_tokens: 4000,
    // A summary is short work: low effort keeps the first open quick.
    output_config: { effort: "low", format: { type: "json_schema", schema: SUMMARY_SCHEMA } },
    // A benign article a classifier declines is re-run on Anthropic's fallback model.
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: SUMMARY_SYSTEM,
    messages: [{ role: "user", content: request }],
  });
  if (message.stop_reason === "refusal" || message.stop_reason === "max_tokens") return null;
  const text = message.content.find((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")?.text;
  const summary = parseSummary(text);
  return summary ? { summary, model: message.model } : null;
}

async function summarizeWithGrok(apiKey: string, model: string, request: string): Promise<{ summary: Summary; model: string } | null> {
  const res = await fetch(XAI_URL, {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    signal: AbortSignal.timeout(SUMMARY_TIMEOUT_MS),
    body: JSON.stringify({
      model,
      max_tokens: 1200,
      messages: [{ role: "system", content: SUMMARY_SYSTEM }, { role: "user", content: request }],
      response_format: { type: "json_schema", json_schema: { name: "article_summary", strict: true, schema: SUMMARY_SCHEMA } },
    }),
  });
  if (!res.ok) {
    console.error(`Grok API error ${res.status}`);
    return null;
  }
  const data = await res.json();
  const summary = parseSummary(data?.choices?.[0]?.message?.content);
  return summary ? { summary, model: typeof data?.model === "string" ? data.model : model } : null;
}

// The summary from whichever assistant the console picked, or null when it
// isn't set up or didn't give one. The log gets the status, never the text.
async function summarize(provider: unknown, article: Article, headline: string, source: string) {
  const request = summaryRequest(article, headline, source);
  try {
    if (chooseProvider(provider, null) === "grok") {
      const apiKey = Deno.env.get("XAI_API_KEY")?.trim();
      return apiKey ? await summarizeWithGrok(apiKey, grokModelName(Deno.env), request) : null;
    }
    const sdk = claude();
    return sdk ? await summarizeWithClaude(sdk, modelName(Deno.env), request) : null;
  } catch (err) {
    if (err instanceof Anthropic.APIError) console.error(`Claude API error ${err.status ?? "?"}:`, err.message);
    else console.error("summary failed:", err instanceof Error ? err.message : err);
    return null;
  }
}

// Grok's summary of a story McFly couldn't read: it opens the link (or finds
// the story elsewhere) with its web search, as the Grok bots research.
async function readWithGrok(story: Story): Promise<{ summary: Summary; model: string } | null> {
  const apiKey = Deno.env.get("XAI_API_KEY")?.trim();
  if (!apiKey) return null;
  const model = Deno.env.get("GROK_READ_MODEL")?.trim() || DEFAULT_READ_MODEL;
  try {
    const res = await fetch(XAI_RESPONSES_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(READ_TIMEOUT_MS),
      body: JSON.stringify({
        model,
        input: [{ role: "system", content: READ_SYSTEM }, { role: "user", content: readRequest(story) }],
        tools: [{ type: "web_search" }],
        store: false,
      }),
    });
    if (!res.ok) {
      console.error(`Grok read error ${res.status}`);
      return null;
    }
    const out = readResponse(await res.json());
    const summary = parseSummary(out.text);
    if (!summary) console.error("Grok read: no summary in the answer");
    return summary ? { summary, model: out.model ?? model } : null;
  } catch (err) {
    console.error("Grok read failed:", err instanceof Error ? err.message : err);
    return null;
  }
}

// ──────────────────────────── Illustration ────────────────────────────

// Grok's picture of the story, kept in the bucket: its path and the model, or
// null when xAI isn't set up, refused or failed. The log gets the status only.
async function illustrate(story: Story): Promise<{ path: string; model: string } | null> {
  const apiKey = Deno.env.get("XAI_API_KEY")?.trim();
  if (!apiKey) return null;
  const model = imageModelName(Deno.env);
  try {
    const res = await fetch(IMAGES_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(IMAGE_TIMEOUT_MS),
      body: JSON.stringify(illustrationRequest(model, illustrationPrompt(story))),
    });
    if (!res.ok) {
      console.error(`Grok image error ${res.status}`);
      return null;
    }
    const image = readIllustration(await res.json());
    if (!image) {
      console.error("Grok image: no picture in the answer");
      return null;
    }
    const path = illustrationPath(story.id, image.type);
    const up = await service.storage.from(BUCKET).upload(path, image.bytes, { contentType: image.type, upsert: true });
    if (up.error) {
      console.error("illustration upload failed:", up.error.message);
      return null;
    }
    return { path, model };
  } catch (err) {
    console.error("illustration failed:", err instanceof Error ? err.message : err);
    return null;
  }
}

// Pictures whose story is gone go after a new one is drawn.
async function sweepIllustrations() {
  const orphans = await service.rpc("orphaned_illustrations", { lim: 100 });
  const paths = (orphans.data ?? []) as string[];
  if (orphans.error || !paths.length) return;
  const removed = await service.storage.from(BUCKET).remove(paths);
  if (removed.error) console.error("illustration sweep failed:", removed.error.message);
}

// The answer: the row with a signed link to its picture, and whether more is coming.
async function answer(row: Row, pending: boolean): Promise<Response> {
  let illustrationUrl: string | null = null;
  if (row.illustration) {
    const signed = await service.storage.from(BUCKET).createSignedUrl(row.illustration, LINK_SECONDS);
    illustrationUrl = signed.data?.signedUrl ?? null;
  }
  return json({ article: { ...row, illustration_url: illustrationUrl, pending } });
}

async function store(row: Row) {
  const stored = await service.rpc("store_news_article", { item: row.item_id, article: row });
  if (stored.error) console.error("store_news_article failed:", stored.error.message);
  return !stored.error;
}

// Work that goes on after the answer.
function later(work: Promise<unknown>) {
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
  runtime?.waitUntil?.(work);
}

// ───────────────────────────── Reading ─────────────────────────────

async function readArticle(url: string): Promise<Article> {
  const video = videoArticle(url);
  if (video) return video;
  const page = await fetchPage(url, fetch);
  if ("error" in page) {
    console.log(`article: ${new URL(url).hostname}: ${page.error}`);
    return { status: "unavailable", title: null, byline: null, site_name: null, published_at: null, lead_image: null, blocks: [], word_count: 0 };
  }
  return extractArticle(page.html, page.url);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const started = Date.now();

  const token = bearerToken(req);
  if (!token) return json({ error: "sign in required" }, 401);
  const read = await readJson(req);
  if ("error" in read) return read.error;
  const itemId = (read.body as Record<string, unknown> | null)?.item_id;
  if (!isUuid(itemId)) return json({ error: "send { item_id } with the story's id" }, 400);

  const who = await authenticate(service, token);
  if ("error" in who) return who.error;

  // The story is read as the caller, under row-level security.
  const db = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const access = await db.rpc("can_read");
  if (access.error) {
    console.error("can_read failed:", access.error.message);
    return json({ error: "couldn't check your access; try again in a moment" }, 503);
  }
  if (access.data !== true) return json({ error: "this account can't read the display" }, 403);

  try {
    const item = await db.from("news_items").select("id, url, headline, takeaway, section_name, source_domain").eq("id", itemId).maybeSingle();
    if (item.error) throw new Error(item.error.message);
    if (!item.data) return json({ error: "no such story" }, 404);
    const story = item.data as Story;

    const cached = await service.from("news_articles").select(COLUMNS).eq("item_id", itemId).maybeSingle();
    if (cached.error) throw new Error(cached.error.message);
    let row = cached.data as Row | null;
    const now = Date.now();
    const xai = Boolean(Deno.env.get("XAI_API_KEY")?.trim());
    const drawing = xai && needsIllustration(row, now);
    if (row && !needsPage(row, now) && !needsSummary(row, now) && !drawing) return await answer(row, isPending(row, xai, now));

    // The picture needs only the story, so Grok draws while the page is read.
    const picture = drawing ? illustrate(story) : Promise.resolve(null);
    if (!row || needsPage(row, now)) {
      const article = await readArticle(story.url);
      row = {
        ...article,
        item_id: itemId,
        summary: null,
        points: [],
        summary_model: null,
        summary_tried_at: null,
        illustration: row?.illustration ?? null,
        illustration_model: row?.illustration_model ?? null,
        illustration_tried_at: row?.illustration_tried_at ?? null,
        fetched_at: new Date().toISOString(),
      };
    }

    // What is under way is marked before the work, so another open waits for
    // it rather than starting it again.
    const source = needsSummary(row, now) ? summarySource(row) : null;
    const summarizing = source === "page" || (source === "web" && xai);
    const stamp = new Date().toISOString();
    row = { ...row, ...(summarizing ? { summary_tried_at: stamp } : {}), ...(drawing ? { illustration_tried_at: stamp } : {}) };
    const begun: Row = row;
    if (summarizing || drawing) await store(begun);

    const summary = !summarizing ? Promise.resolve(null)
      : source === "web" ? readWithGrok(story)
      : db.from("platform_settings").select("assistant_provider").maybeSingle()
        .then((settings) => summarize(settings.data?.assistant_provider, begun, story.headline, story.source_domain ?? ""));
    const work = Promise.all([summary, picture]).then(async ([said, drawn]) => {
      const done: Row = {
        ...begun,
        ...(said ? { summary: said.summary.summary, points: said.summary.points, summary_model: said.model } : {}),
        ...(drawn ? { illustration: drawn.path, illustration_model: drawn.model } : {}),
      };
      // The sweep runs only once the new picture's row is in.
      if (await store(done) && drawn) await sweepIllustrations();
      console.log(`article: ${done.status}, ${done.word_count} words, ${done.blocks.length} blocks, ` +
        `summary ${done.summary ? source ?? "kept" : "no"}, picture ${done.illustration ? "yes" : "no"}`);
      return done;
    });

    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<null>((resolve) => {
      timer = setTimeout(() => resolve(null), Math.max(0, ANSWER_BY_MS - (Date.now() - started)));
    });
    const finished = await Promise.race([work, deadline]);
    clearTimeout(timer);
    if (finished) return await answer(finished, false);
    later(work);
    return await answer(begun, true);
  } catch (err) {
    console.error("article failed:", err instanceof Error ? err.message : err);
    return json({ error: "something went wrong" }, 500);
  }
});
