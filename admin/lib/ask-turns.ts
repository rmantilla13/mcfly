// An Ask conversation's turns when the person cuts an answer short, the
// history the browser posts, and what the proxy passes on to the assistant.
// Pure, so tests/ask-turns.test.mjs can check it.

// `interrupted`: an answer the person cut short (stopped it, or talked over
// it), so the assistant takes the next question as a change to it.
export type AskTurn = { role: "user" | "assistant"; text: string; interrupted?: boolean };

// The answer at the end, marked as cut short. The same array when there's no
// answer there to mark.
export function markCutShort<T extends AskTurn>(turns: T[]): T[] {
  const last = turns.at(-1);
  if (last?.role !== "assistant" || !last.text || last.interrupted) return turns;
  return [...turns.slice(0, -1), { ...last, interrupted: true }];
}

// The thread once an answer still arriving was stopped on purpose: what had
// come stays, marked. With nothing yet, the empty answer goes and the
// question stays (it joins the next one).
export function afterStop<T extends AskTurn>(turns: T[]): T[] {
  const last = turns.at(-1);
  if (last?.role !== "assistant") return turns;
  return last.text ? markCutShort(turns) : turns.slice(0, -1);
}

// The history a browser posted, as the assistant takes it: the last 10
// turns, each clipped. Only an answer can be cut short.
export function askHistory(raw: unknown): AskTurn[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((t): t is AskTurn => !!t && (t.role === "user" || t.role === "assistant") && typeof t.text === "string")
    .slice(-10)
    .map((t) =>
      t.role === "assistant" && t.interrupted === true
        ? { role: t.role, text: t.text.slice(0, 4000), interrupted: true }
        : { role: t.role, text: t.text.slice(0, 4000) },
    );
}

// Whether a question posted to the Ask proxy was suggested rather than typed
// or said by the person: a chip, an insight, Summarize my day, or a question
// carried in a link (/ask?q=…). Only a literal true counts, so a page that
// never says is taken as the person's own words, as before.
export function askSuggested(raw: unknown): boolean {
  return raw === true;
}

// What the Ask proxy posts to the assistant. `suggested: true` goes only with
// a suggested question: the assistant then answers no agent's ask with it, so
// text an agent pushed (a headline in a chip, a link's ?q=) can't pick an
// answer. The person's own questions send nothing.
export function assistantBody(message: string, history: AskTurn[], mode: string, suggested: boolean) {
  return { message, history, mode, stream: true, ...(suggested ? { suggested: true } : {}) };
}
