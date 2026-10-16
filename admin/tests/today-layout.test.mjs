// lib/today-layout.ts: the cookie that picks the Today page's layout.
import assert from "node:assert/strict";
import { test } from "node:test";
import { TODAY_LAYOUTS, todayLayout } from "../lib/today-layout.ts";

test("a known layout passes", () => {
  for (const l of TODAY_LAYOUTS) assert.equal(todayLayout(l), l);
});

test("anything else is today", () => {
  for (const v of [undefined, null, "", "masonry", "Bento", "today; path=/"]) assert.equal(todayLayout(v), "today");
});
