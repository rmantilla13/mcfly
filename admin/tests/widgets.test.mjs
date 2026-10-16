// Dashboard widgets as the preview reads them (lib/widgets.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  areaPath,
  barTotals,
  chartPoints,
  countUpValue,
  decimalPlaces,
  easeOutCubic,
  formatFrame,
  formatMetricValue,
  formatValue,
  lastPoint,
  monotoneTangents,
  parseWidget,
  parseWidgets,
  pointTimeLabel,
  progressPercent,
  seriesRange,
  smoothPath,
  sparklinePath,
  trendTone,
  widgetWide,
} from "../lib/widgets.ts";

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

test("widgetWide gives a chart, a list and a note the whole row, as FeedStore does", () => {
  assert.deepEqual(
    parseWidgets([
      { type: "metric", value: 1 },
      { type: "status", state: "ok" },
      { type: "progress", value: 1 },
      { type: "list", items: [] },
      { type: "text", body: "" },
      { type: "chart", points: [] },
    ]).map(widgetWide),
    [false, false, false, true, true, true],
  );
});

// Every coordinate in a path, as [x, y] pairs.
const coords = (d) => [...d.matchAll(/(-?[\d.]+),(-?[\d.]+)/g)].map((m) => [Number(m[1]), Number(m[2])]);

test("smoothPath runs through every point and never leaves the box", () => {
  const series = [
    [40, 42, 38, 51, 60],
    [0, 0, 100, 0, 0], // a spike: a Catmull-Rom curve would dip below 0 beside it
    [5, 100, 0, 100], // reversals
    [0, 0, 10, 10], // a step: no overshoot at either corner
    [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9],
  ];
  for (const points of series) {
    const path = smoothPath(points, 120, 32, 2);
    assert.match(path, /^M[\d.]+,[\d.]+( C[\d.]+,[\d.]+ [\d.]+,[\d.]+ [\d.]+,[\d.]+)+$/, path);
    // A Bézier stays inside its control points, so bounding them bounds the curve.
    for (const [x, y] of coords(path)) {
      assert.ok(x >= 2 && x <= 118, `x ${x} in ${path}`);
      assert.ok(y >= 2 && y <= 30, `y ${y} in ${path}`);
    }
    // The curve passes through each data point (every segment's end).
    const ends = [coords(path)[0], ...coords(path).filter((_, i) => i % 3 === 0 && i > 0)];
    const expected = chartPoints(points, 120, 32, 2).map((p) => [Math.round(p.x * 100) / 100, Math.round(p.y * 100) / 100]);
    assert.deepEqual(ends, expected);
  }
});

// Series that exercise every branch of the tangents: peaks and troughs,
// flat steps, a steep climb between gentle ones (where Fritsch–Carlson has to
// shorten the tangents), and a long noisy run.
let seed = 11;
const noise = Array.from({ length: 60 }, () => (seed = (seed * 16807) % 2147483647) % 1000);
const SERIES = [
  [1, 3, 2, 8, 8, 4, 9, 0],
  [0, 0, 100, 0, 0],
  [5, 100, 0, 100],
  [0, 1, 10, 11],
  [0, 0.5, 1, 40, 41, 41.5, 90, 90.2],
  [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9],
  noise,
];

// The checks below look at the tangents themselves: smoothPath clamps its
// control points to each segment, which would hide a wrong tangent (as a
// kink) from any check on the path's bounds alone.
test("monotoneTangents levels off at every peak, trough and flat step", () => {
  for (const points of SERIES) {
    const m = monotoneTangents(chartPoints(points, 1000, 1000, 0));
    for (let i = 1; i < points.length - 1; i++) {
      const turns = (points[i] - points[i - 1]) * (points[i + 1] - points[i]) <= 0;
      if (turns) assert.equal(m[i], 0, `point ${i} of ${points}`);
    }
    for (let i = 0; i < points.length - 1; i++) {
      if (points[i] === points[i + 1]) assert.ok(m[i] === 0 && m[i + 1] === 0, `flat ${i} of ${points}`);
    }
  }
});

test("monotoneTangents stays inside Fritsch–Carlson's circle, so the clamp has nothing to do", () => {
  for (const points of SERIES) {
    const p = chartPoints(points, 1000, 1000, 0);
    const m = monotoneTangents(p);
    for (let i = 0; i < p.length - 1; i++) {
      const [a, b] = [p[i], p[i + 1]];
      const secant = (b.y - a.y) / (b.x - a.x);
      if (secant === 0) continue;
      const alpha = m[i] / secant;
      const beta = m[i + 1] / secant;
      // Same direction as the segment, and α² + β² ≤ 9: monotone between its ends.
      assert.ok(alpha >= 0 && beta >= 0, `segment ${i} of ${points}: α ${alpha}, β ${beta}`);
      assert.ok(alpha * alpha + beta * beta <= 9 + 1e-9, `segment ${i} of ${points}: α²+β² ${alpha * alpha + beta * beta}`);
      // So the control points smoothPath derives already sit between the ends.
      const third = (b.x - a.x) / 3;
      const [lo, hi] = [Math.min(a.y, b.y) - 1e-9, Math.max(a.y, b.y) + 1e-9];
      for (const y of [a.y + m[i] * third, b.y - m[i + 1] * third]) assert.ok(y >= lo && y <= hi, `segment ${i} of ${points}: ${y}`);
    }
  }
});

test("smoothPath turns smoothly through every point", () => {
  // Points are evenly spaced, so the handles either side of a point are the
  // same distance across and must rise by the same amount: one tangent, no kink.
  for (const points of SERIES) {
    const c = coords(smoothPath(points, 1000, 1000, 0));
    for (let i = 3; i + 1 < c.length; i += 3) {
      const [, y] = c[i];
      const rise = [y - c[i - 1][1], c[i + 1][1] - y];
      assert.ok(Math.abs(rise[0] - rise[1]) <= 0.011, `point ${i / 3} of ${points}: ${rise}`);
    }
  }
});

test("smoothPath keeps each segment between its two ends", () => {
  const points = [1, 3, 2, 8, 8, 4, 9, 0];
  const c = coords(smoothPath(points, 140, 40, 0));
  for (let i = 0; i + 3 < c.length; i += 3) {
    const [, y0] = c[i];
    const [, y3] = c[i + 3];
    for (const [, y] of [c[i + 1], c[i + 2]]) {
      assert.ok(y >= Math.min(y0, y3) && y <= Math.max(y0, y3), `segment ${i / 3}: ${y} outside ${y0}..${y3}`);
    }
  }
  // Flat neighbours make a flat segment, and a peak has a level tangent.
  assert.match(smoothPath([1, 2, 2, 1], 90, 20, 0), / C[\d.]+,0 [\d.]+,0 60,0 /);
  assert.match(smoothPath([1, 3, 2], 60, 20, 0), /^M0,20 C10,[\d.]+ 20,0 30,0 C40,0 /);
});

test("smoothPath matches Fritsch–Carlson worked by hand", () => {
  // Secants -⅓, -⅔, -⅓; tangents are the mean of their neighbours and need
  // no shortening.
  assert.equal(smoothPath([0, 1, 3, 4], 90, 40, 0), "M0,40 C10,36.67 20,35 30,30 C40,25 50,15 60,10 C70,5 80,3.33 90,0");
  // A steep middle: the means (-⅓, -5/3) give α = 1, β = 5 on the gentle
  // ends, outside the circle, so both are scaled by 3/√26.
  assert.equal(smoothPath([0, 1, 10, 11], 90, 110, 0), "M0,110 C10,108.04 20,109.81 30,100 C40,90.19 50,19.81 60,10 C70,0.19 80,1.96 90,0");
});

test("smoothPath draws what sparklinePath draws for the edge cases", () => {
  assert.equal(smoothPath([], 100, 20), "");
  assert.equal(smoothPath([3], 100, 20, 2), sparklinePath([3], 100, 20, 2));
  assert.equal(smoothPath([5, 5, 5], 100, 20, 0), "M0,10 C16.67,10 33.33,10 50,10 C66.67,10 83.33,10 100,10");
  // Two points: a straight line, its control points on it.
  assert.equal(smoothPath([0, 10], 90, 30, 0), "M0,30 C30,20 60,10 90,0");
});

test("areaPath closes under the line at its own ends", () => {
  assert.equal(areaPath([], 100, 20), "");
  const line = smoothPath([1, 3, 2], 120, 32, 4);
  assert.equal(areaPath([1, 3, 2], 120, 32, 4), `${line} L116,32 L4,32 Z`);
  assert.equal(areaPath([1, 3, 2], 120, 32, 4, 40), `${line} L116,40 L4,40 Z`); // a lower base
  assert.equal(areaPath([7], 100, 20, 2), "M2,10 L98,10 L98,20 L2,20 Z");
});

test("lastPoint is the newest point, where the dot goes", () => {
  assert.deepEqual(lastPoint([0, 10], 100, 20, 0), { x: 100, y: 0 });
  assert.deepEqual(lastPoint([10, 0], 100, 20, 2), { x: 98, y: 18 });
  assert.deepEqual(lastPoint([4], 100, 20, 2), { x: 98, y: 10 });
  assert.equal(lastPoint([], 100, 20), null);
});

test("seriesRange finds the low and the high", () => {
  assert.deepEqual(seriesRange([3, 1, 4, 1, 5]), { min: 1, max: 5, minIndex: 1, maxIndex: 4 });
  assert.equal(seriesRange([]), null);
});

test("trendTone follows the first and last points", () => {
  assert.equal(trendTone([1, 5, 2]), "up");
  assert.equal(trendTone([5, 9, 2]), "down");
  assert.equal(trendTone([2, 9, 2]), "neutral");
  assert.equal(trendTone([2]), "neutral");
});

test("barTotals stacks only what adds height", () => {
  assert.deepEqual(barTotals([{ values: [1, 2] }, { values: [4, -3, Number.NaN] }, { values: [] }]), { totals: [3, 4, 0], max: 4 });
  assert.deepEqual(barTotals([]), { totals: [], max: 0 });
});

test("pointTimeLabel shows the hour for a day of points and the date for more", () => {
  const t = Date.UTC(2026, 9, 14, 15, 5);
  assert.equal(pointTimeLabel(t, 6 * 3_600_000), "3:05 PM UTC");
  assert.equal(pointTimeLabel(t, 30 * 86_400_000), "Oct 14");
  assert.equal(pointTimeLabel(t, 6 * 3_600_000, "America/Chicago"), "10:05 AM CDT");
  assert.equal(pointTimeLabel(t, 6 * 3_600_000, "Not/AZone"), "3:05 PM UTC");
  assert.equal(pointTimeLabel(Number.NaN, 1), "");
});

test("formatValue covers each serializable format", () => {
  assert.equal(formatValue(1240.4), "1,240"); // int by default
  assert.equal(formatValue(3.14159, { format: "decimal" }), "3.14");
  assert.equal(formatValue(2.5, { format: "decimal", decimals: 2 }), "2.50");
  assert.equal(formatValue(12.5, { format: "percent" }), "12.5%");
  assert.equal(formatValue(99.98, { format: "percent", decimals: 1 }), "100.0%");
  assert.equal(formatValue(6420, { format: "compact" }), "6,420");
  assert.equal(formatValue(1240000, { format: "compact" }), "1.2M");
  assert.equal(formatValue(4280, { format: "currency" }), "$4,280.00");
  assert.equal(formatValue(4280, { format: "currency", currency: "EUR", decimals: 0 }), "€4,280");
  assert.equal(formatValue(187.4, { format: "price", currency: "USD" }), "$187.40");
  assert.equal(formatValue(187.4, { format: "price", currency: "nope" }), "$187.40");
  assert.equal(formatValue(5, { format: "int", prefix: "~", suffix: " agents" }), "~5 agents");
  assert.equal(formatValue(Number.NaN), "—");
  // Nothing rounds to "-0".
  assert.equal(formatValue(-0.4), "0");
  assert.equal(formatValue(-0.001, { format: "decimal" }), "0");
  assert.equal(formatValue(-0.001, { format: "currency" }), "$0.00");
});

test("formatValue's metric format is formatMetricValue, byte for byte", () => {
  for (const [value, unit] of [
    [4280, "USD"],
    [99.98, "%"],
    [212, "ms"],
    [1240000, ""],
    [6420, undefined],
    [0.12, "%"],
    [1234567.5, "k"],
  ]) {
    assert.equal(formatValue(value, { format: "metric", unit }), formatMetricValue(value, unit));
  }
});

test("countUpValue eases out and keeps the end value's places", () => {
  assert.equal(easeOutCubic(0), 0);
  assert.equal(easeOutCubic(1), 1);
  assert.equal(easeOutCubic(0.5), 0.875);
  assert.equal(countUpValue(0, 4280, 0), 0);
  assert.equal(countUpValue(0, 4280, 1), 4280);
  assert.ok(Number.isInteger(countUpValue(0, 4280, 0.37))); // whole numbers on the way to a whole number
  assert.equal(countUpValue(0, 4280, 0.5), 3745);
  assert.equal(countUpValue(0, 99.98, 0.5), 87.48); // hundredths on the way to 99.98
  assert.equal(countUpValue(100, 50, 0.5), 56); // counts down as well
  assert.equal(countUpValue(0, 10, 0.5, 2), 8.75); // or to the places asked for
  assert.equal(countUpValue(-1, 0, 0.9999), 0); // never "-0"
  assert.equal(decimalPlaces(4280), 0);
  assert.equal(decimalPlaces(99.98), 2);
  assert.equal(decimalPlaces(Number.NaN), 0);
});

test("formatFrame counts toward a compact value in compact steps", () => {
  const metric = { format: "metric", unit: "" };
  assert.equal(formatFrame(312407, 1240000, metric), "312.4K");
  assert.equal(formatFrame(1100000, 1240000, { format: "metric", unit: "req" }), "1.1M req");
  assert.equal(formatFrame(1240000, 1240000, metric), formatMetricValue(1240000, "")); // the last frame is the real text
  assert.equal(formatFrame(523, 25000, { format: "compact" }), "523");
  assert.equal(formatFrame(18000, 25000, { format: "compact", prefix: "~" }), "~18K");
  // Anything that doesn't end compact is formatted as itself.
  assert.equal(formatFrame(1500, 4280, { format: "metric", unit: "USD" }), formatValue(1500, { format: "metric", unit: "USD" }));
  assert.equal(formatFrame(2000000, 4000000, { format: "metric", unit: "EUR" }), "€2,000,000.00");
  assert.equal(formatFrame(87.48, 99.98, { format: "percent" }), "87.48%");
});
