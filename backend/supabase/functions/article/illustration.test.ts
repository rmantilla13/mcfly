// Unit tests for Grok's story pictures: `deno test article/`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  DEFAULT_IMAGE_MODEL,
  ILLUSTRATION_RETRY_MS,
  illustrationPath,
  illustrationPrompt,
  illustrationRequest,
  imageModelName,
  needsIllustration,
  readIllustration,
} from "./illustration.ts";

const b64 = (bytes: number[]) => btoa(String.fromCharCode(...bytes));
const jpeg = [0xff, 0xd8, 0xff, 0xe0, ...Array(200).fill(7)];
const png = [0x89, 0x50, 0x4e, 0x47, ...Array(200).fill(7)];

Deno.test("illustrationPrompt: the story's idea, no words, marks or real people", () => {
  const prompt = illustrationPrompt({ headline: "Musk changes X's   algorithm", takeaway: "Watch time counts more.", section_name: "Social" });
  assert(prompt.includes("Story: Musk changes X's algorithm"));
  assert(prompt.includes("What it means: Watch time counts more."));
  assert(prompt.includes("Section: Social"));
  assert(prompt.includes("No text, letters, numbers, logos"));
  assert(prompt.includes("No real or recognizable people"));
  assert(!illustrationPrompt({ headline: "H", takeaway: "" }).includes("What it means"));
  assert(illustrationPrompt({ headline: "x".repeat(1000) }).length < 1200, "a long headline is cut");
});

Deno.test("illustrationRequest and imageModelName", () => {
  assertEquals(illustrationRequest("m", "p"), { model: "m", prompt: "p", n: 1, aspect_ratio: "4:3", resolution: "1k", response_format: "b64_json" });
  assertEquals(imageModelName({ get: () => undefined }), DEFAULT_IMAGE_MODEL);
  assertEquals(imageModelName({ get: () => " grok-imagine-image-3 " }), "grok-imagine-image-3");
});

Deno.test("readIllustration: JPEG and PNG bytes; anything else is no picture", () => {
  assertEquals(readIllustration({ data: [{ b64_json: b64(jpeg) }] })?.type, "image/jpeg");
  assertEquals(readIllustration({ data: [{ b64_json: "data:image/png;base64," + b64(png) }] })?.type, "image/png");
  assertEquals(readIllustration({ data: [{ b64_json: b64(jpeg) }] })?.bytes.length, jpeg.length);
  assertEquals(readIllustration({ data: [{ url: "https://imgen.x.ai/1.jpg" }] }), null);
  assertEquals(readIllustration({ data: [{ b64_json: b64([0x47, 0x49, 0x46, ...Array(200).fill(1)]) }] }), null, "not a kept format");
  assertEquals(readIllustration({ data: [{ b64_json: "%%%not base64" }] }), null);
  assertEquals(readIllustration({ data: [{ b64_json: b64([0xff, 0xd8]) }] }), null, "too small");
  assertEquals(readIllustration({ error: "rejected" }), null);
  assertEquals(readIllustration(null), null);
});

Deno.test("illustrationPath: the story's id and the picture's kind", () => {
  assertEquals(illustrationPath("0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61", "image/jpeg"), "0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61.jpg");
  assertEquals(illustrationPath("a", "image/png"), "a.png");
  assertEquals(illustrationPath("a", "image/webp"), "a.webp");
});

Deno.test("needsIllustration: none yet, not retried too soon", () => {
  const now = Date.parse("2026-10-21T12:00:00Z");
  assertEquals(needsIllustration(null, now), true);
  assertEquals(needsIllustration({ illustration: null, illustration_tried_at: null }, now), true);
  assertEquals(needsIllustration({ illustration: "a.jpg" }, now), false);
  assertEquals(needsIllustration({ illustration: null, illustration_tried_at: new Date(now - 60_000).toISOString() }, now), false);
  assertEquals(needsIllustration({ illustration: null, illustration_tried_at: new Date(now - ILLUSTRATION_RETRY_MS - 1).toISOString() }, now), true);
});
