// The household thread (lib/messages.ts): merging what a poll brings back,
// where the next poll starts, runs and day headings, and the names field.
import assert from "node:assert/strict";
import { test } from "node:test";
import { awayLabel, awayUntil, isAway, NOT_AWAY, dayHeading, demoMessages, mergeMessages, notifyNote, OVERLAP_MS, parseNames, pollSince, replyStatus, startsRun, threadDays, unreadFromHome } from "../lib/messages.ts";

const NOW = Date.parse("2026-11-03T22:00:00Z"); // 4 pm in Chicago
const at = (minutes) => new Date(NOW + minutes * 60_000).toISOString();
const msg = (id, minutes, extra = {}) => ({
  id,
  sender_kind: "display",
  sender_name: "Mia",
  body: id,
  device_id: null,
  via: "display",
  created_at: at(minutes),
  updated_at: at(minutes),
  read_at: null,
  notified_at: null,
  notify_error: null,
  ...extra,
});

test("mergeMessages keeps the newest copy, in order, and a read made here", () => {
  const a = msg("a", -10), b = msg("b", -5);
  let thread = mergeMessages([], [b, a]);
  assert.deepEqual(thread.map((m) => m.id), ["a", "b"]);
  thread = mergeMessages(thread, [{ ...a, body: "stale", updated_at: at(-20) }]);
  assert.equal(thread[0].body, "a", "an older copy doesn't win");
  thread = mergeMessages(thread, [{ ...a, read_at: at(-1), updated_at: at(-1) }]);
  assert.ok(thread[0].read_at, "a newer one does");
  // Marked read here, and the server's unchanged copy comes back in the overlap.
  const local = [{ ...b, read_at: at(0) }];
  assert.ok(mergeMessages(local, [b])[0].read_at);
  assert.equal(mergeMessages([], Array.from({ length: 5 }, (_, i) => msg(`m${i}`, i)), 3).map((m) => m.id).join(), "m2,m3,m4");
});

test("pollSince looks back from the newest change", () => {
  assert.equal(pollSince([]), null);
  assert.equal(pollSince([msg("a", -10), msg("b", -5, { updated_at: at(-1) })]), new Date(NOW - 60_000 - OVERLAP_MS).toISOString());
});

test("runs, days and statuses", () => {
  const a = msg("a", -30);
  assert.equal(startsRun(a, undefined), true);
  assert.equal(startsRun(msg("b", -28), a), false);
  assert.equal(startsRun(msg("b", -28, { sender_name: "Leo" }), a), true);
  assert.equal(startsRun(msg("b", -19), a), true, "ten minutes on");
  assert.equal(startsRun(msg("b", -28, { sender_kind: "person" }), a), true);

  const tz = "America/Chicago";
  assert.equal(dayHeading(at(-30), NOW, tz), "Today");
  assert.equal(dayHeading(at(-24 * 60), NOW, tz), "Yesterday");
  assert.equal(dayHeading(at(-3 * 24 * 60), NOW, tz), "Saturday");
  assert.equal(dayHeading(at(-20 * 24 * 60), NOW, tz), "Oct 14");
  assert.equal(dayHeading("2025-12-24T18:00:00Z", NOW, tz), "Dec 24, 2025");

  const days = threadDays([msg("t2", -2), msg("y", -24 * 60), msg("t1", -3)], NOW, tz);
  assert.deepEqual(days.map((d) => d.title), ["Yesterday", "Today"]);
  assert.deepEqual(days[1].items.map((i) => [i.message.id, i.runStart]), [["t1", true], ["t2", false]]);

  assert.equal(replyStatus(msg("r", 0, { sender_kind: "person" })), "Sent");
  assert.equal(replyStatus(msg("r", 0, { sender_kind: "person", read_at: at(0) })), "Seen at home");
  assert.equal(notifyNote(msg("n", 0, { notify_error: "no phone has turned on notifications yet" })), "No notification: no phone has turned on notifications yet");
  assert.equal(notifyNote(msg("n", 0, { notified_at: at(0) })), null);
  assert.equal(unreadFromHome([msg("u", 0), msg("r", 0, { read_at: at(0) }), msg("p", 0, { sender_kind: "person" })]).length, 1);
});

test("away mode ends on its own", () => {
  const tz = "America/Chicago";
  assert.equal(isAway(NOT_AWAY, NOW), false);
  const away = { since: at(-60), until: null, note: "At work", name: "Dad" };
  assert.equal(isAway(away, NOW), true);
  assert.equal(awayLabel(away, NOW, tz), "Away");
  assert.equal(awayLabel({ ...away, until: at(120) }, NOW, tz), "Away until 6:00 PM");
  assert.equal(awayLabel({ ...away, until: at(24 * 60) }, NOW, tz), "Away until Wednesday 4:00 PM");
  assert.equal(isAway({ ...away, until: at(-1) }, NOW), false, "run out");
  assert.equal(awayLabel({ ...away, until: at(-1) }, NOW, tz), "Home");
  assert.equal(awayUntil("", NOW), null);
  assert.equal(awayUntil("3", NOW), new Date(NOW + 3 * 3_600_000).toISOString());
  assert.equal(awayUntil("99", NOW), null);
});

test("parseNames takes lines or commas", () => {
  assert.deepEqual(parseNames(" Mia, Leo\nmia\n\n Sam "), ["Mia", "Leo", "Sam"]);
  assert.deepEqual(parseNames(""), []);
});

test("the demo has news from home", () => {
  const thread = demoMessages(NOW);
  assert.equal(unreadFromHome(thread).length, 2);
  assert.equal(thread.at(-1).sender_name, "Mia");
});
