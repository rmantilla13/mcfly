// Made dashboards: the templates, reading a recipe, and the demo's drawing
// (lib/dashboard-sources.ts, lib/dashboard-draw.ts). The database's own
// drawing is checked in backend/tests/dashboards_test.sql.
import assert from "node:assert/strict";
import { test } from "node:test";
import { drawDashboard, whenLabel } from "../lib/dashboard-draw.ts";
import { DASHBOARD_TEMPLATES, PART_KINDS, blankPart, describePart, findTemplate, readPart, readParts, templateParts } from "../lib/dashboard-sources.ts";
import { parseWidgets } from "../lib/widgets.ts";

test("every template reads back as itself and has a part", () => {
  const ids = new Set();
  for (const t of DASHBOARD_TEMPLATES) {
    assert.ok(/^[a-z0-9][a-z0-9-]{0,39}$/.test(t.id), `${t.id} is a usable template id`);
    assert.ok(!ids.has(t.id), `${t.id} is unique`);
    ids.add(t.id);
    assert.ok(t.parts.length >= 1 && t.parts.length <= 20, `${t.id} has 1 to 20 parts`);
    assert.deepEqual(readParts(t.parts), t.parts, `${t.id} needs no cleaning`);
    assert.ok(t.title.length <= 80);
  }
  assert.equal(findTemplate("markets")?.label, "Markets");
  assert.equal(findTemplate("nope"), null);
});

test("a template's parts are a copy", () => {
  const t = findTemplate("today");
  const parts = templateParts(t);
  parts[0].days = 31;
  assert.equal(t.parts[0].days, 1);
});

test("a blank part of every kind reads back", () => {
  for (const { kind } of PART_KINDS) {
    const part = blankPart(kind);
    assert.equal(part.from, kind);
    // A note needs words before it is a part.
    assert.deepEqual(readPart(part), kind === "note" ? null : part);
  }
});

test("reading a part cleans what it can and drops what it can't", () => {
  assert.deepEqual(readPart({ from: "quotes", symbols: [" aapl ", "AAPL", "bad symbol!", 4], show: "candles", limit: "40" }), {
    from: "quotes",
    symbols: ["AAPL"],
    show: "tiles",
    limit: 12,
  });
  assert.deepEqual(readPart({ from: "metrics", keys: ["API.P95"], group: "  ", show: "chart", title: " Speed " }), {
    from: "metrics",
    keys: ["api.p95"],
    show: "chart",
    title: "Speed",
  });
  assert.deepEqual(readPart({ from: "calendar", calendars: ["Work"], days: 6 }), { from: "calendar", calendars: ["Work"], days: 7 }, "days snap to a choice");
  assert.deepEqual(readPart({ from: "calendar", days: 1 }), { from: "calendar", calendars: [], days: 1 });
  assert.deepEqual(readPart({ from: "todos", kind: "chores" }), { from: "todos", kind: "all" });
  assert.deepEqual(readPart({ from: "brief", kind: "weekly", agent: "not-an-id" }), { from: "brief" });
  assert.deepEqual(readPart({ from: "projects", projects: ["00000000-0000-0000-0000-00000000A004", "x"] }), {
    from: "projects",
    projects: ["00000000-0000-0000-0000-00000000a004"],
    show: "progress",
  });
  assert.deepEqual(readPart({ from: "agents", hours: 30 }), { from: "agents", agents: [], hours: 24 });
  assert.equal(readPart({ from: "note", body: "   " }), null);
  assert.equal(readPart({ from: "weather" }), null);
  assert.equal(readPart("quotes"), null);
  assert.equal(readParts(Array.from({ length: 30 }, () => ({ from: "todos" }))).length, 20, "at most twenty parts");
  assert.deepEqual(readParts("nope"), []);
});

test("a part says where it pulls from", () => {
  const options = {
    symbols: [],
    metrics: [{ key: "api.p95", label: "API p95", group: "Ops", unit: "ms", hidden: false }],
    projects: [{ id: "p1", name: "McFly", status: "active", agent_name: "GitHub" }],
    calendars: [],
    news_sections: [{ key: "tech", name: "Tech" }],
    agents: [{ id: "a1", name: "Grok", color: "#7A64E8", has_key: true }],
    timezone: "UTC",
  };
  assert.equal(describePart({ from: "quotes", symbols: ["AAPL", "NVDA"], show: "tiles" }), "AAPL, NVDA as tiles");
  assert.equal(describePart({ from: "quotes", symbols: ["A", "B", "C", "D", "E"], show: "chart", limit: 2 }), "A, B, C and 2 more as charts, up to 2");
  assert.equal(describePart({ from: "metrics", keys: ["api.p95"], show: "tiles" }, options), "API p95 as tiles");
  assert.equal(describePart({ from: "metrics", keys: [], group: "Ops", show: "chart" }), "Every Ops metric as charts");
  assert.equal(describePart({ from: "projects", projects: ["p1"], show: "list" }, options), "McFly, as a list");
  assert.equal(describePart({ from: "calendar", calendars: [], days: 1 }), "Every calendar, today");
  assert.equal(describePart({ from: "calendar", calendars: ["Work"], days: 7 }), "Work, the next 7 days");
  assert.equal(describePart({ from: "todos", kind: "reminder" }), "Reminders");
  assert.equal(describePart({ from: "news", section: "tech", limit: 3 }, options), "Tech headlines, up to 3");
  assert.equal(describePart({ from: "brief", kind: "daily", agent: "a1" }, options), "The newest daily brief from Grok");
  assert.equal(describePart({ from: "agents", agents: [], hours: 72 }), "Every agent with a key, quiet after 3 days");
  assert.equal(describePart({ from: "note", body: "x", title: "Hi" }), "A note: Hi");
});

// ─────────────────────────── The demo's drawing ───────────────────────────

const NOW = Date.parse("2026-10-16T15:00:00Z"); // 10 AM in Chicago
const at = (hoursFromNow) => new Date(NOW + hoursFromNow * 3_600_000).toISOString();
const DATA = {
  now: NOW,
  timeZone: "America/Chicago",
  symbols: [
    { symbol: "SPY", sort_order: 0, hidden: false },
    { symbol: "AAPL", sort_order: 1, hidden: false },
    { symbol: "OLD", sort_order: 2, hidden: true },
  ],
  quotes: [
    { id: 1, symbol: "AAPL", name: "Apple", price: 245.12, change: 1.42, change_pct: 0.58, currency: "USD", as_of: at(-24) },
    { id: 2, symbol: "AAPL", name: "Apple", price: 247.9, change: 2.78, change_pct: 1.13, currency: "USD", as_of: at(0) },
    { id: 3, symbol: "SPY", name: "S&P 500 ETF", price: 668.42, change: null, change_pct: 0.32, currency: "USD", as_of: at(0) },
  ],
  metricSettings: [
    { key: "api.p95", label: "API p95", group_name: "Ops", sort_order: 0, hidden: false },
    { key: "steps", label: null, group_name: "Me", sort_order: 1, hidden: false },
  ],
  metrics: [
    { id: 1, key: "api.p95", label: null, value: 230, unit: "ms", delta: null, delta_pct: null, as_of: at(-24) },
    { id: 2, key: "api.p95", label: null, value: 212, unit: "ms", delta: -18, delta_pct: null, as_of: at(0) },
    { id: 3, key: "steps", label: "Steps", value: 6420, unit: null, delta: null, delta_pct: -8, as_of: at(0) },
  ],
  projects: [
    { id: "p1", name: "McFly", status: "active", progress: 62, summary: "", next_step: "Ship it", sort_order: 0 },
    { id: "p2", name: "Onyx", status: "blocked", progress: null, summary: "Waiting on review", next_step: null, sort_order: 1 },
    { id: "p3", name: "Old", status: "done", progress: 100, summary: "", next_step: null, sort_order: 2 },
  ],
  events: [
    { calendar: "Work", title: "Standup", starts_at: at(-1), ends_at: at(-0.5), all_day: false },
    { calendar: "Work", title: "Review", starts_at: at(5.5), ends_at: at(6), all_day: false },
    { calendar: "Home", title: "Flight", starts_at: at(48), ends_at: at(51), all_day: false },
    { calendar: "Home", title: "Launch day", starts_at: "2026-10-20T05:00:00Z", ends_at: "2026-10-21T04:59:59Z", all_day: true },
  ],
  todos: [
    { id: "b", kind: "todo", title: "No date", due_at: null, all_day: false, done_at: null, created_at: at(-5) },
    { id: "a", kind: "todo", title: "Call the bank", due_at: at(3), all_day: false, done_at: null, created_at: at(-3) },
    { id: "c", kind: "todo", title: "Done", due_at: null, all_day: false, done_at: at(-1), created_at: at(-9) },
    { id: "d", kind: "reminder", title: "Water plants", due_at: at(26), all_day: false, done_at: null, created_at: at(-2) },
  ],
  news: [
    { section_key: "tech", section_name: "Tech", section_order: 1, position: 0, headline: "Chips" },
    { section_key: "world", section_name: "World", section_order: 0, position: 1, headline: "Second" },
    { section_key: "world", section_name: "World", section_order: 0, position: 0, headline: "First" },
  ],
  briefs: [
    { agent_id: "g", title: "Morning", body: "Three things.", kind: "daily", published_at: at(-3), expires_at: null },
    { agent_id: "g", title: "Hourly", body: "Quiet.", kind: "hourly", published_at: at(-0.3), expires_at: null },
    { agent_id: "g", title: "Gone", body: "x", kind: "alert", published_at: at(-0.1), expires_at: at(-0.05) },
  ],
  agents: [
    { id: "g", name: "Grok", has_key: true, revoked: false, last: { created_at: at(-0.25), status: "ok", message: null } },
    { id: "s", name: "Stocks", has_key: true, revoked: false, last: { created_at: at(-30), status: "ok", message: null } },
    { id: "x", name: "Broken", has_key: true, revoked: false, last: { created_at: at(-1), status: "error", message: "bad key" } },
    { id: "n", name: "New", has_key: true, revoked: false, last: null },
    { id: "m", name: "McFly", has_key: false, revoked: false, last: null },
  ],
};
const draw = (parts) => drawDashboard(readParts(parts), DATA);

test("times read the way the database writes them", () => {
  assert.equal(whenLabel(at(5.5), false, "America/Chicago", NOW), "Today 3:30 PM");
  assert.equal(whenLabel(at(24), false, "America/Chicago", NOW), "Tomorrow 10:00 AM");
  assert.equal(whenLabel(at(-24), true, "America/Chicago", NOW), "Yesterday");
  assert.equal(whenLabel("2026-10-20T05:00:00Z", true, "America/Chicago", NOW), "Tue Oct 20");
  assert.equal(whenLabel(at(96), false, "UTC", NOW), "Tue Oct 20 3:00 PM");
});

test("quotes: every visible symbol in order, or the ones picked", () => {
  assert.deepEqual(draw([{ from: "quotes" }]), [
    { type: "metric", label: "SPY", value: 668.42, unit: "USD", delta_pct: 0.32 },
    { type: "metric", label: "AAPL", value: 247.9, unit: "USD", delta: 2.78, delta_pct: 1.13 },
  ]);
  assert.deepEqual(draw([{ from: "quotes", symbols: ["AAPL"], show: "chart" }]), [
    { type: "chart", label: "Apple (AAPL)", unit: "USD", points: [245.12, 247.9] },
  ]);
  assert.deepEqual(draw([{ from: "quotes", symbols: ["ZZZZ"] }]), [{ type: "text", title: "Markets", body: "No quotes yet for ZZZZ." }]);
});

test("metrics: picked, by group, or all; the console's label first", () => {
  assert.deepEqual(draw([{ from: "metrics", keys: ["api.p95"] }]), [{ type: "metric", label: "API p95", value: 212, unit: "ms", delta: -18 }]);
  assert.deepEqual(draw([{ from: "metrics", group: "Me" }]), [{ type: "metric", label: "Steps", value: 6420, delta_pct: -8 }]);
  assert.deepEqual(draw([{ from: "metrics", keys: ["api.p95"], show: "chart" }])[0].points, [230, 212]);
  assert.deepEqual(draw([{ from: "metrics", keys: ["nope"], title: "Shop" }]), [{ type: "text", title: "Shop", body: "No numbers yet." }]);
});

test("projects: active and blocked ones, as rings and statuses or a list", () => {
  assert.deepEqual(draw([{ from: "projects" }]), [
    { type: "progress", label: "McFly", value: 62, max: 100, unit: "%" },
    { type: "status", label: "Onyx", state: "warn", detail: "Waiting on review" },
  ]);
  assert.deepEqual(draw([{ from: "projects", show: "list", title: "Next" }]), [{ type: "list", title: "Next", items: ["McFly · Ship it", "Onyx"] }]);
});

test("the calendar: what hasn't ended, inside the window", () => {
  assert.deepEqual(draw([{ from: "calendar", days: 1 }]), [{ type: "list", title: "Today", items: ["Today 3:30 PM · Review"] }]);
  assert.deepEqual(draw([{ from: "calendar", days: 7, calendars: ["Home"] }]), [
    { type: "list", title: "Next 7 days", items: ["Sun Oct 18 10:00 AM · Flight", "Tue Oct 20 · Launch day"] },
  ]);
  assert.deepEqual(draw([{ from: "calendar", days: 1, calendars: ["Home"] }]), [{ type: "text", title: "Today", body: "Nothing on the calendar." }]);
});

test("todos: open ones, dated first", () => {
  assert.deepEqual(draw([{ from: "todos", kind: "todo" }]), [{ type: "list", title: "To do", items: ["Call the bank · Today 1:00 PM", "No date"] }]);
  assert.deepEqual(draw([{ from: "todos", kind: "reminder" }]), [{ type: "list", title: "Reminders", items: ["Water plants · Tomorrow 12:00 PM"] }]);
});

test("news, a brief, the agents and a note", () => {
  assert.deepEqual(draw([{ from: "news", limit: 2 }]), [{ type: "list", title: "Headlines", items: ["First", "Second"] }]);
  assert.deepEqual(draw([{ from: "news", section: "tech" }]), [{ type: "list", title: "Tech", items: ["Chips"] }]);
  assert.deepEqual(draw([{ from: "brief" }]), [{ type: "text", title: "Hourly", body: "Quiet." }], "the newest unexpired brief");
  assert.deepEqual(draw([{ from: "brief", kind: "daily" }])[0].title, "Morning");
  assert.deepEqual(
    draw([{ from: "agents", hours: 24 }]).map((w) => [w.label, w.state, w.detail]),
    [
      ["Broken", "down", "Last push failed: bad key"],
      ["Grok", "ok", "Last push Today 9:45 AM"],
      ["New", "unknown", "No pushes yet"],
      ["Stocks", "warn", "Quiet since Yesterday 4:00 AM"],
    ],
    "keyed agents, by name; the keyless McFly is left out",
  );
  assert.deepEqual(draw([{ from: "note", body: "Hello" }]), [{ type: "text", body: "Hello" }]);
});

test("a board always has a widget, and every one is one the screens draw", () => {
  assert.deepEqual(drawDashboard([], DATA), [{ type: "text", body: "Nothing to show yet." }]);
  for (const t of DASHBOARD_TEMPLATES) {
    const widgets = drawDashboard(t.parts, DATA);
    assert.ok(widgets.length >= 1 && widgets.length <= 40, `${t.id} draws 1 to 40 widgets`);
    assert.equal(parseWidgets(widgets).length, widgets.length, `${t.id}'s widgets all parse`);
  }
  assert.equal(drawDashboard(Array.from({ length: 20 }, () => ({ from: "agents", agents: [], hours: 24 })), DATA).length, 40, "at most 40");
});
