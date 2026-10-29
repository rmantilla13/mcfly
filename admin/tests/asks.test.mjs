// Questions agents wait on (lib/asks.ts): the open ones, oldest first, and
// answer_ask's refusal when another screen got there first.
import assert from "node:assert/strict";
import { test } from "node:test";
import { answeredElsewhere, demoAsks, openAsks } from "../lib/asks.ts";

const NOW = Date.parse("2026-10-29T20:00:00Z");
const ask = (id, created, extra = {}) => ({
  id,
  question: `${id}?`,
  detail: null,
  choices: ["Yes", "No"],
  url: null,
  expires_at: null,
  created_at: created,
  agent_name: "Grok",
  agent_color: "#7A64E8",
  ...extra,
});

test("the open ones, oldest first", () => {
  const rows = [
    ask("newer", "2026-10-29T19:50:00Z", { expires_at: "2026-10-29T21:00:00Z" }),
    ask("ran-out", "2026-10-29T18:00:00Z", { expires_at: "2026-10-29T19:59:00Z" }),
    ask("older", "2026-10-29T19:00:00Z"),
    ask("one-choice", "2026-10-29T19:30:00Z", { choices: ["Only"] }),
  ];
  assert.deepEqual(openAsks(rows, NOW).map((a) => a.id), ["older", "newer"]);
});

test("answered on another screen first", () => {
  assert.equal(answeredElsewhere("already answered: Hold"), "Hold");
  assert.equal(answeredElsewhere("Already answered: Ship it."), "Ship it");
  assert.equal(answeredElsewhere("This question ran out."), null);
});

test("the demo asks the display's two", () => {
  const asks = demoAsks([{ id: "a1", name: "Grok", kind: "grok", color: "#7A64E8" }, { id: "a3", name: "Daily Pulse", kind: "news", color: "#E2725B" }], NOW);
  assert.deepEqual(asks.map((a) => a.choices), [["Ship it", "Hold"], ["Chips", "Rates", "Launch"]]);
  assert.equal(asks[1].agent_name, "Daily Pulse");
  assert.deepEqual(openAsks(asks, NOW).map((a) => a.id), asks.map((a) => a.id));
});
