// Quote, metric and push-log series (lib/series.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { bucketHourly, dailyCloses, downsample, median, rangeOf, robustZ, usualSwing, windowChange, withLatest } from "../lib/series.ts";

const H = 3_600_000;
const line = (values, step = H) => values.map((v, i) => ({ t: i * step, v }));

test("downsample keeps the ends, the count and the spikes", () => {
  const flat = Array.from({ length: 100 }, (_, i) => (i === 57 ? 100 : 10 + (i % 3)));
  const out = downsample(line(flat), 10);
  assert.equal(out.length, 10);
  assert.deepEqual(out[0], { t: 0, v: 10 });
  assert.deepEqual(out.at(-1), { t: 99 * H, v: flat[99] });
  assert.ok(out.some((p) => p.v === 100), "the spike survives");
  assert.ok(out.every((p, i) => i === 0 || p.t > out[i - 1].t), "still in time order");
});

test("downsample with few points or a tiny n", () => {
  const pts = line([1, 2, 3]);
  const same = downsample(pts, 30);
  assert.deepEqual(same, pts);
  assert.notEqual(same, pts, "a copy, not the caller's array");
  assert.deepEqual(downsample(pts, 2), [pts[0], pts[2]]);
  assert.deepEqual(downsample(pts, 1), [pts[2]]);
  assert.deepEqual(downsample(pts, 0), []);
  assert.deepEqual(downsample([], 5), []);
});

test("window change, first to last", () => {
  assert.deepEqual(windowChange(line([100, 90, 110])), { abs: 10, pct: 10 });
  assert.deepEqual(windowChange(line([-50, -25])), { abs: 25, pct: 50 });
  assert.deepEqual(windowChange(line([0, 5])), { abs: 5, pct: null });
  assert.equal(windowChange(line([5])), null);
  assert.equal(windowChange([]), null);
});

test("range and where the latest value sits in it", () => {
  assert.deepEqual(rangeOf(line([10, 30, 20])), { min: 10, max: 30, position: 0.5 });
  assert.equal(rangeOf(line([10, 30, 30])).position, 1);
  assert.equal(rangeOf(line([7, 7, 7])).position, 0.5);
  assert.equal(rangeOf([]), null);
});

test("hourly buckets are rolling hours ending now, oldest first", () => {
  const now = Date.UTC(2026, 9, 14, 15, 0);
  const counts = bucketHourly(
    [
      now - 1 * 60_000, // last 60 minutes
      now - 59 * 60_000,
      now - 60 * 60_000, // exactly an hour ago: the bucket before
      now - 2.5 * H,
      now - 5 * H, // outside a 4-hour window
      now + 30_000, // the database clock a little ahead: still now
      Number.NaN,
    ],
    4,
    now,
  );
  assert.deepEqual(counts, [0, 1, 1, 3]);
  assert.deepEqual(bucketHourly([], 3, now), [0, 0, 0]);
  assert.deepEqual(bucketHourly([now], 0, now), []);
});

test("median", () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([4, 1, 3, 2]), 2.5);
  assert.equal(median([]), null);
});

test("robust z flags the last value against the ones before", () => {
  const usual = [240, 238, 243, 241, 239, 244, 240, 242, 237, 241];
  assert.ok(robustZ([...usual, 212]) <= -3);
  assert.ok(Math.abs(robustZ([...usual, 241])) < 1);
  // One old spike doesn't hide the next unusual value.
  assert.ok(robustZ([...usual.slice(0, 4), 900, ...usual.slice(4), 300]) >= 3);
});

test("robust z with too little or no spread is null, never Infinity", () => {
  assert.equal(robustZ([1, 2, 3, 4, 5, 6, 7, 8]), null, "7 earlier points is too few");
  assert.equal(robustZ([5, 5, 5, 5, 5, 5, 5, 5, 5, 9]), null, "no spread at all");
  // Mostly one value (MAD is 0): the mean deviation stands in.
  const z = robustZ([20, 20, 20, 20, 20, 21, 20, 20, 19, 20, 30]);
  assert.ok(Number.isFinite(z) && z >= 3);
});

test("daily closes in the zone", () => {
  const TZ = "America/Chicago";
  const pts = [
    { t: Date.parse("2026-10-13T15:00:00Z"), v: 1 }, // Oct 13, 10 am
    { t: Date.parse("2026-10-14T04:30:00Z"), v: 2 }, // Oct 13, 11:30 pm: the 13th's close
    { t: Date.parse("2026-10-14T05:30:00Z"), v: 3 }, // Oct 14, 12:30 am
    { t: Date.parse("2026-10-14T20:00:00Z"), v: 4 },
  ];
  assert.deepEqual(dailyCloses(pts, TZ).map((p) => p.v), [2, 4]);
  assert.deepEqual(dailyCloses(pts, "UTC").map((p) => p.v), [1, 4]);
});

test("daily closes across a DST change, and none from nothing", () => {
  // Chicago falls back on 2026-11-01: that day is 25 hours long.
  const TZ = "America/Chicago";
  const at = (iso, v) => ({ t: Date.parse(iso), v });
  const pts = [
    at("2026-11-01T05:30:00Z", 1), // 00:30 CDT, Nov 1
    at("2026-11-01T06:30:00Z", 2), // 01:30 CDT
    at("2026-11-01T07:30:00Z", 3), // 01:30 CST, the hour again
    at("2026-11-02T05:30:00Z", 4), // 23:30 CST, still Nov 1
    at("2026-11-02T06:30:00Z", 5), // 00:30 CST, Nov 2
  ];
  assert.deepEqual(dailyCloses(pts, TZ).map((p) => p.v), [4, 5]);
  assert.deepEqual(dailyCloses([], "Not/AZone"), [], "nothing to group, so the zone isn't touched");
});

test("the latest reading goes on the end only when it is newer", () => {
  const history = line([10, 11, 12]);
  const latest = new Date(3 * H).toISOString();
  const out = withLatest(history, latest, 13);
  assert.deepEqual(out.map((p) => p.v), [10, 11, 12, 13]);
  assert.equal(out.at(-1).t, 3 * H);
  assert.equal(history.length, 3, "the shared history is left alone");
  assert.equal(withLatest(history, new Date(2 * H).toISOString(), 99), history, "same time: already there");
  assert.equal(withLatest(history, new Date(H).toISOString(), 99), history, "older: not the latest after all");
  assert.equal(withLatest(history, null, 13), history);
  assert.equal(withLatest(history, latest, null), history);
  assert.equal(withLatest(history, "not a date", 13), history);
  assert.deepEqual(withLatest([], latest, 13), [], "no history, no line to extend");
});

test("usual swing leaves today's move out", () => {
  const closes = [100, 101, 100, 101, 100, 101, 100];
  const calm = usualSwing(closes);
  assert.ok(calm > 0.9 && calm < 1.1, `about 1%: ${calm}`);
  assert.equal(usualSwing([...closes.slice(0, -1), 130]), calm, "a big last day doesn't change the usual");
  assert.equal(usualSwing([100, 101, 102, 103]), null, "too few days");
  assert.equal(usualSwing([100, 100, 100, 100, 100, 100, 100]), null, "no movement at all");
});
