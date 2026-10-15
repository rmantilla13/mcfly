// A dashboard's widgets arrive as the agent's JSON (dashboards.widgets); the
// database only checks that each has a known type. This turns one into the
// typed shape the preview renders, tolerating strings for numbers and
// dropping what it can't read. Pure, so tests/widgets.test.mjs can check it.

import type { Widget } from "@/lib/types";

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
