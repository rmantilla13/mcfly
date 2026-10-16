// The Ask box's suggested questions (lib/suggestions.ts): built from what's
// on the page, at most four, each short enough to share a row.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildSuggestions, matchScore, MAX_SUGGESTION_CHARS, SUMMARIZE_DAY } from "../lib/suggestions.ts";

const NOW = Date.parse("2026-10-14T15:00:00Z");
const MIN = 60_000;
const iso = (ms) => new Date(ms).toISOString();

const page = () => ({
  nowMs: NOW,
  blocked: [{ name: "Onyx" }],
  tickers: [
    { symbol: "SPY", changePct: 0.3 },
    { symbol: "TSLA", changePct: -4.12 },
    { symbol: "NVDA", changePct: 1.5 },
  ],
  metrics: [{}],
  events: [
    { title: "All hands", starts_at: iso(NOW + 30 * MIN), all_day: true },
    { title: "Standup", starts_at: iso(NOW + 40 * MIN), all_day: false },
  ],
  hero: { headline: "Google launches Gemini 4 Argon" },
  brief: { agent: "Grok", publishedAt: iso(NOW - 20 * MIN) },
});

test("from the page, in order: blocked, mover, next meeting, the Pulse", () => {
  assert.deepEqual(buildSuggestions(page()), [
    "What's blocking Onyx?",
    "Why is TSLA down 4.1% today?",
    "What do I need for Standup?",
    "More on Google launches Gemini 4 Argon",
  ]);
});

test("the rest from a fresh brief, then questions that fit any day", () => {
  const p = { ...page(), blocked: [], hero: null, events: [] };
  assert.deepEqual(buildSuggestions(p), ["Why is TSLA down 4.1% today?", "What did Grok just say?", "Summarize my day", "How are the markets doing?"]);
  assert.deepEqual(buildSuggestions({ nowMs: NOW }), ["Summarize my day", "Anything I should know?"]);
  assert.deepEqual(buildSuggestions({ nowMs: NOW, events: page().events, metrics: [{}] }), [
    "What do I need for Standup?",
    "Summarize my day",
    "What's next on my calendar?",
    "How are my metrics looking?",
  ]);
});

test("a question the surface offers its own way is skipped before the four are picked", () => {
  const p = { ...page(), blocked: [], hero: null, events: [] };
  assert.deepEqual(buildSuggestions(p, NOW, [SUMMARIZE_DAY]), [
    "Why is TSLA down 4.1% today?",
    "What did Grok just say?",
    "How are the markets doing?",
    "How are my metrics looking?",
  ]);
  assert.deepEqual(buildSuggestions({ nowMs: NOW }, NOW, [SUMMARIZE_DAY]), ["Anything I should know?"]);
});

test("only real movers, meetings in the next 3 hours, briefs under 3 hours", () => {
  const p = page();
  const calm = buildSuggestions({ nowMs: NOW, tickers: [{ symbol: "SPY", changePct: 0.9 }] });
  assert.ok(!calm.some((s) => s.startsWith("Why is")), "under 1% isn't asked about");
  const stale = buildSuggestions({ nowMs: NOW, tickers: [{ symbol: "NVDA", changePct: 3, asOf: iso(NOW - 40 * 60 * MIN) }] });
  assert.ok(!stale.some((s) => s.startsWith("Why is")));
  const late = buildSuggestions({ ...p, events: [{ title: "Dinner", starts_at: iso(NOW + 4 * 60 * MIN), all_day: false }] });
  assert.ok(!late.some((s) => s.includes("Dinner")));
  const past = buildSuggestions({ ...p, events: [{ title: "Standup", starts_at: iso(NOW - 5 * MIN), all_day: false }] });
  assert.ok(!past.some((s) => s.includes("Standup")));
  const old = buildSuggestions({ nowMs: NOW, brief: { agent: "Grok", publishedAt: iso(NOW - 4 * 60 * MIN) } });
  assert.ok(!old.some((s) => s.includes("Grok")));
});

test("the page's clock, not the machine's", () => {
  const later = { ...page(), nowMs: NOW + 3 * 60 * MIN };
  assert.ok(!buildSuggestions(later).some((s) => s.includes("Standup")), "Standup is over by then");
  assert.ok(!buildSuggestions(later).some((s) => s.includes("Grok")), "and the brief is over 3 hours old");
});

test("long names are cut at a word to fit, with an ellipsis", () => {
  const p = {
    nowMs: NOW,
    blocked: [{ name: "The very long project name that keeps going" }],
    events: [{ title: "Pulse review with the whole team and the agency", starts_at: iso(NOW + 60 * MIN), all_day: false }],
    hero: { headline: "Google adds channel-level reporting to Performance Max" },
  };
  const out = buildSuggestions(p);
  assert.deepEqual(out.slice(0, 3), [
    "What's blocking The very long project…?",
    "What do I need for Pulse review with the…?",
    "More on Google adds channel-level…",
  ]);
  for (const s of out) assert.ok(s.length <= MAX_SUGGESTION_CHARS, `${s} (${s.length})`);
});

test("never more than four, never twice the same", () => {
  const out = buildSuggestions({ ...page(), brief: { agent: "Grok", publishedAt: iso(NOW) } });
  assert.equal(out.length, 4);
  assert.equal(new Set(out).size, out.length);
});

test("the command bar's matching: prefix, word, substring, letters in order", () => {
  const rank = (q, items) => items.map((t) => [t, matchScore(q, t)]).filter(([, s]) => s > 0).sort((a, b) => b[1] - a[1]).map(([t]) => t);
  assert.equal(matchScore("", "Anything"), 1, "nothing typed: everything matches");
  assert.deepEqual(rank("feed", ["Overview", "Feed · Markets", "Feed", "Newsfeed"]), ["Feed", "Feed · Markets", "Newsfeed"]);
  assert.deepEqual(rank("mark", ["Markets", "Feed · Markets", "Bookmarks"]), ["Markets", "Feed · Markets", "Bookmarks"]);
  assert.ok(matchScore("nv", "NVDA · NVIDIA") > 0);
  assert.ok(matchScore("dp", "Daily Pulse") > 0, "initials");
  assert.ok(matchScore("grok bot", "Grok bots") > 0, "each word starts one");
  assert.ok(matchScore("api p95", "API p95 · Ops") > 0);
  assert.equal(matchScore("zq", "Daily Pulse"), 0);
  assert.equal(matchScore("ayl", "Daily Pulse"), 0, "letters in order but scattered mid-word: no match");
  assert.equal(matchScore("nv", "Ambient view"), 0, "the first letter has to start a word");
  assert.ok(matchScore("gbot", "Grok bots") > 0, "a word's start, then the next word's");
  assert.ok(matchScore("café", "Cafe Onyx") > 0 && matchScore("cafe", "Café Onyx") > 0, "accents fold");
  assert.ok(matchScore("S&P", "SPY · S&P 500 ETF") >= 70);
});
