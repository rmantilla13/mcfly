// The Calendars page's Google section (lib/google-calendars.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { googleCalendarRows, googleNotice, googleReturnTo } from "../lib/google-calendars.ts";

const account = { id: "acct-1", email: "ricky@example.com", connected_at: "2026-10-06T00:00:00Z", last_error: null, calendars: 2 };
const source = (over) => ({
  id: "src", name: "X", host: "calendar.google.com", color: null, enabled: true, last_synced_at: null, last_error: null, event_count: 0,
  created_at: "2026-10-06T00:00:00Z", kind: "google", account_id: "acct-1", account_email: "ricky@example.com", google_calendar_id: "cal", ...over,
});
const listed = [
  { id: "ricky@example.com", name: "ricky@example.com", color: "#4F7CF7", primary: true, access_role: "owner", selected: true },
  { id: "c_holidays", name: "Holidays", color: "#0B8043", primary: false, access_role: "reader", selected: true },
  { id: "c_work", name: "Work", color: "#5B7CF5", primary: false, access_role: "writer", selected: false },
];

test("every listed calendar gets a row, with its subscription when it has one", () => {
  const rows = googleCalendarRows(account, listed, [
    source({ id: "s-work", name: "Office", color: "#E2725B", google_calendar_id: "c_work", event_count: 14 }),
    source({ id: "s-other", account_id: "acct-2", google_calendar_id: "c_holidays" }),
    source({ id: "s-link", kind: "ical", account_id: null, google_calendar_id: null, host: "p12-caldav.icloud.com" }),
  ]);
  assert.deepEqual(rows.map((r) => r.id), ["ricky@example.com", "c_work", "c_holidays"], "primary, then subscribed, then Google's order");
  assert.equal(rows[1].name, "Office", "the subscription's name wins");
  assert.equal(rows[1].color, "#E2725B", "and its color");
  assert.equal(rows[1].source?.event_count, 14);
  assert.equal(rows[2].source, null, "another account's subscription is not this one's");
  assert.equal(rows[0].listed, true);
});

test("a subscribed calendar Google no longer lists stays, flagged", () => {
  const rows = googleCalendarRows(account, [listed[0]], [source({ id: "s-gone", name: "Old team", google_calendar_id: "c_gone" })]);
  assert.deepEqual(rows.map((r) => [r.id, r.listed]), [["ricky@example.com", true], ["c_gone", false]]);
  assert.equal(rows[1].access_role, null);
  assert.equal(rows[1].source?.id, "s-gone");
});

test("no list from Google (its sign-in failed) still shows what is subscribed", () => {
  const rows = googleCalendarRows(account, null, [source({ google_calendar_id: "c_work", name: "Work" })]);
  assert.deepEqual(rows.map((r) => [r.name, r.listed]), [["Work", false]]);
});

test("the notice Google's redirect carries", () => {
  assert.deepEqual(googleNotice({ google: "connected" }), { kind: "connected" });
  assert.deepEqual(googleNotice({ google_error: "Google's sign-in was cancelled" }), { kind: "error", message: "Google's sign-in was cancelled" });
  assert.deepEqual(googleNotice({ google_error: ["first", "second"] }), { kind: "error", message: "first" });
  assert.equal(googleNotice({ google_error: "a\u0000b\n\nc" })?.message, "a b c", "control characters go");
  assert.equal(googleNotice({ google_error: "x".repeat(400) })?.message.length, 300);
  assert.equal(googleNotice({}), null);
  assert.equal(googleNotice({ google: "whatever" }), null);
});

test("the return address is this console's Calendars page", () => {
  assert.equal(googleReturnTo("https://mcfly.bot"), "https://mcfly.bot/calendars");
  assert.equal(googleReturnTo("http://localhost:3000"), "http://localhost:3000/calendars");
  assert.equal(googleReturnTo("https://mcfly.bot/elsewhere"), null, "a path is not an origin");
  assert.equal(googleReturnTo("javascript:alert(1)"), null);
  assert.equal(googleReturnTo("https://user@mcfly.bot"), null);
  assert.equal(googleReturnTo(null), null);
  assert.equal(googleReturnTo("not a url"), null);
});
