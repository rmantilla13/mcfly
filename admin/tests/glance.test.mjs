// lib/glance.ts: the assistant-first Today's opening lines, from feeds that
// are empty, partial and full. The same cases, and the same wording, as the
// display's (display/tests/tst_homeglance.cpp). Every time is fixed on the
// display's clock (Chicago), so the results don't depend on where or when the
// tests run.
import assert from "node:assert/strict";
import { test } from "node:test";
import { glance } from "../lib/glance.ts";

const TZ = "America/Chicago";
// Thursday, October 15, 2026 (CDT, UTC−5) at hh:mm.
const at = (hh, mm, day = 15) => Date.parse(`2026-10-${day}T${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:00-05:00`);
const iso = (ms) => new Date(ms).toISOString();
const event = (title, start, minutes, allDay = false) => ({
  id: title,
  title,
  calendar: "Work",
  location: null,
  starts_at: iso(start),
  ends_at: iso(start + minutes * 60_000),
  all_day: allDay,
  color: "#5B7CF5",
});
const project = (name) => ({ id: name, name, next: "", progress: null, color: "#E2604A" });
const ticker = (symbol, pct) => ({ symbol, changePct: pct, direction: pct > 0 ? "up" : pct < 0 ? "down" : "flat" });
const feed = (rows = {}) => ({ events: [], tickers: [], blocked: [], brief: null, hero: null, displayName: "McFly", timeZone: TZ, ...rows });
// Times are glued with a no-break space ("3:30 pm" on one line); compare in plain spaces.
const headline = (rows, now) => glance(feed(rows), now).headline.replaceAll(" ", " ");

test("an empty feed is a quiet day", () => {
  const g = glance(feed(), at(15, 0));
  assert.equal(g.headline, "Good afternoon. It's a quiet day so far.");
  assert.equal(g.quiet, true);
  assert.ok(g.detail.endsWith("Ask me anything."));
  assert.deepEqual(g.chips, ["What can you do?"]);
  assert.equal(g.next, null);
});

test("the greeting follows the display's clock and name", () => {
  assert.ok(headline({}, at(3, 0)).startsWith("Good night."));
  assert.ok(headline({}, at(9, 12)).startsWith("Good morning."));
  assert.ok(headline({}, at(17, 30)).startsWith("Good afternoon."));
  assert.ok(headline({}, at(19, 30)).startsWith("Good evening."));
  assert.ok(headline({ displayName: "Ricky" }, at(9, 12)).startsWith("Good morning, Ricky."));
});

test("the next event, in minutes and hours", () => {
  const rows = { events: [event("Standup", at(9, 30), 15)] };
  assert.equal(headline(rows, at(9, 12)), "Good morning. Standup is in 18 minutes.");
  assert.equal(headline(rows, at(9, 29)), "Good morning. Standup is about to start.");
  assert.equal(headline(rows, at(9, 35)), "Good morning. Standup is on now.");
  assert.equal(headline(rows, at(7, 0)), "Good morning. Standup is at 9:30 am.");
  assert.equal(glance(feed(rows), at(9, 12)).next.title, "Standup");
});

test("a time doesn't break across lines", () => {
  const g = glance(feed({ events: [event("Standup", at(9, 30), 15)] }), at(7, 0));
  assert.ok(g.headline.includes("9:30 am"));
});

test("a long title asks about the day instead", () => {
  const g = glance(feed({ events: [event("Pulse review with the team", at(15, 30), 30)] }), at(11, 0));
  assert.equal(g.chips[0], "What else is on today?");
});

test("tomorrow starts the sentence", () => {
  const rows = { events: [event("Investor call", at(11, 0, 16), 60)] };
  assert.equal(headline(rows, at(21, 0)), "Good evening. Tomorrow starts with Investor call at 11:00 am.");
});

test("all-day and finished events are skipped", () => {
  const rows = { events: [event("Holiday", at(0, 0), 24 * 60, true), event("Standup", at(9, 30), 15), event("Pulse review", at(15, 30), 30)] };
  assert.equal(headline(rows, at(12, 0)), "Good afternoon. Pulse review is at 3:30 pm.");
});

test("blocked projects", () => {
  assert.equal(headline({ blocked: [project("Onyx")] }, at(10, 0)), "Good morning. Onyx is blocked.");
  assert.ok(glance(feed({ blocked: [project("Onyx")] }), at(10, 0)).chips.includes("What's blocking Onyx?"));
  assert.equal(headline({ blocked: [project("Onyx"), project("Ohana")] }, at(10, 0)), "Good morning. Onyx and Ohana are blocked.");
  assert.equal(headline({ blocked: [project("Onyx"), project("Ohana"), project("Atlas")] }, at(10, 0)), "Good morning. Onyx and 2 others are blocked.");
});

test("the biggest move leads the markets", () => {
  const g = glance(feed({ tickers: [ticker("SPY", 0.32), ticker("MSFT", -1.2), ticker("TSLA", 3.96), ticker("AAPL", 0)] }), at(10, 0));
  assert.equal(g.headline, "Good morning. TSLA is up 4.0%.");
  assert.deepEqual(g.movers.map((t) => t.symbol), ["TSLA", "MSFT"]); // a move under 1% isn't news
  assert.equal(g.chips[0], "Why is TSLA up?");
  assert.equal(headline({ tickers: [ticker("MSFT", -2.04)] }, at(10, 0)), "Good morning. MSFT is down 2.0%.");
  assert.equal(headline({ tickers: [ticker("SPY", 0.32)] }, at(10, 0)), "Good morning. It's a quiet day so far.");
});

test("everything in one sentence", () => {
  const rows = { events: [event("Standup", at(9, 30), 15)], blocked: [project("Onyx")], tickers: [ticker("TSLA", 3.96)] };
  assert.equal(headline(rows, at(9, 12)), "Good morning. Standup is in 18 minutes, Onyx is blocked, and TSLA is up 4.0%.");
  assert.deepEqual(glance(feed(rows), at(9, 12)).chips, ["What's on after Standup?", "What's blocking Onyx?", "Why is TSLA up?"]);
});

test("today's Pulse and the newest brief", () => {
  const rows = {
    hero: { reportId: "r", source: "Daily Pulse", color: "#C2552F", count: 6, headline: "Google launches Gemini 4 Argon", takeaway: "", imageUrl: null },
    brief: { id: "b", agent: "Grok", color: "#7B5CE6", publishedAt: iso(at(16, 7)), title: "Hourly check-in.", summary: "", bullets: [], kind: "hourly" },
  };
  const g = glance(feed(rows), at(16, 10));
  assert.equal(g.headline, "Good afternoon. Nothing is next, and nothing needs you.");
  assert.equal(g.detail, "Today's Daily Pulse leads with Google launches Gemini 4 Argon. Grok's latest: Hourly check-in.");
  assert.deepEqual(g.chips, ["Read me the Daily Pulse", "What did Grok say?", "What can you do?"]);
});

test("never more than three chips, and no repeats", () => {
  const rows = {
    events: [event("Standup", at(9, 30), 15)],
    blocked: [project("Onyx")],
    tickers: [ticker("TSLA", 3.96)],
    brief: { id: "b", agent: "Grok", color: "#7B5CE6", publishedAt: iso(at(8, 30)), title: "Morning briefing", summary: "", bullets: [], kind: "daily" },
  };
  const chips = glance(feed(rows), at(9, 12)).chips;
  assert.equal(chips.length, 3);
  assert.equal(new Set(chips).size, 3);
});
