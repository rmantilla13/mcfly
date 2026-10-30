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
  wordsOf,
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
  answers: [string, string, string][] = [];
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
  answerAsk(id: string, choice: string, question: string) {
    if (this.answerError) return Promise.reject(new Error(this.answerError));
    this.answers.push([id, choice, question]);
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

const YES_NO = ["Yes", "No"];
const SHIP = ["Ship it", "Hold"];

Deno.test("wordsOf: words in any script, without accents, case or emoji", () => {
  assertEquals(wordsOf("Sí, ship it! 👍"), ["si", "ship", "it"]);
  assertEquals(wordsOf("Don’t  'hold' — CAFÉ"), ["don't", "hold", "cafe"]);
  assertEquals(wordsOf("是的"), ["是的"]);
  assertEquals(wordsOf("👍"), []);
});

Deno.test("saidChoice: the choice in the person's own words", () => {
  assertEquals(saidChoice("OK, ship it!", "Ship it", SHIP), true);
  assertEquals(saidChoice("tell Grok to hold", "Hold", SHIP), true);
  assertEquals(saidChoice("‘ship it’", "Ship it", SHIP), true, "quotes round it");
  assertEquals(saidChoice("ship", "Ship it", SHIP), false);
  assertEquals(saidChoice("householder", "Hold", SHIP), false, "a whole word, not part of one");
  assertEquals(saidChoice("go ahead", "Yes", YES_NO), true);
  assertEquals(saidChoice("Do it.", "Yes", YES_NO), true, "an answer that opens with \"do\"");
  assertEquals(saidChoice("Affirmative", "Yes", YES_NO), true);
  assertEquals(saidChoice("Nope, don’t renew it", "No", YES_NO), true);
  assertEquals(saidChoice("No.", "No", YES_NO), true);
  assertEquals(saidChoice("no, hold off for now", "No", YES_NO), true);
  assertEquals(saidChoice("go ahead", "Ship it", SHIP), false, "yes-words only stand in for Yes");
  assertEquals(saidChoice("what does Grok want?", "Yes", YES_NO), false);
  assertEquals(saidChoice("B", "b", ["a", "b"]), true);
  assertEquals(saidChoice("", "Yes", YES_NO), false, "a suggested message says nothing");
});

Deno.test("saidChoice: filler, negations, questions and two choices don't answer", () => {
  // Each of these passed before: a word appeared, but nobody chose it.
  assertEquals(saidChoice("I'm not sure, what do you think?", "Yes", YES_NO), false);
  assertEquals(saidChoice("ok what's on today", "Yes", YES_NO), false);
  assertEquals(saidChoice("ok, what's Ops asking?", "Yes", YES_NO), false);
  assertEquals(saidChoice("sure", "Yes", YES_NO), false, "filler isn't yes");
  assertEquals(saidChoice("I don't know yet", "No", YES_NO), false);
  assertEquals(saidChoice("don't answer that yet", "No", YES_NO), false);
  assertEquals(saidChoice("I have no idea", "No", YES_NO), false, "a bare no only first");
  assertEquals(saidChoice("don't ship it", "Ship it", SHIP), false);
  assertEquals(saidChoice("dont ship it", "Ship it", SHIP), false);
  assertEquals(saidChoice("we won't ship it", "Ship it", SHIP), false);
  assertEquals(saidChoice("never hold", "Hold", SHIP), false);
  assertEquals(saidChoice("not approved", "Yes", YES_NO), false);
  assertEquals(saidChoice("don't go ahead", "Yes", YES_NO), false);
  assertEquals(saidChoice("should I ship it or hold?", "Ship it", SHIP), false);
  assertEquals(saidChoice("should I ship it or hold?", "Hold", SHIP), false);
  assertEquals(saidChoice("should I ship it", "Ship it", SHIP), false, "a question spoken without its ?");
  assertEquals(saidChoice("what's the hold up, ship it", "Ship it", SHIP), false);
  assertEquals(saidChoice("shouldn't we hold", "Hold", SHIP), false);
  assertEquals(saidChoice("Don't wait, ship it", "Ship it", SHIP), true, "an order, not a question");
  assertEquals(saidChoice("do it?", "Yes", YES_NO), false);
  assertEquals(saidChoice("what do they want me to say yes or no to?", "Yes", YES_NO), false);
  assertEquals(saidChoice("ship it or hold, I can't decide", "Ship it", SHIP), false, "two choices named");
  assertEquals(saidChoice("don't ship it", "Hold", SHIP), false, "turning one down isn't choosing the other");
  assertEquals(saidChoice("yes and no", "Yes", YES_NO), false);
  assertEquals(saidChoice("yes, no problem", "Yes", YES_NO), false, "a no anywhere is enough to doubt a yes");
  assertEquals(saidChoice("no, go ahead", "No", YES_NO), false, "a no-word and a yes-word");
  assertEquals(saidChoice("yeah, not now", "Yes", YES_NO), false);
  // Contractions ask as their verbs do, and a "?" may have more after it.
  assertEquals(saidChoice("can't we just ship it", "Ship it", SHIP), false);
  assertEquals(saidChoice("won't you hold", "Hold", SHIP), false);
  assertEquals(saidChoice("isn't it time to ship it", "Ship it", SHIP), false);
  assertEquals(saidChoice("Yes?!", "Yes", YES_NO), false);
  assertEquals(saidChoice("yes? 🙂", "Yes", YES_NO), false);
  assertEquals(saidChoice("ship it?...", "Ship it", SHIP), false);
  assertEquals(saidChoice("yes!", "Yes", YES_NO), true);
  assertEquals(saidChoice("ship it 🙂", "Ship it", SHIP), true);
});

Deno.test("saidChoice: a choice turned down beside the one chosen", () => {
  assertEquals(saidChoice("hold, don't ship it", "Hold", SHIP), true);
  assertEquals(saidChoice("don't hold, ship it", "Ship it", SHIP), true);
  assertEquals(saidChoice("don't hold off, go ahead", "Yes", YES_NO), true);
  assertEquals(saidChoice("don't hold, ship it", "Hold", SHIP), false);
});

Deno.test("saidChoice: a choice inside a longer one, and labels in other scripts", () => {
  const later = ["Ship it", "Ship it later"];
  assertEquals(saidChoice("ship it later", "Ship it later", later), true);
  assertEquals(saidChoice("ship it later", "Ship it", later), false);
  assertEquals(saidChoice("just ship it", "Ship it", later), true);
  // A word that says Yes or No and is also another label names both: the
  // message can't tell them apart, so neither passes.
  assertEquals(saidChoice("skip it", "No", ["Yes", "No", "Skip it"]), false);
  assertEquals(saidChoice("skip it", "Skip it", ["Yes", "No", "Skip it"]), false);
  assertEquals(saidChoice("approve", "Yes", ["Yes", "Approve"]), false);
  assertEquals(saidChoice("approve", "Approve", ["Yes", "Approve"]), false);
  assertEquals(saidChoice("go ahead", "Yes", ["Yes", "Go ahead"]), false);
  assertEquals(saidChoice("go ahead", "Go ahead", ["Yes", "Go ahead"]), false);
  assertEquals(saidChoice("yes", "Yes", ["Yes", "Approve"]), true, "the label itself still answers");
  assertEquals(saidChoice("sí", "Sí", ["Sí", "No"]), true);
  assertEquals(saidChoice("si", "Sí", ["Sí", "No"]), true, "the accent dropped");
  assertEquals(saidChoice("I like U.S. stocks", "Sí", ["Sí", "No"]), false, "\"Sí\" is si, not s");
  assertEquals(saidChoice("cafe", "Café", ["Café", "Tea"]), true);
  assertEquals(saidChoice("是", "是", ["是", "否"]), true);
  assertEquals(saidChoice("👍", "👍", ["👍", "👎"]), false, "an emoji has no words to say");
});

const ASKS = [
  { id: "a-1", question: "Ship v2.3\nto TestFlight?", choices: ["Ship it", "Hold\nfor now"], agent: "Grok" },
  { id: "a-2", question: "Renew the domain?", choices: ["Yes", "No"], agent: "Ops" },
  { id: "a-3", question: "Send the digest?", choices: ["Yes", "No"], agent: "Mail Bot" },
  { id: "a-4", question: "How was it?", choices: ["👍", "👎"], agent: "Survey" },
];

Deno.test("ToolRunner: answers an ask only with the choice the person said", async () => {
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "Tell Grok to ship it");
  assertEquals(await runner.run("answer_ask", { id: "a-1", choice: "ship IT" }), {
    content: 'Answered Grok\'s question "Ship v2.3 to TestFlight?": Ship it. Grok will read it when it next checks.',
    isError: false,
  });
  assertEquals(store.answers, [["a-1", "Ship it", "Ship v2.3\nto TestFlight?"]], "the agent's own label, and the question as stored");
  assertEquals([...runner.changed], ["asks"]);
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
  assertEquals((await other.run("answer_ask", { id: "a-1", choice: "Later" })).content, 'Not answered: the choices are "Ship it" or "Hold for now".');
  assertEquals((await new ToolRunner(store, CHI, [], () => NOW).run("answer_ask", { id: "a-1", choice: "Hold" })).isError, true,
    "nothing offered, nothing answered");
});

Deno.test("ToolRunner: a label on two lines is shown on one and sent as stored", async () => {
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "hold it for now");
  assertEquals((await runner.run("answer_ask", { id: "a-1", choice: "Hold for now" })).content,
    'Not answered: they didn\'t say "Hold for now" themselves. Ask them to say "Ship it" or "Hold for now".');
  const said = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "Hold for now, please");
  assertEquals((await said.run("answer_ask", { id: "a-1", choice: "hold for now" })).content,
    'Answered Grok\'s question "Ship v2.3 to TestFlight?": Hold for now. Grok will read it when it next checks.');
  assertEquals(store.answers, [["a-1", "Hold\nfor now", "Ship v2.3\nto TestFlight?"]]);
});

Deno.test("ToolRunner: the same ask twice keeps the first answer", async () => {
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "ship it — no wait, hold for now");
  // Both labels are in that message, so neither passes; a plain one does.
  assertEquals((await runner.run("answer_ask", { id: "a-1", choice: "Ship it" })).isError, true);
  const plain = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "ship it");
  assertEquals((await plain.run("answer_ask", { id: "a-1", choice: "Ship it" })).isError, false);
  assertEquals(await plain.run("answer_ask", { id: "a-1", choice: "ship it" }),
    { content: "Already saved in this answer; nothing more to do.", isError: false });
  assertEquals(await plain.run("answer_ask", { id: "a-1", choice: "Hold for now" }), {
    content: 'Not answered: "Ship it" was already given for this question in this answer, and it can\'t be changed. Tell them it was answered "Ship it".',
    isError: true,
  });
  assertEquals(store.answers.map(([id, choice]) => [id, choice]), [["a-1", "Ship it"]], "saved once");
  assertEquals(plain.writes, 1);
});

Deno.test("ToolRunner: a second question from one message must be named", async () => {
  const store = new FakeStore();
  const yes = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "yes");
  assertEquals((await yes.run("answer_ask", { id: "a-2", choice: "Yes" })).isError, false);
  assertEquals(await yes.run("answer_ask", { id: "a-3", choice: "Yes" }), {
    content: "Not answered: their message already answered another question and doesn't name Mail Bot. Ask them which question they meant.",
    isError: true,
  });
  assertEquals(store.answers.map(([id]) => id), ["a-2"], "one yes, one answer");

  const both = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "Yes for Ops, and yes for the mail bot");
  assertEquals((await both.run("answer_ask", { id: "a-2", choice: "Yes" })).isError, false);
  assertEquals((await both.run("answer_ask", { id: "a-3", choice: "Yes" })).isError, false);
  assertEquals(store.answers.map(([id]) => id), ["a-2", "a-2", "a-3"]);
});

Deno.test("ToolRunner: a message that names an agent answers only that agent's question", async () => {
  // Even the first answer: "yes for Ops" can't answer Mail Bot first.
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "yes for Ops");
  assertEquals(await runner.run("answer_ask", { id: "a-3", choice: "Yes" }), {
    content: "Not answered: their message is about another agent's question and doesn't name Mail Bot. Ask them which question they meant.",
    isError: true,
  });
  assertEquals(store.answers, []);
  assertEquals((await runner.run("answer_ask", { id: "a-2", choice: "Yes" })).isError, false);
  assertEquals(store.answers.map(([id]) => id), ["a-2"]);
});

Deno.test("ToolRunner: labels that can't be said are for a tap", async () => {
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [], () => NOW).offerAsks(
    [...ASKS, { id: "a-5", question: "Which?", choices: ["Sí", "Si"], agent: "Grok" }], "👍");
  assertEquals(await runner.run("answer_ask", { id: "a-4", choice: "👍" }), {
    content: 'Not answered: "👍" can only be answered with a tap on a screen (the display, the app or the console). Tell them so.',
    isError: true,
  });
  assertMatch((await runner.run("answer_ask", { id: "a-5", choice: "si" })).content, /^Not answered: "Si" can only be answered with a tap/);
  assertEquals(store.answers.length, 0);
});

Deno.test("ToolRunner: a suggested message answers nothing", async () => {
  // index.ts offers the asks with ownWords(req): "" for a chip, an insight
  // or a link's question, whatever its words.
  const store = new FakeStore();
  const runner = new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, "");
  assertEquals((await runner.run("answer_ask", { id: "a-1", choice: "Ship it" })).content,
    'Not answered: they didn\'t say "Ship it" themselves. Ask them to say "Ship it" or "Hold for now".');
  assertEquals(store.answers.length, 0);
});

Deno.test("ToolRunner: an ask answered elsewhere, taken back, changed or broken", async () => {
  const store = new FakeStore();
  const said = (s: string) => new ToolRunner(store, CHI, [], () => NOW).offerAsks(ASKS, s);
  store.answerError = "already answered: Hold\nfor now";
  assertEquals((await said("ship it").run("answer_ask", { id: "a-1", choice: "Ship it" })).content,
    'Not answered: it was already answered "Hold for now", on another screen.');
  store.answerError = "the agent took this question back";
  assertEquals((await said("ship it").run("answer_ask", { id: "a-1", choice: "Ship it" })).content,
    "Not answered: the agent took this question back.");
  store.answerError = "the agent changed this question; look again";
  assertEquals((await said("ship it").run("answer_ask", { id: "a-1", choice: "Ship it" })).content,
    "Not answered: Grok changed this question just now. Tell them it changed and to look at it again before answering.");
  store.answerError = "answer with one of: Ship, Wait";
  assertEquals((await said("ship it").run("answer_ask", { id: "a-1", choice: "Ship it" })).content,
    "Not answered: Grok changed this question's choices just now. Tell them they changed and to look at it again before answering.");
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
