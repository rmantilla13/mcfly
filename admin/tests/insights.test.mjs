// What stands out on Today (lib/insights.ts): the ranking, the rules behind
// each kind, and which way is good news.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildInsights, goodDirection, MAX_INSIGHTS } from "../lib/insights.ts";

const TZ = "America/Chicago";
const NOW = Date.parse("2026-10-14T15:00:00Z"); // 10 AM in Chicago
const MIN = 60_000;
const iso = (ms) => new Date(ms).toISOString();
const usualP95 = [240, 238, 243, 241, 239, 244, 240, 242, 237, 241, 240, 239];

const everything = () => ({
  timeZone: TZ,
  blocked: [{ id: "p1", name: "Onyx", next: "App Review answer", color: "#E2604A" }],
  metrics: [
    { key: "api.p95", label: "API p95", unit: "ms", valueLabel: "212 ms", deltaPct: -7.8, points: [...usualP95, 212] },
    { key: "sales.today", label: "Sales today", unit: "USD", valueLabel: "$4,280.00", deltaPct: 12.5, points: [3900, 3700, 4100, 3850, 4000, 3950, 3800, 4050, 3900, 4280] },
  ],
  events: [
    { id: "e1", title: "Standup", starts_at: iso(NOW + 18 * MIN), ends_at: iso(NOW + 33 * MIN), all_day: false, color: "#5B7CF5", location: "Zoom" },
    { id: "e2", title: "Later", starts_at: iso(NOW + 3 * 60 * MIN), ends_at: iso(NOW + 4 * 60 * MIN), all_day: false, color: "#5B7CF5" },
  ],
  tickers: [
    { symbol: "TSLA", price: "$402.10", changePct: 4.1, points: [], swingPct: 2 },
    { symbol: "SPY", price: "$668.42", changePct: 0.3, points: [], swingPct: 0.5 },
  ],
  brief: { id: "b1", agent: "Grok", color: "#7A64E8", publishedAt: iso(NOW - 20 * MIN), title: "Hourly check-in", summary: "Quiet hour.", kind: "hourly" },
  hero: { reportId: "r1", source: "Daily Pulse", color: "#E2725B", count: 6, headline: "Google launches Gemini 4 Argon" },
});

test("ranked blocked, metric, event, mover, brief, Pulse; at most five", () => {
  const all = buildInsights(everything(), NOW);
  assert.equal(all.length, MAX_INSIGHTS);
  assert.deepEqual(
    all.map((i) => i.kind),
    ["blocked", "metric", "event", "mover", "brief"],
  );
  const calmer = buildInsights({ ...everything(), events: [], tickers: [] }, NOW);
  assert.deepEqual(
    calmer.map((i) => i.kind),
    ["blocked", "metric", "brief", "pulse"],
  );
  assert.deepEqual(buildInsights({ timeZone: TZ }, NOW), []);
});

test("each carries a stable id, a link and a question", () => {
  const all = buildInsights({ ...everything(), events: [] }, NOW);
  const later = buildInsights({ ...everything(), events: [] }, NOW + MIN);
  assert.deepEqual(
    all.map((i) => i.id),
    later.map((i) => i.id),
  );
  const by = Object.fromEntries(buildInsights({ ...everything(), metrics: [] }, NOW).map((i) => [i.kind, i]));
  assert.deepEqual(
    { id: by.blocked.id, href: by.blocked.href, question: by.blocked.question, title: by.blocked.title },
    { id: "blocked:p1", href: "/feed/projects/p1", question: "What's blocking Onyx?", title: "Onyx is blocked" },
  );
  assert.equal(by.mover.question, "Why is TSLA up 4.1% today?");
  assert.equal(by.mover.href, "/feed?tab=markets");
  assert.equal(by.event.question, "What do I need for Standup?");
  assert.equal(by.brief.question, "What did Grok just say?");
  const pulse = buildInsights({ timeZone: TZ, hero: everything().hero }, NOW)[0];
  assert.equal(pulse.id, "pulse:r1");
  assert.equal(pulse.href, "/feed/news/r1");
  assert.equal(pulse.detail, "Daily Pulse · 6 stories");
});

test("a metric anomaly: robust z on long history, with good news by direction", () => {
  const [m] = buildInsights({ timeZone: TZ, metrics: everything().metrics }, NOW);
  assert.equal(m.id, "metric:api.p95");
  assert.equal(m.title, "API p95 is unusually low");
  assert.equal(m.tone, "good", "latency falling is good news");
  assert.equal(m.detail, "212 ms, against a usual 240 ms");
  assert.equal(m.question, "What's behind the drop in API p95?");
  // Sales +12.5% sits inside its usual spread: long history wins over the jump.
  assert.equal(buildInsights({ timeZone: TZ, metrics: [everything().metrics[1]] }, NOW).length, 0);
  // Uptime that should rise, unusually low: bad news.
  const up = buildInsights({ timeZone: TZ, metrics: [{ key: "site.uptime", label: "Uptime", unit: "%", valueLabel: "97%", deltaPct: -2, points: [99.9, 99.95, 99.9, 99.92, 99.94, 99.9, 99.93, 99.91, 99.92, 97] }] }, NOW);
  assert.equal(up[0].tone, "bad");
});

test("a metric jump counts when the history is too short or flat for z", () => {
  const short = buildInsights({ timeZone: TZ, metrics: [{ key: "sales.today", label: "Sales today", unit: "USD", valueLabel: "$4,280.00", deltaPct: 12.5, points: [3804, 4280] }] }, NOW);
  assert.equal(short[0].title, "Sales today is up 12.5%");
  assert.equal(short[0].tone, "good");
  const flat = buildInsights({ timeZone: TZ, metrics: [{ key: "queue.depth", label: "Queue", unit: null, valueLabel: "14", deltaPct: 40, points: [10, 10, 10, 10, 10, 10, 10, 10, 10, 14] }] }, NOW);
  assert.equal(flat[0].title, "Queue is up 40.0%");
  assert.equal(flat[0].tone, "bad", "a growing queue is bad news");
  // A precomputed z from the raw history wins over the points.
  const given = buildInsights({ timeZone: TZ, metrics: [{ ...everything().metrics[0], z: -1.2, history: 400 }] }, NOW);
  assert.equal(given.length, 0);
});

test("big movers: 2% or more, or 2.5× the usual swing (and at least 1%)", () => {
  const movers = (tickers) => buildInsights({ timeZone: TZ, tickers }, NOW).map((i) => i.title);
  assert.deepEqual(movers([{ symbol: "NVDA", changePct: 2, points: [] }]), ["NVDA is up 2.0%"]);
  assert.deepEqual(movers([{ symbol: "SPY", changePct: -1.5, points: [], swingPct: 0.5 }]), ["SPY is down 1.5%"]);
  assert.deepEqual(movers([{ symbol: "SPY", changePct: 0.8, points: [], swingPct: 0.2 }]), [], "under 1% is never news");
  assert.deepEqual(movers([{ symbol: "TSLA", changePct: 1.9, points: [], swingPct: 2 }]), []);
  assert.deepEqual(movers([{ symbol: "NVDA", changePct: 3, points: [], asOf: iso(NOW - 40 * 60 * MIN) }]), [], "Friday's move isn't today's");
  const two = movers([
    { symbol: "A", changePct: 2.1, points: [] },
    { symbol: "B", changePct: -6, points: [] },
    { symbol: "C", changePct: 3, points: [] },
  ]);
  assert.deepEqual(two, ["B is down 6.0%", "C is up 3.0%"], "the two biggest");
  const [detail] = buildInsights({ timeZone: TZ, tickers: [{ symbol: "NVDA", price: "$191.25", changePct: 3.4, points: [], swingPct: 1.6 }] }, NOW);
  assert.equal(detail.detail, "$191.25 · 2.1× its usual daily move");
  assert.equal(detail.tone, "good");
});

test("events: within 30 minutes, or just started; never all-day", () => {
  const ev = (offsetMin, extra = {}) => ({ id: "e", title: "Standup", starts_at: iso(NOW + offsetMin * MIN), ends_at: iso(NOW + (offsetMin + 15) * MIN), all_day: false, color: "#5B7CF5", ...extra });
  const one = (e) => buildInsights({ timeZone: TZ, events: [e] }, NOW)[0];
  assert.equal(one(ev(18)).title, "Standup starts in 18 min");
  assert.equal(one(ev(18)).tone, "neutral");
  assert.equal(one(ev(8)).tone, "warn");
  assert.equal(one(ev(18, { location: "Zoom" })).detail, "10:18 – 10:33 AM · Zoom");
  assert.equal(one(ev(-3)).title, "Standup has started");
  assert.equal(one(ev(45)), undefined);
  assert.equal(one(ev(-20)), undefined);
  assert.equal(one(ev(10, { all_day: true })), undefined);
});

test("briefs under an hour old; alerts warn", () => {
  const b = (minutesAgo, kind = "hourly") => buildInsights({ timeZone: TZ, brief: { ...everything().brief, publishedAt: iso(NOW - minutesAgo * MIN), kind } }, NOW);
  assert.equal(b(20)[0].title, "Grok posted “Hourly check-in”");
  assert.equal(b(20)[0].detail, "20 min ago · Quiet hour.");
  assert.equal(b(20, "alert")[0].tone, "warn");
  assert.deepEqual(b(90), []);
});

test("refused pushes, and an agent that stopped pushing", () => {
  const push = (agent, minutesAgo, status = "ok", message = null) => ({
    created_at: iso(NOW - minutesAgo * MIN),
    status,
    agent_id: agent,
    agent_name: agent === "a1" ? "Market desk" : "Ops",
    agent_color: agent === "a1" ? "#3DB37A" : "red;position:fixed",
    message,
  });
  const WEEK_MIN = 7 * 24 * 60;
  const ingest = [
    // Market desk pushed every 15 minutes, day and night, then stopped 3 hours ago.
    ...Array.from({ length: (WEEK_MIN + 24 * 60) / 15 }, (_, i) => push("a1", 180 + i * 15)),
    push("a1", 200, "error", "quote 3: price must be a number"),
    // Ops pushes every 30 minutes and still does.
    ...Array.from({ length: (WEEK_MIN + 24 * 60) / 30 }, (_, i) => push("a2", 5 + i * 30)),
    push("a2", 26 * 60, "error", "too old to count"),
  ];
  const ingestSince = NOW - 9 * 24 * 60 * MIN;
  const [errors, silent, ...rest] = buildInsights({ timeZone: TZ, ingest, ingestSince }, NOW);
  assert.equal(errors.title, "1 push refused in the last 24 h");
  assert.equal(errors.detail, "Market desk: quote 3: price must be a number");
  assert.equal(errors.question, undefined, "the assistant can't see the log");
  assert.equal(silent.id, "silent:a1");
  assert.equal(silent.title, "Market desk has gone quiet");
  assert.equal(silent.detail, "Last push 3 h ago; usually every 15 min");
  assert.equal(silent.color, "#3DB37A");
  assert.deepEqual(rest, []);

  // Quiet agents need a week of the log behind them; refused pushes don't.
  const kinds = (input) => buildInsights({ timeZone: TZ, ...input }, NOW).map((i) => i.kind);
  assert.deepEqual(kinds({ ingest }), ["errors"], "no idea how far back the log goes");
  assert.deepEqual(kinds({ ingest, ingestSince: NOW - 24 * 60 * MIN }), ["errors"], "a day of it isn't enough");
  assert.deepEqual(kinds({ ingest: ingest.filter((e) => e.status === "error"), ingestSince }), ["errors"], "the Today page reads only refused pushes");
});

test("an agent that keeps market hours isn't quiet in the evening or at the weekend", () => {
  // Every 15 minutes, 9:30 to 16:00 in Chicago (14:30Z to 21:00Z in October), weekdays.
  const pushes = [];
  for (let day = Date.parse("2026-10-01T00:00:00Z"); day < Date.parse("2026-10-20T00:00:00Z"); day += 24 * 60 * MIN) {
    const weekday = new Date(day).getUTCDay();
    if (weekday === 0 || weekday === 6) continue;
    for (let t = day + 14.5 * 60 * MIN; t <= day + 21 * 60 * MIN; t += 15 * MIN) pushes.push(t);
  }
  const ingestSince = Date.parse("2026-10-01T00:00:00Z");
  const quiet = (nowIso, skip = () => false) => {
    const now = Date.parse(nowIso);
    const ingest = pushes
      .filter((t) => t <= now && !skip(t))
      .map((t) => ({ created_at: iso(t), status: "ok", agent_id: "a1", agent_name: "Market desk", agent_color: "#3DB37A" }));
    return buildInsights({ timeZone: TZ, ingest, ingestSince }, now).filter((i) => i.kind === "silent").map((i) => i.detail);
  };
  assert.deepEqual(quiet("2026-10-15T02:00:00Z"), [], "Wednesday, 9 PM");
  assert.deepEqual(quiet("2026-10-17T02:00:00Z"), [], "Friday, 9 PM");
  assert.deepEqual(quiet("2026-10-17T15:00:00Z"), [], "Saturday morning");
  assert.deepEqual(quiet("2026-10-19T02:00:00Z"), [], "Sunday, 9 PM");
  assert.deepEqual(quiet("2026-10-19T14:00:00Z"), [], "Monday, before the open");
  const monday = (t) => t >= Date.parse("2026-10-19T00:00:00Z");
  assert.deepEqual(quiet("2026-10-19T14:31:00Z", monday), [], "Monday's first push is a minute late");
  assert.deepEqual(quiet("2026-10-19T15:15:00Z", monday), ["Last push 3 d ago; usually every 15 min"], "Monday, 10:15, and nothing since Friday");
  const thursday = (t) => t >= Date.parse("2026-10-15T00:00:00Z");
  assert.deepEqual(quiet("2026-10-15T16:00:00Z", thursday), ["Last push 19 h ago; usually every 15 min"], "Thursday, 11 AM, nothing since Wednesday");
});

test("colours are checked, and nothing unserializable comes out", () => {
  const input = everything();
  input.blocked[0].color = "red;position:fixed";
  const all = buildInsights(input, NOW);
  assert.ok(!("color" in all[0]), "an unsafe colour is left out, not passed through");
  assert.deepEqual(JSON.parse(JSON.stringify(all)), all);
});

test("which way is good news", () => {
  const down = [
    ["ms", "api.p95"],
    [null, "api.p95"],
    [null, "checkout.latency"],
    ["%", "errors.rate"],
    [null, "error_rate"],
    ["USD", "cloud.cost"],
    ["USD", "ads.spend"],
    [null, "churn"],
    [null, "queue.depth"],
    [null, "jobs.backlog"],
    ["ms", "anything"],
    [null, "crashes"],
  ];
  const up = [
    ["USD", "sales.today"],
    ["%", "site.uptime"],
    [null, "steps"],
    [null, "orders.open"],
    [null, "signups"],
    ["%", "conversion"],
  ];
  for (const [unit, key] of down) assert.equal(goodDirection(unit, key), "down", `${key} (${unit})`);
  for (const [unit, key] of up) assert.equal(goodDirection(unit, key), "up", `${key} (${unit})`);
});
