// assistant: answers questions about what's on the display, spoken (the Pi's
// quick-answer card, the phone), typed, or read on the console's full-screen
// Ask (mode "read": longer, Markdown-shaped answers).
//
//   POST { message, mode?: "chat" | "quick" | "read", stream?: boolean,
//          history?: [{ role, text, interrupted? }], provider?: "claude" | "grok" }
//     stream false -> { reply, model, changed? }
//     stream true  -> text/event-stream: delta…, then done { reply, model, changed? } (or error)
//
// The caller is a paired display or an admin: anyone can_read() says may.
// The snapshot the answer is grounded in (settings, briefs, quotes, projects,
// metrics, dashboards, the week's calendar, open todos, the newest report) is
// read with the caller's own JWT, so row-level security decides what it sees.
//
// Tools (tools.ts): when the person asks, it adds an event, a todo or a
// reminder, or checks a todo off. Those writes go through the ingest SQL
// functions with the service role, as McFly's own agent, after can_read()
// has said the caller may read; the display itself still never writes.
// `done` (and the JSON reply) carries `changed: ["events" | "todos"]` when
// something was written, so a client can refresh at once.
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
  type Changed,
  CLAUDE_TOOLS,
  type EventItem,
  GROK_TOOLS,
  grokArguments,
  GrokToolCalls,
  MAX_ROUNDS,
  type Store,
  type TodoItem,
  TOOL_TOKENS,
  ToolRunner,
} from "./tools.ts";
import {
  type AssistantRequest,
  chooseProvider,
  conversation,
  EFFORT,
  formatSnapshot,
  grokChunk,
  grokModelName,
  type GrokMessage,
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
  const [settings, briefs, symbols, quotes, projects, metricSettings, metrics, dashboards, events, reports, memories, todos] = await Promise.all([
    db.from("platform_settings").select("display_name, timezone, assistant_provider").maybeSingle(),
    db.from("briefs").select("title, kind, published_at, body")
      .or(`expires_at.is.null,expires_at.gt.${now}`)
      .order("published_at", { ascending: false }).limit(SNAPSHOT.briefs),
    db.from("symbols").select("symbol, name").eq("hidden", false).order("sort_order").order("symbol"),
    db.from("quotes_latest").select("symbol, name, price, change_pct, currency, note, as_of"),
    // Open projects with the newest update of each.
    db.from("projects").select("name, status, progress, summary, next_step, stages, stage, project_updates(kind, text, happened_at)")
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
    // Open todos and reminders, soonest first, undated last. A reminder whose
    // time passed more than a day ago is over.
    db.from("todos").select("id, kind, title, due_at, all_day").is("done_at", null)
      .or(`kind.eq.todo,due_at.gte.${new Date(Date.now() - 86_400_000).toISOString()}`)
      .order("due_at", { ascending: true, nullsFirst: false }).order("created_at").limit(SNAPSHOT.todos),
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
    todos: failed("todos", todos) ? null : todos.data ?? [],
  };
}

// ───────────────────────────── Writes ─────────────────────────────

// What the tools write through: the ingest SQL functions, with the service
// role, as McFly's own agent. Each call is one row; failures throw.
const store: Store = {
  async agent() {
    const { data, error } = await service.rpc("mcfly_agent");
    if (error || typeof data !== "string") throw new Error(error?.message ?? "no agent");
    return data;
  },
  async addEvent(agent: string, event: EventItem) {
    // Never replace_calendar: that would remove McFly's other events.
    const { error } = await service.rpc("ingest_events", { agent, items: [event], replace_calendar: null });
    if (error) throw new Error(error.message);
  },
  async addTodo(agent: string, todo: TodoItem) {
    const { data, error } = await service.rpc("ingest_todos", { agent, items: [todo] });
    if (error) throw new Error(error.message);
    return Array.isArray(data) ? String(data[0] ?? "") : "";
  },
  async setDone(id: string) {
    const { error } = await service.rpc("set_todo_done", { todo: id, done: true });
    if (error) throw new Error(error.message);
  },
  async log(agent: string, feed: Changed, ok: boolean, message?: string) {
    const { error } = await service.rpc("record_ingest", { agent, feed, count: 1, status: ok ? "ok" : "error", message: message ?? null });
    if (error) console.error("record_ingest failed:", error.message);
  },
};

// ───────────────────────────── Conversation ─────────────────────────────

interface Turn {
  mode: Mode;
  snapshot: string;
  messages: Anthropic.Beta.BetaMessageParam[];
  tools: ToolRunner;
  signal?: AbortSignal;
  onText?: (text: string) => void;
}
interface Answer {
  reply: string;
  model: string;
  changed?: Changed[];
}

// The reply as streamed: text from every round, the rounds' texts kept apart
// so "Done." doesn't run into what came before it.
function replyStream(mode: Mode, onText?: (text: string) => void) {
  const reply = new ReplyBuilder();
  let newRound = false;
  return {
    reply,
    emit(text: string) {
      if (newRound && reply.text && text.trim()) {
        const gap = reply.push(mode === "quick" ? " " : "\n\n");
        if (gap) onText?.(gap);
      }
      if (text.trim()) newRound = false;
      const out = reply.push(text);
      if (out) onText?.(out);
    },
    nextRound() {
      newRound = true;
    },
  };
}

const changedOf = (tools: ToolRunner): Pick<Answer, "changed"> =>
  tools.changed.size ? { changed: [...tools.changed].sort() } : {};

// Asks Claude, streaming text as it arrives, and runs the tools it calls
// (at most MAX_ROUNDS model calls; the last can't call any). Returns the
// reply and the model that served it; API errors propagate to the caller.
async function converseClaude({ claude, model, mode, snapshot, messages, tools, signal, onText }: Turn & { claude: Anthropic; model: string }): Promise<Answer> {
  const out = replyStream(mode, onText);
  const transcript = [...messages];
  let served = model;
  const usage = { input: 0, cached: 0, output: 0 };
  for (let round = 1; round <= MAX_ROUNDS; round++) {
    const stream = claude.beta.messages.stream({
      model,
      max_tokens: MAX_TOKENS[mode] + TOOL_TOKENS,
      // Talking is latency-sensitive: low effort keeps answers quick. The
      // full-screen reader (read) spends a little more for a better answer.
      // Thinking stays at the model's default (adaptive).
      output_config: { effort: EFFORT[mode] },
      // If a safety classifier declines a benign question, the API re-runs it on
      // Anthropic's fallback model instead of failing the turn.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: systemPrompt(snapshot, mode),
      tools: CLAUDE_TOOLS,
      tool_choice: round === MAX_ROUNDS ? { type: "none" } : { type: "auto" },
      messages: transcript,
    }, { signal });
    for await (const event of stream) {
      if (event.type === "content_block_start" && event.content_block.type === "text") out.emit(event.content_block.text);
      else if (event.type === "content_block_delta" && event.delta.type === "text_delta") out.emit(event.delta.text);
    }
    const message = await stream.finalMessage();
    served = message.model;
    usage.input += message.usage.input_tokens;
    usage.cached += message.usage.cache_read_input_tokens ?? 0;
    usage.output += message.usage.output_tokens;

    // The whole fallback chain declined. Any partial text is discarded; the
    // `done` reply replaces what was streamed. A refused turn's tool calls
    // never run.
    if (message.stop_reason === "refusal") {
      console.log(`assistant ${mode}: ${served}, refused after ${tools.writes} writes`);
      return { reply: REPLY.refusal, model: served, ...changedOf(tools) };
    }
    const calls = message.content.filter((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === "tool_use");
    // A call cut off at max_tokens may parse as a shorter input: don't run it.
    if (message.stop_reason !== "tool_use" || !calls.length) break;

    // The assistant turn goes back exactly as it came, thinking included.
    transcript.push({ role: "assistant", content: message.content });
    const results: Anthropic.Beta.BetaToolResultBlockParam[] = [];
    for (const call of calls) {
      const r = await tools.run(call.name, call.input);
      results.push({ type: "tool_result", tool_use_id: call.id, content: r.content, ...(r.isError ? { is_error: true } : {}) });
    }
    transcript.push({ role: "user", content: results });
    out.nextRound();
  }
  console.log(`assistant ${mode}: ${served}, ${usage.input} in (${usage.cached} cached), ${usage.output} out, ${tools.writes} writes`);
  return { reply: out.reply.text || REPLY.empty, model: served, ...changedOf(tools) };
}

// Asks Grok through xAI's Chat Completions API, always streaming, reads the
// `data:` lines as they come, and runs the tools it calls, like Claude's.
// Failures are GrokErrors.
async function converseGrok({ apiKey, model, mode, snapshot, messages, tools, signal, onText }: Turn & { apiKey: string; model: string }): Promise<Answer> {
  const out = replyStream(mode, onText);
  const base = grokRequestBody({ model, mode, snapshot, messages, stream: true });
  const extra: GrokMessage[] = [];
  let served = model;
  let usage: GrokUsage | undefined;
  for (let round = 1; round <= MAX_ROUNDS; round++) {
    let res: Response;
    try {
      res = await fetch(XAI_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json", Accept: "text/event-stream" },
        body: JSON.stringify({
          ...base,
          max_tokens: base.max_tokens + TOOL_TOKENS,
          messages: [...base.messages, ...extra],
          tools: GROK_TOOLS,
          tool_choice: round === MAX_ROUNDS ? "none" : "auto",
        }),
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

    const calls = new GrokToolCalls();
    let said = "";
    let finish = "";
    // One chunk's payloads; true once [DONE] has been seen.
    const take = (payloads: string[]): boolean => {
      for (const payload of payloads) {
        if (payload === "[DONE]") return true;
        const chunk = grokChunk(payload);
        if (!chunk) continue;
        if (chunk.model) served = chunk.model;
        if (chunk.usage) usage = chunk.usage;
        if (chunk.toolCalls) calls.push(chunk.toolCalls);
        if (chunk.finish) finish = chunk.finish;
        said += chunk.text;
        out.emit(chunk.text);
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

    const called = calls.calls;
    // Cut off mid-call ("length"): the arguments can't be trusted.
    if (!called.length || finish === "length") break;
    extra.push({
      role: "assistant",
      content: said || null,
      tool_calls: called.map((c) => ({ id: c.id, type: "function" as const, function: { name: c.name, arguments: c.arguments } })),
    });
    for (const c of called) {
      const args = grokArguments(c.arguments);
      const r = args.ok ? await tools.run(c.name, args.input) : { content: `Not saved: ${args.error}.`, isError: true };
      extra.push({ role: "tool", tool_call_id: c.id, content: r.content });
    }
    out.nextRound();
  }
  console.log(`assistant ${mode}: ${served}, ${usage?.prompt_tokens ?? "?"} in, ${usage?.completion_tokens ?? "?"} out, ${tools.writes} writes`);
  return { reply: out.reply.text || REPLY.empty, model: served, ...changedOf(tools) };
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
  const open = (rows.todos ?? []).map((t) => ({ id: t.id, title: oneLine(t.title, 300) }));
  const turn: Turn = {
    mode: req.mode,
    snapshot: snapshot.text,
    messages: conversation(req.history, req.message),
    tools: new ToolRunner(store, snapshot.timezone, open),
  };

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
