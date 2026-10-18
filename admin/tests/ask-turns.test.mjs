// Answers the person cut short, and the history the Ask proxy passes on (lib/ask-turns.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { afterStop, askHistory, markCutShort } from "../lib/ask-turns.ts";

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
