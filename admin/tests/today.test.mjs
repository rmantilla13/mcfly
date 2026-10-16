// The web Today timeline (lib/today.ts): the display's rules, in the display's zone.
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  briefBullets,
  buildTimeline,
  buildTomorrow,
  countdown,
  focusIndex,
  greeting,
  metricDeltaLabel,
  metricRows,
  nextDay,
  nextIndex,
  nextStream,
  nowPosition,
  railWindow,
  rowState,
  stampLabel,
  streamWords,
  tickerRows,
  todayFacts,
  toMetric,
  tomorrowLabel,
  toTicker,
  untilLabel,
  upNext,
} from "../lib/today.ts";

const TZ = "America/Chicago";
const NOW = new Date("2026-10-14T15:00:00Z"); // 10 AM in Chicago
const at = (h, m = 0) => new Date(Date.UTC(2026, 9, 14, h + 5, m)).toISOString(); // Chicago hour → UTC

const input = {
  timeZone: TZ,
  now: NOW,
  briefs: [
    { id: "b1", agent_name: "Grok", agent_color: "#7A64E8", title: "Morning briefing", body: "Three things.\n\nMore.", kind: "daily", published_at: at(8, 30) },
    { id: "b0", agent_name: "Grok", agent_color: "#7A64E8", title: "Yesterday", body: "", kind: "hourly", published_at: "2026-10-13T20:00:00Z" },
    { id: "b2", agent_name: "Desk", agent_color: "#2E9E6A", title: "TSLA up", body: "", kind: "alert", published_at: at(9, 5) },
  ],
  reports: [
    {
      id: "r1", report_date: "2026-10-14", published_at: "2026-10-14T04:00:00Z", agent_name: "Daily Pulse", agent_color: "#5B7CF5", hero_item: "b",
      items: [
        { item_key: "a", headline: "A", image_url: null, section_order: 0, position: 0 },
        { item_key: "b", headline: "B", image_url: "https://img/b.jpg", section_order: 1, position: 0 },
        { item_key: "c", headline: "C", image_url: null, section_order: 1, position: 1 },
        { item_key: "d", headline: "D", image_url: null, section_order: 2, position: 0 },
      ],
    },
    { id: "r0", report_date: "2026-10-13", published_at: "2026-10-13T12:00:00Z", agent_name: "Daily Pulse", agent_color: "#5B7CF5", hero_item: null,
      items: [{ item_key: "x", headline: "Old", image_url: null, section_order: 0, position: 0 }] },
  ],
  projects: [
    { id: "p1", name: "McFly", status: "active", progress: 62, color: null, agent_color: "#7A64E8",
      updates: [{ id: 3, kind: "ci", text: "CI green", happened_at: at(9, 25) }, { id: 2, kind: "note", text: "Old", happened_at: "2026-10-12T12:00:00Z" }] },
  ],
  events: [
    { id: "e1", title: "Standup", calendar: "Work", location: "Zoom", starts_at: at(9, 30), ends_at: at(10, 15), all_day: false, color: null },
    { id: "e2", title: "Pulse review", calendar: "Work", location: null, starts_at: at(15, 30), ends_at: at(16), all_day: false, color: "#E2725B" },
    { id: "e3", title: "Holiday", calendar: "Home", location: null, starts_at: "2026-10-14T05:00:00Z", ends_at: "2026-10-15T05:00:00Z", all_day: true, color: null },
    { id: "e4", title: "Tomorrow", calendar: "Work", location: null, starts_at: at(33), ends_at: at(34), all_day: false, color: null },
  ],
};

test("only today's rows, all-day first, then in time order", () => {
  const t = buildTimeline(input);
  assert.deepEqual(t.map((i) => i.title), ["Holiday", "B", "Morning briefing", "TSLA up", "CI green", "Standup", "Pulse review"]);
  assert.equal(t[0].time, "All day");
});

test("tomorrow's events preview under the day, all-day first", () => {
  const dayOff = { id: "e5", title: "Day off", calendar: "Home", location: null, starts_at: "2026-10-15T05:00:00Z", ends_at: "2026-10-16T05:00:00Z", all_day: true, color: null };
  const t = buildTomorrow({ events: [...input.events, dayOff], timeZone: TZ, now: NOW });
  assert.deepEqual(t.map((i) => i.title), ["Day off", "Tomorrow"]);
  assert.equal(t[0].time, "All day");
  assert.equal(t[1].kind, "event");
  assert.equal(`${t[1].time} ${t[1].ampm}`, "9:00 am");
  assert.equal(t[1].detail, "9:00 am – 10:00 am");
  assert.equal(t[1].href, "/feed?tab=calendar");
  assert.equal(tomorrowLabel(NOW.getTime(), TZ), "Thursday");
  assert.equal(nextDay("2026-10-31"), "2026-11-01");
  // Late in the evening it is still today's tomorrow, in the display's zone.
  assert.equal(tomorrowLabel(Date.parse("2026-10-15T04:30:00Z"), TZ), "Thursday"); // 11:30 pm on the 14th in Chicago
});

test("a report written overnight opens the day with its hero and the rest", () => {
  const news = buildTimeline(input).find((i) => i.kind === "news");
  assert.equal(news.time, "12:00");
  assert.equal(news.ampm, "am");
  assert.equal(news.title, "B");
  assert.equal(news.detail, "A · C · 1 more");
  assert.equal(news.label, "Daily Pulse · 4 stories");
  assert.equal(news.href, "/feed/news/r1");
  assert.equal(news.imageUrl, "https://img/b.jpg");
});

test("rows carry their kind, time and link", () => {
  const t = buildTimeline(input);
  const alert = t.find((i) => i.title === "TSLA up");
  assert.equal(alert.kind, "alert");
  assert.equal(`${alert.time} ${alert.ampm}`, "9:05 am");
  const ci = t.find((i) => i.kind === "project");
  assert.equal(ci.detail, "62% done");
  assert.equal(ci.href, "/feed/projects/p1");
  const standup = t.find((i) => i.title === "Standup");
  assert.equal(standup.detail, "9:30 am – 10:15 am · Zoom");
  assert.equal(t.find((i) => i.title === "Morning briefing").detail, "Three things.");
});

test("past, now and next follow the clock", () => {
  const t = buildTimeline(input);
  const now = NOW.getTime();
  const standup = t.findIndex((i) => i.title === "Standup");
  const review = t.findIndex((i) => i.title === "Pulse review");
  assert.equal(rowState(t[standup], standup, t, now), "now");
  assert.equal(rowState(t[review], review, t, now), "next");
  assert.equal(nextIndex(t, now), review);
  assert.equal(focusIndex(t, now), standup);
  const later = Date.parse(at(11));
  assert.equal(rowState(t[standup], standup, t, later), "past");
  assert.equal(focusIndex(t, Date.parse(at(17))), t.length - 1);
});

test("up next skips all-day and finished events", () => {
  assert.equal(upNext(input.events, NOW.getTime()).title, "Standup");
  assert.equal(upNext(input.events, Date.parse(at(11))).title, "Pulse review");
  assert.equal(upNext(input.events, Date.parse(at(36))), null);
});

test("labels", () => {
  const now = NOW.getTime();
  assert.equal(untilLabel(now + 18 * 60_000, now), "in 18 min");
  assert.equal(untilLabel(now + 18 * 60_000, now, true), "in 18 minutes");
  assert.equal(untilLabel(now + 125 * 60_000, now), "in 2 h 5 min");
  assert.equal(untilLabel(now - 1, now), "now");
  assert.equal(greeting(now, TZ), "Good morning");
  assert.equal(greeting(now, TZ, "Ricky"), "Good morning, Ricky");
  assert.equal(greeting(Date.parse(at(19)), TZ), "Good evening");
});

// ---- The rest of the page (todayFacts and its pieces).

const DAY = 86_400_000;
const series = (values, end = NOW.getTime(), step = DAY) => values.map((v, i) => ({ t: end - (values.length - 1 - i) * step, v }));
const quote = (over) => ({
  symbol: "NVDA", name: "NVIDIA", sort_order: 0, hidden: false, price: 191.25, change: 6.29, change_pct: 3.4, currency: "USD",
  note: "Orders beat.", as_of: "2026-10-14T14:56:00Z", agent_name: "Market desk", agent_color: "#3DB37A", history_count: 30, ...over,
});
const metric = (over) => ({
  key: "api.p95", label: "API p95", group_name: "Ops", sort_order: 0, hidden: false, value: 212, unit: "ms", delta: -18, delta_pct: null,
  note: null, as_of: "2026-10-14T14:51:00Z", agent_name: "Ops", agent_color: "#F6B94A", history_count: 13, ...over,
});

test("metric changes in the metric's own unit", () => {
  assert.equal(metricDeltaLabel(-18, null, "ms"), "−18 ms");
  assert.equal(metricDeltaLabel(476, 12.5, "USD"), "+$476.00 (+12.5%)");
  assert.equal(metricDeltaLabel(null, -8, null), "−8.0%");
  assert.equal(metricDeltaLabel(0, null, "%"), "0%");
  assert.equal(metricDeltaLabel(null, null, "ms"), "");
});

test("a ticker: thirty points at most, ending on the price, and its usual swing", () => {
  const prices = Array.from({ length: 60 }, (_, i) => 180 + (i % 2 ? 2 : -2));
  prices.push(191.25);
  const t = toTicker(quote(), series(prices), TZ);
  assert.equal(t.points.length, 30);
  assert.equal(t.points.at(-1), 191.25);
  assert.equal(t.since, NOW.getTime() - 60 * DAY);
  assert.equal(t.price, "$191.25");
  assert.deepEqual([t.value, t.currency], [191.25, "USD"], "the price as a number, for a count-up");
  assert.equal(t.change, "+3.40%");
  assert.equal(t.direction, "up");
  assert.equal(t.changePct, 3.4);
  assert.ok(t.swingPct > 2 && t.swingPct < 2.5, `swing ${t.swingPct}`);
  // Only a change came: the percent is worked out from the price before it.
  assert.equal(toTicker(quote({ change_pct: null, price: 102, change: 2 })).changePct, 2);
  const bare = toTicker(quote());
  assert.deepEqual([bare.points, bare.since, bare.swingPct], [[], null, null]);
  assert.equal(toTicker(quote({ price: null })).value, null);
});

test("a metric: good news by direction, how unusual, and the history behind it", () => {
  const usual = [240, 238, 243, 241, 239, 244, 240, 242, 237, 241, 240, 239];
  const m = toMetric(metric(), series([...usual, 212]));
  assert.equal(m.valueLabel, "212 ms");
  assert.equal(m.deltaLabel, "−18 ms");
  assert.equal(m.good, true, "latency down is good");
  assert.ok(m.z <= -3);
  assert.equal(m.usual, 240);
  assert.equal(m.history, 13);
  assert.deepEqual(m.points, [...usual, 212]);
  assert.equal(toMetric(metric({ key: "sales.today", unit: "USD", delta: 476 })).good, true);
  assert.equal(toMetric(metric({ key: "steps", unit: null, delta: null, delta_pct: -8 })).good, false);
  assert.equal(toMetric(metric({ delta: null })).good, null, "no change, no verdict");
  const bare = toMetric(metric());
  assert.deepEqual([bare.points, bare.z, bare.usual, bare.history], [[], null, null, 0]);
});

test("history up to an hour old still ends on the latest row", () => {
  // The cached history stops at 14:00; the latest rows came in since.
  const end = Date.parse("2026-10-14T14:00:00Z");
  const usual = [240, 238, 243, 241, 239, 244, 240, 242, 237, 241, 240, 239];
  const history = series(usual, end);
  const m = toMetric(metric(), history);
  assert.equal(m.points.at(-1), 212, "the line ends on the latest value");
  assert.equal(m.history, 13);
  assert.ok(m.z <= -3, "and that is the value judged");
  assert.equal(history.length, 12, "the cached history isn't changed");
  const prices = Array.from({ length: 40 }, (_, i) => 180 + (i % 2 ? 2 : -2));
  const t = toTicker(quote(), series(prices, end), TZ);
  assert.equal(t.points.at(-1), 191.25);
  // Already there (the demo, or a fresh read): nothing doubles up.
  const fresh = series([...usual, 212], Date.parse("2026-10-14T14:51:00Z"));
  assert.equal(toMetric(metric(), fresh).history, 13);
});

test("which quotes and metrics the page shows", () => {
  const quotes = [quote({ symbol: "B", sort_order: 2 }), quote({ symbol: "H", hidden: true }), quote({ symbol: "N", price: null }), quote({ symbol: "A", sort_order: 1 })];
  assert.deepEqual(tickerRows(quotes).map((q) => q.symbol), ["A", "B"]);
  assert.equal(tickerRows(Array.from({ length: 9 }, (_, i) => quote({ symbol: `S${i}` }))).length, 6);
  assert.deepEqual(metricRows([metric({ key: "a" }), metric({ key: "h", hidden: true }), metric({ key: "n", value: null })]).map((m) => m.key), ["a"]);
});

test("the facts: events from now, blocked projects, the newest brief, today's hero", () => {
  const facts = todayFacts({
    now: NOW,
    timeZone: TZ,
    quotes: [quote()],
    metrics: [metric()],
    series: { quotes: { NVDA: series([185, 191.25]) }, metrics: {} },
    projects: [
      { id: "p1", name: "Onyx", status: "blocked", progress: 80, color: null, next_step: "App Review", summary: "" },
      { id: "p2", name: "McFly", status: "active", progress: 62, color: null, next_step: null, summary: "" },
    ],
    events: input.events.map((e) => ({ ...e, agent_id: "a", agent_name: "Cal", external_id: e.id, url: null })),
    brief: { id: "b1", agent_name: "Grok", agent_color: "#7A64E8", title: "Morning briefing", body: "Three *things*.\n\n- One", kind: "daily", published_at: at(8, 30) },
    report: { ...input.reports[0], items: input.reports[0].items.map((i) => ({ ...i, takeaway: `${i.headline} matters` })) },
  });
  assert.deepEqual(facts.events.map((e) => e.title), ["Holiday", "Standup", "Pulse review", "Tomorrow"], "not over yet, by start");
  assert.equal(facts.events[0].color, "#5B7CF5");
  assert.deepEqual(facts.blocked, [{ id: "p1", name: "Onyx", next: "App Review", progress: 80, color: "#E2604A" }]);
  assert.deepEqual(facts.brief, { id: "b1", agent: "Grok", color: "#7A64E8", publishedAt: at(8, 30), title: "Morning briefing", summary: "Three things.", bullets: ["One"], kind: "daily" });
  assert.deepEqual(facts.hero, { reportId: "r1", source: "Daily Pulse", color: "#5B7CF5", count: 4, headline: "B", takeaway: "B matters", imageUrl: "https://img/b.jpg" });
  assert.deepEqual(facts.tickers.map((t) => [t.symbol, t.points]), [["NVDA", [185, 191.25]]]);
  assert.equal(facts.metrics[0].key, "api.p95");
  assert.equal(todayFacts({ ...facts, now: NOW, timeZone: TZ, quotes: [], metrics: [], series: { quotes: {}, metrics: {} }, projects: [], events: [], brief: null, report: null }).hero, null);
});

// ---- The page's moving parts.

const MIN = 60_000;

test("a brief's list items, cleaned, four at most", () => {
  assert.deepEqual(briefBullets("Three things.\n\n- The **Fed** minutes\n* Your call moved\n• Rain clears\n1. Fourth\n2) Fifth"), [
    "The Fed minutes",
    "Your call moved",
    "Rain clears",
    "Fourth",
  ]);
  assert.deepEqual(briefBullets("Quiet hour. - not a list"), []);
  assert.deepEqual(briefBullets("-\n- \n-x"), [], "a dash alone, or one without a space, isn't an item");
});

test("up next's ring: under way, within the hour, further off", () => {
  const start = Date.parse(at(10));
  const end = Date.parse(at(11));
  assert.deepEqual(countdown(start, end, start + 15 * MIN), { mode: "now", value: 0.25, minutes: 45 });
  assert.deepEqual(countdown(start, end, end), { mode: "now", value: 1, minutes: 0 });
  assert.deepEqual(countdown(start, start, start), { mode: "now", value: 1, minutes: 0 }, "no length: done as it starts");
  assert.deepEqual(countdown(start, end, start - 45 * MIN), { mode: "soon", value: 0.25, minutes: 45 }, "fills as it nears");
  assert.deepEqual(countdown(start, end, start - 60 * MIN), { mode: "soon", value: 0, minutes: 60 });
  assert.deepEqual(countdown(start, end, start - 90 * MIN), { mode: "later", value: 0, minutes: 90 });
});

test("the now line: between two rows by the clock, all-day rows above it", () => {
  const row = (h, m = 0, len = 0, allDay = false) => ({ allDay, startMs: Date.parse(at(h, m)), endMs: Date.parse(at(h, m)) + len * MIN });
  const items = [row(0, 0, 0, true), row(9), row(10, 0, 60), row(12)];
  assert.deepEqual(nowPosition(items, Date.parse(at(8))), { from: 1, to: 1, f: 0 }, "before the first timed row: just above it");
  assert.deepEqual(nowPosition(items, Date.parse(at(9, 30))), { from: 1, to: 2, f: 0.5 });
  assert.deepEqual(nowPosition(items, Date.parse(at(11))), { from: 2, to: 3, f: 0.5 }, "through a meeting toward the next row");
  assert.deepEqual(nowPosition(items, Date.parse(at(13))), { from: 3, to: 4, f: 1 }, "after a brief: under it");
  const meeting = [row(9), row(10, 0, 60)];
  assert.deepEqual(nowPosition(meeting, Date.parse(at(10, 15))), { from: 1, to: 2, f: 0.25 }, "the last row, under way");
  assert.deepEqual(nowPosition([row(0, 0, 0, true)], Date.parse(at(10))), { from: 1, to: 1, f: 0 }, "all-day only: below them");
  assert.deepEqual(nowPosition([], Date.parse(at(10))), { from: 0, to: 0, f: 0 });
});

test("streamed text: carried on, or replaced", () => {
  let s = { text: "", gen: 0 };
  s = nextStream(s, "Two things ");
  s = nextStream(s, "Two things stand out.");
  assert.deepEqual(s, { text: "Two things stand out.", gen: 0 });
  assert.equal(nextStream(s, s.text), s, "nothing new: the same object");
  assert.deepEqual(nextStream(s, "I can't help with that."), { text: "I can't help with that.", gen: 1 }, "the done event differs");
  assert.deepEqual(streamWords("Two  things\nstand out. "), ["Two  ", "things\n", "stand ", "out. "]);
  assert.equal(streamWords(" lead").join(""), " lead");
  assert.deepEqual(streamWords(""), []);
});

test("the ambient rail turns through the pool when it overflows", () => {
  const pool = ["brief", "markets", "metrics", "blocked", "pulse"];
  const P = 12_000;
  assert.deepEqual(railWindow(pool.slice(0, 4), 4, 5 * P, P), { shown: pool.slice(0, 4), fading: false }, "fits: no turning");
  assert.deepEqual(railWindow(pool, 4, 0, P).shown, ["brief", "markets", "metrics", "blocked"]);
  assert.deepEqual(railWindow(pool, 4, P, P).shown, ["markets", "metrics", "blocked", "pulse"]);
  assert.deepEqual(railWindow(pool, 2, 4 * P + 1, P).shown, ["pulse", "brief"], "wraps around");
  assert.equal(railWindow(pool, 4, P - 500, P).fading, true, "fades out just before the turn");
  assert.equal(railWindow(pool, 4, P + 500, P).fading, false);
});

test("a feed's latest: its time today, the day too once it isn't today's", () => {
  const now = Date.parse(at(0, 17)); // 12:17 AM in Chicago, the 14th
  assert.equal(stampLabel(Date.parse(at(0, 5)), now, TZ), "12:05 am");
  assert.equal(stampLabel(Date.parse(at(-1, 55)), now, TZ), "Yesterday 11:55 pm", "last night's");
  assert.equal(stampLabel(Date.parse("2026-10-12T17:00:00Z"), now, TZ), "Mon, Oct 12 12:00 pm");
});
