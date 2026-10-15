// ingest: where agents push. An agent sends its key and a feed's payload;
// the function finds the agent, checks the payload, writes it through the
// ingest_* SQL functions and logs what happened. See docs/AGENTS.md.
//
//   POST /ingest/briefs      { briefs: [{ title, body, kind?, id?, published_at? }] }
//   POST /ingest/quotes      { as_of?, quotes: [{ symbol, price, change?, change_pct?, name?, note? }] }
//   POST /ingest/news        the Daily Pulse items JSON: { date, slug, hero, sections: [...] }
//   POST /ingest/projects    { projects: [{ key, name, kind?, status?, progress?, summary?, next_step?, updates? }] }
//   POST /ingest/metrics     { as_of?, metrics: [{ key, value, label?, unit?, delta?, delta_pct?, note?, group? }] }
//   POST /ingest/dashboards  { dashboards: [{ key, title, subtitle?, widgets: [{ type, ... }] }] }
//   POST /ingest/events      { calendar?, replace?, events: [{ id?, title, starts_at, ends_at?, all_day?, location? }] }
//   POST /ingest             any of the above with "type": "briefs" | "quotes" | ... | "events"
//   GET  /ingest             who the key belongs to and its last few pushes
//
//   Authorization: Bearer mcf_…   (or X-Agent-Key: mcf_…)
//
// Answers { ok: true, feed, count, ... } or { error } with 400 (bad payload),
// 401 (no or unknown key), 404 (unknown feed), 405, 413 (body too big) or 503
// (the database is unreachable).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { json, preflight, readJson } from "../_shared/http.ts";
import { resolveImages } from "./images.ts";
import { agentKey, feedFromBody, feedFromPath, FEEDS, KEY_SHAPE, parse, type Parsed } from "./parse.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MAX_BODY = 1024 * 1024; // a Pulse report with long takeaways is far under this

const service = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type Agent = { id: string; name: string; slug: string; kind: string };

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

const cors = { "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
const reply = (body: unknown, status = 200) => {
  const res = json(body, status);
  for (const [k, v] of Object.entries(cors)) res.headers.set(k, v);
  return res;
};

async function findAgent(key: string): Promise<Agent | null | "down"> {
  const { data, error } = await service.rpc("agent_for_key", { hash: await sha256Hex(key) });
  if (error) {
    console.error("agent_for_key failed:", error.message);
    return "down";
  }
  const rows = (Array.isArray(data) ? data : data ? [data] : []) as Agent[];
  return rows[0] ?? null;
}

async function record(agent: Agent, feed: string, count: number, status: "ok" | "error", message?: string) {
  const { error } = await service.rpc("record_ingest", { agent: agent.id, feed, count, status, message: message ?? null });
  if (error) console.error("record_ingest failed:", error.message);
}

async function whoami(agent: Agent): Promise<Response> {
  const { data } = await service.from("ingest_log")
    .select("feed, count, status, message, created_at")
    .eq("agent_id", agent.id)
    .order("id", { ascending: false })
    .limit(10);
  return reply({ ok: true, agent, recent: data ?? [], feeds: FEEDS });
}

async function store(agent: Agent, parsed: Parsed): Promise<{ count: number; extra: Record<string, unknown> } | { error: string }> {
  switch (parsed.feed) {
    case "briefs": {
      const { data, error } = await service.rpc("ingest_briefs", { agent: agent.id, items: parsed.briefs });
      return error ? { error: error.message } : { count: Number(data ?? parsed.briefs.length), extra: {} };
    }
    case "quotes": {
      const { data, error } = await service.rpc("ingest_quotes", {
        agent: agent.id,
        items: parsed.quotes,
        as_of_default: parsed.as_of ?? new Date().toISOString(),
      });
      return error ? { error: error.message } : { count: Number(data ?? parsed.quotes.length), extra: { symbols: parsed.quotes.map((q) => q.symbol) } };
    }
    case "news": {
      const items = parsed.report.sections.flatMap((s) => s.items);
      let images = items.filter((i) => i.image).length;
      if (parsed.resolveImages) images += await resolveImages(items, fetch);
      const { data, error } = await service.rpc("ingest_news", { agent: agent.id, report: parsed.report });
      if (error) return { error: error.message };
      return { count: items.length, extra: { report_id: data, slug: parsed.report.slug, images, items: items.length } };
    }
    case "projects": {
      const { data, error } = await service.rpc("ingest_projects", { agent: agent.id, items: parsed.projects });
      return error ? { error: error.message } : { count: Number(data ?? parsed.projects.length), extra: { keys: parsed.projects.map((p) => p.key) } };
    }
    case "metrics": {
      const { data, error } = await service.rpc("ingest_metrics", {
        agent: agent.id,
        items: parsed.metrics,
        as_of_default: parsed.as_of ?? new Date().toISOString(),
      });
      return error ? { error: error.message } : { count: Number(data ?? parsed.metrics.length), extra: { keys: parsed.metrics.map((m) => m.key) } };
    }
    case "dashboards": {
      const { data, error } = await service.rpc("ingest_dashboards", { agent: agent.id, items: parsed.dashboards });
      return error ? { error: error.message } : { count: Number(data ?? parsed.dashboards.length), extra: { keys: parsed.dashboards.map((d) => d.key) } };
    }
    case "events": {
      // With `replace`, the push is the whole calendar: its other events from
      // this agent are removed.
      const { data, error } = await service.rpc("ingest_events", {
        agent: agent.id,
        items: parsed.events,
        replace_calendar: parsed.replace ? parsed.calendar : null,
      });
      if (error) return { error: error.message };
      return {
        count: Number(data ?? parsed.events.length),
        extra: { ...(parsed.calendar ? { calendar: parsed.calendar } : {}), replaced: parsed.replace },
      };
    }
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    const res = preflight();
    for (const [k, v] of Object.entries(cors)) res.headers.set(k, v);
    return res;
  }
  if (req.method !== "GET" && req.method !== "POST") return reply({ error: "GET or POST only" }, 405);

  const key = agentKey(req.headers);
  if (!key) return reply({ error: "send your agent key as Authorization: Bearer mcf_… (docs/AGENTS.md)" }, 401);
  if (!KEY_SHAPE.test(key)) return reply({ error: "that is not a McFly agent key (they start with mcf_)" }, 401);
  const agent = await findAgent(key);
  if (agent === "down") return reply({ error: "couldn't check the key; try again in a moment" }, 503);
  if (!agent) return reply({ error: "unknown or revoked agent key" }, 401);

  const path = feedFromPath(new URL(req.url).pathname);
  if (path === null) return reply({ error: `the feed must be ${FEEDS.slice(0, -1).join(", ")} or ${FEEDS.at(-1)}` }, 404);
  if (req.method === "GET") return whoami(agent);

  const read = await readJson(req, MAX_BODY);
  if ("error" in read) return read.error;
  const feed = path || feedFromBody(read.body);
  if (!feed) return reply({ error: 'say which feed: POST /ingest/briefs, /quotes, /news, /projects, /metrics, /dashboards or /events, or add "type"' }, 400);

  const parsed = parse(feed, read.body);
  if ("error" in parsed) {
    await record(agent, feed, 0, "error", parsed.error);
    return reply({ error: parsed.error }, 400);
  }
  try {
    const result = await store(agent, parsed);
    if ("error" in result) {
      await record(agent, feed, 0, "error", result.error);
      // P0001 (raise exception) messages are the SQL checks' own sentences.
      return reply({ error: result.error }, 400);
    }
    await record(agent, feed, result.count, "ok");
    // Retention, a little at a time: every push is a fine moment.
    service.rpc("prune_feed").then(({ error }) => error && console.error("prune_feed failed:", error.message));
    return reply({ ok: true, feed, count: result.count, agent: agent.slug, ...result.extra });
  } catch (err) {
    console.error(`ingest ${feed} from ${agent.slug} failed:`, err);
    await record(agent, feed, 0, "error", "something went wrong");
    return reply({ error: "something went wrong" }, 500);
  }
});
