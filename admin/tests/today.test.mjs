// The web Today timeline (lib/today.ts): the display's rules, in the display's zone.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildTimeline, focusIndex, greeting, nextIndex, rowState, untilLabel, upNext } from "../lib/today.ts";

const TZ = "America/Chicago";
const NOW = new Date("2026-10-14T15:00:00Z"); // 10 AM in Chicago
const at = (h, m = 0) => new Date(Date.UTC(2026, 9, 14, h + 5, m)).toISOString(); // Chicago hour → UTC

const input = {
  timeZone: TZ,
  now: NOW,
  briefs: [
    { id: "b1", agent_name: "Grok", agent_color: "#7A64E8", title: "Morning briefing", body: "Three things.\n\nMore.", kind: "daily", published_at: at(8, 30) },
    { id: "b0", agent_name: "Grok", agent_color: "#7A64E8", title: "Yesterday", body: "", kind: "hourly", published_at: "2026-10-13T20:00:00Z" },
    { id: "b2", agent_name: "Desk", agent_color: "#2E9E6A", title: "TSLA up", body: "", kind: "alert", published_at: at(9, 5) },
  ],
  reports: [
    {
      id: "r1", report_date: "2026-10-14", published_at: "2026-10-14T04:00:00Z", agent_name: "Daily Pulse", agent_color: "#5B7CF5", hero_item: "b",
      items: [
        { item_key: "a", headline: "A", image_url: null, section_order: 0, position: 0 },
        { item_key: "b", headline: "B", image_url: "https://img/b.jpg", section_order: 1, position: 0 },
        { item_key: "c", headline: "C", image_url: null, section_order: 1, position: 1 },
        { item_key: "d", headline: "D", image_url: null, section_order: 2, position: 0 },
      ],
    },
    { id: "r0", report_date: "2026-10-13", published_at: "2026-10-13T12:00:00Z", agent_name: "Daily Pulse", agent_color: "#5B7CF5", hero_item: null,
      items: [{ item_key: "x", headline: "Old", image_url: null, section_order: 0, position: 0 }] },
  ],
  projects: [
    { id: "p1", name: "McFly", status: "active", progress: 62, color: null, agent_color: "#7A64E8",
      updates: [{ id: 3, kind: "ci", text: "CI green", happened_at: at(9, 25) }, { id: 2, kind: "note", text: "Old", happened_at: "2026-10-12T12:00:00Z" }] },
  ],
  events: [
    { id: "e1", title: "Standup", calendar: "Work", location: "Zoom", starts_at: at(9, 30), ends_at: at(10, 15), all_day: false, color: null },
    { id: "e2", title: "Pulse review", calendar: "Work", location: null, starts_at: at(15, 30), ends_at: at(16), all_day: false, color: "#E2725B" },
    { id: "e3", title: "Holiday", calendar: "Home", location: null, starts_at: "2026-10-14T05:00:00Z", ends_at: "2026-10-15T05:00:00Z", all_day: true, color: null },
    { id: "e4", title: "Tomorrow", calendar: "Work", location: null, starts_at: at(33), ends_at: at(34), all_day: false, color: null },
  ],
};

test("only today's rows, all-day first, then in time order", () => {
  const t = buildTimeline(input);
  assert.deepEqual(t.map((i) => i.title), ["Holiday", "B", "Morning briefing", "TSLA up", "CI green", "Standup", "Pulse review"]);
  assert.equal(t[0].time, "All day");
});

test("a report written overnight opens the day with its hero and the rest", () => {
  const news = buildTimeline(input).find((i) => i.kind === "news");
  assert.equal(news.time, "12:00");
  assert.equal(news.ampm, "am");
  assert.equal(news.title, "B");
  assert.equal(news.detail, "A · C · 1 more");
  assert.equal(news.label, "Daily Pulse · 4 stories");
  assert.equal(news.href, "/feed/news/r1");
  assert.equal(news.imageUrl, "https://img/b.jpg");
});

test("rows carry their kind, time and link", () => {
  const t = buildTimeline(input);
  const alert = t.find((i) => i.title === "TSLA up");
  assert.equal(alert.kind, "alert");
  assert.equal(`${alert.time} ${alert.ampm}`, "9:05 am");
  const ci = t.find((i) => i.kind === "project");
  assert.equal(ci.detail, "62% done");
  assert.equal(ci.href, "/feed/projects/p1");
  const standup = t.find((i) => i.title === "Standup");
  assert.equal(standup.detail, "9:30 am – 10:15 am · Zoom");
  assert.equal(t.find((i) => i.title === "Morning briefing").detail, "Three things.");
});

test("past, now and next follow the clock", () => {
  const t = buildTimeline(input);
  const now = NOW.getTime();
  const standup = t.findIndex((i) => i.title === "Standup");
  const review = t.findIndex((i) => i.title === "Pulse review");
  assert.equal(rowState(t[standup], standup, t, now), "now");
  assert.equal(rowState(t[review], review, t, now), "next");
  assert.equal(nextIndex(t, now), review);
  assert.equal(focusIndex(t, now), standup);
  const later = Date.parse(at(11));
  assert.equal(rowState(t[standup], standup, t, later), "past");
  assert.equal(focusIndex(t, Date.parse(at(17))), t.length - 1);
});

test("up next skips all-day and finished events", () => {
  assert.equal(upNext(input.events, NOW.getTime()).title, "Standup");
  assert.equal(upNext(input.events, Date.parse(at(11))).title, "Pulse review");
  assert.equal(upNext(input.events, Date.parse(at(36))), null);
});

test("labels", () => {
  const now = NOW.getTime();
  assert.equal(untilLabel(now + 18 * 60_000, now), "in 18 min");
  assert.equal(untilLabel(now + 18 * 60_000, now, true), "in 18 minutes");
  assert.equal(untilLabel(now + 125 * 60_000, now), "in 2 h 5 min");
  assert.equal(untilLabel(now - 1, now), "now");
  assert.equal(greeting(now, TZ), "Good morning");
  assert.equal(greeting(now, TZ, "Ricky"), "Good morning, Ricky");
  assert.equal(greeting(Date.parse(at(19)), TZ), "Good evening");
});
