// Dismissed callouts (lib/dismissals.ts): an id's dismissal hides it until it runs out.
import assert from "node:assert/strict";
import { test } from "node:test";
import { isDismissed } from "../lib/dismissals.ts";

const NOW = Date.parse("2026-10-21T20:00:00Z");

test("a dismissal hides its id, any case, until it runs out", () => {
  const dismissals = [
    { key: "blocked:0f1e", hide_until: null }, // until the project changes
    { key: "metric:sales.today", hide_until: "2026-10-22T05:00:00Z" }, // tonight
    { key: "mover:aapl", hide_until: "2026-10-21T05:00:00Z" }, // ran out this morning
  ];
  assert.equal(isDismissed(dismissals, "blocked:0F1E", NOW), true);
  assert.equal(isDismissed(dismissals, " metric:sales.today ", NOW), true);
  assert.equal(isDismissed(dismissals, "mover:AAPL", NOW), false);
  assert.equal(isDismissed(dismissals, "blocked:other", NOW), false);
  assert.equal(isDismissed([], "errors", NOW), false);
});
