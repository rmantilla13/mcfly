// Weather over the ambient view (lib/weather.ts): which season, where, what
// a setting comes to, how many, and the particles' numbers. The rules have to
// stay the display's (display/src/hardware/DisplayController.cpp: weatherFor,
// seasonFor, southernZone, weatherCount), checked here against its source,
// and its tests' cases are these.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  WEATHERS,
  displayWeather,
  makeParticles,
  parseWeather,
  seasonFor,
  southernZone,
  weatherCount,
  weatherFor,
} from "../lib/weather.ts";

const at = (iso) => Date.parse(iso);

test("the setting is off unless it is one the display knows", () => {
  for (const w of WEATHERS) assert.equal(parseWeather(w), w);
  for (const junk of [null, undefined, "", "SNOW", "rain", 1, {}]) assert.equal(parseWeather(junk), "off");
  assert.deepEqual([...WEATHERS], ["off", "season", "snow", "petals", "fireflies", "leaves"]);
});

test("seasons are whole months, and the south has the north's six months on", () => {
  const north = Array.from({ length: 12 }, (_, i) => seasonFor(i + 1, false));
  assert.deepEqual(north, ["winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter"]);
  assert.equal(seasonFor(12, true), "summer");
  assert.equal(seasonFor(7, true), "winter");
  assert.equal(seasonFor(10, true), "spring");
  assert.equal(seasonFor(4, true), "autumn");
});

test("the hemisphere comes from the time zone, and an unknown one is north", () => {
  for (const tz of ["Australia/Sydney", "Pacific/Auckland", "America/Argentina/Buenos_Aires", "America/Santiago", "America/Sao_Paulo", "Africa/Johannesburg", "Antarctica/McMurdo"])
    assert.equal(southernZone(tz), true, tz);
  for (const tz of ["America/Chicago", "Europe/London", "Asia/Tokyo", "Africa/Cairo", "America/Bogota", "UTC", "", null, undefined])
    assert.equal(southernZone(tz), false, String(tz));
});

test("by the season is the season's weather where the display is; the rest are themselves", () => {
  assert.equal(weatherFor("season", at("2026-12-20T18:00:00Z"), "America/Chicago"), "snow");
  assert.equal(weatherFor("season", at("2026-12-20T02:00:00Z"), "Australia/Sydney"), "fireflies");
  assert.equal(weatherFor("season", at("2026-04-20T18:00:00Z"), "America/Chicago"), "petals");
  assert.equal(weatherFor("season", at("2026-04-20T02:00:00Z"), "Australia/Sydney"), "leaves");
  assert.equal(weatherFor("season", at("2026-10-16T18:00:00Z"), "America/Chicago"), "leaves");
  // The month is the zone's: 1 December in Sydney is still November in UTC.
  assert.equal(weatherFor("season", at("2026-11-30T14:00:00Z"), "Australia/Sydney"), "fireflies");
  assert.equal(weatherFor("season", at("2026-11-30T14:00:00Z"), "UTC"), "leaves");
  for (const kind of ["snow", "petals", "fireflies", "leaves"]) assert.equal(weatherFor(kind, at("2026-01-01T12:00:00Z"), "America/Chicago"), kind);
  assert.equal(weatherFor("off", Date.now(), "America/Chicago"), null);
});

test("a small screen gets a few, a big one is not crowded: the display's numbers", () => {
  for (const kind of ["snow", "petals", "fireflies", "leaves"]) {
    const phone = weatherCount(kind, 390, 844);
    const laptop = weatherCount(kind, 1440, 900);
    const huge = weatherCount(kind, 5120, 2880);
    assert.ok(phone > 0 && phone <= laptop && laptop <= huge, kind);
    assert.equal(weatherCount(kind, 0, 0), weatherCount(kind, 1, 1));
    assert.equal(huge, weatherCount(kind, 20000, 20000));
  }
  assert.deepEqual(["snow", "petals", "fireflies", "leaves"].map((k) => weatherCount(k, 1440, 900)), [44, 18, 20, 14]);
  assert.equal(weatherCount("rain", 1440, 900), 0);
});

test("the zones and the counts are the display's, line for line", () => {
  const cpp = readFileSync(new URL("../../display/src/hardware/DisplayController.cpp", import.meta.url), "utf8");
  const zonesBlock = cpp.slice(cpp.indexOf("southernZone("), cpp.indexOf("weatherFor(const QString"));
  const quoted = [...zonesBlock.matchAll(/"([A-Za-z_/-]+)"/g)].map((m) => m[1]);
  const prefixes = quoted.filter((z) => z.endsWith("/"));
  const zones = quoted.filter((z) => !z.endsWith("/"));
  for (const p of prefixes) assert.equal(southernZone(`${p}Somewhere`), true, p);
  for (const z of zones) assert.equal(southernZone(z), true, z);
  assert.ok(zones.length > 40, "the display's list was read");
  const table = [...cpp.matchAll(/\{"(snow|petals|leaves|fireflies)", (\d+), (\d+), (\d+)\}/g)];
  assert.equal(table.length, 4);
  for (const [, kind, per, min, max] of table) {
    assert.equal(weatherCount(kind, 0, 0), Number(min), kind);
    assert.equal(weatherCount(kind, 1e5, 1e5), Number(max), kind);
    assert.equal(weatherCount(kind, Number(per), 10), Math.max(Number(min), Math.min(Number(max), 10)), kind);
  }
});

test("the display seen last says the weather", () => {
  const d = (weather, seen, created = "2026-10-01T00:00:00Z") => ({ settings: weather === undefined ? {} : { weather }, last_seen_at: seen, created_at: created });
  assert.equal(displayWeather([]), "off");
  assert.equal(displayWeather([d("snow", "2026-10-16T10:00:00Z"), d("leaves", "2026-10-16T12:00:00Z")]), "leaves");
  assert.equal(displayWeather([d(undefined, "2026-10-16T12:00:00Z")]), "off");
  assert.equal(displayWeather([d("rain", "2026-10-16T12:00:00Z")]), "off");
});

test("what falls starts part-way through, inside the screen's width, one wind for all", () => {
  for (const kind of ["snow", "petals", "leaves"]) {
    const ps = makeParticles(kind, 200);
    for (const p of ps) {
      assert.ok(p.delay <= 0 && p.delay >= -p.dur, `${kind} delay`);
      assert.ok(p.x + p.drift > -40 && p.x + p.drift < 140, `${kind} lands at ${p.x + p.drift}vw`);
      assert.ok(p.alpha > 0 && p.alpha <= 1);
      assert.ok(p.flipK >= -1 && p.flipK <= 1);
    }
    assert.ok(new Set(ps.filter((p) => p.drift !== 0).map((p) => Math.sign(p.drift))).size <= 1, `${kind} drifts both ways`);
  }
  for (const p of makeParticles("leaves", 50)) {
    assert.equal(p.spinDur, p.swayDur, "a leaf's tilt keeps time with its swing");
    assert.equal(p.spinDelay, p.swayDelay);
  }
  for (const p of makeParticles("fireflies", 100)) {
    for (const x of p.xs) assert.ok(x >= 2 && x <= 98);
    for (const y of p.ys) assert.ok(y >= 30 && y <= 95, `firefly at ${y}vh`);
  }
});
