// One voice for the account, read from the displays (lib/account-voice.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { accountVoice, followVoice, isKokoroVoice } from "../lib/account-voice.ts";

test("the account's voice is the first display's that has one", () => {
  assert.equal(accountVoice([]), null);
  assert.equal(accountVoice([{ settings: {} }, { settings: null }]), null);
  assert.equal(accountVoice([{ settings: {} }, { settings: { voice: "am_fenrir" } }, { settings: { voice: "af_bella" } }]), "am_fenrir");
  assert.equal(accountVoice([{ settings: { voice: "af_bella" } }, { settings: { voice: "am_michael" } }]), "af_bella");
});

test("a voice that isn't Kokoro's is skipped", () => {
  assert.equal(accountVoice([{ settings: { voice: "system" } }, { settings: { voice: "am_michael" } }]), "am_michael");
  assert.equal(accountVoice([{ settings: { voice: 3 } }]), null);
  assert.equal(isKokoroVoice("system"), false);
  assert.equal(isKokoroVoice("af_heart"), true);
});

test("this device's voice stays; a Kokoro voice follows the account", () => {
  assert.equal(followVoice("system", "af_bella"), "system");
  assert.equal(followVoice("af_heart", "af_bella"), "af_bella");
  assert.equal(followVoice("am_fenrir", null), "am_fenrir"); // no display: the local choice is all there is
  assert.equal(followVoice("system", null), "system");
});
