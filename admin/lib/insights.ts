// What stands out right now, ranked: a blocked project, a metric far off its
// usual, a meeting about to start, a big mover, a fresh brief, today's
// Pulse. Deterministic, with no model call, because loadToday runs again every
// 60 s in every open tab. Each insight carries a question the assistant can
// answer from its snapshot (latest values, notes, projects, events, briefs,
// the Pulse; no history, no push log). Pure, so tests/insights.test.mjs can
// check it.

import { formatEventTime } from "./events.ts";
import { cssColor } from "./format.ts";
import { median, MIN_HISTORY, robustZ, usualSwing } from "./series.ts";
import { formatMetricValue } from "./widgets.ts";

export type InsightKind = "blocked" | "metric" | "mover" | "event" | "brief" | "pulse" | "silent" | "errors";
export type InsightTone = "neutral" | "good" | "bad" | "warn";

// id is stable across refreshes (kind:thing), so a list can key on it.
export type Insight = {
  id: string;
  kind: InsightKind;
  tone: InsightTone;
  title: string;
  detail?: string;
  href?: string;
  question?: string;
  color?: string;
};

// The shapes TodayData already has (lib/today.ts); every list is optional so
// a page with only some of them (the push log, say) can ask too.
export type InsightInput = {
  timeZone: string;
  blocked?: { id: string; name: string; next: string; color: string }[];
  tickers?: {
    symbol: string;
    price?: string;
    changePct: number | null;
    points: number[];
    swingPct?: number | null; // from daily closes; else estimated from points
    asOf?: string | null;
  }[];
  metrics?: {
    key: string;
    label: string;
    unit: string | null;
    valueLabel: string;
    deltaPct: number | null;
    points: number[];
    z?: number | null; // from the raw series; else estimated from points
    usual?: number | null;
    history?: number; // raw points behind z
  }[];
  events?: { id: string; title: string; starts_at: string; ends_at: string; all_day: boolean; color: string; location?: string | null }[];
  brief?: { id?: string; agent: string; color: string; publishedAt: string; title: string; summary?: string; kind?: string } | null;
  hero?: { reportId: string; source: string; color: string; count: number; headline: string } | null;
  ingest?: { created_at: string; status: string; agent_id: string | null; agent_name?: string | null; agent_color?: string | null; message?: string | null }[];
  // Epoch ms the push log is complete from. Quiet agents are judged only when
  // it reaches back over a week (silentAgents); refused pushes need none.
  ingestSince?: number;
};

export const MAX_INSIGHTS = 5;
export const ANOMALY_Z = 3;
export const SHORT_HISTORY_PCT = 10; // a metric's jump that counts when z can't be had
export const BIG_MOVE_PCT = 2;
export const SWING_RATIO = 2.5;
const SWING_FLOOR_PCT = 1; // a 0.4% day is never news, however calm the stock
const MIN = 60_000;
const HOUR = 60 * MIN;
const WEEK = 7 * 24 * HOUR;
const EVENT_SOON_MS = 30 * MIN;
const BRIEF_FRESH_MS = HOUR;
const QUOTE_FRESH_MS = 36 * HOUR; // Friday's move isn't "today" on Sunday

// Which way is good news. Latency, error rates, cost, churn, queues and the
// like should fall; everything else should rise. From the unit and the key
// only, since that is all an agent's push says.
const DOWN_PREFIXES = [
  "latenc", "error", "fail", "crash", "incident", "outage", "downtime", "churn", "cost", "spend",
  "expens", "refund", "backlog", "queue", "bounce", "ttfb", "cancel", "complaint", "defect", "bug",
];
const DOWN_WORDS = new Set(["lag", "lags", "delay", "delays", "wait", "waits", "debt", "burn", "err", "errs", "p50", "p75", "p90", "p95", "p99", "p999"]);
const DOWN_UNITS = new Set(["ms", "µs", "us", "ns"]);

export function goodDirection(unit: string | null, key: string): "up" | "down" {
  if (DOWN_UNITS.has((unit ?? "").trim().toLowerCase())) return "down";
  for (const word of key.toLowerCase().split(/[^a-z0-9]+/)) {
    if (!word) continue;
    if (DOWN_WORDS.has(word) || /^p\d{2,3}$/.test(word)) return "down";
    if (DOWN_PREFIXES.some((p) => word.startsWith(p))) return "down";
  }
  return "up";
}

export function agoLabel(ms: number, now: number): string {
  const m = Math.round((now - ms) / MIN);
  if (m < 1) return "just now";
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  return h < 48 ? `${h} h ago` : `${Math.round(h / 24)} d ago`;
}

export function durationLabel(ms: number): string {
  const m = Math.max(1, Math.round(ms / MIN));
  if (m < 60) return `${m} min`;
  const h = Math.round(m / 60);
  return h < 48 ? `${h} h` : `${Math.round(h / 24)} d`;
}

export function clip(text: string, max: number): string {
  const t = text.replace(/\s+/g, " ").trim();
  return t.length <= max ? t : `${t.slice(0, max - 1).trimEnd()}…`;
}

const pct1 = (n: number) => Math.abs(n).toFixed(1);
// An agent's colour only when it is a plain hex colour (it ends up in a style).
const tint = (c: string | null | undefined): { color?: string } => {
  const color = cssColor(c);
  return color ? { color } : {};
};

export function buildInsights(input: InsightInput, now: number): Insight[] {
  const out: Insight[] = [];

  // 1. A blocked project: the one thing only you can unstick.
  const blocked = input.blocked ?? [];
  if (blocked.length) {
    const p = blocked[0];
    out.push({
      id: `blocked:${p.id}`,
      kind: "blocked",
      tone: "warn",
      title: blocked.length > 1 ? `${p.name} and ${blocked.length - 1} more are blocked` : `${p.name} is blocked`,
      ...(p.next ? { detail: p.next } : {}),
      href: `/feed/projects/${p.id}`,
      question: `What's blocking ${p.name}?`,
      ...tint(p.color),
    });
  }

  // 2. A metric far from its usual: robust z on the history, or a big jump
  //    when there's too little history (or none that varies) for a z.
  const anomalies: { insight: Insight; strength: number }[] = [];
  for (const m of input.metrics ?? []) {
    const z = m.z !== undefined ? m.z : robustZ(m.points);
    const history = m.history ?? m.points.length;
    let dir = 0;
    let strength = 0;
    let unusual = false;
    if (z !== null && history - 1 >= MIN_HISTORY) {
      if (Math.abs(z) >= ANOMALY_Z) {
        dir = Math.sign(z);
        strength = Math.abs(z);
        unusual = true;
      }
    } else if (m.deltaPct != null && Math.abs(m.deltaPct) >= SHORT_HISTORY_PCT) {
      dir = Math.sign(m.deltaPct);
      strength = (Math.abs(m.deltaPct) / SHORT_HISTORY_PCT) * ANOMALY_Z;
    }
    if (!dir) continue;
    const better = goodDirection(m.unit, m.key) === "up" ? 1 : -1;
    const usual = m.usual !== undefined ? m.usual : median(m.points.slice(0, -1));
    anomalies.push({
      strength,
      insight: {
        id: `metric:${m.key}`,
        kind: "metric",
        tone: dir === better ? "good" : "bad",
        title: unusual ? `${m.label} is unusually ${dir > 0 ? "high" : "low"}` : `${m.label} is ${dir > 0 ? "up" : "down"} ${pct1(m.deltaPct!)}%`,
        detail: unusual && usual != null ? `${m.valueLabel}, against a usual ${formatMetricValue(usual, m.unit)}` : m.valueLabel,
        href: "/feed?tab=metrics",
        question: `What's behind the ${dir > 0 ? "rise" : "drop"} in ${m.label}?`,
      },
    });
  }
  out.push(...anomalies.sort((a, b) => b.strength - a.strength).slice(0, 2).map((a) => a.insight));

  // 3. A meeting about to start (or that just did).
  const soon = (input.events ?? [])
    .filter((e) => !e.all_day)
    .map((e) => ({ e, start: Date.parse(e.starts_at) }))
    .filter(({ start }) => start - now <= EVENT_SOON_MS && now - start <= 5 * MIN)
    .sort((a, b) => a.start - b.start)[0];
  if (soon) {
    const { e, start } = soon;
    const m = Math.round((start - now) / MIN);
    const when = formatEventTime(e, input.timeZone);
    out.push({
      id: `event:${e.id}`,
      kind: "event",
      tone: m <= 10 ? "warn" : "neutral",
      title: start <= now ? `${e.title} has started` : m < 1 ? `${e.title} starts now` : `${e.title} starts in ${m} min`,
      detail: e.location ? `${when} · ${e.location}` : when,
      href: "/feed?tab=calendar",
      question: `What do I need for ${e.title}?`,
      ...tint(e.color),
    });
  }

  // 4. A big mover: 2% or more, or 2.5× its usual daily swing.
  const movers: { insight: Insight; strength: number }[] = [];
  for (const t of input.tickers ?? []) {
    const pct = t.changePct;
    if (pct == null || !Number.isFinite(pct) || pct === 0) continue;
    if (t.asOf && now - Date.parse(t.asOf) > QUOTE_FRESH_MS) continue;
    const swing = t.swingPct !== undefined ? t.swingPct : usualSwing(t.points);
    const ratio = swing ? Math.abs(pct) / swing : null;
    const big = Math.abs(pct) >= BIG_MOVE_PCT;
    const unusual = ratio !== null && ratio >= SWING_RATIO && Math.abs(pct) >= SWING_FLOOR_PCT;
    if (!big && !unusual) continue;
    const dir = pct > 0 ? "up" : "down";
    const parts = [t.price, ratio !== null && ratio >= 1.5 ? `${ratio.toFixed(1)}× its usual daily move` : null].filter(Boolean);
    movers.push({
      strength: Math.max(Math.abs(pct) / BIG_MOVE_PCT, (ratio ?? 0) / SWING_RATIO),
      insight: {
        id: `mover:${t.symbol}`,
        kind: "mover",
        tone: pct > 0 ? "good" : "bad",
        title: `${t.symbol} is ${dir} ${pct1(pct)}%`,
        ...(parts.length ? { detail: parts.join(" · ") } : {}),
        href: "/feed?tab=markets",
        question: `Why is ${t.symbol} ${dir} ${pct1(pct)}% today?`,
      },
    });
  }
  out.push(...movers.sort((a, b) => b.strength - a.strength).slice(0, 2).map((m) => m.insight));

  // 5. A brief from the last hour.
  const brief = input.brief;
  const briefAt = brief ? Date.parse(brief.publishedAt) : NaN;
  if (brief && now - briefAt < BRIEF_FRESH_MS && briefAt - now < 5 * MIN) {
    const ago = agoLabel(briefAt, now);
    out.push({
      id: `brief:${brief.id ?? brief.publishedAt}`,
      kind: "brief",
      tone: brief.kind === "alert" ? "warn" : "neutral",
      title: `${brief.agent} posted “${clip(brief.title, 60)}”`,
      detail: brief.summary ? `${ago} · ${clip(brief.summary, 120)}` : ago,
      href: "/feed?tab=briefs",
      question: `What did ${brief.agent} just say?`,
      ...tint(brief.color),
    });
  }

  // 6. Today's Pulse, led by its hero story.
  const hero = input.hero;
  if (hero) {
    out.push({
      id: `pulse:${hero.reportId}`,
      kind: "pulse",
      tone: "neutral",
      title: hero.headline,
      detail: `${hero.source} · ${hero.count === 1 ? "1 story" : `${hero.count} stories`}`,
      href: `/feed/news/${hero.reportId}`,
      question: `Tell me more about “${clip(hero.headline, 70)}”`,
      ...tint(hero.color),
    });
  }

  // 7 and 8, from the push log when the page has it. The assistant can't
  // see the log, so these carry no question.
  const log = input.ingest ?? [];
  const refused = log.filter((e) => e.status === "error" && now - Date.parse(e.created_at) <= 24 * HOUR);
  if (refused.length) {
    const newest = [...refused].sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
    out.push({
      id: "errors",
      kind: "errors",
      tone: "bad",
      title: `${refused.length === 1 ? "1 push" : `${refused.length} pushes`} refused in the last 24 h`,
      detail: clip(`${newest.agent_name ?? "An agent"}: ${newest.message ?? "refused"}`, 140),
      href: "/",
      ...tint(newest.agent_color),
    });
  }
  out.push(...silentAgents(log, input.ingestSince, now).slice(0, 2));

  return out.slice(0, MAX_INSIGHTS);
}

// An agent that has missed its own rhythm. Its usual gap alone can't tell:
// an agent that works market hours, or rests at night or at the weekend,
// would "go quiet" every evening. So it is held to last week: by this time
// a week ago, less a grace of twice its usual gap (at least half an hour),
// it had pushed at some point; a week on from that push it should have
// pushed again, and it hasn't. That needs the log to reach back a week and
// the grace; with less (the Today page reads only refused pushes) nobody is
// judged.
function silentAgents(log: NonNullable<InsightInput["ingest"]>, since: number | undefined, now: number): Insight[] {
  if (since === undefined || !Number.isFinite(since)) return [];
  const byAgent = new Map<string, { name: string; color: string | null | undefined; times: number[] }>();
  for (const e of log) {
    if (e.status !== "ok" || !e.agent_id) continue;
    const t = Date.parse(e.created_at);
    if (!Number.isFinite(t) || t < since) continue;
    const a = byAgent.get(e.agent_id) ?? { name: e.agent_name ?? "An agent", color: e.agent_color, times: [] };
    a.times.push(t);
    byAgent.set(e.agent_id, a);
  }
  const found: { insight: Insight; ratio: number }[] = [];
  for (const [id, a] of byAgent) {
    if (a.times.length < 4) continue;
    const times = a.times.sort((x, y) => x - y);
    const usual = median(times.slice(1).map((t, i) => t - times[i]))!;
    if (!(usual > 0)) continue;
    const then = now - WEEK - Math.max(2 * usual, 30 * MIN);
    if (since > then) continue;
    const lastWeek = times.findLast((t) => t <= then);
    const last = times[times.length - 1];
    if (lastWeek === undefined || last >= lastWeek + WEEK) continue;
    found.push({
      ratio: (now - last) / usual,
      insight: {
        id: `silent:${id}`,
        kind: "silent",
        tone: "warn",
        title: `${a.name} has gone quiet`,
        detail: `Last push ${agoLabel(last, now)}; usually every ${durationLabel(usual)}`,
        href: "/agents",
        ...tint(a.color),
      },
    });
  }
  return found.sort((x, y) => y.ratio - x.ratio).map((f) => f.insight);
}
