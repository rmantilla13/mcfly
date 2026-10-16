// Who reads a reply aloud in the browser (lib/speech-engine.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { replySpeaker } from "../lib/speech-engine.ts";

const KOKORO = ["af_heart", "af_bella", "am_michael", "am_fenrir"];

test("a Kokoro voice waits for the model, never the browser's voice", () => {
  for (const voice of KOKORO) {
    assert.equal(replySpeaker(voice, "idle", true), "load");
    assert.equal(replySpeaker(voice, "loading", true), "load");
    assert.equal(replySpeaker(voice, "loading", false), "load");
    assert.equal(replySpeaker(voice, "ready", true), "kokoro");
    assert.equal(replySpeaker(voice, "ready", false), "kokoro");
  }
});

test("a failed load is tried once more before the browser's voice speaks", () => {
  assert.equal(replySpeaker("af_heart", "failed", true), "load");
  assert.equal(replySpeaker("af_heart", "failed", false), "browser");
});

test("this device's voice is the browser's, whatever Kokoro is doing", () => {
  for (const status of ["idle", "loading", "ready", "failed"]) {
    assert.equal(replySpeaker("system", status, true), "browser");
  }
});
