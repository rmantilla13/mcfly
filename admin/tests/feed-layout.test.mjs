// The console's visual layouts (lib/feed-layout.ts): pushes by the hour, the
// agents' heartbeat, project lanes, brief bodies, day groups, dashboard
// health strips and the Pulse's section colours.
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  activityByDay,
  agentBeat,
  bentoSpans,
  briefParts,
  cadenceLabel,
  expiryLeft,
  groupByDay,
  hourSpanLabel,
  metricTile,
  projectLanes,
  pushBars,
  sectionColor,
  sectionColorByName,
  stageTrack,
  timeInStage,
  widgetBlocks,
} from "../lib/feed-layout.ts";

const MIN = 60_000;
const HOUR = 60 * MIN;
const NOW = Date.parse("2026-10-15T17:30:00Z"); // 12:30 PM in Chicago (CDT)
const ago = (ms) => new Date(NOW - ms).toISOString();

test("pushes by the hour: rows per feed, refused apart, adding up", () => {
  const entries = [
    ...Array.from({ length: 96 }, (_, i) => ({ created_at: ago(4 * MIN + i * 15 * MIN), feed: "quotes", status: "ok" })),
    ...Array.from({ length: 24 }, (_, i) => ({ created_at: ago(20 * MIN + i * HOUR), feed: "briefs", status: "ok" })),
    { created_at: ago(49 * MIN), feed: "quotes", status: "error" },
    { created_at: ago(3.1 * HOUR), feed: "dashboards", status: "error" },
    { created_at: ago(25 * HOUR), feed: "news", status: "ok" }, // outside the day
  ];
  const out = pushBars(entries, NOW);
  assert.equal(out.bars.length, 24);
  assert.deepEqual(out.series.map((s) => s.label), ["Markets", "Briefs"]);
  assert.equal(out.total, 120);
  assert.equal(out.refused, 2);
  assert.equal(out.bars.reduce((sum, b) => sum + b.values.reduce((a, v) => a + v, 0), 0), out.total);
  // The last bar is the last 60 minutes: four quotes and a brief, one refused.
  assert.deepEqual(out.bars[23].values, [4, 1]);
  assert.equal(out.bars[23].alert, 1);
  assert.equal(out.bars[23].end, NOW);
  assert.equal(out.bars[20].alert, 1); // 3.1 h ago
  assert.equal(out.bars[0].end, NOW - 23 * HOUR);
});

test("pushes by the hour: quiet feeds fold into Other, colours keep their feed", () => {
  const feeds = { quotes: 9, briefs: 1, metrics: 5, events: 4, projects: 3, news: 2, dashboards: 1 };
  const entries = Object.entries(feeds).flatMap(([feed, n]) => Array.from({ length: n }, (_, i) => ({ created_at: ago(i * MIN + 1000), feed, status: "ok" })));
  const out = pushBars(entries, NOW);
  // The four busiest keep their colour, in the feeds' own order; three fold.
  assert.deepEqual(out.series.map((s) => s.feed), ["quotes", "metrics", "events", "projects", "other"]);
  assert.deepEqual(out.bars[23].values, [9, 5, 4, 3, 4]);
  // Five or fewer feeds: no Other.
  const few = pushBars(entries.filter((e) => ["quotes", "news"].includes(e.feed)), NOW);
  assert.deepEqual(few.series.map((s) => s.feed), ["quotes", "news"]);
  // Nothing at all: empty bars, still 24 of them.
  const none = pushBars([], NOW);
  assert.equal(none.bars.length, 24);
  assert.deepEqual(none.series, []);
  assert.equal(none.total, 0);
});

test("an hour's label in the display's zone", () => {
  assert.equal(hourSpanLabel(NOW, "America/Chicago"), "11:30 AM – 12:30 PM");
  assert.equal(hourSpanLabel(NOW - 30 * MIN, "America/Chicago"), "11:00 AM – 12:00 PM");
  assert.equal(hourSpanLabel(NOW - 2 * HOUR, "UTC"), "2:30 – 3:30 PM");
});

test("an agent's heartbeat against its own rhythm", () => {
  const every = (gap, n, from = 0, feed = "quotes") => Array.from({ length: n }, (_, i) => ({ at: NOW - from - i * gap, feed }));
  const agent = (lastAgo, pushes_7d = 0, revoked = false) => ({
    last_seen_at: lastAgo === null ? null : ago(lastAgo),
    revoked_at: revoked ? ago(HOUR) : null,
    pushes_7d,
  });
  // Every 15 minutes, last 4 min ago: live.
  let b = agentBeat(agent(4 * MIN), every(15 * MIN, 96, 4 * MIN), NOW);
  assert.equal(b.state, "live");
  assert.equal(b.cadence, 15 * MIN);
  assert.equal(cadenceLabel(b.cadence), "every 15 min");
  // The same agent 25 minutes on: past its gap, not live. Its gap alone
  // doesn't make it late, at 31 minutes or at 5 hours.
  assert.equal(agentBeat(agent(25 * MIN), every(15 * MIN, 96, 25 * MIN), NOW).state, "ok");
  assert.equal(agentBeat(agent(31 * MIN), every(15 * MIN, 96, 31 * MIN), NOW).state, "ok");
  // Every 2 h, last 35 min ago: live (within the hour cap); 3 h and 5 h: ok.
  assert.equal(agentBeat(agent(35 * MIN), every(2 * HOUR, 12, 35 * MIN), NOW).state, "live");
  assert.equal(agentBeat(agent(3 * HOUR), every(2 * HOUR, 12, 3 * HOUR), NOW).state, "ok");
  assert.equal(agentBeat(agent(5 * HOUR), every(2 * HOUR, 12, 5 * HOUR), NOW).state, "ok");
  // One push in the log: the week's count stands in (7 a week: daily).
  b = agentBeat(agent(6 * HOUR, 7), [{ at: NOW - 6 * HOUR, feed: "news" }], NOW);
  assert.equal(b.state, "ok");
  assert.equal(cadenceLabel(b.cadence), "daily");
  // Two in a week says nothing about a rhythm yet.
  assert.equal(agentBeat(agent(6 * HOUR, 2), [{ at: NOW - 6 * HOUR, feed: "news" }], NOW).cadence, null);
  // Never pushed, revoked.
  assert.equal(agentBeat(agent(null), [], NOW).state, "never");
  assert.equal(agentBeat(agent(4 * MIN, 9, true), [{ at: NOW - 4 * MIN, feed: "news" }], NOW).state, "revoked");
  // No rhythm known at all: live within the hour, quiet only after 8 days.
  assert.equal(agentBeat(agent(20 * MIN), [], NOW).state, "live");
  assert.equal(agentBeat(agent(3 * 24 * HOUR), [], NOW).state, "ok");
  assert.equal(agentBeat(agent(7.5 * 24 * HOUR), [], NOW).state, "ok");
  assert.equal(agentBeat(agent(8.5 * 24 * HOUR), [], NOW).state, "quiet");
});

test("an agent that rests outside market hours isn't late overnight", () => {
  // Every 15 minutes from 13:30 to 20:00 UTC on Oct 15; now 01:00 UTC on
  // the 16th (8 PM in Chicago).
  const open = Date.parse("2026-10-15T13:30:00Z");
  const pushes = Array.from({ length: 27 }, (_, i) => ({ at: open + i * 15 * MIN, feed: "quotes" }));
  const now = Date.parse("2026-10-16T01:00:00Z");
  const b = agentBeat({ last_seen_at: new Date(open + 26 * 15 * MIN).toISOString(), revoked_at: null, pushes_7d: 130 }, pushes, now);
  assert.equal(b.state, "ok");
  assert.equal(b.cadence, 15 * MIN);
  // And at the weekend, two days on.
  assert.equal(agentBeat({ last_seen_at: new Date(open + 26 * 15 * MIN).toISOString(), revoked_at: null, pushes_7d: 130 }, pushes, now + 2 * 24 * HOUR).state, "ok");
});

test("one run's pushes to several feeds are one beat, not a rhythm", () => {
  // Hourly, three feeds 0.8 s apart each run, 20 runs; now 40 min after the last.
  const runs = Array.from({ length: 20 }, (_, r) => NOW - 40 * MIN - r * HOUR);
  const pushes = runs.flatMap((t) => ["briefs", "metrics", "dashboards"].map((feed, i) => ({ at: t + i * 800, feed })));
  const agent = { last_seen_at: new Date(runs[0] + 1600).toISOString(), revoked_at: null, pushes_7d: 504 };
  const b = agentBeat(agent, pushes, NOW);
  assert.equal(b.cadence, HOUR);
  assert.equal(cadenceLabel(b.cadence), "hourly");
  assert.equal(b.state, "live");
  // Feeds minutes apart in a run (a model call between them): still hourly.
  const spread = runs.flatMap((t) => ["briefs", "metrics", "dashboards"].map((feed, i) => ({ at: t + i * 3 * MIN, feed })));
  assert.equal(agentBeat(agent, spread, NOW).cadence, HOUR);
  // A feed pushed twice in the same minute is one run too.
  const doubled = runs.flatMap((t) => [{ at: t, feed: "briefs" }, { at: t + 20_000, feed: "briefs" }]);
  assert.equal(agentBeat(agent, doubled, NOW).cadence, HOUR);
  // With nothing pushed twice, the week's count is per run: a daily agent
  // that pushes three feeds is daily, not every 8 hours.
  const once = ["briefs", "metrics", "dashboards"].map((feed, i) => ({ at: NOW - 6 * HOUR + i * 800, feed }));
  const daily = agentBeat({ last_seen_at: ago(6 * HOUR), revoked_at: null, pushes_7d: 21 }, once, NOW);
  assert.equal(cadenceLabel(daily.cadence), "daily");
  // Two feeds on their own rhythms: the shorter one is its beat.
  const mixed = [...every2(15 * MIN, 40, "quotes"), ...every2(24 * HOUR, 2, "news")];
  assert.equal(agentBeat(agent, mixed, NOW).cadence, 15 * MIN);
});

function every2(gap, n, feed) {
  return Array.from({ length: n }, (_, i) => ({ at: NOW - i * gap, feed }));
}

test("cadence in words", () => {
  assert.equal(cadenceLabel(null), "");
  assert.equal(cadenceLabel(30 * 1000), "every 1 min");
  assert.equal(cadenceLabel(30 * MIN), "every 30 min");
  assert.equal(cadenceLabel(HOUR), "hourly");
  assert.equal(cadenceLabel(2 * HOUR), "every 2 h");
  assert.equal(cadenceLabel(26 * HOUR), "daily");
  assert.equal(cadenceLabel(3.5 * 24 * HOUR), "every 4 days");
});

test("projects in lanes, the one that needs you first", () => {
  const p = (status, name) => ({ status, name });
  const lanes = projectLanes([p("active", "McFly"), p("blocked", "Onyx"), p("done", "Voice"), p("paused", "Homestead"), p("active", "Two"), p("archived", "Odd")]);
  assert.deepEqual(lanes.map((l) => l.status), ["blocked", "active", "paused", "done"]);
  assert.deepEqual(lanes[1].projects.map((x) => x.name), ["McFly", "Two", "Odd"]);
  assert.deepEqual(projectLanes([]).map((l) => l.projects.length), [0, 0, 0, 0]);
});

test("a project's stages as steps, in its status", () => {
  const stages = ["Plan", "Build", "Review", "Ship"];
  const states = (t) => t.steps.map((s) => s.state);
  const active = stageTrack({ stages, stage: "Build", status: "active" });
  assert.deepEqual(states(active), ["done", "current", "next", "next"]);
  assert.deepEqual([active.current, active.index, active.headline, active.position], ["Build", 1, "Build", "2 of 4"]);
  // Blocked or paused, the stage it's in says so.
  const blocked = stageTrack({ stages, stage: "Review", status: "blocked" });
  assert.deepEqual(states(blocked), ["done", "done", "blocked", "next"]);
  assert.equal(blocked.headline, "Blocked in Review");
  assert.equal(stageTrack({ stages, stage: "Ship", status: "paused" }).headline, "Paused in Ship");
  // Done: through them all, whatever stage it last named.
  const done = stageTrack({ stages, stage: "Build", status: "done" });
  assert.deepEqual(states(done), ["done", "done", "done", "done"]);
  assert.deepEqual([done.current, done.index, done.headline, done.position], [null, 4, "All 4 stages done", "4 of 4"]);
  assert.equal(stageTrack({ stages: ["Ship"], stage: null, status: "done" }).headline, "Done");
  // Stages but no stage yet: none reached.
  const fresh = stageTrack({ stages, stage: null, status: "active" });
  assert.deepEqual(states(fresh), ["next", "next", "next", "next"]);
  assert.deepEqual([fresh.index, fresh.headline, fresh.position], [-1, "Not started", "4 stages"]);
  // No stages, no track: the page shows the status alone.
  assert.equal(stageTrack({ stages: [], stage: null, status: "active" }), null);
});

test("how long a project has been in its stage", () => {
  assert.equal(timeInStage(ago(20 * MIN), NOW), "under an hour");
  assert.equal(timeInStage(ago(5 * HOUR + 10 * MIN), NOW), "5 hr");
  assert.equal(timeInStage(ago(30 * HOUR), NOW), "1 day");
  assert.equal(timeInStage(ago(3 * 24 * HOUR), NOW), "3 days");
  assert.equal(timeInStage(ago(20 * 24 * HOUR), NOW), "2 wk");
  assert.equal(timeInStage(ago(130 * 24 * HOUR), NOW), "4 mo");
  assert.equal(timeInStage(null, NOW), "");
  assert.equal(timeInStage("nope", NOW), "");
  assert.equal(timeInStage(ago(-HOUR), NOW), "under an hour"); // a clock a little ahead
});

test("a brief's lead and its points", () => {
  assert.deepEqual(briefParts("Three things for today.\n\n- The Fed minutes land at 1 PM CT.\n- Your 3 PM call moved to 3:30.\n* Rain clears by noon."), {
    lead: "Three things for today.",
    bullets: ["The Fed minutes land at 1 PM CT.", "Your 3 PM call moved to 3:30.", "Rain clears by noon."],
  });
  assert.deepEqual(briefParts("Quiet hour.\nNothing else."), { lead: "Quiet hour. Nothing else.", bullets: [] });
  assert.deepEqual(briefParts(""), { lead: "", bullets: [] });
  // A dash inside a sentence is not a point.
  assert.deepEqual(briefParts("Up 2% - a good day"), { lead: "Up 2% - a good day", bullets: [] });
});

test("an alert's life left", () => {
  const left = expiryLeft(ago(5 * HOUR), ago(-19 * HOUR), NOW);
  assert.equal(left.ms, 19 * HOUR);
  assert.ok(Math.abs(left.share - 19 / 24) < 1e-9);
  assert.equal(expiryLeft(ago(5 * HOUR), ago(HOUR), NOW).share, 0);
  assert.equal(expiryLeft(ago(5 * HOUR), null, NOW), null);
  assert.equal(expiryLeft(ago(5 * HOUR), ago(6 * HOUR), NOW), null); // expires before it was published
  assert.equal(expiryLeft("nope", ago(-HOUR), NOW), null);
});

test("things grouped by their day in the zone, newest first", () => {
  const items = [{ at: ago(20 * MIN) }, { at: ago(13 * HOUR) }, { at: ago(3 * HOUR) }, { at: ago(30 * HOUR) }, { at: "bad" }];
  const groups = groupByDay(items, (i) => i.at, "America/Chicago", new Date(NOW));
  // 12:30 PM in Chicago: 13 h ago is yesterday at 11:30 PM.
  assert.deepEqual(groups.map((g) => g.label), ["Today", "Yesterday", "Undated"]);
  assert.deepEqual(groups[0].items.map((i) => i.at), [ago(20 * MIN), ago(3 * HOUR)]);
  assert.deepEqual(groups[1].items.map((i) => i.at), [ago(13 * HOUR), ago(30 * HOUR)]);
});

test("activity by day, counted on the calendar", () => {
  const out = activityByDay([ago(MIN), ago(2 * HOUR), ago(13 * HOUR), ago(40 * 24 * HOUR)], 30, NOW, "America/Chicago");
  assert.equal(out.length, 30);
  assert.equal(out[29].day, "2026-10-15");
  assert.equal(out[29].count, 2);
  assert.equal(out[28].count, 1);
  assert.equal(out[0].day, "2026-09-16");
  assert.equal(out.reduce((a, d) => a + d.count, 0), 3);
  // Across the spring change (Chicago, March 8 2026): every day is there once.
  const spring = activityByDay([], 3, Date.parse("2026-03-09T05:30:00Z"), "America/Chicago");
  assert.deepEqual(spring.map((d) => d.day), ["2026-03-07", "2026-03-08", "2026-03-09"]);
});

test("dashboard widgets with runs of statuses as one strip", () => {
  const s = (label) => ({ type: "status", label, state: "ok" });
  const m = { type: "metric", label: "Requests", value: 1 };
  const blocks = widgetBlocks([s("API"), s("Workers"), m, s("Lonely"), m, s("A"), s("B"), s("C")]);
  assert.deepEqual(
    blocks.map((b) => (b.kind === "health" ? `health:${b.items.map((i) => i.label).join(",")}` : `${b.widget.type}:${b.index}`)),
    ["health:API,Workers", "metric:2", "status:3", "metric:4", "health:A,B,C"],
  );
  assert.deepEqual(widgetBlocks([]), []);
});

test("which tile a metric gets", () => {
  assert.equal(metricTile("%", "site.uptime"), "ring");
  assert.equal(metricTile("USD", "sales.today"), "money");
  assert.equal(metricTile("ms", "api.p95"), "latency");
  assert.equal(metricTile(null, "api.p95"), "latency");
  assert.equal(metricTile(null, "orders.open"), "count");
  assert.equal(metricTile("", "steps"), "count");
  assert.equal(metricTile("k", "requests"), "count");
});

test("the Pulse's section colours, as the display picks them", () => {
  assert.equal(sectionColor("s", 0), "#F07F5A");
  assert.equal(sectionColor("social-media", 3), "#F07F5A");
  assert.equal(sectionColor("a", 1), "#F6B94A");
  assert.equal(sectionColor("ads", 1), "#F6B94A");
  assert.equal(sectionColor("i", 2), "#5B7CF5");
  assert.equal(sectionColor("ai-tech", 2), "#5B7CF5");
  assert.equal(sectionColor("x", 0), "#7A64E8");
  assert.equal(sectionColor("y", 5), "#3DB37A");
  // From the names alone.
  assert.equal(sectionColorByName("Social", 0), "#F07F5A");
  assert.equal(sectionColorByName("Paid Ads", 0), "#F6B94A");
  assert.equal(sectionColorByName("AI Tech", 0), "#5B7CF5");
  assert.equal(sectionColorByName("Sports", 2), "#E86A92");
  // "Paid" or "Aid" is not an ad, "Daily" isn't AI.
  assert.equal(sectionColorByName("Aid", 1), "#3DB37A");
  assert.equal(sectionColorByName("Daily", 0), "#7A64E8");
});

test("a dashboard's blocks fill whole rows, in the agent's order", () => {
  // The demo's Ops board: a strip, three numbers, a chart, a list, a note.
  const ops = ["health", "small", "small", "small", "chart", "wide", "wide"];
  assert.deepEqual(bentoSpans(ops, 6), [6, 2, 2, 2, 6, 3, 3]);
  assert.deepEqual(bentoSpans(ops, 2), [2, 1, 1, 2, 2, 2, 2]);
  assert.deepEqual(bentoSpans(ops, 1), [1, 1, 1, 1, 1, 1, 1]);
  // Launch week: a ring, a list, a number.
  assert.deepEqual(bentoSpans(["small", "wide", "small"], 6), [2, 4, 6]);
  // Every row adds up to the width.
  for (const cols of [1, 2, 3, 4, 6]) {
    for (const blocks of [ops, ["small"], ["chart", "small", "small", "wide"], ["wide", "small", "chart", "health", "small"]]) {
      let row = 0;
      for (const span of bentoSpans(blocks, cols)) {
        assert.ok(span >= 1 && span <= cols);
        row += span;
        if (row === cols) row = 0;
        assert.ok(row < cols, `row overflows at ${cols}: ${bentoSpans(blocks, cols)}`);
      }
      assert.equal(row, 0, `last row not full at ${cols}: ${bentoSpans(blocks, cols)}`);
    }
  }
  assert.deepEqual(bentoSpans([], 6), []);
});
