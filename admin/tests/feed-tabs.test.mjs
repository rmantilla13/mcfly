// ?tab= on /feed (lib/feed-tabs.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { readFeedTab } from "../lib/feed-tabs.ts";

test("names a tab or falls back to briefs", () => {
  assert.equal(readFeedTab("markets"), "markets");
  assert.equal(readFeedTab("news"), "news");
  for (const t of ["projects", "metrics", "dashboards", "calendar"]) assert.equal(readFeedTab(t), t);
  assert.equal(readFeedTab("events"), "briefs"); // the tab is named calendar
  assert.equal(readFeedTab(["news", "briefs"]), "news");
  for (const v of ["", "x", "__proto__", undefined]) assert.equal(readFeedTab(v), "briefs");
});
