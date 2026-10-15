// Dashboard widgets as the preview reads them (lib/widgets.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { formatMetricValue, parseWidget, parseWidgets, progressPercent, sparklinePath } from "../lib/widgets.ts";

test("reads each widget type the migration allows", () => {
  assert.deepEqual(parseWidget({ type: "metric", label: "Requests", value: 1240000, unit: "", delta_pct: 4.2 }), {
    type: "metric",
    label: "Requests",
    value: 1240000,
    delta_pct: 4.2,
  });
  assert.deepEqual(parseWidget({ type: "status", label: "API", state: "ok", detail: "All checks passing" }), {
    type: "status",
    label: "API",
    state: "ok",
    detail: "All checks passing",
  });
  assert.deepEqual(parseWidget({ type: "progress", label: "Storage", value: 68, max: 100, unit: "%" }), {
    type: "progress",
    label: "Storage",
    value: 68,
    max: 100,
    unit: "%",
  });
  assert.deepEqual(parseWidget({ type: "list", title: "On call", items: ["Ricky", "Pager quiet"] }), {
    type: "list",
    title: "On call",
    items: ["Ricky", "Pager quiet"],
  });
  assert.deepEqual(parseWidget({ type: "text", title: "Note", body: "Deploy tonight." }), { type: "text", title: "Note", body: "Deploy tonight." });
  assert.deepEqual(parseWidget({ type: "chart", label: "Requests per hour", points: [1, 2, 3], unit: "k" }), {
    type: "chart",
    label: "Requests per hour",
    points: [1, 2, 3],
    unit: "k",
  });
});

test("tolerates what agents actually send", () => {
  assert.equal(parseWidget({ type: "metric", value: "1,240" }).value, 1240);
  assert.equal(parseWidget({ type: "status", label: "x", state: "flying" }).state, "unknown");
  assert.equal(parseWidget({ type: "progress", value: 3 }).max, 100);
  assert.equal(parseWidget({ type: "progress", value: 3, max: 0 }).max, 100);
  assert.deepEqual(parseWidget({ type: "list", items: ["a", 7, { text: "b" }, ""] }).items, ["a", "7", "b"]);
  assert.deepEqual(parseWidget({ type: "chart", points: [1, "2", "x", null] }).points, [1, 2]);
  assert.equal(parseWidget({ type: "text" }).body, "");
});

test("drops what it can't read", () => {
  for (const bad of [null, "metric", { type: "video" }, { type: "metric" }, { type: "metric", value: "n/a" }, { type: "progress" }]) {
    assert.equal(parseWidget(bad), null, JSON.stringify(bad));
  }
  assert.equal(parseWidgets([{ type: "text", body: "ok" }, { type: "video" }, 3]).length, 1);
  assert.deepEqual(parseWidgets("nope"), []);
});

test("sparklinePath spans the box left to right", () => {
  assert.equal(sparklinePath([0, 10], 100, 20, 0), "M0,20 L100,0");
  assert.equal(sparklinePath([5, 5, 5], 100, 20, 0), "M0,10 L50,10 L100,10"); // flat: the middle
  assert.equal(sparklinePath([3], 100, 20, 2), "M2,10 L98,10"); // one point: a line across
  assert.equal(sparklinePath([], 100, 20), "");
  const path = sparklinePath([40, 42, 38, 51, 60], 120, 32);
  assert.match(path, /^M2,/);
  assert.match(path, / L118,2$/); // the last point is the max, at the top
});

test("progressPercent clamps", () => {
  assert.equal(progressPercent(14, 20), 70);
  assert.equal(progressPercent(25, 20), 100);
  assert.equal(progressPercent(-1, 20), 0);
  assert.equal(progressPercent(5, 0), 0);
});

test("formatMetricValue reads like the display", () => {
  assert.equal(formatMetricValue(4280, "USD"), "$4,280.00");
  assert.equal(formatMetricValue(99.98, "%"), "99.98%");
  assert.equal(formatMetricValue(212, "ms"), "212 ms");
  assert.equal(formatMetricValue(1240000, ""), "1.2M");
  assert.equal(formatMetricValue(6420, null), "6,420");
  assert.equal(formatMetricValue(0.12, "%"), "0.12%");
  assert.equal(formatMetricValue(null, "USD"), "—");
});
