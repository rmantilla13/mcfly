import { assertEquals } from "jsr:@std/assert@1";
import { parseIcs } from "./ics.ts";

const ICS = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VTIMEZONE
TZID:America/Chicago
BEGIN:DAYLIGHT
TZOFFSETFROM:-0600
TZOFFSETTO:-0500
TZNAME:CDT
DTSTART:19700308T020000
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
END:DAYLIGHT
BEGIN:STANDARD
TZOFFSETFROM:-0500
TZOFFSETTO:-0600
TZNAME:CST
DTSTART:19701101T020000
RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU
END:STANDARD
END:VTIMEZONE
BEGIN:VEVENT
UID:standup
SUMMARY:Standup
LOCATION:Zoom
DTSTART;TZID=America/Chicago:20261012T093000
DTEND;TZID=America/Chicago:20261012T094500
RRULE:FREQ=DAILY;COUNT=10
EXDATE;TZID=America/Chicago:20261014T093000
END:VEVENT
BEGIN:VEVENT
UID:standup
RECURRENCE-ID;TZID=America/Chicago:20261015T093000
SUMMARY:Standup (moved)
DTSTART;TZID=America/Chicago:20261015T110000
DTEND;TZID=America/Chicago:20261015T111500
END:VEVENT
BEGIN:VEVENT
UID:trip
SUMMARY:Trip
DTSTART;VALUE=DATE:20261017
DTEND;VALUE=DATE:20261019
END:VEVENT
BEGIN:VEVENT
UID:gone
SUMMARY:Cancelled thing
STATUS:CANCELLED
DTSTART:20261016T150000Z
DTEND:20261016T160000Z
END:VEVENT
BEGIN:VEVENT
UID:old
SUMMARY:Last month
DTSTART:20260901T150000Z
DTEND:20260901T160000Z
END:VEVENT
BEGIN:VEVENT
UID:untitled
DTSTART:20261016T200000Z
END:VEVENT
END:VCALENDAR`;

const window = { from: new Date("2026-10-13T00:00:00Z"), to: new Date("2026-10-20T00:00:00Z") };

Deno.test("expands recurrences in the window, in the feed's zone", () => {
  const items = parseIcs(ICS, window);
  const standups = items.filter((i) => i.id.startsWith("standup@"));
  // Oct 13..19, minus the 14th (EXDATE): 6 occurrences.
  assertEquals(standups.length, 6);
  assertEquals(standups[0].starts_at, "2026-10-13T14:30:00.000Z"); // 9:30 CDT
  assertEquals(standups[0].location, "Zoom");
  const moved = standups.find((s) => s.title === "Standup (moved)");
  assertEquals(moved?.starts_at, "2026-10-15T16:00:00.000Z"); // 11:00 CDT
});

Deno.test("all-day, cancelled, out of window, untitled", () => {
  const items = parseIcs(ICS, { ...window, color: "#14C2C2" });
  const trip = items.find((i) => i.id === "trip");
  assertEquals(trip?.all_day, true);
  assertEquals(trip?.starts_at, "2026-10-17T00:00:00Z");
  assertEquals(trip?.ends_at, "2026-10-18T23:59:59Z");
  assertEquals(trip?.color, "#14C2C2");
  assertEquals(items.some((i) => i.id === "gone"), false);
  assertEquals(items.some((i) => i.id === "old"), false);
  assertEquals(items.find((i) => i.id === "untitled")?.title, "Busy");
  for (let i = 1; i < items.length; i++) assertEquals(items[i - 1].starts_at <= items[i].starts_at, true);
});
