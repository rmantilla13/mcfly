// Run with `npm test` (Node 22+ strips the TypeScript types itself).
import assert from "node:assert/strict";
import { test } from "node:test";
import { COMMON_TIMEZONES, knownTimeZone, locationErrorSentence, parseTimeZoneLookup, timeZoneAt, timeZoneLookupUrl } from "../lib/timezones.ts";

test("every suggested zone is one this runtime knows", () => {
  for (const tz of COMMON_TIMEZONES) assert.ok(knownTimeZone(tz), tz);
  assert.equal(knownTimeZone("Mars/Olympus"), false);
  assert.equal(knownTimeZone(""), false);
});

test("the lookup asks Open-Meteo for the zone at about a kilometre, and nothing else", () => {
  const url = new URL(timeZoneLookupUrl(30.267153, -97.743057));
  assert.equal(url.host, "api.open-meteo.com");
  assert.equal(url.pathname, "/v1/forecast");
  assert.equal(url.searchParams.get("latitude"), "30.27");
  assert.equal(url.searchParams.get("longitude"), "-97.74");
  assert.equal(url.searchParams.get("timezone"), "auto");
  assert.equal(url.searchParams.get("current"), null);
  assert.equal(url.searchParams.get("daily"), null);
  assert.throws(() => timeZoneLookupUrl(Number.NaN, 2), RangeError);
});

test("the answer's zone is taken when this runtime knows it", () => {
  // Open-Meteo's answer to the lookup URL, as of October 2026.
  const answer = { latitude: 30.269146, longitude: -97.75338, generationtime_ms: 0.001, utc_offset_seconds: -18000, timezone: "America/Chicago", timezone_abbreviation: "GMT-5", elevation: 164 };
  assert.equal(parseTimeZoneLookup(answer), "America/Chicago");
  assert.equal(parseTimeZoneLookup({ timezone: "UTC" }), "UTC");
  for (const bad of [null, undefined, "America/Chicago", 7, {}, { timezone: 7 }, { timezone: "" }, { timezone: "Mars/Olympus" }, { error: true, reason: "Latitude must be in range" }]) {
    assert.equal(parseTimeZoneLookup(bad), null, JSON.stringify(bad));
  }
});

test("timeZoneAt reads the zone, and says what went wrong in a sentence", async () => {
  const calls = [];
  const paris = async (url) => {
    calls.push(String(url));
    return new Response(JSON.stringify({ timezone: "Europe/Paris", utc_offset_seconds: 7200 }));
  };
  assert.equal(await timeZoneAt(48.8566, 2.3522, paris), "Europe/Paris");
  assert.match(calls[0], /latitude=48\.86&longitude=2\.35&timezone=auto/);
  await assert.rejects(timeZoneAt(0, 0, async () => new Response("down", { status: 503 })), /couldn't be reached/);
  await assert.rejects(
    timeZoneAt(0, 0, async () => {
      throw new TypeError("Failed to fetch");
    }),
    /couldn't be reached/,
  );
  await assert.rejects(timeZoneAt(0, 0, async () => new Response("not json")), /No time zone is known/);
  await assert.rejects(timeZoneAt(0, 0, async () => new Response(JSON.stringify({ timezone: "Nowhere/Else" }))), /No time zone is known/);
});

test("a browser's reasons for giving no position read as sentences", () => {
  assert.match(locationErrorSentence(1), /^Location is off for this site/);
  assert.match(locationErrorSentence(3), /took too long/);
  assert.match(locationErrorSentence(2), /couldn't be found/);
  assert.match(locationErrorSentence(42), /couldn't be found/);
});
