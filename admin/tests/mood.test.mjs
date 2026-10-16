// The console's time of day (lib/mood.ts): the display's mood clock, in the
// display's zone, and the glow colours globals.css paints each mood with.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { MOODS, MOOD_GLOW, MOOD_SCRIPT, isNight, minuteOfDay, moodAt } from "../lib/mood.ts";

// A wall-clock time in a zone with a fixed offset on that date, as epoch ms.
const local = (iso, offsetMinutes) => Date.parse(`${iso}Z`) - offsetMinutes * 60_000;

test("the display's boundaries, minute by minute", () => {
  const tz = "America/Chicago"; // CDT, UTC-5, in October
  const at = (hm) => local(`2026-10-14T${hm}:00`, -300);
  const cases = [
    ["00:00", "night"],
    ["06:29", "night"],
    ["06:30", "morning"],
    ["10:59", "morning"],
    ["11:00", "day"],
    ["16:59", "day"],
    ["17:00", "evening"],
    ["21:29", "evening"],
    ["21:30", "night"],
    ["23:59", "night"],
  ];
  for (const [hm, mood] of cases) assert.equal(moodAt(at(hm), tz), mood, hm);
  assert.equal(moodAt(at("06:29") + 59_999, tz), "night", "the last millisecond of night");
});

test("isNight is exactly the night mood, all day", () => {
  const start = local("2026-10-14T00:00:00", 0);
  for (let m = 0; m < 24 * 60; m += 1) {
    const ms = start + m * 60_000;
    assert.equal(isNight(ms, "UTC"), moodAt(ms, "UTC") === "night", `minute ${m}`);
    assert.equal(minuteOfDay(ms, "UTC"), m);
  }
});

test("the same instant is a different mood in another zone", () => {
  const instant = Date.parse("2026-10-14T03:00:00Z");
  assert.equal(moodAt(instant, "UTC"), "night"); // 3:00
  assert.equal(moodAt(instant, "Asia/Tokyo"), "day"); // 12:00
  assert.equal(moodAt(instant, "America/Los_Angeles"), "evening"); // 20:00 the day before
  assert.equal(moodAt(instant, "Europe/Berlin"), "night"); // 5:00
});

test("zones off the hour turn on their own half hour", () => {
  const tz = "Asia/Kathmandu"; // UTC+5:45
  assert.equal(moodAt(local("2026-10-14T21:29:00", 345), tz), "evening");
  assert.equal(moodAt(local("2026-10-14T21:30:00", 345), tz), "night");
  assert.equal(moodAt(local("2026-10-14T06:30:00", 345), tz), "morning");
});

test("daylight saving moves the morning with the clock", () => {
  const tz = "America/New_York";
  // Saturday, EST (UTC-5): morning at 11:30 UTC.
  assert.equal(moodAt(Date.parse("2026-03-07T11:29:00Z"), tz), "night");
  assert.equal(moodAt(Date.parse("2026-03-07T11:30:00Z"), tz), "morning");
  // Sunday, clocks forward at 2:00 to EDT (UTC-4): morning at 10:30 UTC.
  assert.equal(moodAt(Date.parse("2026-03-08T10:29:00Z"), tz), "night");
  assert.equal(moodAt(Date.parse("2026-03-08T10:30:00Z"), tz), "morning");
});

test("the pre-paint script picks moodAt's mood at every minute", () => {
  // The script reads the browser's local clock; a stand-in Date says the
  // minute, and moodAt is asked about the same minute in UTC.
  const start = Date.parse("2026-10-14T00:00:00Z");
  for (let m = 0; m < 24 * 60; m += 1) {
    const root = { dataset: {} };
    class LocalDate {
      getHours() {
        return Math.floor(m / 60);
      }
      getMinutes() {
        return m % 60;
      }
    }
    new Function("document", "Date", MOOD_SCRIPT)({ documentElement: root }, LocalDate);
    assert.equal(root.dataset.mood, moodAt(start + m * 60_000, "UTC"), `minute ${m}`);
  }
});

test("the pre-paint script never throws", () => {
  assert.doesNotThrow(() => new Function("document", "Date", MOOD_SCRIPT)(undefined, Date));
});

test("a zone the runtime doesn't know still gives a mood", () => {
  const mood = moodAt(Date.now(), "Not/AZone");
  assert.ok(MOODS.includes(mood));
  assert.ok(MOODS.includes(moodAt(Date.now())));
});

test("every mood has three glow colours, as hex", () => {
  assert.deepEqual(Object.keys(MOOD_GLOW).sort(), [...MOODS].sort());
  for (const mood of MOODS) {
    assert.equal(MOOD_GLOW[mood].length, 3, mood);
    for (const c of MOOD_GLOW[mood]) assert.match(c, /^#[0-9a-f]{6}$/, `${mood} ${c}`);
  }
});

test("globals.css paints each mood with exactly MOOD_GLOW", () => {
  const css = readFileSync(new URL("../app/globals.css", import.meta.url), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
  const declarations = (body) =>
    Object.fromEntries(
      body
        .split(";")
        .map((d) => d.trim())
        .filter(Boolean)
        .map((d) => {
          const i = d.indexOf(":");
          return [d.slice(0, i).trim(), d.slice(i + 1).trim().toLowerCase()];
        }),
    );

  // Day is the plain :root block.
  const root = css.match(/(?:^|\n):root\s*\{([^}]*)\}/);
  assert.ok(root, ":root block");
  const day = declarations(root[1]);
  assert.deepEqual([day["--glow-1"], day["--glow-2"], day["--glow-3"]], [...MOOD_GLOW.day]);

  // The others override --glow-1..3 and nothing else, once each.
  const blocks = [...css.matchAll(/:root\[data-mood=["']?(\w+)["']?\]\s*\{([^}]*)\}/g)];
  assert.deepEqual(blocks.map((b) => b[1]).sort(), ["evening", "morning", "night"]);
  for (const [, mood, body] of blocks) {
    assert.deepEqual(declarations(body), {
      "--glow-1": MOOD_GLOW[mood][0],
      "--glow-2": MOOD_GLOW[mood][1],
      "--glow-3": MOOD_GLOW[mood][2],
    }, mood);
  }
});
