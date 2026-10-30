// Answers the person cut short, the history the Ask proxy passes on, and
// whether a question was suggested rather than the person's own (lib/ask-turns.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { afterStop, askHistory, askSuggested, assistantBody, markCutShort } from "../lib/ask-turns.ts";

const q = { role: "user", text: "What's on this weekend?" };

test("talked over: the answer at the end is marked", () => {
  const turns = [q, { role: "assistant", text: "Saturday you have brunch." }];
  assert.deepEqual(markCutShort(turns), [q, { role: "assistant", text: "Saturday you have brunch.", interrupted: true }]);
  assert.equal(turns[1].interrupted, undefined); // the input isn't changed
  // Nothing to mark: the same array back.
  for (const same of [[], [q], [q, { role: "assistant", text: "" }], markCutShort(turns)]) assert.equal(markCutShort(same), same);
});

test("stopped: what came is kept and marked; nothing yet, the question stays", () => {
  assert.deepEqual(afterStop([q, { role: "assistant", text: "Saturday you" }]), [q, { role: "assistant", text: "Saturday you", interrupted: true }]);
  assert.deepEqual(afterStop([q, { role: "assistant", text: "" }]), [q]);
  assert.deepEqual(afterStop([]), []); // a new conversation started meanwhile
});

test("the proxy's history: last ten, clipped, only answers cut short", () => {
  assert.deepEqual(askHistory("none"), []);
  assert.deepEqual(
    askHistory([
      { role: "user", text: "a", interrupted: true },
      { role: "assistant", text: "b", interrupted: true },
      { role: "assistant", text: "c", interrupted: "yes" },
      { role: "system", text: "x" },
      { role: "user", text: 7 },
      null,
    ]),
    [
      { role: "user", text: "a" },
      { role: "assistant", text: "b", interrupted: true },
      { role: "assistant", text: "c" },
    ],
  );
  const many = Array.from({ length: 12 }, (_, i) => ({ role: "user", text: `${i}`.repeat(i === 11 ? 5000 : 1) }));
  const out = askHistory(many);
  assert.equal(out.length, 10);
  assert.equal(out[0].text, "2");
  assert.equal(out[9].text.length, 4000);
});

test("suggested: only a page that says so; the person's own questions go as before", () => {
  assert.equal(askSuggested(true), true);
  for (const not of [undefined, null, false, "true", 1, {}]) assert.equal(askSuggested(not), false, String(not));
});

test("the assistant hears suggested only when it was", () => {
  const history = [q];
  assert.deepEqual(assistantBody("Tell me more about the rollout", history, "read", true), {
    message: "Tell me more about the rollout",
    history,
    mode: "read",
    stream: true,
    suggested: true,
  });
  // Typed or spoken: no key at all, as an older console sent it.
  const own = assistantBody("Ship it", history, "chat", false);
  assert.deepEqual(own, { message: "Ship it", history, mode: "chat", stream: true });
  assert.equal("suggested" in own, false);
});
