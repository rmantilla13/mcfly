// Calendar events by day in the display's zone (lib/events.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { dayKey, dayLabel, formatEventTime, groupEventsByDay, safeTimeZone, zonedMidnightUtc } from "../lib/events.ts";

const CHICAGO = "America/Chicago";
const NOW = new Date("2026-10-14T17:00:00Z"); // noon in Chicago (CDT)

test("dayKey is the zone's day, not UTC's", () => {
  assert.equal(dayKey("2026-10-15T02:00:00Z", CHICAGO), "2026-10-14"); // 9 PM the day before
  assert.equal(dayKey("2026-10-15T02:00:00Z", "UTC"), "2026-10-15");
  assert.equal(dayKey("garbage", CHICAGO), "invalid");
});

test("zonedMidnightUtc finds the zone's midnight, across DST", () => {
  assert.equal(zonedMidnightUtc("2026-10-14", CHICAGO), "2026-10-14T05:00:00.000Z"); // CDT, UTC-5
  assert.equal(zonedMidnightUtc("2026-12-14", CHICAGO), "2026-12-14T06:00:00.000Z"); // CST, UTC-6
  assert.equal(zonedMidnightUtc("2026-11-01", CHICAGO), "2026-11-01T05:00:00.000Z"); // the day clocks fall back
  assert.equal(zonedMidnightUtc("2026-10-14", "UTC"), "2026-10-14T00:00:00.000Z");
});

test("dayLabel says today, tomorrow and yesterday", () => {
  assert.equal(dayLabel("2026-10-14", CHICAGO, NOW), "Today");
  assert.equal(dayLabel("2026-10-15", CHICAGO, NOW), "Tomorrow");
  assert.equal(dayLabel("2026-10-13", CHICAGO, NOW), "Yesterday");
  assert.equal(dayLabel("2026-10-17", CHICAGO, NOW), "Sat, Oct 17");
});

test("groupEventsByDay buckets by the zone's day, in start order", () => {
  const events = [
    { id: "late", starts_at: "2026-10-15T02:00:00Z", ends_at: "2026-10-15T03:00:00Z", all_day: false }, // 9 PM Oct 14 Chicago
    { id: "early", starts_at: "2026-10-14T14:30:00Z", ends_at: "2026-10-14T14:45:00Z", all_day: false },
    { id: "past", starts_at: "2026-10-13T14:00:00Z", ends_at: "2026-10-13T15:00:00Z", all_day: false },
    { id: "allday", starts_at: "2026-10-20T05:00:00Z", ends_at: "2026-10-21T04:59:59Z", all_day: true },
  ];
  const days = groupEventsByDay(events, CHICAGO, NOW);
  assert.deepEqual(
    days.map((d) => [d.day, d.label, d.past, d.events.map((e) => e.id)]),
    [
      ["2026-10-13", "Yesterday", true, ["past"]],
      ["2026-10-14", "Today", false, ["early", "late"]],
      ["2026-10-20", "Tue, Oct 20", false, ["allday"]],
    ],
  );
  assert.deepEqual(groupEventsByDay([], CHICAGO, NOW), []);
});

test("formatEventTime", () => {
  const at = (s, e, all_day = false) => ({ starts_at: s, ends_at: e, all_day });
  assert.equal(formatEventTime(at("2026-10-14T14:30:00Z", "2026-10-14T14:45:00Z"), CHICAGO), "9:30 – 9:45 AM");
  assert.equal(formatEventTime(at("2026-10-14T16:30:00Z", "2026-10-14T17:30:00Z"), CHICAGO), "11:30 AM – 12:30 PM");
  assert.equal(formatEventTime(at("2026-10-20T05:00:00Z", "2026-10-21T04:59:59Z", true), CHICAGO), "All day");
  assert.equal(formatEventTime(at("2026-10-14T23:00:00Z", "2026-10-15T06:00:00Z"), CHICAGO), "6:00 PM – Oct 15, 1:00 AM");
  assert.equal(formatEventTime(at("2026-10-14T14:30:00Z", "2026-10-14T14:30:00Z"), CHICAGO), "9:30 AM"); // no span
});

test("safeTimeZone falls back to UTC", () => {
  assert.equal(safeTimeZone(CHICAGO), CHICAGO);
  assert.equal(safeTimeZone("Mars/Olympus"), "UTC");
  assert.equal(safeTimeZone(""), "UTC");
  assert.equal(safeTimeZone(null), "UTC");
});
