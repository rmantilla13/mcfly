// A dashboard's widgets arrive as the agent's JSON (dashboards.widgets); the
// database only checks that each has a known type. This turns one into the
// typed shape the preview renders, tolerating strings for numbers and
// dropping what it can't read. Pure, so tests/widgets.test.mjs can check it.

import { formatCompact, formatPrice } from "./format.ts";
import type { Widget } from "./types.ts";

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

function num(v: unknown): number | undefined {
  if (typeof v === "number") return Number.isFinite(v) ? v : undefined;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v.replace(/[,\s]/g, ""));
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

function str(v: unknown, max = 300): string | undefined {
  if (typeof v !== "string") return undefined;
  const s = v.trim();
  return s ? s.slice(0, max) : undefined;
}

const STATES = new Set(["ok", "warn", "down", "unknown"]);

export function parseWidget(raw: unknown): Widget | null {
  if (!isObject(raw)) return null;
  switch (raw.type) {
    case "metric": {
      const value = num(raw.value);
      if (value === undefined) return null;
      return {
        type: "metric",
        label: str(raw.label) ?? "",
        value,
        ...(str(raw.unit, 16) ? { unit: str(raw.unit, 16) } : {}),
        ...(num(raw.delta) !== undefined ? { delta: num(raw.delta) } : {}),
        ...(num(raw.delta_pct) !== undefined ? { delta_pct: num(raw.delta_pct) } : {}),
      };
    }
    case "status": {
      const state = typeof raw.state === "string" && STATES.has(raw.state) ? raw.state : "unknown";
      return { type: "status", label: str(raw.label) ?? "", state: state as "ok" | "warn" | "down" | "unknown", ...(str(raw.detail) ? { detail: str(raw.detail) } : {}) };
    }
    case "progress": {
      const value = num(raw.value);
      if (value === undefined) return null;
      const max = num(raw.max);
      return {
        type: "progress",
        label: str(raw.label) ?? "",
        value,
        max: max !== undefined && max > 0 ? max : 100,
        ...(str(raw.unit, 16) ? { unit: str(raw.unit, 16) } : {}),
      };
    }
    case "list": {
      const items = Array.isArray(raw.items) ? raw.items.map((i) => (typeof i === "string" ? i : isObject(i) ? str(i.text) ?? "" : String(i))).filter(Boolean) : [];
      return { type: "list", ...(str(raw.title) ? { title: str(raw.title) } : {}), items: items.slice(0, 50) };
    }
    case "text": {
      const body = typeof raw.body === "string" ? raw.body.trim().slice(0, 4000) : "";
      return { type: "text", ...(str(raw.title) ? { title: str(raw.title) } : {}), body };
    }
    case "chart": {
      const points = Array.isArray(raw.points) ? raw.points.map(num).filter((p): p is number => p !== undefined) : [];
      return { type: "chart", label: str(raw.label) ?? "", points: points.slice(0, 500), ...(str(raw.unit, 16) ? { unit: str(raw.unit, 16) } : {}) };
    }
    default:
      return null;
  }
}

export function parseWidgets(raw: unknown): Widget[] {
  if (!Array.isArray(raw)) return [];
  return raw.map(parseWidget).filter((w): w is Widget => w !== null);
}

// The widgets the display gives a whole row (FeedStore's `wide`): a chart
// needs the width, and a list or a note reads badly in a narrow column.
export function widgetWide(widget: Widget): boolean {
  return widget.type === "chart" || widget.type === "list" || widget.type === "text";
}

// The SVG path of a sparkline through `points`, left to right, inside a
// width × height box with `pad` kept clear. One point or a flat series
// draws a line across the middle.
export function sparklinePath(points: number[], width = 120, height = 32, pad = 2): string {
  if (points.length === 0) return "";
  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = max - min;
  const innerW = width - pad * 2;
  const innerH = height - pad * 2;
  const x = (i: number) => (points.length === 1 ? width / 2 : pad + (i / (points.length - 1)) * innerW);
  const y = (v: number) => (span === 0 ? height / 2 : pad + innerH - ((v - min) / span) * innerH);
  const round = (n: number) => Math.round(n * 10) / 10;
  if (points.length === 1) return `M${round(pad)},${round(y(points[0]))} L${round(width - pad)},${round(y(points[0]))}`;
  return points.map((v, i) => `${i === 0 ? "M" : "L"}${round(x(i))},${round(y(v))}`).join(" ");
}

// 0–100, however value and max relate.
export function progressPercent(value: number, max: number): number {
  if (!(max > 0)) return 0;
  return Math.max(0, Math.min(100, Math.round((value / max) * 100)));
}

const integer = new Intl.NumberFormat("en-US");
const decimal = new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 });
const compact = new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 });

// "4,280 USD", "99.98%", "1.2M", "212 ms". Big round numbers go compact;
// a percent sign hugs the number.
export function formatMetricValue(value: number | null | undefined, unit?: string | null): string {
  if (value == null || !Number.isFinite(value)) return "—";
  const u = unit?.trim() ?? "";
  if (/^[A-Z]{3}$/.test(u)) {
    try {
      return new Intl.NumberFormat("en-US", { style: "currency", currency: u, maximumFractionDigits: 2 }).format(value);
    } catch {
      // not a currency code after all; fall through to "value UNIT"
    }
  }
  const n = Math.abs(value) >= 1_000_000 && Number.isInteger(value) ? compact.format(value) : Number.isInteger(value) ? integer.format(value) : decimal.format(value);
  if (!u) return n;
  return u === "%" ? `${n}%` : `${n} ${u}`;
}

// ─────────────────────────── Chart geometry ───────────────────────────
// components/charts/* draw from these. Every helper places points the way
// sparklinePath does: left to right in a width × height box with `pad` kept
// clear, the highest value at the top, a flat series across the middle.

export type ChartPoint = { x: number; y: number };

// Two decimals: enough for a curve that is stretched to fill a card.
const fine = (n: number) => Math.round(n * 100) / 100;

function range(points: number[]): { min: number; max: number; minIndex: number; maxIndex: number } {
  let min = Infinity;
  let max = -Infinity;
  let minIndex = -1;
  let maxIndex = -1;
  points.forEach((v, i) => {
    if (v < min) [min, minIndex] = [v, i];
    if (v > max) [max, maxIndex] = [v, i];
  });
  return { min, max, minIndex, maxIndex };
}

// The lowest and highest values and where they first occur, for a chart's
// low/high labels. Null for an empty series.
export function seriesRange(points: number[]): { min: number; max: number; minIndex: number; maxIndex: number } | null {
  return points.length ? range(points) : null;
}

export function chartPoints(points: number[], width = 120, height = 32, pad = 2): ChartPoint[] {
  if (points.length === 0) return [];
  const { min, max } = range(points);
  const span = max - min;
  const innerW = Math.max(0, width - pad * 2);
  const innerH = Math.max(0, height - pad * 2);
  const last = points.length - 1;
  return points.map((v, i) => ({
    x: last === 0 ? width / 2 : pad + (i / last) * innerW,
    y: span === 0 ? height / 2 : pad + innerH - ((v - min) / span) * innerH,
  }));
}

// Fritsch–Carlson tangents (dy/dx at each point) for a monotone cubic: zero
// at a peak, a trough or a flat step, and never so steep that a segment
// swings past either of its ends. That is what keeps a smoothed line from
// dipping below the lowest value or poking above the highest. Exported for
// the tests, which check these rather than the path the clamp below tidies.
export function monotoneTangents(p: ChartPoint[]): number[] {
  const n = p.length;
  const secant: number[] = [];
  for (let i = 0; i < n - 1; i++) {
    const dx = p[i + 1].x - p[i].x;
    secant.push(dx > 0 ? (p[i + 1].y - p[i].y) / dx : 0);
  }
  const m = p.map((_, i) => {
    if (i === 0) return secant[0];
    if (i === n - 1) return secant[n - 2];
    return secant[i - 1] * secant[i] <= 0 ? 0 : (secant[i - 1] + secant[i]) / 2;
  });
  for (let i = 0; i < n - 1; i++) {
    if (secant[i] === 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    const a = m[i] / secant[i];
    const b = m[i + 1] / secant[i];
    const s = a * a + b * b;
    if (s > 9) {
      const t = 3 / Math.sqrt(s);
      m[i] = t * a * secant[i];
      m[i + 1] = t * b * secant[i];
    }
  }
  return m;
}

// The SVG path of a smooth line through `points`: a monotone cubic, so it
// bends between points but never overshoots them. Empty, single-point and
// flat series draw what sparklinePath draws.
export function smoothPath(points: number[], width = 120, height = 32, pad = 2): string {
  const p = chartPoints(points, width, height, pad);
  if (p.length === 0) return "";
  if (p.length === 1) return `M${fine(pad)},${fine(p[0].y)} L${fine(width - pad)},${fine(p[0].y)}`;
  const m = monotoneTangents(p);
  let d = `M${fine(p[0].x)},${fine(p[0].y)}`;
  for (let i = 0; i < p.length - 1; i++) {
    const a = p[i];
    const b = p[i + 1];
    const third = (b.x - a.x) / 3;
    // The control points already sit between a.y and b.y; the clamp only
    // keeps floating-point dust from nudging one outside.
    const lo = Math.min(a.y, b.y);
    const hi = Math.max(a.y, b.y);
    const y1 = Math.min(hi, Math.max(lo, a.y + m[i] * third));
    const y2 = Math.min(hi, Math.max(lo, b.y - m[i + 1] * third));
    d += ` C${fine(a.x + third)},${fine(y1)} ${fine(b.x - third)},${fine(y2)} ${fine(b.x)},${fine(b.y)}`;
  }
  return d;
}

// The closed shape under smoothPath, down to `base` (the bottom of the box
// unless told otherwise) and back, for the soft fill under a line. It drops
// straight down from the first and last points so nothing pokes out past
// the line's ends.
export function areaPath(points: number[], width = 120, height = 32, pad = 2, base = height): string {
  const line = smoothPath(points, width, height, pad);
  if (!line) return "";
  const p = chartPoints(points, width, height, pad);
  const left = p.length === 1 ? pad : p[0].x;
  const right = p.length === 1 ? width - pad : p[p.length - 1].x;
  return `${line} L${fine(right)},${fine(base)} L${fine(left)},${fine(base)} Z`;
}

// Where the newest point is drawn (the dot at the end of a sparkline). A
// single point is drawn as a line across, so its end is at the right.
export function lastPoint(points: number[], width = 120, height = 32, pad = 2): ChartPoint | null {
  const p = chartPoints(points, width, height, pad);
  if (p.length === 0) return null;
  const end = p[p.length - 1];
  return { x: p.length === 1 ? width - pad : end.x, y: end.y };
}

// Up, down or neither, oldest point to newest: the colour a sparkline takes
// when the caller has nothing better to go on.
export function trendTone(points: number[]): "up" | "down" | "neutral" {
  if (points.length < 2) return "neutral";
  const delta = points[points.length - 1] - points[0];
  return delta > 0 ? "up" : delta < 0 ? "down" : "neutral";
}

// Each bar's total and the tallest, for a stacked strip. Nothing below zero
// (or not a number) adds height.
export function barTotals(bars: { values: number[] }[]): { totals: number[]; max: number } {
  const totals = bars.map((b) => b.values.reduce((sum, v) => sum + (Number.isFinite(v) && v > 0 ? v : 0), 0));
  return { totals, max: totals.reduce((a, b) => Math.max(a, b), 0) };
}

// A point's time under a chart's crosshair: the hour for a day or so of
// points, the date for anything longer. UTC unless a zone is given, like
// every other date in the console.
export function pointTimeLabel(ms: number, spanMs: number, timeZone = "UTC"): string {
  if (!Number.isFinite(ms)) return "";
  const options: Intl.DateTimeFormatOptions =
    spanMs < 36 * 3_600_000 ? { hour: "numeric", minute: "2-digit", timeZoneName: "short" } : { month: "short", day: "numeric" };
  try {
    return new Intl.DateTimeFormat("en-US", { ...options, timeZone }).format(ms);
  } catch {
    return new Intl.DateTimeFormat("en-US", { ...options, timeZone: "UTC" }).format(ms);
  }
}

// ─────────────────────────── Number formats ───────────────────────────
// A number's format as plain data, so a server component can hand it to a
// client one (AnimatedNumber, AreaChart) that formats every frame itself.
//   int       1,240             (rounded)
//   decimal   3.14              (up to `decimals`, default 2)
//   percent   12.5%             (the number is already a percentage)
//   compact   6,420 · 1.2M      (whole below 10,000, like formatCompact)
//   currency  $4,280.00         (`currency`, default USD; `decimals` fixes the places)
//   price     $187.40           (formatPrice: a quote in its currency)
//   metric    4,280 USD · 212 ms · 99.98%   (formatMetricValue with `unit`)

export type NumberFormatKind = "int" | "decimal" | "percent" | "compact" | "currency" | "price" | "metric";

export type NumberFormat = {
  format?: NumberFormatKind;
  decimals?: number;
  currency?: string;
  unit?: string;
  prefix?: string;
  suffix?: string;
};

// A number plus how to show it: AnimatedNumber's props and StatTile's `numeric`.
export type NumberSpec = NumberFormat & { value: number };

const places = (decimals: number | undefined) => (decimals === undefined ? undefined : Math.max(0, Math.min(6, Math.round(decimals))));

function decimalFormat(decimals: number | undefined): Intl.NumberFormat {
  const d = places(decimals);
  return new Intl.NumberFormat("en-US", d === undefined ? { maximumFractionDigits: 2 } : { minimumFractionDigits: d, maximumFractionDigits: d });
}

function currencyText(value: number, code: string | undefined, decimals: number | undefined): string {
  const c = code && /^[A-Z]{3}$/.test(code) ? code : "USD";
  const d = places(decimals);
  try {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: c,
      ...(d === undefined ? { maximumFractionDigits: 2 } : { minimumFractionDigits: d, maximumFractionDigits: d }),
    }).format(value);
  } catch {
    return `${value.toFixed(d ?? 2)} ${c}`;
  }
}

// The places each format shows, so a value that rounds to nothing is shown
// as 0 rather than "-0".
function shownPlaces(spec: NumberFormat): number {
  switch (spec.format ?? "int") {
    case "int":
    case "compact":
      return 0;
    case "metric":
      return 2;
    default:
      return places(spec.decimals) ?? 2;
  }
}

export function formatValue(value: number, spec: NumberFormat = {}): string {
  if (!Number.isFinite(value)) return "—";
  const n = Math.abs(value) < 0.5 / 10 ** shownPlaces(spec) ? 0 : value;
  let text: string;
  switch (spec.format ?? "int") {
    case "int":
      text = integer.format(Math.round(n));
      break;
    case "decimal":
      text = decimalFormat(spec.decimals).format(n);
      break;
    case "percent":
      text = `${decimalFormat(spec.decimals).format(n)}%`;
      break;
    case "compact":
      text = formatCompact(Math.round(n));
      break;
    case "currency":
      text = currencyText(n, spec.currency, spec.decimals);
      break;
    case "price":
      text = spec.decimals === undefined ? formatPrice(n, spec.currency) : currencyText(n, spec.currency, spec.decimals);
      break;
    case "metric":
      text = formatMetricValue(n, spec.unit);
      break;
  }
  return `${spec.prefix ?? ""}${text}${spec.suffix ?? ""}`;
}

// ─────────────────────────── Count-up ───────────────────────────
// AnimatedNumber's frames, the web twin of the display's AnimatedNumber.qml
// (OutCubic). Each frame is rounded to the places the end value shows, so
// "4,280" counts in whole numbers and "99.98%" in hundredths, and the text
// doesn't flicker between widths on the way.

export const easeOutCubic = (t: number) => 1 - Math.pow(1 - Math.max(0, Math.min(1, t)), 3);

export function decimalPlaces(n: number): number {
  if (!Number.isFinite(n) || Number.isInteger(n)) return 0;
  const match = /\.(\d+)/.exec(String(n));
  return Math.min(6, match ? match[1].length : 6);
}

// One frame of a count toward `target`, written the way the target is: a
// count to "1.2M" runs "312.4K", "1.1M" rather than "312,407" and then a
// jump in width. The last frame is exactly formatValue(target).
export function formatFrame(value: number, target: number, spec: NumberFormat = {}): string {
  const kind = spec.format ?? "int";
  const unit = spec.unit?.trim() ?? "";
  const compactTarget =
    (kind === "metric" && Number.isInteger(target) && Math.abs(target) >= 1_000_000 && !/^[A-Z]{3}$/.test(unit)) ||
    (kind === "compact" && Math.abs(target) >= 10_000);
  if (!compactTarget || value === target || !Number.isFinite(value)) return formatValue(value, spec);
  const n = compact.format(value);
  const text = kind === "compact" || !unit ? n : unit === "%" ? `${n}%` : `${n} ${unit}`;
  return `${spec.prefix ?? ""}${text}${spec.suffix ?? ""}`;
}

export function countUpValue(from: number, to: number, progress: number, decimals?: number): number {
  if (progress >= 1) return to;
  const v = from + (to - from) * easeOutCubic(progress);
  const p = places(decimals) ?? Math.max(decimalPlaces(from), decimalPlaces(to));
  const scale = 10 ** p;
  const rounded = Math.round(v * scale) / scale;
  return rounded === 0 ? 0 : rounded;
}
