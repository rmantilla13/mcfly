// Grok bot starters and schedule wording (lib/bots.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { BOT_STARTERS, SCHEDULES, scheduleLabel } from "../lib/bots.ts";

test("starters are complete and on a known schedule", () => {
  const minutes = SCHEDULES.map((s) => s.minutes);
  for (const b of BOT_STARTERS) {
    assert.ok(b.prompt.length >= 10 && b.name && b.label, b.id);
    assert.ok(minutes.includes(b.every_minutes), b.id);
    assert.ok(b.web_search || b.x_search, `${b.id} searches`);
  }
  assert.equal(new Set(BOT_STARTERS.map((b) => b.id)).size, BOT_STARTERS.length);
});

test("schedule wording", () => {
  assert.equal(scheduleLabel(1440, 420), "Daily at 7:00 AM");
  assert.equal(scheduleLabel(1440, null), "Once a day");
  assert.equal(scheduleLabel(60, null), "Every hour");
  assert.equal(scheduleLabel(180, 480), "Every 3 hours, from 8:00 AM");
  assert.equal(scheduleLabel(1440, 0), "Daily at 12:00 AM");
  assert.equal(scheduleLabel(1440, 1290), "Daily at 9:30 PM");
  assert.equal(scheduleLabel(45, null), "Every 45 minutes");
});
