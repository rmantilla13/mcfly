// Time series for the console's charts and its deterministic insights: quote
// and metric history (lib/data.ts listSeries) and push counts (listIngestSince).
// The display does the same shaping in C++ (FeedStore::rebuild). Pure, so
// tests/series.test.mjs can check it.

// t is epoch ms. Series run oldest → newest.
export type SeriesPoint = { t: number; v: number };

const HOUR = 3_600_000;

// Fewer earlier points than this and a z-score says more about the sample
// than about the value.
export const MIN_HISTORY = 8;

// At most n points with the shape kept: largest-triangle-three-buckets, which
// keeps spikes and dips a plain stride would skip. The first and last points
// always survive, so the line still ends on the latest value.
export function downsample(points: SeriesPoint[], n: number): SeriesPoint[] {
  const len = points.length;
  if (n <= 0 || len === 0) return [];
  if (n >= len) return points.slice();
  if (n === 1) return [points[len - 1]];
  if (n === 2) return [points[0], points[len - 1]];

  const out: SeriesPoint[] = [points[0]];
  const every = (len - 2) / (n - 2);
  let a = 0;
  for (let i = 0; i < n - 2; i++) {
    // The next bucket's average is the third corner of the triangle.
    const nextStart = Math.floor((i + 1) * every) + 1;
    const nextEnd = Math.min(Math.floor((i + 2) * every) + 1, len);
    let avgT = 0;
    let avgV = 0;
    for (let j = nextStart; j < nextEnd; j++) {
      avgT += points[j].t;
      avgV += points[j].v;
    }
    const count = Math.max(nextEnd - nextStart, 1);
    avgT /= count;
    avgV /= count;

    const from = Math.floor(i * every) + 1;
    const to = Math.floor((i + 1) * every) + 1;
    const pa = points[a];
    let best = from;
    let bestArea = -1;
    for (let j = from; j < to; j++) {
      const area = Math.abs((pa.t - avgT) * (points[j].v - pa.v) - (pa.t - points[j].t) * (avgV - pa.v));
      if (area > bestArea) {
        bestArea = area;
        best = j;
      }
    }
    out.push(points[best]);
    a = best;
  }
  out.push(points[len - 1]);
  return out;
}

// The history with the latest reading on the end. The history can be up to
// an hour old (lib/data.ts keeps it that long); the latest row comes fresh
// every refresh. It goes on only when it is newer than the last point, so
// the line, the z-score and today's close all end on the current value. A
// new array when it adds one: the history is shared and never changed.
export function withLatest(points: SeriesPoint[], asOf: string | null | undefined, value: number | null | undefined): SeriesPoint[] {
  const t = asOf ? Date.parse(asOf) : NaN;
  if (points.length === 0 || value == null || !Number.isFinite(value) || !Number.isFinite(t)) return points;
  return t > points[points.length - 1].t ? [...points, { t, v: value }] : points;
}

// First to last: how much it moved over the window. pct is null when the
// window starts at zero (no base to divide by).
export function windowChange(points: SeriesPoint[]): { abs: number; pct: number | null } | null {
  if (points.length < 2) return null;
  const first = points[0].v;
  const abs = points[points.length - 1].v - first;
  return { abs, pct: first === 0 ? null : (abs / Math.abs(first)) * 100 };
}

// Low, high and where the latest value sits between them (0 = at the low,
// 1 = at the high; a flat series sits in the middle).
export function rangeOf(points: SeriesPoint[]): { min: number; max: number; position: number } | null {
  if (points.length === 0) return null;
  let min = Infinity;
  let max = -Infinity;
  for (const p of points) {
    if (p.v < min) min = p.v;
    if (p.v > max) max = p.v;
  }
  const last = points[points.length - 1].v;
  return { min, max, position: max === min ? 0.5 : (last - min) / (max - min) };
}

// Counts per hour over the last `hours` hours, oldest → newest. Rolling
// windows ending at `now`, not clock hours, so it needs no time zone: the
// last bucket is the last 60 minutes. A time a little ahead of `now` (the
// database clock) counts in the last bucket; anything older is dropped.
export function bucketHourly(times: number[], hours: number, now: number): number[] {
  const n = Math.max(0, Math.floor(hours));
  const out: number[] = new Array(n).fill(0);
  for (const t of times) {
    if (!Number.isFinite(t)) continue;
    const i = n - 1 - Math.floor(Math.max(0, now - t) / HOUR);
    if (i >= 0) out[i]++;
  }
  return out;
}

export function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

// How unusual the last value is against the ones before it: a robust
// z-score, (last − median) / (1.4826 · MAD), so one old spike doesn't hide
// the next. When over half the history is one value (open orders, uptime)
// the MAD is 0; the mean absolute deviation stands in. Null when there is
// too little history or no spread at all: never Infinity or NaN, because
// it crosses into the page as JSON.
export function robustZ(values: number[], minHistory = MIN_HISTORY): number | null {
  if (values.length - 1 < minHistory) return null;
  const earlier = values.slice(0, -1);
  const last = values[values.length - 1];
  const mid = median(earlier)!;
  const deviations = earlier.map((v) => Math.abs(v - mid));
  let scale = 1.4826 * median(deviations)!;
  if (!(scale > 0)) scale = 1.2533 * (deviations.reduce((sum, d) => sum + d, 0) / deviations.length);
  if (!(scale > 0)) return null;
  const z = (last - mid) / scale;
  return Number.isFinite(z) ? z : null;
}

// One formatter per zone, kept: building one costs a hundred times more than
// using it, and a busy quote brings a thousand points every refresh. The
// string only has to differ from one day to the next.
const DAY_FORMATS = new Map<string, Intl.DateTimeFormat>();
function dayFormat(timeZone: string): Intl.DateTimeFormat {
  let f = DAY_FORMATS.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone, year: "numeric", month: "numeric", day: "numeric" });
    DAY_FORMATS.set(timeZone, f);
  }
  return f;
}

// The last point of each day in the zone: a quote's daily closes, however
// often the agent pushes.
export function dailyCloses(points: SeriesPoint[], timeZone: string): SeriesPoint[] {
  if (points.length === 0) return [];
  const f = dayFormat(timeZone);
  const out: SeriesPoint[] = [];
  let day = "";
  for (const p of points) {
    const d = f.format(p.t);
    if (d === day) out[out.length - 1] = p;
    else {
      out.push(p);
      day = d;
    }
  }
  return out;
}

// The usual day-to-day move, in percent: the standard deviation of the
// daily % changes, leaving out the last one (today's, the move being
// judged). Null with fewer than `minChanges` earlier days.
export function usualSwing(closes: number[], minChanges = 5): number | null {
  const changes: number[] = [];
  for (let i = 1; i < closes.length - 1; i++) {
    if (closes[i - 1] !== 0) changes.push(((closes[i] - closes[i - 1]) / Math.abs(closes[i - 1])) * 100);
  }
  if (changes.length < minChanges) return null;
  const mean = changes.reduce((s, c) => s + c, 0) / changes.length;
  const variance = changes.reduce((s, c) => s + (c - mean) ** 2, 0) / (changes.length - 1);
  const sd = Math.sqrt(variance);
  return Number.isFinite(sd) && sd > 0 ? sd : null;
}
