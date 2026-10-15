// Speech pieces for the Kokoro voice (lib/sentences.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { speechPieces } from "../lib/sentences.ts";

test("sentences, markdown and links cleaned", () => {
  // The first sentence is short, so it rides along with the second.
  assert.deepEqual(speechPieces("**Markets** are up today, led by NVDA. See https://x.com/a for more! Standup is at 9:30."), [
    "Markets are up today, led by NVDA. See a link for more!",
    "Standup is at 9:30.",
  ]);
  assert.deepEqual(speechPieces("   "), []);
});

test("short ones merge, long ones split under the limit", () => {
  assert.deepEqual(speechPieces("Hi. Here is the news."), ["Hi. Here is the news."]);
  const long = ("word ".repeat(120) + "end.").trim();
  const pieces = speechPieces(long);
  assert.ok(pieces.length >= 3);
  for (const p of pieces) assert.ok(p.length <= 220, p.length);
  assert.equal(pieces.join(" ").replace(/\s+/g, " "), long);
});

test("a sentence without a full stop is kept", () => {
  assert.deepEqual(speechPieces("No punctuation at the end"), ["No punctuation at the end"]);
});
