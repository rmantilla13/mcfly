// Today, as one stream: what arrived and what is planned, in time order.
// The web twin of the display's FeedStore.timeline (display/src/models): the
// same rows, the same order, the same past / now / next rules. Pure, so
// tests/today.test.mjs can check it.

import type { Brief, EventRow, MetricRow, NewsItem, NewsReportRow, ProjectRow, QuoteRow } from "@/lib/types";
import { dayKey, dayLabel, zonedMidnightUtc } from "./events.ts";
import { changeDirection, cssColor, formatChange, formatPrice } from "./format.ts";
import { goodDirection } from "./insights.ts";
import type { SeriesPoint } from "./series.ts";
import { dailyCloses, downsample, median, robustZ, usualSwing, withLatest } from "./series.ts";
import { formatMetricValue } from "./widgets.ts";

type BriefIn = { id: string; agent_name: string; agent_color: string; title: string; body: string; kind: string; published_at: string };
type ReportIn = {
  id: string;
  report_date: string;
  published_at: string;
  agent_name: string;
  agent_color: string;
  hero_item: string | null;
  items: { item_key: string; headline: string; image_url: string | null; section_order: number; position: number }[];
};
type ProjectIn = {
  id: string;
  name: string;
  status: string;
  progress: number | null;
  color: string | null;
  agent_color: string;
  updates: { id: number; kind: string; text: string; happened_at: string }[];
};
type EventIn = {
  id: string;
  title: string;
  calendar: string;
  location: string | null;
  starts_at: string;
  ends_at: string;
  all_day: boolean;
  color: string | null;
};

export type TimelineKind = "news" | "brief" | "alert" | "project" | "event";

export type TimelineItem = {
  key: string;
  kind: TimelineKind;
  startMs: number;
  endMs: number;
  allDay: boolean;
  time: string; // "3:30" or "All day"
  ampm: string; // "pm", "" for all-day
  label: string; // kicker: source and kind
  title: string;
  detail: string;
  color: string;
  href: string;
  imageUrl: string | null;
};

export const STATUS_COLOR: Record<string, string> = {
  active: "#2E9E6A",
  blocked: "#E2604A",
  paused: "#B08A2E",
  done: "#7A7A85",
};

function clock(ms: number, timeZone: string): { time: string; ampm: string } {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit", hour12: true }).formatToParts(new Date(ms));
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return { time: `${get("hour")}:${get("minute")}`, ampm: get("dayPeriod").toLowerCase() };
}

export function formatClock(ms: number, timeZone: string): string {
  const c = clock(ms, timeZone);
  return `${c.time} ${c.ampm}`;
}

// When the latest of a feed arrived: its time on the display's day, with
// the day in front otherwise ("Yesterday 11:55 pm"), so last night's brief
// doesn't read as this morning's.
export function stampLabel(ms: number, nowMs: number, timeZone: string): string {
  const day = dayKey(new Date(ms), timeZone);
  const now = new Date(nowMs);
  return day === dayKey(now, timeZone) ? formatClock(ms, timeZone) : `${dayLabel(day, timeZone, now)} ${formatClock(ms, timeZone)}`;
}

export function buildTimeline(input: {
  briefs: BriefIn[];
  reports: ReportIn[];
  projects: ProjectIn[];
  events: EventIn[];
  timeZone: string;
  now: Date;
}): TimelineItem[] {
  const { timeZone } = input;
  const today = dayKey(input.now, timeZone);
  const onToday = (iso: string) => dayKey(iso, timeZone) === today;
  const out: TimelineItem[] = [];
  const add = (item: Omit<TimelineItem, "time" | "ampm">) => out.push(shape(item, timeZone));

  // Today's news reports, every source: the top story and how many more.
  for (const r of input.reports) {
    if (r.report_date !== today || r.items.length === 0) continue;
    const items = [...r.items].sort((a, b) => a.section_order - b.section_order || a.position - b.position);
    const hero = items.find((i) => r.hero_item && i.item_key === r.hero_item) ?? items[0];
    const others = items.filter((i) => i !== hero).slice(0, 2).map((i) => i.headline);
    const more = items.length - 1 - others.length;
    // Written last night for today, it opens the day.
    const at = Date.parse(onToday(r.published_at) ? r.published_at : zonedMidnightUtc(today, timeZone));
    add({
      key: `news:${r.id}`,
      kind: "news",
      startMs: at,
      endMs: at,
      allDay: false,
      label: `${r.agent_name || "Daily Pulse"} · ${items.length} stories`,
      title: hero.headline,
      detail: others.join(" · ") + (more > 0 ? ` · ${more} more` : ""),
      color: r.agent_color,
      href: `/feed/news/${r.id}`,
      imageUrl: hero.image_url,
    });
  }

  for (const b of input.briefs) {
    if (!onToday(b.published_at)) continue;
    const at = Date.parse(b.published_at);
    add({
      key: `brief:${b.id}`,
      kind: b.kind === "alert" ? "alert" : "brief",
      startMs: at,
      endMs: at,
      allDay: false,
      label: `${b.agent_name} · ${b.kind}`,
      title: b.title,
      detail: firstParagraph(b.body),
      color: b.agent_color,
      href: "/feed?tab=briefs",
      imageUrl: null,
    });
  }

  for (const p of input.projects) {
    for (const u of p.updates) {
      if (!onToday(u.happened_at)) continue;
      const at = Date.parse(u.happened_at);
      add({
        key: `project:${p.id}:${u.id}`,
        kind: "project",
        startMs: at,
        endMs: at,
        allDay: false,
        label: p.name,
        title: u.text,
        detail: p.progress != null ? `${Math.round(p.progress)}% done` : capitalise(p.status),
        color: p.color || STATUS_COLOR[p.status] || p.agent_color,
        href: `/feed/projects/${p.id}`,
        imageUrl: null,
      });
    }
  }

  for (const e of input.events) {
    if (onToday(e.starts_at)) add(eventRow(e, timeZone));
  }
  return byStart(out);
}

// Tomorrow's events as rows: the preview under today's last row.
export function buildTomorrow(input: { events: EventIn[]; timeZone: string; now: Date }): TimelineItem[] {
  const tomorrow = nextDay(dayKey(input.now, input.timeZone));
  return byStart(
    input.events.filter((e) => dayKey(e.starts_at, input.timeZone) === tomorrow).map((e) => shape(eventRow(e, input.timeZone), input.timeZone)),
  );
}

// The day after a "yyyy-mm-dd".
export function nextDay(day: string): string {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
}

// Tomorrow's weekday ("Friday") in the display's zone, for the preview's heading.
export function tomorrowLabel(nowMs: number, timeZone: string): string {
  const day = nextDay(dayKey(new Date(nowMs), timeZone));
  return new Intl.DateTimeFormat("en-US", { timeZone: "UTC", weekday: "long" }).format(new Date(`${day}T00:00:00Z`));
}

// A row's clock face: "3:30" over "pm", or "All day".
function shape(item: Omit<TimelineItem, "time" | "ampm">, timeZone: string): TimelineItem {
  return { ...item, ...(item.allDay ? { time: "All day", ampm: "" } : clock(item.startMs, timeZone)) };
}

// An event's row: the calendar over the title, the hours and the place under it.
function eventRow(e: EventIn, timeZone: string): Omit<TimelineItem, "time" | "ampm"> {
  const start = Date.parse(e.starts_at);
  const end = Date.parse(e.ends_at);
  const range = e.all_day ? e.calendar : `${formatClock(start, timeZone)} – ${formatClock(end, timeZone)}`;
  return {
    key: `event:${e.id}`,
    kind: "event",
    startMs: start,
    endMs: Number.isNaN(end) ? start : end,
    allDay: e.all_day,
    label: e.calendar,
    title: e.title,
    detail: e.location && !e.all_day ? `${range} · ${e.location}` : range,
    color: e.color || "#5B7CF5",
    href: "/feed?tab=calendar",
    imageUrl: null,
  };
}

// All-day first, then by start; ties keep their insertion order.
function byStart(items: TimelineItem[]): TimelineItem[] {
  return items
    .map((item, i) => ({ item, i }))
    .sort((a, b) => Number(b.item.allDay) - Number(a.item.allDay) || a.item.startMs - b.item.startMs || a.i - b.i)
    .map(({ item }) => item);
}

function firstParagraph(text: string): string {
  const plain = text.replace(/[#*_`>]/g, "").trim();
  const cut = plain.indexOf("\n\n");
  return (cut > 0 ? plain.slice(0, cut) : plain).replace(/\s+/g, " ");
}

function capitalise(s: string): string {
  return s ? s[0].toUpperCase() + s.slice(1) : s;
}

// ---- Where "now" is. QML derives these from a ticking clock; so does the page.

export type RowState = "past" | "now" | "next" | "";

export function nextIndex(items: TimelineItem[], nowMs: number): number {
  return items.findIndex((i) => i.kind === "event" && !i.allDay && i.startMs > nowMs);
}

export function rowState(item: TimelineItem, index: number, items: TimelineItem[], nowMs: number): RowState {
  if (item.kind !== "event" || item.allDay) return "";
  if (item.startMs <= nowMs && item.endMs > nowMs) return "now";
  if (item.endMs <= nowMs) return "past";
  return index === nextIndex(items, nowMs) ? "next" : "";
}

// The row to scroll to: the first event not yet over, else the newest row.
export function focusIndex(items: TimelineItem[], nowMs: number): number {
  const i = items.findIndex((it) => it.kind === "event" && !it.allDay && it.endMs >= nowMs);
  return i >= 0 ? i : items.length - 1;
}

export function untilLabel(ms: number, nowMs: number, long = false): string {
  const m = Math.max(0, Math.round((ms - nowMs) / 60_000));
  if (m < 1) return "now";
  if (m < 60) return long ? `in ${m} minutes` : `in ${m} min`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r === 0 ? `in ${h} h` : `in ${h} h ${r} min`;
}

// The event on now, else the next one (today or later), skipping all-day ones.
export function upNext<T extends { all_day: boolean; ends_at: string; starts_at: string }>(events: T[], nowMs: number): T | null {
  return [...events].sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at)).find((e) => !e.all_day && Date.parse(e.ends_at) > nowMs) ?? null;
}

export function greeting(nowMs: number, timeZone: string, name?: string): string {
  const hour = Number(new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", hourCycle: "h23" }).format(new Date(nowMs)));
  const part = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
  return name && name !== "McFly" ? `${part}, ${name}` : part;
}

// ---- The rest of the page: tickers, metrics, the blocked projects, the
// newest brief and today's Pulse, decorated the way FeedStore decorates them
// for the display. loadToday (lib/today-data.ts) and the demo assistant both
// build from this, so the page and the demo's answers agree.

export type TodayEvent = { id: string; title: string; calendar: string; location: string | null; starts_at: string; ends_at: string; all_day: boolean; color: string };
export type TodayTicker = {
  symbol: string;
  name: string | null;
  price: string; // "$191.25"
  value: number | null; // the same price as a number, for a count-up
  currency: string | null;
  change: string; // "+3.40%"
  direction: "up" | "down" | "flat";
  changePct: number | null; // today's move in percent (derived from change when only that came)
  points: number[]; // up to SPARK_POINTS prices, oldest → newest, the last one the current price
  since: number | null; // epoch ms of the first point: the stretch the points really cover
  swingPct: number | null; // the usual day-to-day move in percent, today's left out
  note: string | null;
  asOf: string | null;
};
export type TodayMetric = {
  key: string;
  label: string;
  group: string | null;
  value: number;
  valueLabel: string; // "212 ms", "$4,280.00", "99.98%"
  unit: string | null;
  delta: number | null;
  deltaPct: number | null;
  deltaLabel: string; // "−18 ms", "+$476.00 (+12.5%)", "" when the agent sent neither
  points: number[]; // up to SPARK_POINTS values, oldest → newest, the last one the latest
  since: number | null;
  good: boolean | null; // the change is good news (a falling latency); null when there's no change
  z: number | null; // how unusual the latest value is (robust z over the raw history)
  usual: number | null; // the median before it
  history: number; // raw points behind z
  note: string | null;
  asOf: string | null;
};
export type TodayProject = { id: string; name: string; next: string; progress: number | null; color: string };
export type TodayBrief = {
  id: string;
  agent: string;
  color: string;
  publishedAt: string;
  title: string;
  summary: string; // the first paragraph, flattened
  bullets: string[]; // its list items ("- …"), at most BRIEF_BULLETS
  kind: string;
} | null;
export type TodayHero = { reportId: string; source: string; color: string; count: number; headline: string; takeaway: string; imageUrl: string | null } | null;

export type TodayFacts = {
  events: TodayEvent[]; // from now on, today and the next week
  tickers: TodayTicker[];
  metrics: TodayMetric[];
  blocked: TodayProject[];
  brief: TodayBrief;
  hero: TodayHero;
};

export const TICKER_LIMIT = 6;
export const METRIC_LIMIT = 8; // each is a series read (kept an hour per server, lib/data.ts)
export const SPARK_POINTS = 30;
export const SERIES_DAYS = 30;

// The quotes the page shows, in the display's order: visible and priced.
export function tickerRows<T extends Pick<QuoteRow, "hidden" | "price" | "sort_order">>(quotes: T[]): T[] {
  return quotes.filter((q) => !q.hidden && q.price != null).sort((a, b) => a.sort_order - b.sort_order).slice(0, TICKER_LIMIT);
}

// The metrics it shows: visible ones with a value, in the console's order.
export function metricRows<T extends Pick<MetricRow, "hidden" | "value">>(metrics: T[]): T[] {
  return metrics.filter((m) => !m.hidden && m.value != null).slice(0, METRIC_LIMIT);
}

const round = (n: number, digits = 2) => Math.round(n * 10 ** digits) / 10 ** digits;
const sign = (n: number) => (n > 0 ? "+" : n < 0 ? "−" : "");

// "−18 ms", "+$476.00 (+12.5%)", "−8.0%": the change in the metric's own unit.
export function metricDeltaLabel(delta: number | null, pct: number | null, unit: string | null): string {
  const hasDelta = delta != null && Number.isFinite(delta);
  const hasPct = pct != null && Number.isFinite(pct);
  const pctText = hasPct ? `${sign(pct)}${Math.abs(pct).toFixed(1)}%` : "";
  if (!hasDelta) return pctText;
  const abs = `${sign(delta)}${formatMetricValue(Math.abs(delta), unit)}`;
  return hasPct ? `${abs} (${pctText})` : abs;
}

export function toTicker(q: QuoteRow, history: SeriesPoint[] = [], timeZone = "UTC"): TodayTicker {
  const series = withLatest(history, q.as_of, q.price);
  const base = q.price != null && q.change != null ? q.price - q.change : null;
  const pct = q.change_pct ?? (q.change != null && base ? (q.change / Math.abs(base)) * 100 : null);
  const swing = usualSwing(dailyCloses(series, timeZone).map((p) => p.v));
  return {
    symbol: q.symbol,
    name: q.name,
    price: formatPrice(q.price, q.currency),
    value: q.price != null && Number.isFinite(q.price) ? q.price : null,
    currency: q.currency ?? null,
    change: q.change_pct != null ? formatChange(null, q.change_pct) : formatChange(q.change, null),
    direction: changeDirection(q.change, q.change_pct),
    changePct: pct != null && Number.isFinite(pct) ? round(pct) : null,
    points: downsample(series, SPARK_POINTS).map((p) => p.v),
    since: series[0]?.t ?? null,
    swingPct: swing != null ? round(swing) : null,
    note: q.note ?? null,
    asOf: q.as_of ?? null,
  };
}

export function toMetric(m: MetricRow, history: SeriesPoint[] = []): TodayMetric {
  const series = withLatest(history, m.as_of, m.value);
  const value = m.value ?? 0;
  const values = series.map((p) => p.v);
  const change = m.delta ?? m.delta_pct;
  const z = robustZ(values);
  const usual = values.length > 1 ? median(values.slice(0, -1)) : null;
  return {
    key: m.key,
    label: m.label,
    group: m.group_name,
    value,
    valueLabel: formatMetricValue(value, m.unit),
    unit: m.unit,
    delta: m.delta,
    deltaPct: m.delta_pct,
    deltaLabel: metricDeltaLabel(m.delta, m.delta_pct, m.unit),
    points: downsample(series, SPARK_POINTS).map((p) => p.v),
    since: series[0]?.t ?? null,
    good: change == null || change === 0 ? null : (change > 0) === (goodDirection(m.unit, m.key) === "up"),
    z: z != null ? round(z) : null,
    usual: usual != null ? round(usual, 4) : null,
    history: values.length,
    note: m.note ?? null,
    asOf: m.as_of ?? null,
  };
}

export function todayFacts(input: {
  now: Date;
  timeZone: string;
  quotes: QuoteRow[];
  metrics: MetricRow[];
  series: { quotes: Record<string, SeriesPoint[]>; metrics: Record<string, SeriesPoint[]> };
  projects: ProjectRow[];
  events: EventRow[];
  brief: Brief | null; // the newest
  report: (NewsReportRow & { items: NewsItem[] }) | null; // today's newest, with its stories
}): TodayFacts {
  const { now, brief, report } = input;
  const items = report ? [...report.items].sort((a, b) => a.section_order - b.section_order || a.position - b.position) : [];
  const heroItem = items.find((i) => report?.hero_item && i.item_key === report.hero_item) ?? items[0];
  return {
    events: input.events
      .filter((e) => Date.parse(e.ends_at) > now.getTime())
      .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at))
      .map((e) => ({ id: e.id, title: e.title, calendar: e.calendar, location: e.location, starts_at: e.starts_at, ends_at: e.ends_at, all_day: e.all_day, color: cssColor(e.color) ?? "#5B7CF5" })),
    tickers: tickerRows(input.quotes).map((q) => toTicker(q, input.series.quotes[q.symbol], input.timeZone)),
    metrics: metricRows(input.metrics).map((m) => toMetric(m, input.series.metrics[m.key])),
    blocked: input.projects
      .filter((p) => p.status === "blocked")
      .map((p) => ({ id: p.id, name: p.name, next: p.next_step || p.summary || "", progress: p.progress, color: cssColor(p.color) ?? STATUS_COLOR.blocked })),
    brief: brief
      ? {
          id: brief.id,
          agent: brief.agent_name,
          color: cssColor(brief.agent_color) ?? "#5B7CF5",
          publishedAt: brief.published_at,
          title: brief.title,
          summary: brief.body.replace(/[#*_`>]/g, "").split(/\n\s*\n/)[0].replace(/\s+/g, " ").trim(),
          bullets: briefBullets(brief.body),
          kind: brief.kind,
        }
      : null,
    hero:
      report && heroItem
        ? {
            reportId: report.id,
            source: report.agent_name || "Daily Pulse",
            color: cssColor(report.agent_color) ?? "#5B7CF5",
            count: items.length,
            headline: heroItem.headline,
            takeaway: heroItem.takeaway ?? "",
            imageUrl: heroItem.image_url,
          }
        : null,
  };
}

export const BRIEF_BULLETS = 4;

// A brief's list items ("- …", "* …", "• …", "1. …"), cleaned of Markdown,
// for the Today card. Agents write their key points this way (docs/AGENTS.md).
export function briefBullets(body: string): string[] {
  const out: string[] = [];
  for (const line of body.split("\n")) {
    const m = /^\s*(?:[-*•]|\d+[.)])\s+(.+)$/.exec(line);
    const text = m ? m[1].replace(/[#*_`>]/g, "").replace(/\s+/g, " ").trim() : "";
    if (text) out.push(text);
    if (out.length === BRIEF_BULLETS) break;
  }
  return out;
}

// ---- The Today page's moving parts, worked out here so they can be tested.

// Up next's ring. "now": an event under way; `value` is how far through it
// is and `minutes` how many are left. "soon": it starts within the hour; the
// ring fills as it nears (0 an hour out, 1 at the start) and `minutes` counts
// down. "later": further off, no ring.
export type Countdown = { mode: "now" | "soon" | "later"; value: number; minutes: number };

export function countdown(startMs: number, endMs: number, nowMs: number): Countdown {
  const clamp01 = (v: number) => Math.max(0, Math.min(1, v));
  if (startMs <= nowMs) {
    const span = endMs - startMs;
    return { mode: "now", value: span > 0 ? clamp01((nowMs - startMs) / span) : 1, minutes: Math.max(0, Math.round((endMs - nowMs) / 60_000)) };
  }
  const minutes = Math.round((startMs - nowMs) / 60_000);
  if (minutes > 60) return { mode: "later", value: 0, minutes };
  return { mode: "soon", value: clamp01(1 - (startMs - nowMs) / 3_600_000), minutes };
}

// Where "now" falls in the day's list, for the timeline's now line: at row
// `from`'s top, `f` of the way to row `to`'s (by their start times), where
// row `items.length` is the bottom of the list. All-day rows stay above it.
// Between two timed rows it moves with the clock; past the last, it runs
// through that row for as long as it lasts (a brief or a story lasts no
// time, so the line sits under it).
export function nowPosition(items: { allDay: boolean; startMs: number; endMs: number }[], nowMs: number): { from: number; to: number; f: number } {
  const n = items.length;
  let a = -1;
  let b = -1;
  items.forEach((item, i) => {
    if (item.allDay) return;
    if (item.startMs <= nowMs) a = i;
    else if (b < 0) b = i;
  });
  if (a < 0 && b < 0) return { from: n, to: n, f: 0 };
  if (a < 0) return { from: b, to: b, f: 0 };
  if (b < 0) {
    const { startMs, endMs } = items[a];
    const f = endMs > startMs ? Math.max(0, Math.min(1, (nowMs - startMs) / (endMs - startMs))) : 1;
    return { from: a, to: n, f };
  }
  const span = items[b].startMs - items[a].startMs;
  return { from: a, to: b, f: span > 0 ? Math.max(0, Math.min(1, (nowMs - items[a].startMs) / span)) : 0 };
}

// Text arriving word by word. Each step either carries on the text so far
// (the same generation, so the words already shown stay put) or replaces it
// (a new generation: the assistant's last word, a refusal say, differs from
// what streamed).
export function nextStream(prev: { text: string; gen: number }, text: string): { text: string; gen: number } {
  if (text === prev.text) return prev;
  return { text, gen: text.startsWith(prev.text) ? prev.gen : prev.gen + 1 };
}

// The words of a text with the space after each one, so the pieces join
// back into exactly the text.
export function streamWords(text: string): string[] {
  return text.match(/\s*\S+\s*/g) ?? [];
}

// The ambient rail: which cards are up, when there are more than fit. The
// pool turns by one every `periodMs` (from the clock, so every tab and every
// render agrees), and the rail fades out for the last `fadeMs` of each turn
// so the change happens unseen: longer than a second, so a clock ticking
// once a second always lands in it.
export function railWindow<T>(pool: T[], slots: number, nowMs: number, periodMs: number, fadeMs = 1500): { shown: T[]; fading: boolean } {
  if (pool.length <= slots) return { shown: pool, fading: false };
  const turn = Math.floor(nowMs / periodMs);
  const start = turn % pool.length;
  const shown = Array.from({ length: slots }, (_, i) => pool[(start + i) % pool.length]);
  return { shown, fading: nowMs % periodMs >= periodMs - fadeMs };
}
