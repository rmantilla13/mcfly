// How full one day is, from its timed events, by the app's rules
// (apple/McFlyKit DayLoad.swift) and the display's (FeedStore::dayLoad):
// where two or more run at once (conflicts), which follow each other with
// five minutes or less between them (back to back), the run of two or more
// events with the most booked time when that is an hour or more (the
// busiest stretch), and how booked the two hours around each quarter hour
// are, for drawing. All-day events take no time here; one that runs over
// midnight counts only for its part of the day. Pure, so
// tests/day-load.test.mjs can check it.

import { zonedMidnightUtc } from "./events.ts";

type Timed = { id: string; starts_at: string; ends_at: string; all_day: boolean };

export type LoadKind = "clear" | "backToBack" | "conflict";
export type Span = { start: number; end: number }; // epoch ms

export type DayLoad = {
  dayStart: number;
  dayEnd: number;
  conflicts: Span[];
  conflicting: Set<string>;
  backToBack: Set<string>;
  backToBackCount: number;
  busiest: Span | null;
  // A value per quarter hour of the day, 0 to 1.
  heat: number[];
};

const MIN = 60_000;
export const BACK_TO_BACK_GAP = 5 * MIN;
const SLOT = 15 * MIN;
const WINDOW = 8; // quarter hours: the two hours heat looks at
const STRETCH_GAP = 15 * MIN;
const BUSIEST_FLOOR = 60 * MIN;

// "2026-10-14" plus a day.
function nextDayKey(day: string): string {
  const d = new Date(`${day}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

export function dayLoad(events: Timed[], day: string, timeZone: string): DayLoad {
  const dayStart = Date.parse(zonedMidnightUtc(day, timeZone));
  const dayEnd = Date.parse(zonedMidnightUtc(nextDayKey(day), timeZone));
  // Each timed event's part of this day, by start then end.
  const timed = events
    .filter((e) => !e.all_day)
    .map((e) => ({ id: e.id, start: Math.max(Date.parse(e.starts_at), dayStart), end: Math.min(Date.parse(e.ends_at), dayEnd) }))
    .filter((e) => Number.isFinite(e.start) && Number.isFinite(e.end) && e.end > e.start)
    .sort((a, b) => a.start - b.start || a.end - b.end);

  // Conflicts: walk in start order, keeping the furthest end so far and who
  // reaches it; anything starting before it overlaps.
  const overlaps: Span[] = [];
  const conflicting = new Set<string>();
  let reach: { end: number; id: string } | null = null;
  for (const e of timed) {
    if (reach && e.start < reach.end) {
      overlaps.push({ start: e.start, end: Math.min(e.end, reach.end) });
      conflicting.add(e.id);
      conflicting.add(reach.id);
    }
    if (!reach || e.end > reach.end) reach = { end: e.end, id: e.id };
  }

  // Back to back: the next starts at, or up to five minutes after, the
  // latest end so far.
  const backToBack = new Set<string>();
  let links = 0;
  reach = null;
  for (const e of timed) {
    if (reach && e.start >= reach.end && e.start - reach.end <= BACK_TO_BACK_GAP) {
      backToBack.add(e.id);
      backToBack.add(reach.id);
      links += 1;
    }
    if (!reach || e.end > reach.end) reach = { end: e.end, id: e.id };
  }

  // Booked quarter hours (overlaps count once, at the larger share), then
  // the booked share of the two hours around each.
  const slots = Math.max(1, Math.round((dayEnd - dayStart) / SLOT));
  const booked = new Array<number>(slots).fill(0);
  for (const e of timed) {
    const first = Math.floor((e.start - dayStart) / SLOT);
    const last = Math.ceil((e.end - dayStart) / SLOT);
    for (let i = Math.max(0, first); i < Math.min(slots, last); i++) {
      const slotStart = dayStart + i * SLOT;
      const covered = Math.min(e.end, slotStart + SLOT) - Math.max(e.start, slotStart);
      booked[i] = Math.max(booked[i], covered / SLOT);
    }
  }
  const heat = booked.map((_, i) => {
    let sum = 0;
    for (let j = Math.max(0, i - WINDOW / 2); j < Math.min(slots, i + WINDOW / 2); j++) sum += booked[j];
    return sum / WINDOW;
  });

  // Stretches: events joined while the next starts within 15 minutes of the
  // latest end, with their booked time (overlaps once). The busiest is the
  // one of two or more with the most, the earlier on a tie.
  const stretches: { span: Span; booked: number; count: number }[] = [];
  for (const e of timed) {
    const last = stretches.at(-1);
    if (last && e.start - last.span.end <= STRETCH_GAP) {
      last.booked += Math.max(0, e.end - Math.max(e.start, last.span.end));
      last.span = { start: last.span.start, end: Math.max(last.span.end, e.end) };
      last.count += 1;
    } else {
      stretches.push({ span: { start: e.start, end: e.end }, booked: e.end - e.start, count: 1 });
    }
  }
  let top: (typeof stretches)[number] | null = null;
  for (const s of stretches) if (s.count >= 2 && s.booked > (top?.booked ?? 0)) top = s;

  return {
    dayStart,
    dayEnd,
    conflicts: mergeSpans(overlaps),
    conflicting,
    backToBack,
    backToBackCount: links,
    busiest: top && top.booked >= BUSIEST_FLOOR ? top.span : null,
    heat,
  };
}

// An event's place in its day: it clashes, it runs into the next, or neither.
export function loadKind(load: DayLoad, id: string): LoadKind {
  return load.conflicting.has(id) ? "conflict" : load.backToBack.has(id) ? "backToBack" : "clear";
}

// Overlaps that touch or cross, joined.
function mergeSpans(spans: Span[]): Span[] {
  const out: Span[] = [];
  for (const s of [...spans].sort((a, b) => a.start - b.start)) {
    const last = out.at(-1);
    if (last && s.start <= last.end) last.end = Math.max(last.end, s.end);
    else out.push({ ...s });
  }
  return out;
}

// The heat's colour: nothing when free, amber deepening as it fills, red
// from three quarters booked (the app's and the display's).
export function heatColor(heat: number): string | null {
  if (heat <= 0.001) return null;
  if (heat >= 0.75) return "rgb(229 96 77 / 0.9)";
  return `rgb(242 169 59 / ${(0.25 + (0.75 * heat) / 0.75).toFixed(3)})`;
}
