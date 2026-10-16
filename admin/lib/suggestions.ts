// Questions to offer under the Ask box, built from what is on the page so a
// chip always points at something real: the blocked project, the biggest
// mover, the next meeting, the Pulse's lead story, a fresh brief. At most
// four, each short enough for two chips to share a row (the display's
// SuggestionChips packs them the same way). Pure, so
// tests/suggestions.test.mjs can check it.

export const MAX_SUGGESTIONS = 4;
export const MAX_SUGGESTION_CHARS = 42;
export const SUMMARIZE_DAY = "Summarize my day";

const MIN = 60_000;
const HOUR = 60 * MIN;
const MOVER_MIN_PCT = 1; // below this, "why is it up?" has no answer worth asking
const QUOTE_FRESH_MS = 36 * HOUR;
const EVENT_WINDOW_MS = 3 * HOUR;
const BRIEF_FRESH_MS = 3 * HOUR;

// The fields TodayData already carries (lib/today.ts).
export type SuggestionInput = {
  nowMs: number;
  blocked?: { name: string }[];
  tickers?: { symbol: string; changePct: number | null; asOf?: string | null }[];
  metrics?: unknown[];
  events?: { title: string; starts_at: string; all_day: boolean }[];
  hero?: { headline: string } | null;
  brief?: { agent: string; publishedAt: string } | null;
};

// before + value + after in MAX_SUGGESTION_CHARS, the value cut at a word
// with an ellipsis when it has to be. Null when too little of it would fit.
function fit(before: string, value: string, after: string): string | null {
  const v = value.replace(/\s+/g, " ").trim();
  if (!v) return null;
  const room = MAX_SUGGESTION_CHARS - before.length - after.length;
  if (v.length <= room) return before + v + after;
  if (room < 8) return null;
  let cut = v.slice(0, room - 1);
  // Back up to the last whole word, unless the cut already fell between two.
  const space = cut.lastIndexOf(" ");
  if (v[room - 1] !== " " && space >= (room - 1) * 0.6) cut = cut.slice(0, space);
  return `${before}${cut.replace(/[\s,.;:!?'"“”‘’–—-]+$/, "")}…${after}`;
}

// `skip`: questions a surface already offers its own way (Today's digest
// has a "Summarize my day" button), left out before the four are picked.
export function buildSuggestions(input: SuggestionInput, now: number = input.nowMs, skip: readonly string[] = []): string[] {
  const out: (string | null)[] = [];

  const blocked = input.blocked?.[0];
  if (blocked) out.push(fit("What's blocking ", blocked.name, "?"));

  const mover = (input.tickers ?? [])
    .filter((t) => t.changePct != null && Number.isFinite(t.changePct) && Math.abs(t.changePct) >= MOVER_MIN_PCT)
    .filter((t) => !t.asOf || !(now - Date.parse(t.asOf) > QUOTE_FRESH_MS))
    .sort((a, b) => Math.abs(b.changePct!) - Math.abs(a.changePct!))[0];
  if (mover) {
    const pct = mover.changePct!;
    const move = `${mover.symbol} ${pct > 0 ? "up" : "down"} ${Math.abs(pct).toFixed(1)}%`;
    const long = `Why is ${move} today?`;
    out.push(long.length <= MAX_SUGGESTION_CHARS ? long : `Why is ${move}?`.length <= MAX_SUGGESTION_CHARS ? `Why is ${move}?` : null);
  }

  const next = (input.events ?? [])
    .filter((e) => !e.all_day)
    .map((e) => ({ e, start: Date.parse(e.starts_at) }))
    .filter(({ start }) => start > now && start - now <= EVENT_WINDOW_MS)
    .sort((a, b) => a.start - b.start)[0];
  if (next) out.push(fit("What do I need for ", next.e.title, "?"));

  if (input.hero) out.push(fit("More on ", input.hero.headline, ""));

  const brief = input.brief;
  if (brief) {
    const at = Date.parse(brief.publishedAt);
    if (now - at < BRIEF_FRESH_MS && at - now < 5 * MIN) out.push(fit("What did ", brief.agent, " just say?"));
  }

  // The rest from questions that fit any day, skipping ones about feeds
  // that are empty.
  out.push(
    SUMMARIZE_DAY,
    input.events?.length ? "What's next on my calendar?" : null,
    input.tickers?.length ? "How are the markets doing?" : null,
    input.metrics?.length ? "How are my metrics looking?" : null,
    "Anything I should know?",
  );

  const seen = new Set<string>();
  const result: string[] = [];
  for (const s of out) {
    if (!s || s.length > MAX_SUGGESTION_CHARS || seen.has(s) || skip.includes(s)) continue;
    seen.add(s);
    result.push(s);
    if (result.length === MAX_SUGGESTIONS) break;
  }
  return result;
}

// ---- What's typed against what's offered: the command bar (⌘K) ranks the
// console's pages, the feeds' names and these questions with it. Higher is a
// better match, 0 is none. A whole-text prefix beats a word's prefix beats
// any substring; failing those, the letters in order (so "nv" finds NVIDIA
// and "dp" Daily Pulse), better when they start words and run together.

const fold = (s: string) =>
  s
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9%$&.?]+/g, " ")
    .trim();

export function matchScore(query: string, text: string): number {
  const q = fold(query);
  const t = fold(text);
  if (!q) return 1;
  if (!t) return 0;
  // Shorter texts win ties: "Feed" before "Feed · Markets" for "feed".
  const brevity = 1 - Math.min(t.length, 60) / 120;
  if (t.startsWith(q)) return 90 + brevity * 10;
  const words = t.split(" ");
  if (words.some((w) => w.startsWith(q))) return 70 + brevity * 10;
  if (t.includes(q)) return 55 + brevity * 10;
  // Every word typed starts a word there ("grok bot" → "Grok bots").
  const parts = q.split(" ");
  if (parts.length > 1 && parts.every((p) => words.some((w) => w.startsWith(p)))) return 50 + brevity * 10;

  // The letters in order, starting a word, scored by how many more start a
  // word or follow the last one; too scattered is no match.
  const flat = q.replace(/ /g, "");
  if (flat.length < 2) return 0;
  let at = -1;
  let good = 0;
  for (const ch of flat) {
    const next = t.indexOf(ch, at + 1);
    if (next < 0) return 0;
    const starts = next === 0 || t[next - 1] === " ";
    if (at < 0 && !starts) return 0;
    if (starts || next === at + 1) good++;
    at = next;
  }
  const quality = good / flat.length;
  return quality >= 0.6 ? 10 + quality * 30 + brevity * 5 : 0;
}
