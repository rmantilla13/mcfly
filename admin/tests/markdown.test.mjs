// The full-screen Ask's Markdown (lib/markdown.ts): what the assistant writes
// in read mode, parsed to data, never HTML, and sane while it streams.
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseInline, parseMarkdown, plainText } from "../lib/markdown.ts";

const text = (v) => ({ t: "text", v });

test("headings, paragraphs and rules", () => {
  assert.deepEqual(parseMarkdown("### Markets\nNVDA led.\nAAPL lagged.\n\n---\n\nDone."), [
    { t: "heading", level: 3, c: [text("Markets")] },
    { t: "p", c: [text("NVDA led."), { t: "br" }, text("AAPL lagged.")] },
    { t: "hr" },
    { t: "p", c: [text("Done.")] },
  ]);
  // Deeper than four is shown as four; no space after # is just text.
  assert.equal(parseMarkdown("###### Small")[0].level, 4);
  assert.deepEqual(parseMarkdown("#hashtag"), [{ t: "p", c: [text("#hashtag")] }]);
});

test("bold, italic, struck and code", () => {
  assert.deepEqual(parseInline("**NVDA** is up *2.1%* (`$120`), ~~flat~~"), [
    { t: "strong", c: [text("NVDA")] },
    text(" is up "),
    { t: "em", c: [text("2.1%")] },
    text(" ("),
    { t: "code", v: "$120" },
    text("), "),
    { t: "del", c: [text("flat")] },
  ]);
  // Bold inside italic.
  assert.deepEqual(parseInline("*a **b** c*"), [{ t: "em", c: [text("a "), { t: "strong", c: [text("b")] }, text(" c")] }]);
});

test("asterisks and underscores that aren't emphasis stay as they are", () => {
  assert.deepEqual(parseInline("2 * 3 * 4"), [text("2 * 3 * 4")]);
  assert.deepEqual(parseInline("snake_case_name and a_b"), [text("snake_case_name and a_b")]);
  assert.deepEqual(parseInline("a footnote*"), [text("a footnote*")]);
  assert.deepEqual(parseInline("\\*not em\\*"), [text("*not em*")]);
});

test("while streaming: an unclosed ** is bold to the end of its line", () => {
  assert.deepEqual(parseInline("Revenue **up 4"), [text("Revenue "), { t: "strong", c: [text("up 4")] }]);
  assert.deepEqual(parseInline("**open\nnext"), [{ t: "strong", c: [text("open")] }, { t: "br" }, text("next")]);
  // A trailing pair with nothing after it yet is still just characters.
  assert.deepEqual(parseInline("Revenue **"), [text("Revenue **")]);
});

test("links keep their words, never their address", () => {
  assert.deepEqual(parseInline("see [the brief](https://evil.example/x) now"), [text("see the brief now")]);
});

test("tags are text: nothing here becomes HTML", () => {
  const blocks = parseMarkdown('<img src=x onerror="alert(1)"> **hi**');
  assert.deepEqual(blocks, [{ t: "p", c: [text('<img src=x onerror="alert(1)"> '), { t: "strong", c: [text("hi")] }] }]);
});

test("bulleted and numbered lists, nested by indent", () => {
  assert.deepEqual(parseMarkdown("- One\n  - One a\n- Two\n\n1. First\n2. Second"), [
    {
      t: "list",
      ordered: false,
      start: 1,
      items: [
        { c: [text("One")], sub: { t: "list", ordered: false, start: 1, items: [{ c: [text("One a")], sub: null }] } },
        { c: [text("Two")], sub: null },
      ],
    },
    { t: "list", ordered: true, start: 1, items: [{ c: [text("First")], sub: null }, { c: [text("Second")], sub: null }] },
  ]);
  // A list can start anywhere, and a • works as a bullet.
  assert.equal(parseMarkdown("3. Third")[0].start, 3);
  assert.equal(parseMarkdown("• Dot")[0].t, "list");
  // A paragraph right before a list ends at the list.
  assert.deepEqual(parseMarkdown("Three things:\n- a").map((b) => b.t), ["p", "list"]);
});

test("a list's wrapped lines stay with their item; a blank line between items keeps one list", () => {
  const [list, ...rest] = parseMarkdown("- Alpha\n  carries on\n\n- Beta\n\nAfter.");
  assert.equal(list.items.length, 2);
  assert.deepEqual(list.items[0].c, [text("Alpha"), { t: "br" }, text("carries on")]);
  assert.deepEqual(rest, [{ t: "p", c: [text("After.")] }]);
});

test("tables: header, alignment, rows as wide as the header", () => {
  const [table] = parseMarkdown("| Symbol | Price | Change |\n|:--|--:|:-:|\n| NVDA | $120 | **+2.1%** |\n| AAPL | $230 |\n| X | 1 | 2 | extra |");
  assert.equal(table.t, "table");
  assert.deepEqual(table.align, ["left", "right", "center"]);
  assert.deepEqual(table.head, [[text("Symbol")], [text("Price")], [text("Change")]]);
  assert.deepEqual(table.rows[0][2], [{ t: "strong", c: [text("+2.1%")] }]);
  assert.deepEqual(table.rows[1], [[text("AAPL")], [text("$230")], []]);
  assert.equal(table.rows[2].length, 3);
});

test("while streaming: a table's header is a paragraph until its divider arrives", () => {
  assert.equal(parseMarkdown("| Symbol | Price |")[0].t, "p");
  assert.equal(parseMarkdown("| Symbol | Price |\n|---|---|")[0].t, "table");
  // Escaped pipes are text in a cell.
  const [table] = parseMarkdown("a | b\n--|--\nx \\| y | z");
  assert.deepEqual(table.rows[0][0], [text("x | y")]);
});

test("quotes and fenced code, including a fence still open", () => {
  assert.deepEqual(parseMarkdown("> Heads up\n> twice\n\nok"), [
    { t: "quote", c: [text("Heads up"), { t: "br" }, text("twice")] },
    { t: "p", c: [text("ok")] },
  ]);
  assert.deepEqual(parseMarkdown("```\n**raw**\n```\nafter"), [{ t: "code", v: "**raw**" }, { t: "p", c: [text("after")] }]);
  assert.deepEqual(parseMarkdown("```js\nlet a"), [{ t: "code", v: "let a" }]);
});

test("every prefix of an answer parses (what streaming feeds it)", () => {
  const answer = "### Today\nYou have **three** things.\n\n- **9:00** Standup\n  - room 2\n1. Ship\n\n| A | B |\n|---|--:|\n| x | *1* |\n\n> note\n\n```\ncode\n```";
  for (let n = 0; n <= answer.length; n++) assert.ok(Array.isArray(parseMarkdown(answer.slice(0, n))));
});

test("plainText: words for the voice, rows and items as sentences", () => {
  const md = "### Markets\nNVDA is **up**.\n\n- Standup at 9\n- Lunch\n\n| Symbol | Price |\n|---|---|\n| NVDA | $120 |";
  assert.equal(plainText(md), "Markets.\nNVDA is up.\nStandup at 9.\nLunch.\nNVDA, Price $120.");
});
