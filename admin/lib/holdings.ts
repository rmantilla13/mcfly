// What a market agent adds to a quote, `quotes.data` (docs/AGENTS.md,
// "Holdings, signals and the day's numbers"), shaped as the display shapes it
// (display/src/models/FeedStore.cpp: positionOf, signalsOf, statsOf,
// rangesOf, the holdings summed). Pure, so tests/holdings.test.mjs can check it.

import { formatPrice } from "./format.ts";
import type { QuoteRow } from "./types.ts";

// A row of the quotes_latest view: the newest push of each symbol.
export type QuoteLatestRow = {
  symbol: string;
  agent_id: string | null;
  as_of: string | null;
  created_at?: string | null;
  data: unknown;
};

export type Tone = "up" | "down" | "watch";
export type Signal = { text: string; tone: Tone };
export type Holding = {
  shares: number | null;
  value: number;
  avgCost: number | null;
  dayChange: number | null;
  totalChange: number | null;
  totalChangePct: number | null;
  weightPct: number | null; // its share of every holding shown, in percent
};
export type PriceRange = { label: string; low: number; high: number; position: number }; // 0 at the low, 1 at the high
export type Stat = { label: string; value: string };
export type Insight = { holding: Holding | null; signals: Signal[]; stats: Stat[]; ranges: PriceRange[] };
// Percentages are on what each move is measured against: the value before
// today's move, and the cost, over the holdings that gave them.
export type Portfolio = {
  count: number;
  value: number;
  dayChange: number | null;
  dayChangePct: number | null;
  totalChange: number | null;
  totalChangePct: number | null;
};

const MAX_SIGNALS = 6;
// Without created_at (the demo), rows within this of the agent's newest are its newest push.
const SAME_PUSH_MS = 120_000;

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

// A JSON number or a numeric string ("$1,234.50", "12%"); null for anything else.
export function dataNumber(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v !== "string") return null;
  const cleaned = v.replace(/[,$%]/g, "").trim();
  if (!cleaned) return null;
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : null;
}

const first = (o: Record<string, unknown>, ...keys: string[]) => {
  for (const k of keys) {
    const n = dataNumber(o[k]);
    if (n !== null) return n;
  }
  return null;
};

// The holding, with what the agent left out worked out: value from shares ×
// price, the gain from the average cost, today's move from shares × change.
export function holdingOf(data: unknown, price: number, change: number | null): Holding | null {
  const p = isObject(data) && isObject(data.position) ? data.position : null;
  if (!p) return null;
  const shares = first(p, "shares", "quantity");
  const value = first(p, "value", "market_value") ?? (shares !== null ? shares * price : null);
  if (value === null || (value === 0 && !shares)) return null;
  const avgCost = first(p, "avg_cost", "average_cost", "average_buy_price");
  let totalChange = first(p, "total_change", "unrealized_pl", "gain");
  if (totalChange === null && avgCost !== null && shares !== null) totalChange = value - avgCost * shares;
  let totalChangePct = first(p, "total_change_pct", "unrealized_pl_pct", "gain_pct");
  if (totalChangePct === null && totalChange !== null && value - totalChange > 0) totalChangePct = (totalChange / (value - totalChange)) * 100;
  let dayChange = first(p, "day_change", "today");
  if (dayChange === null && shares !== null && change !== null) dayChange = shares * change;
  return { shares, value, avgCost, dayChange, totalChange, totalChangePct, weightPct: first(p, "weight_pct", "weight") };
}

// Up to six, one line each; a plain string is "watch".
export function signalsOf(data: unknown): Signal[] {
  const list = isObject(data) && Array.isArray(data.signals) ? data.signals : [];
  const out: Signal[] = [];
  for (const s of list) {
    const raw = typeof s === "string" ? { text: s } : isObject(s) ? s : {};
    const text = typeof raw.text === "string" ? raw.text.replace(/\s+/g, " ").trim().slice(0, 140) : "";
    if (!text) continue;
    out.push({ text, tone: raw.tone === "up" || raw.tone === "down" ? raw.tone : "watch" });
    if (out.length === MAX_SIGNALS) break;
  }
  return out;
}

// Volumes and market caps: 48.2M, 3.7T.
export function compact(n: number): string {
  for (const [size, suffix] of [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]] as const) {
    if (Math.abs(n) >= size) {
      const v = n / size;
      return `${v.toFixed(Math.abs(v) >= 100 ? 0 : 1)}${suffix}`;
    }
  }
  return n.toFixed(0);
}

// The day's numbers in the display's order, only what was sent (the ranges are rangesOf's).
export function statsOf(data: unknown, currency: string | null): Stat[] {
  const s = isObject(data) && isObject(data.stats) ? data.stats : null;
  if (!s) return [];
  const out: Stat[] = [];
  const add = (label: string, value: string | null) => {
    if (value) out.push({ label, value });
  };
  const price = (k: string) => {
    const n = dataNumber(s[k]);
    return n === null ? null : formatPrice(n, currency);
  };
  add("Open", price("open"));
  add("Prev close", price("prev_close"));
  const volume = dataNumber(s.volume);
  if (volume !== null) {
    const avg = dataNumber(s.avg_volume);
    add("Volume", compact(volume) + (avg && avg > 0 ? ` · ${(volume / avg).toFixed(1)}× avg` : ""));
  }
  const cap = dataNumber(s.market_cap);
  if (cap !== null) add("Market cap", `${!currency || currency === "USD" ? "$" : ""}${compact(cap)}`);
  const pe = first(s, "pe", "pe_ratio");
  if (pe !== null) add("P/E", pe.toFixed(1));
  const yieldPct = dataNumber(s.dividend_yield);
  if (yieldPct !== null) add("Dividend", `${yieldPct.toFixed(2)}%`);
  if (typeof s.earnings === "string") add("Earnings", s.earnings.replace(/\s+/g, " ").trim().slice(0, 40));
  return out;
}

export function rangesOf(data: unknown, price: number): PriceRange[] {
  const s = isObject(data) && isObject(data.stats) ? data.stats : null;
  if (!s) return [];
  const out: PriceRange[] = [];
  for (const [label, lowKey, highKey] of [["Today", "low", "high"], ["52 weeks", "low_52w", "high_52w"]] as const) {
    const low = dataNumber(s[lowKey]);
    const high = dataNumber(s[highKey]);
    if (low === null || high === null || high < low) continue;
    out.push({ label, low, high, position: high > low ? Math.min(Math.max((price - low) / (high - low), 0), 1) : 0.5 });
  }
  return out;
}

const time = (iso: string | null | undefined) => (iso ? Date.parse(iso) : NaN);

// Each shown symbol's insight, and the holdings summed. A holding and its
// signals count while their row is part of its agent's newest push (the rows
// one push writes share their created_at; as_of stands in where that's
// missing): a position the agent stopped sending (sold) goes, its price stays.
export function buildHoldings(quotes: QuoteRow[], latest: QuoteLatestRow[]): { insights: Record<string, Insight>; portfolio: Portfolio } {
  const lastPush = new Map<string, number>();
  const lastAsOf = new Map<string, number>();
  for (const row of latest) {
    const agent = row.agent_id ?? "";
    const created = time(row.created_at);
    if (Number.isFinite(created)) lastPush.set(agent, Math.max(lastPush.get(agent) ?? created, created));
    const asOf = time(row.as_of);
    if (Number.isFinite(asOf)) lastAsOf.set(agent, Math.max(lastAsOf.get(agent) ?? asOf, asOf));
  }
  const bySymbol = new Map(latest.map((r) => [r.symbol, r]));

  const insights: Record<string, Insight> = {};
  for (const q of quotes) {
    if (q.hidden || q.price == null) continue;
    const row = bySymbol.get(q.symbol);
    // Only the row the quote shows (a newer push may not be in the list yet).
    if (!row || !Number.isFinite(time(row.as_of)) || time(row.as_of) !== time(q.as_of)) continue;
    const agent = row.agent_id ?? "";
    const created = time(row.created_at);
    const current = Number.isFinite(created) ? created === lastPush.get(agent) : (lastAsOf.get(agent) ?? Infinity) - time(row.as_of) <= SAME_PUSH_MS;
    const insight: Insight = {
      holding: current ? holdingOf(row.data, q.price, q.change) : null,
      signals: current ? signalsOf(row.data) : [],
      stats: statsOf(row.data, q.currency),
      ranges: rangesOf(row.data, q.price),
    };
    if (insight.holding || insight.signals.length || insight.stats.length || insight.ranges.length) insights[q.symbol] = insight;
  }

  const held = Object.values(insights).flatMap((i) => (i.holding ? [i.holding] : []));
  const value = held.reduce((sum, h) => sum + h.value, 0);
  let day = 0, dayBase = 0, gain = 0, cost = 0, anyDay = false, anyGain = false;
  for (const h of held) {
    if (h.weightPct === null && value > 0) h.weightPct = (h.value / value) * 100;
    if (h.dayChange !== null) {
      day += h.dayChange;
      dayBase += h.value - h.dayChange;
      anyDay = true;
    }
    if (h.totalChange !== null) {
      gain += h.totalChange;
      cost += h.value - h.totalChange;
      anyGain = true;
    }
  }
  return {
    insights,
    portfolio: {
      count: held.length,
      value,
      dayChange: anyDay ? day : null,
      dayChangePct: anyDay && dayBase > 0 ? (day / dayBase) * 100 : null,
      totalChange: anyGain ? gain : null,
      totalChangePct: anyGain && cost > 0 ? (gain / cost) * 100 : null,
    },
  };
}

// "+$1,234.50" / "−$48.00".
export function signedPrice(n: number, currency: string | null): string {
  return `${n < 0 ? "−" : "+"}${formatPrice(Math.abs(n), currency)}`;
}

// "+30.4%" / "−2.9%".
export function signedPct(n: number, digits = 1): string {
  const text = Math.abs(n).toFixed(digits);
  return `${n > 0 ? "+" : n < 0 ? "−" : ""}${text}%`;
}

// "40 shares", "1 share", "0.1864 shares".
export function sharesLabel(n: number): string {
  if (n === 1) return "1 share";
  const text = Math.abs(n - Math.round(n)) < 1e-9 ? String(Math.round(n)) : n.toFixed(4).replace(/0+$/, "");
  return `${text} shares`;
}
