// assistant: answers questions about what's on the display, spoken (the Pi's
// quick-answer card, the phone) or typed.
//
//   POST { message, mode?: "chat" | "quick", stream?: boolean,
//          history?: [{ role, text }], provider?: "claude" | "grok" }
//     stream false -> { reply, model }
//     stream true  -> text/event-stream: delta…, then done (or error)
//
// The caller is a paired display or an admin: anyone can_read() says may.
// The snapshot the answer is grounded in (settings, briefs, quotes, projects,
// metrics, dashboards, the week's calendar, the newest report) is read with
// the caller's own JWT, so row-level security decides what it sees; the
// service role only identifies the caller. Read-only: no tools, nothing
// stored.
//
// Who answers is platform_settings.assistant_provider, which the body may
// override: Claude through the SDK (ANTHROPIC_API_KEY, ASSISTANT_MODEL) or
// Grok through xAI's Chat Completions API (XAI_API_KEY, GROK_MODEL). Both
// get the same prompt and give the same response shape.
//
// Errors: 400 bad body, 401 no session, 403 not a reader, 503 the model (or
// its key) isn't available, as `{ error }` or an `error` event once the
// stream has begun.

import Anthropic from "npm:@anthropic-ai/sdk@^0.133.0";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { authenticate, bearerToken, corsHeaders, HttpError, json, preflight, readJson } from "../_shared/http.ts";
import {
  type AssistantRequest,
  chooseProvider,
  conversation,
  formatSnapshot,
  grokChunk,
  grokModelName,
  grokRequestBody,
  type GrokUsage,
  MAX_TOKENS,
  type Mode,
  modelName,
  oneLine,
  parseRequest,
  ReplyBuilder,
  SNAPSHOT,
  type SnapshotRows,
  splitSseData,
  sseEvent,
  systemPrompt,
} from "./helpers.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const XAI_URL = "https://api.x.ai/v1/chat/completions";

// A message plus ten history turns, each up to 4,000 characters, escaped.
const MAX_BODY_BYTES = 256 * 1024;

const REPLY = {
  notSetUp: (key: string) => `the assistant isn't set up (${key})`,
  refusal: "Sorry, I can't help with that one.",
  empty: "Sorry, I didn't come up with an answer. Try asking another way.",
  busy: "I'm a bit busy right now. Try again in a moment.",
  unavailable: "The assistant isn't available right now. Please try again in a bit.",
  failed: "Sorry, something went wrong. Please try again.",
};

const service = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// ───────────────────────────── Providers ─────────────────────────────

let client: Anthropic | null = null;

// The Claude client, or null when ANTHROPIC_API_KEY isn't set. The key is
// read once; a function's secrets don't change while it runs.
function claude(): Anthropic | null {
  if (client) return client;
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")?.trim();
  if (!apiKey) return null;
  client = new Anthropic({ apiKey });
  return client;
}

// A failed call to xAI: the HTTP status (0 when it couldn't be reached).
class GrokError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

// What a failed model call means to the caller: busy (rate limited or
// overloaded) or unavailable, or null for an error that isn't the API's. The
// log gets the status, never the request.
function modelOutcome(err: unknown): "busy" | "unavailable" | null {
  if (err instanceof Anthropic.APIError) {
    console.error(`Claude API error ${err.status ?? "?"}:`, err.message);
    return err instanceof Anthropic.RateLimitError || err.status === 529 ? "busy" : "unavailable";
  }
  if (err instanceof GrokError) {
    console.error(`Grok API error ${err.status || "?"}:`, err.message);
    return err.status === 429 || err.status === 503 ? "busy" : "unavailable";
  }
  return null;
}

// ───────────────────────────── Snapshot ─────────────────────────────

// The feeds as the caller may see them. A failed read is logged and shows up
// as null, which the snapshot words as "couldn't be read" rather than empty.
async function loadSnapshot(db: SupabaseClient): Promise<SnapshotRows> {
  const now = new Date().toISOString();
  const weekAhead = new Date(Date.now() + SNAPSHOT.eventDays * 86_400_000).toISOString();
  const [settings, briefs, symbols, quotes, projects, metricSettings, metrics, dashboards, events, reports, memories] = await Promise.all([
    db.from("platform_settings").select("display_name, timezone, assistant_provider").maybeSingle(),
    db.from("briefs").select("title, kind, published_at, body")
      .or(`expires_at.is.null,expires_at.gt.${now}`)
      .order("published_at", { ascending: false }).limit(SNAPSHOT.briefs),
    db.from("symbols").select("symbol, name").eq("hidden", false).order("sort_order").order("symbol"),
    db.from("quotes_latest").select("symbol, name, price, change_pct, currency, note, as_of"),
    // Open projects with the newest update of each.
    db.from("projects").select("name, status, progress, summary, next_step, project_updates(kind, text, happened_at)")
      .neq("status", "done").order("sort_order").order("updated_at", { ascending: false }).limit(SNAPSHOT.projects)
      .order("happened_at", { ascending: false, referencedTable: "project_updates" })
      .limit(1, { referencedTable: "project_updates" }),
    db.from("metric_settings").select("key, label, group_name").eq("hidden", false)
      .order("group_name", { nullsFirst: false }).order("sort_order").order("key").limit(SNAPSHOT.metrics),
    db.from("metrics_latest").select("key, label, value, unit, delta_pct, note, as_of"),
    db.from("dashboards").select("title, subtitle, widgets").eq("hidden", false)
      .order("sort_order").order("title").limit(SNAPSHOT.dashboards),
    // Under way now, or starting within the week.
    db.from("events").select("title, calendar, location, starts_at, ends_at, all_day")
      .gte("ends_at", now).lt("starts_at", weekAhead).order("starts_at").limit(SNAPSHOT.events),
    db.from("news_reports")
      .select("display_date, report_date, hero_item, news_items(section_name, section_order, position, item_key, headline, takeaway, source_domain)")
      .order("report_date", { ascending: false }).order("published_at", { ascending: false }).limit(1),
    // Shared notes only: an agent's own working notes stay with the agent.
    db.from("memories").select("text, pinned").is("agent_id", null)
      .order("pinned", { ascending: false }).order("updated_at", { ascending: false }).limit(SNAPSHOT.memories),
  ]);
  const failed = (what: string, r: { error: { message: string } | null }) => {
    if (r.error) console.error(`snapshot ${what} failed:`, r.error.message);
    return r.error !== null;
  };
  return {
    settings: failed("settings", settings) ? null : settings.data,
    briefs: failed("briefs", briefs) ? null : briefs.data ?? [],
    symbols: failed("symbols", symbols) ? null : symbols.data ?? [],
    quotes: failed("quotes", quotes) ? null : quotes.data ?? [],
    projects: failed("projects", projects) ? null : projects.data ?? [],
    metricSettings: failed("metric settings", metricSettings) ? null : metricSettings.data ?? [],
    metrics: failed("metrics", metrics) ? null : metrics.data ?? [],
    dashboards: failed("dashboards", dashboards) ? null : dashboards.data ?? [],
    events: failed("events", events) ? null : events.data ?? [],
    reports: failed("report", reports) ? null : reports.data ?? [],
    memories: failed("notes", memories) ? null : memories.data ?? [],
  };
}

// ───────────────────────────── Conversation ─────────────────────────────

interface Turn {
  mode: Mode;
  snapshot: string;
  messages: Anthropic.Beta.BetaMessageParam[];
  signal?: AbortSignal;
  onText?: (text: string) => void;
}
interface Answer {
  reply: string;
  model: string;
}

// Asks Claude once, streaming text as it arrives. Returns the reply and the
// model that served it; API errors propagate to the caller.
async function converseClaude({ claude, model, mode, snapshot, messages, signal, onText }: Turn & { claude: Anthropic; model: string }): Promise<Answer> {
  const reply = new ReplyBuilder();
  const emit = (text: string) => {
    const out = reply.push(text);
    if (out) onText?.(out);
  };
  const stream = claude.beta.messages.stream({
    model,
    max_tokens: MAX_TOKENS[mode],
    // Conversational and latency-sensitive: low effort keeps answers quick.
    // Thinking stays at the model's default (adaptive).
    output_config: { effort: "low" },
    // If a safety classifier declines a benign question, the API re-runs it on
    // Anthropic's fallback model instead of failing the turn.
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: systemPrompt(snapshot, mode),
    messages,
  }, { signal });
  for await (const event of stream) {
    if (event.type === "content_block_start" && event.content_block.type === "text") emit(event.content_block.text);
    else if (event.type === "content_block_delta" && event.delta.type === "text_delta") emit(event.delta.text);
  }
  const message = await stream.finalMessage();
  const u = message.usage;
  console.log(`assistant ${mode}: ${message.model}, ${u.input_tokens} in (${u.cache_read_input_tokens ?? 0} cached), ${u.output_tokens} out`);

  // The whole fallback chain declined. Any partial text is discarded; the
  // `done` reply replaces what was streamed.
  if (message.stop_reason === "refusal") return { reply: REPLY.refusal, model: message.model };
  return { reply: reply.text || REPLY.empty, model: message.model };
}

// Asks Grok once through xAI's Chat Completions API, always streaming, and
// reads the `data:` lines as they come. Failures are GrokErrors.
async function converseGrok({ apiKey, model, mode, snapshot, messages, signal, onText }: Turn & { apiKey: string; model: string }): Promise<Answer> {
  const reply = new ReplyBuilder();
  const emit = (text: string) => {
    const out = reply.push(text);
    if (out) onText?.(out);
  };
  let res: Response;
  try {
    res = await fetch(XAI_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json", Accept: "text/event-stream" },
      body: JSON.stringify(grokRequestBody({ model, mode, snapshot, messages, stream: true })),
      signal,
    });
  } catch (err) {
    if (signal?.aborted) throw err;
    throw new GrokError(0, err instanceof Error ? err.name : "unreachable");
  }
  if (!res.ok || !res.body) {
    const detail = await res.text().catch(() => "");
    throw new GrokError(res.status, oneLine(detail, 200) || res.statusText || "no body");
  }

  let served = model;
  let usage: GrokUsage | undefined;
  // One chunk's payloads; true once [DONE] has been seen.
  const take = (payloads: string[]): boolean => {
    for (const payload of payloads) {
      if (payload === "[DONE]") return true;
      const chunk = grokChunk(payload);
      if (!chunk) continue;
      if (chunk.model) served = chunk.model;
      if (chunk.usage) usage = chunk.usage;
      emit(chunk.text);
    }
    return false;
  };
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const { data, rest } = splitSseData(buffer);
      buffer = rest;
      if (take(data)) break;
    }
    // A last line without its newline.
    if (buffer.trim()) take(splitSseData(buffer + "\n").data);
  } finally {
    await reader.cancel().catch(() => {});
  }
  console.log(`assistant ${mode}: ${served}, ${usage?.prompt_tokens ?? "?"} in, ${usage?.completion_tokens ?? "?"} out`);
  return { reply: reply.text || REPLY.empty, model: served };
}

// ───────────────────────────── Streaming ─────────────────────────────

type Send = (event: string, data: unknown) => void;

// An SSE response fed by `run`. When the client goes away (the wake word
// interrupting a reply, say) the model call is cut short through `signal`.
function sseResponse(run: (send: Send, signal: AbortSignal) => Promise<void>): Response {
  const encoder = new TextEncoder();
  const aborter = new AbortController();
  let open = true;
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      const send: Send = (event, data) => {
        if (!open) return;
        try {
          controller.enqueue(encoder.encode(sseEvent(event, data)));
        } catch {
          open = false;
        }
      };
      run(send, aborter.signal)
        .catch((err) => {
          if (!aborter.signal.aborted) console.error("assistant stream failed:", err);
          send("error", { message: REPLY.failed });
        })
        .finally(() => {
          if (!open) return;
          open = false;
          controller.close();
        });
    },
    cancel() {
      open = false;
      aborter.abort();
    },
  });
  return new Response(body, {
    headers: { ...corsHeaders, "Content-Type": "text/event-stream", "Cache-Control": "no-cache", "X-Accel-Buffering": "no" },
  });
}

// ───────────────────────────── Handler ─────────────────────────────

async function answer(db: SupabaseClient, req: AssistantRequest): Promise<Response> {
  const rows = await loadSnapshot(db);
  const snapshot = formatSnapshot(rows);
  const turn: Turn = { mode: req.mode, snapshot: snapshot.text, messages: conversation(req.history, req.message) };

  // The provider is picked after the snapshot read: the setting rides in it.
  let ask: (signal?: AbortSignal, onText?: (text: string) => void) => Promise<Answer>;
  if (chooseProvider(rows.settings?.assistant_provider, req.provider) === "grok") {
    const apiKey = Deno.env.get("XAI_API_KEY")?.trim();
    if (!apiKey) throw new HttpError(503, REPLY.notSetUp("XAI_API_KEY"));
    const model = grokModelName(Deno.env);
    ask = (signal, onText) => converseGrok({ ...turn, apiKey, model, signal, onText });
  } else {
    const sdk = claude();
    if (!sdk) throw new HttpError(503, REPLY.notSetUp("ANTHROPIC_API_KEY"));
    const model = modelName(Deno.env);
    ask = (signal, onText) => converseClaude({ ...turn, claude: sdk, model, signal, onText });
  }

  if (!req.stream) {
    try {
      return json(await ask());
    } catch (err) {
      const outcome = modelOutcome(err);
      if (!outcome) throw err;
      return json({ error: outcome === "busy" ? REPLY.busy : REPLY.unavailable }, 503);
    }
  }

  return sseResponse(async (send, signal) => {
    try {
      send("done", await ask(signal, (text) => send("delta", { text })));
    } catch (err) {
      if (signal.aborted) return; // the client left; nobody is listening
      const outcome = modelOutcome(err);
      if (!outcome) throw err;
      send("error", { message: outcome === "busy" ? REPLY.busy : REPLY.unavailable });
    }
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const token = bearerToken(req);
  if (!token) return json({ error: "sign in required" }, 401);

  const read = await readJson(req, MAX_BODY_BYTES);
  if ("error" in read) return read.error;
  const parsed = parseRequest(read.body);
  if (!parsed.ok) return json({ error: parsed.error }, 400);

  const who = await authenticate(service, token);
  if ("error" in who) return who.error;

  // Everything else runs as the caller, under row-level security.
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
    return await answer(db, parsed.request);
  } catch (err) {
    if (err instanceof HttpError) return json({ error: err.message }, err.status);
    console.error("assistant failed:", err);
    return json({ error: "something went wrong" }, 500);
  }
});
