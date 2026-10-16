// The assistant-first Today's opening (components/today/TodayAssistant.tsx):
// McFly speaks first. A greeting, one sentence on what matters now (what's on
// or next, what's blocked, the biggest move in the markets), a second line
// from today's Pulse and the newest brief, and a few questions to tap. Put
// together from the page's own rows, never written by a model, and worded as
// the display words it (display/src/models/HomeGlance.cpp, its tests in
// display/tests/tst_homeglance.cpp and ours in tests/glance.test.mjs), so the
// wall and the web say the same thing. Everything is on the display's clock
// (`timeZone`), and `nowMs` comes in: the server's first render and the
// browser's agree.

import { dayKey, dayLabel } from "./events.ts";
import { formatClock, greeting } from "./today.ts";
import type { TodayBrief, TodayEvent, TodayHero, TodayProject, TodayTicker } from "./today.ts";

export type Glance = {
  greeting: string;
  headline: string; // the greeting and what matters now
  detail: string; // what came in
  chips: string[]; // at most three questions, the specific ones first
  quiet: boolean; // nothing next, blocked or moving
  next: TodayEvent | null; // what the headline's calendar part is about
  blocked: TodayProject[];
  movers: TodayTicker[]; // a move of 1% or more, biggest first, at most three
};

export type GlanceInput = {
  events: TodayEvent[];
  tickers: TodayTicker[];
  blocked: TodayProject[];
  brief?: TodayBrief | null;
  hero: TodayHero;
  displayName: string;
  timeZone: string;
};

const MOVE = 1; // percent: smaller moves aren't news
const NBSP = " ";

// A title as the end of a sentence: no doubled full stop.
function endSentence(s: string): string {
  const t = s.trim();
  return t && !/[.!?]$/.test(t) ? `${t}.` : t;
}

// "a", "a, and b", "a, b, and c": independent clauses, so the comma stays.
function joinClauses(parts: string[]): string {
  if (parts.length <= 1) return parts[0] ?? "";
  return `${parts.slice(0, -1).join(", ")}, and ${parts[parts.length - 1]}`;
}

const sentenceCase = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);
const minutes = (n: number) => (n === 1 ? "1 minute" : `${n} minutes`);

export function glance(input: GlanceInput, nowMs: number): Glance {
  const tz = input.timeZone;
  const hello = greeting(nowMs, tz, input.displayName);
  const clauses: string[] = []; // the headline
  const lines: string[] = []; // the detail
  const chips: string[] = [];
  const ask = (q: string) => {
    if (chips.length < 3 && !chips.includes(q)) chips.push(q);
  };

  // What's on now, else the next timed event (all-day ones don't start).
  const next =
    [...input.events]
      .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at))
      .find((e) => !e.all_day && Math.max(Date.parse(e.ends_at), Date.parse(e.starts_at)) >= nowMs) ?? null;
  if (next) {
    const start = Date.parse(next.starts_at);
    // "3:30 pm" stays on one line in the big type.
    const at = formatClock(start, tz).replace(" ", NBSP);
    const day = dayLabel(dayKey(new Date(start), tz), tz, new Date(nowMs));
    const left = Math.max(0, Math.ceil((start - nowMs) / 60_000));
    const title = next.title;
    if (start <= nowMs) clauses.push(`${title} is on now`);
    else if (day === "Today" && left <= 1) clauses.push(`${title} is about to start`);
    else if (day === "Today" && left < 60) clauses.push(`${title} is in ${minutes(left)}`);
    else if (day === "Today") clauses.push(`${title} is at ${at}`);
    else if (day === "Tomorrow") clauses.push(`tomorrow starts with ${title} at ${at}`);
    else clauses.push(`${title} is next, on ${day}`);
    ask(title.length <= 20 ? `What's on after ${title}?` : "What else is on today?");
  }

  // Anything blocked.
  const blocked = input.blocked;
  if (blocked.length) {
    const first = blocked[0].name;
    if (blocked.length === 1) clauses.push(`${first} is blocked`);
    else if (blocked.length === 2) clauses.push(`${first} and ${blocked[1].name} are blocked`);
    else clauses.push(`${first} and ${blocked.length - 1} others are blocked`);
    ask(`What's blocking ${first}?`);
  }

  // The markets, if something moved: 1% or more, biggest first.
  const movers = input.tickers
    .filter((t) => t.direction !== "flat" && t.changePct != null && Math.abs(t.changePct) >= MOVE)
    .sort((a, b) => Math.abs(b.changePct ?? 0) - Math.abs(a.changePct ?? 0))
    .slice(0, 3);
  if (movers.length) {
    const top = movers[0];
    const pct = top.changePct ?? 0;
    const amount = `${Math.abs(pct).toFixed(1)}%`;
    clauses.push(pct >= 0 ? `${top.symbol} is up ${amount}` : `${top.symbol} is down ${amount}`);
    ask(pct >= 0 ? `Why is ${top.symbol} up?` : `Why is ${top.symbol} down?`);
  }

  // The second line: today's Pulse and the newest brief.
  const lead = input.hero?.headline.trim();
  if (lead) {
    const source = input.hero?.source ?? "";
    lines.push(source ? `Today's ${source} leads with ${endSentence(lead)}` : `The news leads with ${endSentence(lead)}`);
    ask(source ? `Read me the ${source}` : "What's in the news?");
  }
  const brief = input.brief?.title?.trim() ? input.brief : null;
  if (brief) {
    lines.push(brief.agent ? `${brief.agent}'s latest: ${endSentence(brief.title)}` : `The latest brief: ${endSentence(brief.title)}`);
    ask(brief.agent ? `What did ${brief.agent} say?` : "What's the latest brief?");
  }

  const quiet = clauses.length === 0;
  const headline = !quiet
    ? `${hello}. ${sentenceCase(joinClauses(clauses))}.`
    : lines.length
      ? `${hello}. Nothing is next, and nothing needs you.`
      : `${hello}. It's a quiet day so far.`;
  if (quiet && !lines.length) lines.push("Nothing is on the calendar and nothing is waiting on you. Ask me anything.");

  // Then the general ones, so there are always a few to tap.
  if (input.events.length) ask("What's on today?");
  if (input.tickers.length) ask("How are the markets?");
  ask("What can you do?");

  return { greeting: hello, headline, detail: lines.join(" "), chips, quiet, next, blocked, movers };
}
