// Today, as one stream: what arrived and what is planned, in time order.
// The web twin of the display's FeedStore.timeline (display/src/models): the
// same rows, the same order, the same past / now / next rules. Pure, so
// tests/today.test.mjs can check it.

import { dayKey, zonedMidnightUtc } from "./events.ts";

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
  const add = (item: Omit<TimelineItem, "time" | "ampm">) => {
    const c = item.allDay ? { time: "All day", ampm: "" } : clock(item.startMs, timeZone);
    out.push({ ...item, ...c });
  };

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
    if (!onToday(e.starts_at)) continue;
    const start = Date.parse(e.starts_at);
    const end = Date.parse(e.ends_at);
    const range = e.all_day ? e.calendar : `${formatClock(start, timeZone)} – ${formatClock(end, timeZone)}`;
    add({
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
    });
  }

  // All-day first, then by start; ties keep their insertion order.
  return out
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
