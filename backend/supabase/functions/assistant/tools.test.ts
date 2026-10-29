// Unit tests for the assistant's tools: `deno test assistant/`.

import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import {
  type Changed,
  CLAUDE_TOOLS,
  type EventItem,
  GROK_TOOLS,
  grokArguments,
  GrokToolCalls,
  MAX_WRITES,
  parseInput,
  parseLocal,
  saidChoice,
  type Store,
  type TodoItem,
  ToolRunner,
  zonedToUtc,
} from "./tools.ts";

const CHI = "America/Chicago";
const at = (s: string) => new Date(s).getTime();
const utc = (s: string, tz = CHI) => {
  const t = parseLocal(s);
  if (!t) throw new Error(`bad local time ${s}`);
  return new Date(zonedToUtc(t, tz)).toISOString();
};
// Thursday, October 15, 2026, 6:10 PM in Chicago (CDT).
const NOW = at("2026-10-15T23:10:00Z");
let n = 0;
const ctx = { tz: CHI, now: NOW, newId: () => `id-${++n}` };

Deno.test("parseLocal: a day or a day and time, and nothing else", () => {
  assertEquals(parseLocal("2026-10-16T15:00"), { y: 2026, mo: 10, d: 16, h: 15, mi: 0, hasTime: true });
  assertEquals(parseLocal(" 2026-10-16 15:30:00 "), { y: 2026, mo: 10, d: 16, h: 15, mi: 30, hasTime: true });
  assertEquals(parseLocal("2026-10-16"), { y: 2026, mo: 10, d: 16, h: 0, mi: 0, hasTime: false });
  for (const bad of ["2026-11-31", "2026-02-29", "2026-13-01", "2026-10-16T24:00", "2026-10-16T15:00Z", "2026-10-16T15:00-05:00", "tomorrow", "", 5, null]) {
    assertEquals(parseLocal(bad), null, String(bad));
  }
  assertEquals(parseLocal("2028-02-29")?.d, 29);
});

Deno.test("zonedToUtc: the display's zone, across daylight saving", () => {
  // US clocks go back on Sunday, November 1, 2026.
  assertEquals(utc("2026-10-31T09:00"), "2026-10-31T14:00:00.000Z"); // CDT, -5
  assertEquals(utc("2026-11-02T09:00"), "2026-11-02T15:00:00.000Z"); // CST, -6
  assertEquals(utc("2026-11-01T01:30"), "2026-11-01T06:30:00.000Z"); // twice: the first
  assertEquals(utc("2026-11-01T03:00"), "2026-11-01T09:00:00.000Z");
  // Forward on March 8, 2026: 2:30 never happens, read as 3:30 CDT.
  assertEquals(utc("2026-03-08T02:30"), "2026-03-08T08:30:00.000Z");
  assertEquals(utc("2026-03-08T03:30"), "2026-03-08T08:30:00.000Z");
  assertEquals(utc("2026-10-16T09:00", "Asia/Kolkata"), "2026-10-16T03:30:00.000Z");
  assertEquals(utc("2026-10-16T09:00", "UTC"), "2026-10-16T09:00:00.000Z");
  assertEquals(utc("2026-12-31T23:59", "Pacific/Auckland"), "2026-12-31T10:59:00.000Z");
});

Deno.test("parseInput: events, timed and all day", () => {
  assertEquals(parseInput("add_event", { title: " Dentist ", start: "2026-10-16T15:00", location: "Main St" }, ctx), {
    ok: true,
    action: {
      tool: "add_event",
      event: {
        id: `id-${n}`, calendar: "McFly", title: "Dentist", starts_at: "2026-10-16T20:00:00.000Z", ends_at: "2026-10-16T21:00:00.000Z",
        all_day: false, location: "Main St", data: { via: "assistant" },
      },
    },
  });
  const allDay = parseInput("add_event", { title: "Trip", start: "2026-10-31", end: "2026-11-02", notes: "  pack  light " }, ctx);
  assertEquals(allDay.ok && allDay.action.tool === "add_event" && allDay.action.event, {
    id: `id-${n}`, calendar: "McFly", title: "Trip", starts_at: "2026-10-31T05:00:00.000Z", ends_at: "2026-11-03T05:59:59.000Z",
    all_day: true, description: "pack light", data: { via: "assistant" },
  });
  const one = parseInput("add_event", { title: "Holiday", start: "2026-11-26" }, ctx);
  assertEquals(one.ok && one.action.tool === "add_event" && [one.action.event.starts_at, one.action.event.ends_at],
    ["2026-11-26T06:00:00.000Z", "2026-11-27T05:59:59.000Z"]);
  const long = parseInput("add_event", { title: "Call", start: "2026-10-16T09:00", end: "2026-10-16T09:20" }, ctx);
  assertEquals(long.ok && long.action.tool === "add_event" && long.action.event.ends_at, "2026-10-16T14:20:00.000Z");
});

Deno.test("parseInput: what events refuse", () => {
  const err = (input: Record<string, unknown>) => {
    const r = parseInput("add_event", input, ctx);
    return r.ok ? "ok" : r.error;
  };
  assertEquals(err({ start: "2026-10-16T15:00" }), "title is required");
  assertMatch(err({ title: "x", start: "tomorrow at 3" }), /^start must be local time/);
  assertEquals(err({ title: "x", start: "2026-10-16T15:00", end: "2026-10-16" }), "start and end must both have a time, or both be days (all day)");
  assertEquals(err({ title: "x", start: "2026-10-16T15:00", end: "2026-10-16T14:00" }), "end is before start");
  assertEquals(err({ title: "x", start: "2036-10-16T15:00" }), "start is too far from today; check the year");
  assertEquals(err({ title: "x", start: "2026-10-16", end: "2028-10-16" }), "an event can't run longer than a year");
  assertEquals(parseInput("add_event", "x", ctx), { ok: false, error: "the input must be an object" });
  assertEquals(parseInput("delete_everything", {}, ctx), { ok: false, error: "there is no tool called delete_everything" });
});

Deno.test("parseInput: todos and reminders", () => {
  const plain = parseInput("add_todo", { title: "Buy milk" }, ctx);
  assertEquals(plain.ok && plain.action.tool === "add_todo" && plain.action.todo,
    { id: `id-${n}`, kind: "todo", title: "Buy milk", data: { via: "assistant" } });
  const day = parseInput("add_todo", { title: "File taxes", due: "2026-11-02", notes: "extension" }, ctx);
  assertEquals(day.ok && day.action.tool === "add_todo" && day.action.todo, {
    id: `id-${n}`, kind: "todo", title: "File taxes", due_at: "2026-11-02T06:00:00.000Z", all_day: true, notes: "extension", data: { via: "assistant" },
  });
  const time = parseInput("add_todo", { title: "Send invoice", due: "2026-10-16T17:00" }, ctx);
  assertEquals(time.ok && time.action.tool === "add_todo" && [time.action.todo.due_at, time.action.todo.all_day],
    ["2026-10-16T22:00:00.000Z", undefined]);
  const reminder = parseInput("add_reminder", { title: "Call mom", at: "2026-11-02T17:00" }, ctx);
  assertEquals(reminder.ok && reminder.action.tool === "add_reminder" && reminder.action.todo,
    { id: `id-${n}`, kind: "reminder", title: "Call mom", due_at: "2026-11-02T23:00:00.000Z", data: { via: "assistant" } });

  const err = (name: string, input: Record<string, unknown>) => {
    const r = parseInput(name, input, ctx);
    return r.ok ? "ok" : r.error;
  };
  assertMatch(err("add_todo", { title: "x", due: "Friday" }), /^due must be a day/);
  assertMatch(err("add_reminder", { title: "x", at: "2026-10-16" }), /^at must be local time/);
  // 5:00 PM today has passed at 6:10 PM; a minute ago is still fine.
  assertEquals(err("add_reminder", { title: "x", at: "2026-10-15T17:00" }),
    "that time has already passed (it's Thu, Oct 15, 6:10 PM now); use the next time it comes round, or ask");
  assertEquals(err("add_reminder", { title: "x", at: "2026-10-15T18:10" }), "ok");
  assertEquals(err("complete_todo", {}), "id is required: the todo's id from the snapshot");
  assertEquals(err("answer_ask", { choice: "Hold" }), "id is required: the question's id from the snapshot");
  assertEquals(err("answer_ask", { id: "a-1" }), "choice is required: one of the question's choices");
});

class FakeStore implements Store {
  events: EventItem[] = [];
  todos: TodoItem[] = [];
  done: string[] = [];
  answers: [string, string][] = [];
  answerError: string | null = null;
  logs: [Changed, boolean][] = [];
  agentCalls = 0;
  failWith: string | null = null;

  agent() {
    this.agentCalls++;
    return Promise.resolve("agent-mcfly");
  }
  addEvent(_agent: string, event: EventItem) {
    if (this.failWith) return Promise.reject(new Error(this.failWith));
    this.events.push(event);
    return Promise.resolve();
  }
  addTodo(_agent: string, todo: TodoItem) {
    if (this.failWith) return Promise.reject(new Error(this.failWith));
    this.todos.push(todo);
    return Promise.resolve(`row-${this.todos.length}`);
  }
  setDone(id: string) {
    if (this.failWith) return Promise.reject(new Error(this.failWith));
    this.done.push(id);
    return Promise.resolve();
  }
  answerAsk(id: string, choice: string) {
    if (this.answerError) return Promise.reject(new Error(this.answerError));
    this.answers.push([id, choice]);
    return Promise.resolve({ answer: choice });
  }
  log(_agent: string, feed: Changed, ok: boolean) {
    this.logs.push([feed, ok]);
    return Promise.resolve();
  }
}

Deno.test("ToolRunner: writes, and says what it saved in local time", async () => {
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [{ id: "t-1", title: "Buy milk" }], () => NOW);
  assertEquals(await runner.run("add_event", { title: "Dentist", start: "2026-11-02T15:00" }),
    { content: 'Saved. Event "Dentist", Mon, Nov 2, 3:00 PM to 4:00 PM, on McFly\'s calendar.', isError: false });
  assertEquals(await runner.run("add_event", { title: "Trip", start: "2026-10-31", end: "2026-11-01", location: "Austin" }),
    { content: 'Saved. Event "Trip", Sat, Oct 31 to Sun, Nov 1 (all day), at Austin, on McFly\'s calendar.', isError: false });
  assertEquals(await runner.run("add_todo", { title: "File taxes", due: "2026-11-02" }),
    { content: 'Saved. Todo "File taxes", due Mon, Nov 2.', isError: false });
  assertEquals(await runner.run("add_reminder", { title: "Call mom", at: "2026-10-16T17:00" }),
    { content: 'Saved. Reminder "Call mom" at Fri, Oct 16, 5:00 PM; the display will announce it then.', isError: false });
  assertEquals(await runner.run("complete_todo", { id: "t-1" }), { content: 'Checked off: "Buy milk".', isError: false });
  assertEquals(store.events.map((e) => e.starts_at), ["2026-11-02T21:00:00.000Z", "2026-10-31T05:00:00.000Z"]);
  assertEquals(store.todos.map((t) => [t.kind, t.title]), [["todo", "File taxes"], ["reminder", "Call mom"]]);
  assertEquals(store.done, ["t-1"]);
  assertEquals(store.agentCalls, 1, "the agent is looked up once");
  assertEquals([...runner.changed].sort(), ["events", "todos"]);
  assertEquals(runner.writes, 5);
  assertEquals(store.logs, [["events", true], ["events", true], ["todos", true], ["todos", true]]);
});

Deno.test("ToolRunner: refuses, repeats once, caps, and reports failures", async () => {
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [{ id: "t-1", title: "Buy milk" }], () => NOW);
  const bad = await runner.run("add_reminder", { title: "x" });
  assertEquals(bad.isError, true);
  assertMatch(bad.content, /^Not saved: at must be/);
  assertEquals((await runner.run("complete_todo", { id: "t-9" })).content,
    "Not changed: no open todo or reminder has that id. Use an id from the snapshot's todo list.");

  assertEquals((await runner.run("add_todo", { title: "Buy milk" })).isError, false);
  assertEquals(await runner.run("add_todo", { title: "buy milk " }), { content: "Already saved in this answer; nothing more to do.", isError: false });
  assertEquals(store.todos.length, 1, "saved once");
  assertEquals((await runner.run("complete_todo", { id: "t-1" })).isError, false);
  assertEquals((await runner.run("complete_todo", { id: "t-1" })).content, "Already saved in this answer; nothing more to do.");

  for (let i = runner.writes; i < MAX_WRITES; i++) await runner.run("add_todo", { title: `Task ${i}` });
  const capped = await runner.run("add_todo", { title: "One too many" });
  assertEquals(capped.isError, true);
  assertMatch(capped.content, new RegExp(`at most ${MAX_WRITES} changes per question`));

  const broken = new FakeStore();
  broken.failWith = "connection reset";
  const r2 = new ToolRunner(broken, CHI, [{ id: "t-1", title: "Buy milk" }], () => NOW);
  assertEquals((await r2.run("add_event", { title: "x", start: "2026-10-16T09:00" })).content,
    "Not saved: it couldn't be written just now. Say so, and that they can try again in a moment.");
  assertEquals((await r2.run("complete_todo", { id: "t-1" })).content, "Not changed: the todo list couldn't be updated just now.");
  assertEquals(broken.logs, [["events", false]]);
  assertEquals([r2.writes, r2.changed.size], [0, 0]);
});

Deno.test("saidChoice: the choice in the person's own words", () => {
  assertEquals(saidChoice("OK, ship it!", "Ship it"), true);
  assertEquals(saidChoice("tell Grok to hold", "Hold"), true);
  assertEquals(saidChoice("ship", "Ship it"), false);
  assertEquals(saidChoice("householder", "Hold"), false, "a whole word, not part of one");
  assertEquals(saidChoice("go ahead", "Yes"), true);
  assertEquals(saidChoice("Nope, don’t renew it", "No"), true);
  assertEquals(saidChoice("go ahead", "Ship it"), false, "yes-words only stand in for Yes");
  assertEquals(saidChoice("what does Grok want?", "Yes"), false);
  assertEquals(saidChoice("B", "b"), true);
});

const ASKS = [
  { id: "a-1", question: "Ship v2.3 to TestFlight?", choices: ["Ship it", "Hold"], agent: "Grok" },
  { id: "a-2", question: "Renew the domain?", choices: ["Yes", "No"], agent: "Ops" },
];

Deno.test("ToolRunner: answers an ask only with the choice the person said", async () => {
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "Tell Grok to ship it");
  assertEquals(await runner.run("answer_ask", { id: "a-1", choice: "ship IT" }), {
    content: 'Answered Grok\'s question "Ship v2.3 to TestFlight?": Ship it. Grok will read it when it next checks.',
    isError: false,
  });
  assertEquals(store.answers, [["a-1", "Ship it"]], "the agent's own label");
  assertEquals([...runner.changed], ["asks"]);
  assertEquals((await runner.run("answer_ask", { id: "a-1", choice: "Ship it" })).content, "Already saved in this answer; nothing more to do.");
  // The person said nothing about the domain: a pick the model made up (or
  // was talked into by something in the snapshot) is refused.
  assertEquals(await runner.run("answer_ask", { id: "a-2", choice: "Yes" }), {
    content: 'Not answered: they didn\'t say "Yes" themselves. Ask them to say "Yes" or "No".',
    isError: true,
  });
  assertEquals((await runner.run("answer_ask", { id: "a-1x", choice: "Hold" })).content,
    'Not answered: no open question has that id. Use an id from the snapshot\'s "Waiting on them" list.');
  assertEquals(store.answers.length, 1);

  const other = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "maybe later");
  assertEquals((await other.run("answer_ask", { id: "a-1", choice: "Later" })).content, 'Not answered: the choices are "Ship it" or "Hold".');
  assertEquals((await new ToolRunner(store, CHI, [], () => NOW).run("answer_ask", { id: "a-1", choice: "Hold" })).isError, true,
    "nothing offered, nothing answered");
});

Deno.test("ToolRunner: an ask answered elsewhere, taken back or broken", async () => {
  const store = new FakeStore();
  const said = (s: string) => new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, s);
  store.answerError = "already answered: Hold";
  assertEquals((await said("ship it").run("answer_ask", { id: "a-1", choice: "Ship it" })).content,
    'Not answered: it was already answered "Hold", on another screen.');
  store.answerError = "the agent took this question back";
  assertEquals((await said("ship it").run("answer_ask", { id: "a-1", choice: "Ship it" })).content,
    "Not answered: the agent took this question back.");
  store.answerError = "connection reset";
  const broken = said("yes");
  assertEquals((await broken.run("answer_ask", { id: "a-2", choice: "Yes" })).content,
    "Not answered: it couldn't be saved just now. Say so, and that they can try again in a moment.");
  assertEquals([broken.writes, broken.changed.size], [0, 0]);
});

Deno.test("definitions: the same five tools for both providers", () => {
  const names = ["add_event", "add_todo", "add_reminder", "complete_todo", "answer_ask"];
  assertEquals(CLAUDE_TOOLS.map((t) => t.name), names);
  assertEquals(GROK_TOOLS.map((t) => t.function.name), names);
  for (const t of CLAUDE_TOOLS) assertEquals((t.input_schema as unknown as { additionalProperties: boolean }).additionalProperties, false);
});

Deno.test("GrokToolCalls: pieces by index become whole calls", () => {
  const calls = new GrokToolCalls();
  calls.push([{ index: 0, id: "call_a", type: "function", function: { name: "add_todo", arguments: '{"tit' } }]);
  calls.push([{ index: 0, function: { arguments: 'le":"Buy milk"}' } }, { index: 1, function: { name: "add_reminder", arguments: "" } }]);
  calls.push([{ index: 1, function: { arguments: '{"title":"Call mom","at":"2026-10-16T17:00"}' } }]);
  calls.push("junk");
  calls.push([null, { index: 2, function: {} }]);
  assertEquals(calls.calls, [
    { id: "call_a", name: "add_todo", arguments: '{"title":"Buy milk"}' },
    { id: "call_1", name: "add_reminder", arguments: '{"title":"Call mom","at":"2026-10-16T17:00"}' },
  ]);
  assertEquals(grokArguments('{"title":"x"}'), { ok: true, input: { title: "x" } });
  assertEquals(grokArguments(""), { ok: true, input: {} });
  assertEquals(grokArguments("{oops"), { ok: false, error: "the arguments weren't valid JSON" });
});
