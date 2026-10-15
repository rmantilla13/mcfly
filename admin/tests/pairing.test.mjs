// The pairing code as /pair?code= and the claim form take it (lib/pairing.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { formatCode, isCompleteCode, sanitizeCode } from "../lib/pairing.ts";

test("keeps only the first six digits", () => {
  assert.equal(sanitizeCode("123456"), "123456");
  assert.equal(sanitizeCode("12 34-56"), "123456");
  assert.equal(sanitizeCode("1234567890"), "123456");
  assert.equal(sanitizeCode("12"), "12");
});

test("drops anything that isn't a digit, however it got into the URL", () => {
  for (const v of ["<script>alert(x)</script>", "javascript:void", "'; drop table", "", "abc"]) assert.equal(sanitizeCode(v), "");
  // Digits inside markup are still just digits; nothing else survives.
  assert.equal(sanitizeCode("<b>12</b>3"), "123");
  assert.equal(sanitizeCode("<script>alert(1)</script>"), "1");
  for (const v of ["javascript:1", "%3Cimg%20src=x%3E99", "a1b2c3d4e5f6g7"]) assert.match(sanitizeCode(v), /^[0-9]{0,6}$/);
});

test("ignores non-strings", () => {
  for (const v of [null, undefined, 123456, ["123456"], {}]) assert.equal(sanitizeCode(v), "");
});

test("only six digits is a complete code", () => {
  assert.equal(isCompleteCode("123456"), true);
  assert.equal(isCompleteCode("12345"), false);
  assert.equal(isCompleteCode("1234567"), false);
  assert.equal(isCompleteCode("12345a"), false);
});

test("formatCode splits a complete code for reading", () => {
  assert.equal(formatCode("123456"), "123 456");
  assert.equal(formatCode("123"), "123");
});
