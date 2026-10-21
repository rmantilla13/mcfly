// How the console's visual layouts sort and shape the feeds: the Overview's
// pushes by the hour, the agents' heartbeat, project lanes, brief bodies,
// dashboard health strips and the Pulse's section colours. Pure, so
// tests/feed-layout.test.mjs can check it; the pages only lay it out.

import type { ProjectRow, ProjectStatus, Widget } from "@/lib/types";
import { dayKey, dayLabel } from "./events.ts";
import { bucketHourly, median } from "./series.ts";

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

// ---- Pushes by the hour (Overview)

// The display's names for the feeds, in the order the series stack.
const FEED_LABEL: Record<string, string> = {
  quotes: "Markets",
  briefs: "Briefs",
  metrics: "Metrics",
  events: "Calendar",
  projects: "Projects",
  news: "News",
  dashboards: "Dashboards",
};
const FEED_ORDER = Object.keys(FEED_LABEL);

export type PushBars = {
  series: { feed: string; label: string }[];
  // One per hour, oldest first: a value per series, the refused pushes, and
  // the end of the hour (epoch ms; rolling hours that end at `now`).
  bars: { values: number[]; alert: number; end: number }[];
  total: number; // landed pushes, every bar together
  refused: number;
};

type Push = { created_at: string; feed: string; status: "ok" | "error" };

// Landed pushes per hour stacked by feed, with the refused ones apart. Rows,
// not their counts, the way admin_overview counts pushes_24h, so the bars
// add up to the number above them. The busiest feeds keep their own colour
// and the rest fold into "Other", so the chart tokens never repeat. Series
// stay in the feeds' own order whatever the volume, so a colour means the
// same feed from one refresh to the next.
export function pushBars(entries: Push[], now: number, hours = 24, maxSeries = 5): PushBars {
  const n = Math.max(1, Math.floor(hours));
  const byFeed = new Map<string, number[]>();
  const errors: number[] = [];
  for (const e of entries) {
    const t = Date.parse(e.created_at);
    // Older than the window: bucketHourly would drop it, and its feed
    // mustn't take a colour for nothing.
    if (!Number.isFinite(t) || now - t >= n * HOUR) continue;
    if (e.status === "error") errors.push(t);
    else {
      const list = byFeed.get(e.feed);
      if (list) list.push(t);
      else byFeed.set(e.feed, [t]);
    }
  }
  const rank = (feed: string) => (FEED_ORDER.includes(feed) ? FEED_ORDER.indexOf(feed) : FEED_ORDER.length);
  const busiest = [...byFeed.keys()].sort((a, b) => byFeed.get(b)!.length - byFeed.get(a)!.length || rank(a) - rank(b) || a.localeCompare(b));
  const room = Math.max(1, maxSeries);
  const kept = busiest.length <= room ? busiest : busiest.slice(0, room - 1);
  const folded = busiest.filter((f) => !kept.includes(f));
  kept.sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));

  const columns = kept.map((feed) => bucketHourly(byFeed.get(feed)!, n, now));
  const series = kept.map((feed) => ({ feed, label: FEED_LABEL[feed] ?? feed }));
  if (folded.length) {
    columns.push(bucketHourly(folded.flatMap((f) => byFeed.get(f)!), n, now));
    series.push({ feed: "other", label: "Other" });
  }
  const alerts = bucketHourly(errors, n, now);
  const bars = Array.from({ length: n }, (_, i) => ({
    values: columns.map((c) => c[i]),
    alert: alerts[i],
    end: now - (n - 1 - i) * HOUR,
  }));
  return {
    series,
    bars,
    total: columns.reduce((sum, c) => sum + c.reduce((a, b) => a + b, 0), 0),
    refused: alerts.reduce((a, b) => a + b, 0),
  };
}

const CLOCK = new Map<string, Intl.DateTimeFormat>();
function clock(timeZone: string) {
  let f = CLOCK.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" });
    CLOCK.set(timeZone, f);
  }
  return f;
}

// "2:12 – 3:12 PM": the rolling hour that ends at `end`, in the display's
// zone (the bars are rolling hours, not clock hours).
export function hourSpanLabel(end: number, timeZone: string): string {
  const f = clock(timeZone);
  const a = f.format(new Date(end - HOUR));
  const b = f.format(new Date(end));
  return a.slice(-2) === b.slice(-2) ? `${a.slice(0, -3)} – ${b}` : `${a} – ${b}`;
}

// ---- An agent's heartbeat (Overview's roster)

export type AgentBeat = {
  // live: pushed within its usual gap (and the last hour); ok: has pushed,
  // nothing to say; quiet: nothing for over a week; never: no push yet;
  // revoked: key gone.
  state: "live" | "ok" | "quiet" | "never" | "revoked";
  cadence: number | null; // its usual gap between pushes, ms
  last: number | null; // epoch ms of its last push
};

const LIVE_CAP = HOUR; // a daily agent that pushed at dawn isn't "live" at noon
const SAME_RUN = MIN; // a feed pushed twice this close is one run, not a rhythm
// Its usual gap alone can't say an agent is late: one that works market
// hours, or rests at night or at the weekend, would be late every evening.
// lib/insights.ts holds an agent to where it was a week ago instead, which
// takes a week of log; the Overview reads a day. So only an agent silent
// for longer than any weekly rhythm (and a day's drift) is called quiet.
const QUIET_AFTER = 8 * DAY;

// `pushes` are this agent's landed pushes from the log (any order), with
// their feed. Its usual gap is the shortest of its feeds' median gaps: one
// run pushes each feed with its own request, seconds apart, and those gaps
// say nothing about how often it runs. With no feed pushed twice, the
// week's count spread over the week stands in (per run, so a daily agent
// that pushes three feeds isn't "every 8 h"), once there are enough runs to
// mean something (two in a week could be a daily agent that started
// yesterday).
export function agentBeat(
  agent: { last_seen_at: string | null; revoked_at: string | null; pushes_7d: number },
  pushes: { at: number; feed: string }[],
  now: number,
): AgentBeat {
  const lastSeen = agent.last_seen_at ? Date.parse(agent.last_seen_at) : NaN;
  const last = Number.isFinite(lastSeen) ? lastSeen : null;
  const byFeed = new Map<string, number[]>();
  for (const p of pushes) {
    if (!Number.isFinite(p.at)) continue;
    const list = byFeed.get(p.feed);
    if (list) list.push(p.at);
    else byFeed.set(p.feed, [p.at]);
  }
  let cadence: number | null = null;
  for (const times of byFeed.values()) {
    times.sort((a, b) => a - b);
    // Gaps from run to run, each run timed from its first push.
    const gaps: number[] = [];
    let start = times[0];
    for (const t of times) {
      if (t - start <= SAME_RUN) continue;
      gaps.push(t - start);
      start = t;
    }
    const usual = median(gaps);
    if (usual !== null && (cadence === null || usual < cadence)) cadence = usual;
  }
  if (cadence === null) {
    const runs = agent.pushes_7d / Math.max(1, byFeed.size);
    if (runs >= 3) cadence = (7 * DAY) / runs;
  }
  if (agent.revoked_at) return { state: "revoked", cadence, last };
  if (last === null) return { state: "never", cadence, last };
  const age = Math.max(0, now - last);
  if (age <= Math.min(LIVE_CAP, Math.max(cadence ?? HOUR, 5 * MIN))) return { state: "live", cadence, last };
  if (age > QUIET_AFTER) return { state: "quiet", cadence, last };
  return { state: "ok", cadence, last };
}

// "every 15 min", "hourly", "every 2 h", "daily", "every 3 days".
export function cadenceLabel(ms: number | null): string {
  if (ms === null || !Number.isFinite(ms) || ms <= 0) return "";
  const m = Math.round(ms / MIN);
  if (m < 55) return `every ${Math.max(1, m)} min`;
  const h = Math.round(ms / HOUR);
  if (h <= 1) return "hourly";
  if (h < 20) return `every ${h} h`;
  const d = Math.round(ms / DAY);
  return d <= 1 ? "daily" : `every ${d} days`;
}

// ---- Projects as lanes

export const LANES: { status: ProjectStatus; label: string }[] = [
  { status: "blocked", label: "Blocked" },
  { status: "active", label: "Active" },
  { status: "paused", label: "Paused" },
  { status: "planned", label: "Up next" },
  { status: "done", label: "Done" },
];

// Planned's colour wherever a status has one: a calm indigo, neither in
// flight nor finished. The display and the app use the same.
export const PLANNED_COLOR = "#7C8CF8";

// Every lane, in the order that needs you first (the ones in flight, then
// what's up next, then what's done), each in the agent's order (the RPC's).
// A status the console doesn't know joins Active.
export function projectLanes<P extends Pick<ProjectRow, "status">>(projects: P[]): { status: ProjectStatus; label: string; projects: P[] }[] {
  const known = new Set(LANES.map((l) => l.status));
  return LANES.map((lane) => ({
    ...lane,
    projects: projects.filter((p) => (known.has(p.status) ? p.status : "active") === lane.status),
  }));
}

// ---- Projects' stages

export type StageState = "done" | "current" | "blocked" | "paused" | "next";

export type StageTrack = {
  steps: { name: string; state: StageState }[];
  // The stage it is in and its place (from 0): -1 before the first, the
  // count once the project is done.
  current: string | null;
  index: number;
  headline: string; // "Build", "Blocked in App Review", "All 4 stages done", "Not started"
  position: string; // "2 of 4", or "4 stages" before the first
};

// A project's stages as steps: the ones before its stage done, its stage in
// the project's status (blocked or paused, else current), the rest next. A
// done project has been through them all, and a planned one has started
// none. Null for one without stages.
export function stageTrack(p: Pick<ProjectRow, "stages" | "stage" | "status">): StageTrack | null {
  const n = p.stages.length;
  if (!n) return null;
  if (p.status === "done") {
    return {
      steps: p.stages.map((name) => ({ name, state: "done" })),
      current: null,
      index: n,
      headline: n === 1 ? "Done" : `All ${n} stages done`,
      position: `${n} of ${n}`,
    };
  }
  if (p.status === "planned") {
    return { steps: p.stages.map((name) => ({ name, state: "next" })), current: null, index: -1, headline: "Planned", position: n === 1 ? "1 stage" : `${n} stages` };
  }
  const index = p.stage ? p.stages.indexOf(p.stage) : -1;
  const here: StageState = p.status === "blocked" ? "blocked" : p.status === "paused" ? "paused" : "current";
  const steps = p.stages.map((name, i) => ({ name, state: (i < index ? "done" : i === index ? here : "next") as StageState }));
  if (index < 0) return { steps, current: null, index: -1, headline: "Not started", position: n === 1 ? "1 stage" : `${n} stages` };
  const name = p.stages[index];
  return {
    steps,
    current: name,
    index,
    headline: here === "blocked" ? `Blocked in ${name}` : here === "paused" ? `Paused in ${name}` : name,
    position: `${index + 1} of ${n}`,
  };
}

// How long a project has been in its stage: "under an hour", "5 hr",
// "3 days", "2 wk", "4 mo". Empty when the time can't be read.
export function timeInStage(since: string | null, now: number): string {
  const t = since ? Date.parse(since) : NaN;
  if (!Number.isFinite(t)) return "";
  const hours = Math.max(0, now - t) / HOUR;
  if (hours < 1) return "under an hour";
  if (hours < 24) return `${Math.floor(hours)} hr`;
  const days = Math.floor(hours / 24);
  if (days < 14) return days === 1 ? "1 day" : `${days} days`;
  if (days < 60) return `${Math.floor(days / 7)} wk`;
  return `${Math.floor(days / 30)} mo`;
}

// ---- Briefs

// A brief's body as a lead and its "- " points, the way the agents write a
// daily one ("Three things for today.\n\n- …\n- …").
export function briefParts(body: string): { lead: string; bullets: string[] } {
  const lead: string[] = [];
  const bullets: string[] = [];
  for (const raw of body.split("\n")) {
    const line = raw.trim();
    const point = /^[-*•]\s+(.*)$/.exec(line);
    if (point) bullets.push(point[1].trim());
    else if (line) lead.push(line);
  }
  return { lead: lead.join(" "), bullets: bullets.filter(Boolean) };
}

// How much of an alert's life is left: 1 when it was just published, 0 once
// it has expired. Null when it never expires or the times can't be read.
export function expiryLeft(publishedAt: string, expiresAt: string | null, now: number): { share: number; ms: number } | null {
  if (!expiresAt) return null;
  const start = Date.parse(publishedAt);
  const end = Date.parse(expiresAt);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null;
  const ms = Math.max(0, end - now);
  return { share: Math.min(1, ms / (end - start)), ms };
}

// ---- Days

// Items bucketed by their day in the zone, newest day first and newest
// first within it ("Today", "Yesterday", "Mon, Oct 12").
export function groupByDay<T>(items: T[], at: (item: T) => string, timeZone: string, now = new Date()): { day: string; label: string; items: T[] }[] {
  const groups = new Map<string, T[]>();
  const sorted = [...items].sort((a, b) => (Date.parse(at(b)) || 0) - (Date.parse(at(a)) || 0));
  for (const item of sorted) {
    const key = dayKey(at(item), timeZone);
    const list = groups.get(key);
    if (list) list.push(item);
    else groups.set(key, [item]);
  }
  return [...groups.entries()]
    .sort(([a], [b]) => Number(a === "invalid") - Number(b === "invalid") || b.localeCompare(a))
    .map(([day, list]) => ({ day, label: day === "invalid" ? "Undated" : dayLabel(day, timeZone, now), items: list }));
}

// How many things happened on each of the last `days` days in the zone,
// oldest first, today last. Days are counted on the calendar (from today's
// date), not in 24-hour steps, so a daylight-saving change can't skip one.
export function activityByDay(times: string[], days: number, now: number, timeZone: string): { day: string; count: number }[] {
  const n = Math.max(1, Math.floor(days));
  const [y, m, d] = dayKey(new Date(now), timeZone).split("-").map(Number);
  const keys = Array.from({ length: n }, (_, i) => new Date(Date.UTC(y, m - 1, d - (n - 1 - i))).toISOString().slice(0, 10));
  const counts = new Map(keys.map((k) => [k, 0]));
  for (const t of times) {
    const k = dayKey(t, timeZone);
    if (counts.has(k)) counts.set(k, counts.get(k)! + 1);
  }
  return keys.map((day) => ({ day, count: counts.get(day)! }));
}

// ---- Dashboards

type StatusWidget = Extract<Widget, { type: "status" }>;
export type WidgetBlock = { kind: "health"; items: StatusWidget[] } | { kind: "widget"; widget: Widget; index: number };

// The widgets in the agent's order, with each run of two or more statuses
// merged into one health strip: four "OK"s read better as one row of dots
// than as four cards.
export function widgetBlocks(widgets: Widget[]): WidgetBlock[] {
  const out: WidgetBlock[] = [];
  let run: { widget: StatusWidget; index: number }[] = [];
  const flush = () => {
    if (run.length > 1) out.push({ kind: "health", items: run.map((r) => r.widget) });
    else for (const r of run) out.push({ kind: "widget", widget: r.widget, index: r.index });
    run = [];
  };
  widgets.forEach((widget, index) => {
    if (widget.type === "status") run.push({ widget, index });
    else {
      flush();
      out.push({ kind: "widget", widget, index });
    }
  });
  flush();
  return out;
}

// ---- Metrics

// Which tile a metric gets: a ring for a percentage, a big figure over an
// area for money, the figure and its trend for a latency (where falling is
// the good news) and for anything counted.
export function metricTile(unit: string | null, key: string): "ring" | "money" | "latency" | "count" {
  const u = (unit ?? "").trim();
  if (u === "%") return "ring";
  if (/^[A-Z]{3}$/.test(u)) return "money";
  if (["ms", "s", "sec", "µs", "us"].includes(u.toLowerCase()) || /latenc|p9\d|p50|p75|ttfb/i.test(key)) return "latency";
  return "count";
}

// ---- The Pulse's sections

// A section's colour, as the display picks it (FeedStore.cpp sectionColor):
// by key, then by position.
const SECTION_PALETTE = ["#7A64E8", "#3DB37A", "#E86A92", "#14C2C2"];
export function sectionColor(key: string, index: number): string {
  if (key === "s" || key.startsWith("social")) return "#F07F5A";
  if (key === "a" || key.startsWith("ad")) return "#F6B94A";
  if (key === "i" || key.startsWith("ai")) return "#5B7CF5";
  return SECTION_PALETTE[((index % SECTION_PALETTE.length) + SECTION_PALETTE.length) % SECTION_PALETTE.length];
}

// The same colour from a section's name, where the list of reports has only
// names ("Paid Ads", "AI Tech"): the words the keys usually come from.
export function sectionColorByName(name: string, index: number): string {
  const words = name.toLowerCase().split(/[^a-z0-9]+/);
  const key = words.includes("social") ? "social" : words.some((w) => w === "ad" || w === "ads") ? "ad" : words.includes("ai") ? "ai" : `-${name}`;
  return sectionColor(key, index);
}

// How many columns each block takes on a `cols`-wide grid, so the agent's
// order fills whole rows: a health strip takes the row, a chart two thirds,
// a list or a note half, anything else a third. A block that won't fit the
// row's end makes the one before it stretch to the edge, and the last row's
// last block does the same, so there are never holes and never reordering.
export function bentoSpans(blocks: ("health" | "chart" | "wide" | "small")[], cols: number): number[] {
  const c = Math.max(1, Math.floor(cols));
  const base = { health: c, chart: Math.ceil((2 * c) / 3), wide: c <= 2 ? c : Math.ceil(c / 2), small: Math.max(1, Math.floor(c / 3)) };
  const spans: number[] = [];
  let used = 0;
  blocks.forEach((kind, i) => {
    const want = Math.min(c, base[kind]);
    if (used + want > c) {
      spans[i - 1] += c - used;
      used = 0;
    }
    spans.push(want);
    used = (used + want) % c;
  });
  if (used > 0) spans[spans.length - 1] += c - used;
  return spans;
}
