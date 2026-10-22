// A day's conflicts, back-to-back runs and busiest stretch (lib/day-load.ts):
// the app's cases (apple/McFlyKit DayLoadTests.swift), in the display's zone.
import assert from "node:assert/strict";
import { test } from "node:test";
import { dayLoad, heatColor, loadKind } from "../lib/day-load.ts";

const TZ = "America/Chicago";
const DAY = "2026-10-22"; // CDT, UTC-5
// "9:30" on the day (or the day before / after), as an ISO instant.
const at = (h, m = 0, dayOffset = 0) => new Date(Date.UTC(2026, 9, 22 + dayOffset, h + 5, m)).toISOString();
let n = 0;
const ev = (start, end, allDay = false) => ({ id: `e${++n}`, starts_at: start, ends_at: end, all_day: allDay });
const kinds = (load, list) => list.map((e) => loadKind(load, e.id));
const ms = (iso) => Date.parse(iso);

test("overlaps are conflicts", () => {
  const a = ev(at(9), at(10));
  const b = ev(at(9, 30), at(10, 30));
  const c = ev(at(14), at(15));
  const load = dayLoad([a, b, c], DAY, TZ);
  assert.deepEqual(load.conflicts, [{ start: ms(at(9, 30)), end: ms(at(10)) }]);
  assert.deepEqual(kinds(load, [a, b, c]), ["conflict", "conflict", "clear"]);
});

test("an event inside another conflicts, and overlaps join", () => {
  const long = ev(at(9), at(12));
  const inside = ev(at(10), at(10, 30));
  const late = ev(at(11), at(12, 30));
  const load = dayLoad([late, inside, long], DAY, TZ);
  assert.deepEqual(load.conflicts.map((s) => [s.start, s.end]), [[ms(at(10)), ms(at(10, 30))], [ms(at(11)), ms(at(12))]]);
  assert.deepEqual(kinds(load, [long, inside, late]), ["conflict", "conflict", "conflict"]);
});

test("back to back is five minutes or less", () => {
  const a = ev(at(9), at(10));
  const b = ev(at(10), at(10, 30)); // the same minute
  const c = ev(at(10, 35), at(11)); // five minutes later
  const d = ev(at(11, 6), at(12)); // six: not back to back
  const load = dayLoad([a, b, c, d], DAY, TZ);
  assert.deepEqual(kinds(load, [a, b, c, d]), ["backToBack", "backToBack", "backToBack", "clear"]);
  assert.equal(load.backToBackCount, 2);
  assert.deepEqual(load.conflicts, []);
});

test("a conflict outranks back to back", () => {
  const a = ev(at(9), at(10));
  const b = ev(at(10), at(11));
  const c = ev(at(10, 30), at(11, 30));
  assert.deepEqual(kinds(dayLoad([a, b, c], DAY, TZ), [a, b, c]), ["backToBack", "conflict", "conflict"]);
});

test("all-day takes no time, and a multi-day event counts only its part of the day", () => {
  const holiday = ev(at(0), at(0, 0, 1), true);
  const overnight = ev(at(22, 0, -1), at(1));
  const early = ev(at(0, 30), at(2));
  const load = dayLoad([holiday, overnight, early], DAY, TZ);
  assert.equal(loadKind(load, holiday.id), "clear");
  assert.deepEqual(load.conflicts, [{ start: ms(at(0, 30)), end: ms(at(1)) }]);
  assert.deepEqual(dayLoad([overnight, early], "2026-10-21", TZ).conflicts, []);
});

test("the busiest stretch needs two events and an hour booked", () => {
  // 10–12:30 is packed (15 minutes free before lunch still joins it); the
  // afternoon has one short call.
  const load = dayLoad(
    [ev(at(9), at(9, 15)), ev(at(10), at(11)), ev(at(11), at(11, 30)), ev(at(11, 45), at(12, 30)), ev(at(15), at(15, 30))],
    DAY,
    TZ,
  );
  assert.deepEqual(load.busiest, { start: ms(at(10)), end: ms(at(12, 30)) });
  const slot = (h, m) => (h * 60 + m) / 15;
  assert.ok(load.heat[slot(11, 0)] > load.heat[slot(15, 0)]);
  assert.equal(load.heat[slot(3, 0)], 0);
  assert.ok(load.heat.every((h) => h >= 0 && h <= 1));
  assert.equal(load.heat.length, 96);
  // Two half-hour calls aren't busy; nor is one long dinner beside a packed hour of two.
  assert.equal(dayLoad([ev(at(9), at(9, 30)), ev(at(14), at(14, 30))], DAY, TZ).busiest, null);
  const dinner = dayLoad([ev(at(18), at(21)), ev(at(9), at(9, 40)), ev(at(9, 45), at(10, 15))], DAY, TZ);
  assert.deepEqual(dinner.busiest, { start: ms(at(9)), end: ms(at(10, 15)) });
  assert.equal(dayLoad([ev(at(9), at(17))], DAY, TZ).busiest, null);
});

test("overlaps count once toward busy", () => {
  const load = dayLoad([ev(at(9), at(10)), ev(at(9), at(10)), ev(at(9), at(10))], DAY, TZ);
  assert.deepEqual(load.busiest, { start: ms(at(9)), end: ms(at(10)) });
  assert.equal(load.heat[9 * 4 + 2], 0.5); // 9:30: one booked hour of the two around it
});

test("an empty day, a short one, and the heat's colours", () => {
  const empty = dayLoad([], DAY, TZ);
  assert.deepEqual([empty.conflicts, empty.backToBackCount, empty.busiest], [[], 0, null]);
  // The spring-forward day has 23 hours.
  assert.equal(dayLoad([], "2026-03-08", TZ).heat.length, 92);
  assert.equal(heatColor(0), null);
  assert.match(heatColor(0.3), /^rgb\(242 169 59/);
  assert.match(heatColor(0.8), /^rgb\(229 96 77/);
});
