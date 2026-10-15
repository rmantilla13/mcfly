// Unit tests for the pairing rules: `deno test pair-device/`.

import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { CODE, deviceName, randomCode, SECRET_HASH } from "./pairing.ts";

Deno.test("randomCode: six digits, padded", () => {
  for (let i = 0; i < 50; i++) assertMatch(randomCode(), CODE);
});

Deno.test("deviceName: trimmed, capped, defaulted", () => {
  assertEquals(deviceName("  Kitchen  "), "Kitchen");
  assertEquals(deviceName(""), "Display");
  assertEquals(deviceName(42), "Display");
  assertEquals(deviceName("x".repeat(100)).length, 80);
});

Deno.test("shapes", () => {
  assertEquals(CODE.test("012345"), true);
  assertEquals(CODE.test("12345"), false);
  assertEquals(SECRET_HASH.test("a".repeat(64)), true);
  assertEquals(SECRET_HASH.test("A".repeat(64)), false);
});
