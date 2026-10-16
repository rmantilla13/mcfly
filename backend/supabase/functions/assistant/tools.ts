// What the assistant can do besides answer: add an event, a todo or a
// reminder to the person's day, and check a todo off. The definitions (for
// Claude and for Grok), the checks on what the model sent, the conversion of
// local wall-clock times to instants in the display's time zone, and the
// runner that writes through a Store (the ingest SQL functions, under the
// service role, as McFly's own agent). No I/O of its own, so tools.test.ts
// covers it with a fake store.
//
// The model gives times as the person would say them, in the display's
// local time ("2026-10-16T15:00"); the server turns them into instants, so a
// date across a daylight-saving change lands right without the model doing
// arithmetic with offsets. Each result repeats what was stored, in local
// time, so the spoken confirmation is what was saved.

import type Anthropic from "npm:@anthropic-ai/sdk@^0.133.0";
import { fmtLocal, fmtLocalDay, fmtLocalTime, oneLine } from "./helpers.ts";

// At most this many writes per question, and model calls per question (tool
// rounds plus the answer). A runaway loop, or a brief pushed by an agent
// that talks the model into adding things, stops here.
export const MAX_WRITES = 5;
export const MAX_ROUNDS = 4;
// Room for thinking and a tool call on top of the mode's answer budget.
export const TOOL_TOKENS = 1024;
// The calendar McFly's own events are on.
export const MCFLY_CALENDAR = "McFly";

export type ToolName = "add_event" | "add_todo" | "add_reminder" | "complete_todo";
export type Changed = "events" | "todos";

const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

// ───────────────────────────── Definitions ─────────────────────────────

const LOCAL_TIME = "Local time in the display's time zone, as YYYY-MM-DDTHH:MM (24-hour), with no offset";
const LOCAL_DAY = "a day as YYYY-MM-DD";

interface Definition {
  name: ToolName;
  description: string;
  input_schema: {
    type: "object";
    properties: Record<string, { type: "string"; description: string }>;
    required: string[];
    additionalProperties: false;
  };
}

const DEFINITIONS: Definition[] = [
  {
    name: "add_event",
    description:
      "Put an event on the person's calendar (McFly's own calendar, shown on the display and in the apps): something happening at a time or on a day, like an appointment, a meeting or a trip. Only when they ask for it.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string", description: "What it is, short, as they'd write it: \"Dentist\", \"Dinner with Sam\"" },
        start: { type: "string", description: `When it starts. ${LOCAL_TIME}; or ${LOCAL_DAY} for an all-day event` },
        end: {
          type: "string",
          description: `When it ends, in the same form as start. Leave it out for an hour (a timed event) or one day (an all-day one). For an all-day event, the last day`,
        },
        location: { type: "string", description: "Where, if they said" },
        notes: { type: "string", description: "Anything else they said that belongs with it" },
      },
      required: ["title", "start"],
      additionalProperties: false,
    },
  },
  {
    name: "add_todo",
    description:
      "Add something to the person's todo list: a task to get done, maybe by a day or a time. Only when they ask for it.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string", description: "The task, short: \"Buy milk\", \"Renew passport\"" },
        due: { type: "string", description: `When it's due, if they said: ${LOCAL_DAY}, or ${LOCAL_TIME} for a time` },
        notes: { type: "string", description: "Anything else they said that belongs with it" },
      },
      required: ["title"],
      additionalProperties: false,
    },
  },
  {
    name: "add_reminder",
    description:
      "Set a reminder: the display tells the person about something at a time (\"remind me to call mom at 5\"). If they gave a day but no time, use 9:00 that morning. Only when they ask for it.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string", description: "What to remind them of, short: \"Call mom\", \"Take the bins out\"" },
        at: { type: "string", description: `When to remind them. ${LOCAL_TIME}; it must be in the future` },
        notes: { type: "string", description: "Anything else they said that belongs with it" },
      },
      required: ["title", "at"],
      additionalProperties: false,
    },
  },
  {
    name: "complete_todo",
    description:
      "Check an open todo or reminder off, when the person says it's done or asks to clear it. Use the id from the snapshot's todo list.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string", description: "The id of the todo or reminder, from the snapshot" },
      },
      required: ["id"],
      additionalProperties: false,
    },
  },
];

// Claude's tools. Their inputs are a few words, so the API buffers and
// checks each against its schema; parseInput checks again before anything
// runs.
export const CLAUDE_TOOLS: Anthropic.Beta.BetaTool[] = DEFINITIONS.map((d) => ({
  name: d.name,
  description: d.description,
  input_schema: d.input_schema,
}));

// The same tools in Chat Completions form, for Grok.
export const GROK_TOOLS = DEFINITIONS.map((d) => ({
  type: "function" as const,
  function: { name: d.name, description: d.description, parameters: d.input_schema },
}));

// ───────────────────────────── Local time ─────────────────────────────

export interface LocalTime {
  y: number;
  mo: number; // 1-12
  d: number;
  h: number;
  mi: number;
  hasTime: boolean;
}

const LOCAL = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::00)?)?$/;

// "2026-10-16T15:00" or "2026-10-16", checked as a real date and time, or
// null for anything else (an offset, "tomorrow", the 31st of November).
export function parseLocal(value: unknown): LocalTime | null {
  if (typeof value !== "string") return null;
  const m = LOCAL.exec(value.trim());
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const hasTime = m[4] !== undefined;
  const [h, mi] = hasTime ? [Number(m[4]), Number(m[5])] : [0, 0];
  if (mo < 1 || mo > 12 || d < 1 || h > 23 || mi > 59) return null;
  if (d > new Date(Date.UTC(y, mo, 0)).getUTCDate()) return null;
  return { y, mo, d, h, mi, hasTime };
}

const partsFormatters = new Map<string, Intl.DateTimeFormat>();

// The wall clock in `tz` at instant `ms`, as if it were UTC.
function wallClock(ms: number, tz: string): number {
  let f = partsFormatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit",
    });
    partsFormatters.set(tz, f);
  }
  const p: Record<string, number> = {};
  for (const part of f.formatToParts(new Date(ms))) if (part.type !== "literal") p[part.type] = Number(part.value);
  return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
}

// The instant a wall-clock time in `tz` names. A time that happens twice
// (the hour clocks go back) is its first; one that never happens (the hour
// they go forward) is read as after the jump.
export function zonedToUtc(t: Pick<LocalTime, "y" | "mo" | "d" | "h" | "mi">, tz: string): number {
  const wall = Date.UTC(t.y, t.mo - 1, t.d, t.h, t.mi);
  // The zone's offset at `wall` read as UTC, then at the first guess: one of
  // the two is right unless the time is skipped or repeated.
  const first = wall - (wallClock(wall, tz) - wall);
  const second = wall - (wallClock(first, tz) - first);
  const candidates = [...new Set([first, second])];
  const exact = candidates.filter((c) => wallClock(c, tz) === wall).sort((a, b) => a - b);
  return exact.length ? exact[0] : Math.max(...candidates);
}

// Local midnight at the start of the given day.
const dayStart = (t: LocalTime, tz: string) => zonedToUtc({ ...t, h: 0, mi: 0 }, tz);
// The last second of the given day, local.
function dayEnd(t: LocalTime, tz: string): number {
  const next = new Date(Date.UTC(t.y, t.mo - 1, t.d + 1));
  return zonedToUtc({ y: next.getUTCFullYear(), mo: next.getUTCMonth() + 1, d: next.getUTCDate(), h: 0, mi: 0 }, tz) - 1000;
}

const iso = (ms: number) => new Date(ms).toISOString();

// ───────────────────────────── Inputs ─────────────────────────────

export interface EventItem {
  id: string;
  calendar: string;
  title: string;
  starts_at: string;
  ends_at: string;
  all_day: boolean;
  location?: string;
  description?: string;
  data: Record<string, unknown>;
}
export interface TodoItem {
  id: string;
  kind: "todo" | "reminder";
  title: string;
  due_at?: string;
  all_day?: boolean;
  notes?: string;
  data: Record<string, unknown>;
}

export type Action =
  | { tool: "add_event"; event: EventItem }
  | { tool: "add_todo" | "add_reminder"; todo: TodoItem }
  | { tool: "complete_todo"; id: string };

export type ParsedInput = { ok: true; action: Action } | { ok: false; error: string };

// How far ahead (and back) a date may be: a slip of the year, not a plan.
const MAX_YEARS_AHEAD = 5;
const SAME_DAY_GRACE_MS = 60_000;

const text = (v: unknown, max: number): string | undefined => {
  if (typeof v !== "string") return undefined;
  const s = v.replace(/\s+/g, " ").trim();
  return s ? s.slice(0, max) : undefined;
};

// What the model asked for, checked and turned into rows for the ingest
// functions, or the sentence that tells it what to fix. `newId` makes the
// rows' ids (a fresh one per item, so the same title twice isn't one row).
export function parseInput(
  name: string,
  input: unknown,
  ctx: { tz: string; now: number; newId: () => string },
): ParsedInput {
  const bad = (error: string): ParsedInput => ({ ok: false, error });
  if (!isObject(input)) return bad("the input must be an object");
  const data = { via: "assistant" };
  const nowYear = new Date(ctx.now).getUTCFullYear();
  const inRange = (t: LocalTime) => t.y >= nowYear - 1 && t.y <= nowYear + MAX_YEARS_AHEAD;

  switch (name) {
    case "add_event": {
      const title = text(input.title, 300);
      if (!title) return bad("title is required");
      const start = parseLocal(input.start);
      if (!start) return bad(`start must be ${LOCAL_TIME.toLowerCase()}, or a day as YYYY-MM-DD`);
      if (!inRange(start)) return bad("start is too far from today; check the year");
      let end: LocalTime | null = null;
      if (input.end != null && input.end !== "") {
        end = parseLocal(input.end);
        if (!end) return bad("end must be in the same form as start");
        if (end.hasTime !== start.hasTime) return bad("start and end must both have a time, or both be days (all day)");
      }
      const allDay = !start.hasTime;
      const startsAt = allDay ? dayStart(start, ctx.tz) : zonedToUtc(start, ctx.tz);
      const endsAt = allDay ? dayEnd(end ?? start, ctx.tz) : end ? zonedToUtc(end, ctx.tz) : startsAt + 3_600_000;
      if (endsAt < startsAt) return bad("end is before start");
      if (endsAt - startsAt > 366 * 86_400_000) return bad("an event can't run longer than a year");
      const location = text(input.location, 300);
      const notes = text(input.notes, 4000);
      return {
        ok: true,
        action: {
          tool: "add_event",
          event: {
            id: ctx.newId(), calendar: MCFLY_CALENDAR, title, starts_at: iso(startsAt), ends_at: iso(endsAt), all_day: allDay,
            ...(location ? { location } : {}), ...(notes ? { description: notes } : {}), data,
          },
        },
      };
    }
    case "add_todo": {
      const title = text(input.title, 300);
      if (!title) return bad("title is required");
      let due: LocalTime | null = null;
      if (input.due != null && input.due !== "") {
        due = parseLocal(input.due);
        if (!due) return bad(`due must be a day as YYYY-MM-DD, or ${LOCAL_TIME.toLowerCase()}`);
        if (!inRange(due)) return bad("due is too far from today; check the year");
      }
      const notes = text(input.notes, 2000);
      return {
        ok: true,
        action: {
          tool: "add_todo",
          todo: {
            id: ctx.newId(), kind: "todo", title,
            ...(due ? { due_at: iso(due.hasTime ? zonedToUtc(due, ctx.tz) : dayStart(due, ctx.tz)), ...(due.hasTime ? {} : { all_day: true }) } : {}),
            ...(notes ? { notes } : {}), data,
          },
        },
      };
    }
    case "add_reminder": {
      const title = text(input.title, 300);
      if (!title) return bad("title is required");
      const at = parseLocal(input.at);
      if (!at || !at.hasTime) return bad(`at must be ${LOCAL_TIME.toLowerCase()}`);
      if (!inRange(at)) return bad("at is too far from today; check the year");
      const dueAt = zonedToUtc(at, ctx.tz);
      if (dueAt < ctx.now - SAME_DAY_GRACE_MS) {
        return bad(`that time has already passed (it's ${fmtLocal(iso(ctx.now), ctx.tz)} now); use the next time it comes round, or ask`);
      }
      const notes = text(input.notes, 2000);
      return {
        ok: true,
        action: { tool: "add_reminder", todo: { id: ctx.newId(), kind: "reminder", title, due_at: iso(dueAt), ...(notes ? { notes } : {}), data } },
      };
    }
    case "complete_todo": {
      const id = text(input.id, 64);
      if (!id) return bad("id is required: the todo's id from the snapshot");
      return { ok: true, action: { tool: "complete_todo", id } };
    }
    default:
      return bad(`there is no tool called ${oneLine(name, 40)}`);
  }
}

// ───────────────────────────── Results ─────────────────────────────

// "Fri, Oct 16, 3:00 PM to 4:00 PM", "Mon, Oct 19 (all day)", or the span.
export function eventWhenLocal(e: Pick<EventItem, "starts_at" | "ends_at" | "all_day">, tz: string): string {
  const startDay = fmtLocalDay(e.starts_at, tz);
  const endDay = fmtLocalDay(e.ends_at, tz);
  if (e.all_day) return startDay === endDay ? `${startDay} (all day)` : `${startDay} to ${endDay} (all day)`;
  const start = fmtLocal(e.starts_at, tz);
  return startDay === endDay ? `${start} to ${fmtLocalTime(e.ends_at, tz)}` : `${start} to ${fmtLocal(e.ends_at, tz)}`;
}

export function todoWhenLocal(t: Pick<TodoItem, "due_at" | "all_day">, tz: string): string {
  if (!t.due_at) return "";
  return t.all_day ? fmtLocalDay(t.due_at, tz) : fmtLocal(t.due_at, tz);
}

// ───────────────────────────── Running ─────────────────────────────

// Where the writes go. The real one calls the ingest SQL functions with the
// service role (index.ts); tests use a fake.
export interface Store {
  agent(): Promise<string>;
  addEvent(agent: string, event: EventItem): Promise<void>;
  addTodo(agent: string, todo: TodoItem): Promise<string>;
  setDone(id: string): Promise<void>;
  log(agent: string, feed: Changed, ok: boolean, message?: string): Promise<void>;
}

// The open todos the snapshot showed: complete_todo may only touch these.
export interface OpenTodo {
  id: string;
  title: string;
}

export interface ToolResult {
  content: string;
  isError: boolean;
}

// Runs the model's tool calls for one question: checks each input, writes
// through the store, and says what happened in a sentence for the model.
export class ToolRunner {
  readonly changed = new Set<Changed>();
  #writes = 0;
  #agent: Promise<string> | null = null;
  #added = new Set<string>();
  readonly #open: Map<string, string>;

  constructor(
    private readonly store: Store,
    private readonly tz: string,
    open: OpenTodo[],
    private readonly now: () => number = Date.now,
    private readonly newId: () => string = () => crypto.randomUUID(),
  ) {
    this.#open = new Map(open.map((t) => [t.id, t.title]));
  }

  get writes(): number {
    return this.#writes;
  }

  #agentId(): Promise<string> {
    // One lookup per question; a failure is retried on the next call.
    this.#agent ??= this.store.agent().catch((err) => {
      this.#agent = null;
      throw err;
    });
    return this.#agent;
  }

  async run(name: string, input: unknown): Promise<ToolResult> {
    const fail = (content: string): ToolResult => ({ content, isError: true });
    const parsed = parseInput(name, input, { tz: this.tz, now: this.now(), newId: this.newId });
    if (!parsed.ok) return fail(`Not saved: ${parsed.error}.`);
    const action = parsed.action;

    if (this.#writes >= MAX_WRITES) {
      return fail(`Not saved: at most ${MAX_WRITES} changes per question. Tell them what was saved and ask them to say the rest again.`);
    }
    // The same thing twice in one answer (a retry, a repeat) is saved once.
    const key = action.tool === "complete_todo"
      ? `done:${action.id}`
      : action.tool === "add_event"
      ? `event:${action.event.title.toLowerCase()}@${action.event.starts_at}`
      : `${action.todo.kind}:${action.todo.title.toLowerCase()}@${action.todo.due_at ?? ""}`;
    if (this.#added.has(key)) return { content: "Already saved in this answer; nothing more to do.", isError: false };

    if (action.tool === "complete_todo") {
      const title = this.#open.get(action.id);
      if (title === undefined) {
        return fail("Not changed: no open todo or reminder has that id. Use an id from the snapshot's todo list.");
      }
      try {
        await this.store.setDone(action.id);
      } catch (err) {
        console.error("complete_todo failed:", err instanceof Error ? err.message : err);
        return fail("Not changed: the todo list couldn't be updated just now.");
      }
      this.#writes++;
      this.#added.add(key);
      this.#open.delete(action.id);
      this.changed.add("todos");
      return { content: `Checked off: "${title}".`, isError: false };
    }

    const feed: Changed = action.tool === "add_event" ? "events" : "todos";
    let agent: string;
    try {
      agent = await this.#agentId();
      if (action.tool === "add_event") await this.store.addEvent(agent, action.event);
      else await this.store.addTodo(agent, action.todo);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`${action.tool} failed:`, message);
      if (this.#agent) await this.#agent.then((a) => this.store.log(a, feed, false, message)).catch(() => {});
      return fail("Not saved: it couldn't be written just now. Say so, and that they can try again in a moment.");
    }
    this.#writes++;
    this.#added.add(key);
    this.changed.add(feed);
    await this.store.log(agent, feed, true).catch(() => {});

    if (action.tool === "add_event") {
      const e = action.event;
      return { content: `Saved. Event "${e.title}", ${eventWhenLocal(e, this.tz)}${e.location ? `, at ${e.location}` : ""}, on McFly's calendar.`, isError: false };
    }
    const t = action.todo;
    // The display announces it (card and voice); the phone doesn't yet.
    if (t.kind === "reminder") {
      return { content: `Saved. Reminder "${t.title}" at ${todoWhenLocal(t, this.tz)}; the display will announce it then.`, isError: false };
    }
    const due = todoWhenLocal(t, this.tz);
    return { content: `Saved. Todo "${t.title}"${due ? `, due ${due}` : ""}.`, isError: false };
  }
}

// ───────────────────────────── Grok tool calls ─────────────────────────────

export interface GrokToolCall {
  id: string;
  name: string;
  arguments: string;
}

// Streamed tool calls arrive in pieces by index: the first piece has the id
// and name, the rest add to the arguments.
export class GrokToolCalls {
  #calls: GrokToolCall[] = [];

  push(deltas: unknown): void {
    if (!Array.isArray(deltas)) return;
    for (const d of deltas) {
      if (!isObject(d)) continue;
      const index = typeof d.index === "number" && d.index >= 0 && d.index < 16 ? d.index : this.#calls.length;
      const call = (this.#calls[index] ??= { id: "", name: "", arguments: "" });
      if (typeof d.id === "string" && d.id) call.id = d.id;
      const fn = isObject(d.function) ? d.function : null;
      if (fn && typeof fn.name === "string" && fn.name) call.name = fn.name;
      if (fn && typeof fn.arguments === "string") call.arguments += fn.arguments;
    }
  }

  get calls(): GrokToolCall[] {
    return this.#calls.filter((c) => c && c.name).map((c, i) => ({ ...c, id: c.id || `call_${i}` }));
  }
}

// A tool call's arguments as an object, or the reason they aren't one.
export function grokArguments(raw: string): { ok: true; input: unknown } | { ok: false; error: string } {
  try {
    return { ok: true, input: raw.trim() ? JSON.parse(raw) : {} };
  } catch {
    return { ok: false, error: "the arguments weren't valid JSON" };
  }
}
