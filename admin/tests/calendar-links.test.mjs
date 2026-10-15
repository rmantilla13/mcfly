// The add-calendar form's warning about Google public addresses (lib/calendar-links.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { isGooglePublicAddress } from "../lib/calendar-links.ts";

const google = "https://calendar.google.com/calendar/ical";

test("a Google public address is flagged", () => {
  assert.equal(isGooglePublicAddress(`${google}/team%40example.com/public/basic.ics`), true);
  assert.equal(isGooglePublicAddress(`  webcal://calendar.google.com/calendar/ical/x/public/basic.ics `), true);
});

test("secret addresses and other calendars are not", () => {
  assert.equal(isGooglePublicAddress(`${google}/me%40example.com/private-0123abcd/basic.ics`), false);
  assert.equal(isGooglePublicAddress("https://p12-caldav.icloud.com/published/2/abc"), false);
  assert.equal(isGooglePublicAddress("https://outlook.office365.com/owa/calendar/x/public/calendar.ics"), false);
});

test("half-typed text is not flagged", () => {
  assert.equal(isGooglePublicAddress(""), false);
  assert.equal(isGooglePublicAddress("calendar.google"), false);
});
