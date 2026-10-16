"use client";

import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { splitEvents } from "@/lib/sse";

// Asking McFly from the web (/api/ask, streamed). Shared by the Today page's
// Ask panel, the full-page voice screen and the full-screen Ask (/ask).
// The conversation lives in the page, except that the full-screen Ask keeps
// its thread for the tab (`persist`), and Today's panel hands its thread over
// when it expands (saveThread), so a conversation survives the move.

export type Turn = { role: "user" | "assistant"; text: string };
export type AskMode = "chat" | "quick" | "read";

const THREAD_KEY = "mcfly.ask.thread";
const noSubscribe = () => () => {};

function savedThreadRaw(): string | null {
  try {
    return sessionStorage.getItem(THREAD_KEY);
  } catch {
    return null; // storage blocked: the thread lives in the page only
  }
}

function parseThread(raw: string | null): Turn[] {
  if (!raw) return [];
  try {
    const turns = JSON.parse(raw) as unknown;
    if (!Array.isArray(turns)) return [];
    return turns.filter(
      (t): t is Turn => !!t && (t.role === "user" || t.role === "assistant") && typeof t.text === "string" && !!t.text,
    );
  } catch {
    return [];
  }
}

// Keeps `turns` as the tab's conversation for the full-screen Ask to open on.
export function saveThread(turns: Turn[]) {
  try {
    sessionStorage.setItem(THREAD_KEY, JSON.stringify(turns.filter((t) => t.text).slice(-40)));
  } catch {
    // Blocked: /ask opens on a fresh conversation.
  }
}

export function useAsk(onReply?: (reply: string) => void, { persist = false }: { persist?: boolean } = {}) {
  // The saved thread is read once the page is in the browser (none on the
  // server), and stands until this page asks or clears something itself.
  const savedRaw = useSyncExternalStore(noSubscribe, () => (persist ? savedThreadRaw() : null), () => null);
  const saved = useMemo(() => parseThread(savedRaw), [savedRaw]);
  const [own, setOwn] = useState<Turn[] | null>(null);
  const turns = own ?? saved;
  const [busy, setBusy] = useState(false);
  const [waiting, setWaiting] = useState(false); // asked, nothing back yet
  const [error, setError] = useState<string | null>(null);
  const turnsRef = useRef<Turn[]>([]);
  const abort = useRef<AbortController | null>(null);
  useEffect(() => {
    turnsRef.current = turns;
  }, [turns]);

  // Saved once an answer is whole, not at every word.
  useEffect(() => {
    if (persist && own && !busy) saveThread(own);
  }, [persist, own, busy]);

  useEffect(() => () => abort.current?.abort(), []);

  const ask = useCallback(
    async (question: string, mode: AskMode) => {
      const q = question.trim();
      if (!q || busy) return;
      setError(null);
      setBusy(true);
      setWaiting(true);
      const before = turnsRef.current;
      const history = before.slice(-10);
      setOwn([...before, { role: "user", text: q }, { role: "assistant", text: "" }]);
      const setReply = (text: string) => setOwn((t) => [...(t ?? []).slice(0, -1), { role: "assistant", text }]);
      const controller = new AbortController();
      abort.current = controller;
      let reply = "";
      try {
        const res = await fetch("/api/ask", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: q, history, mode }),
          signal: controller.signal,
        });
        if (!res.ok || !res.body) {
          const body = (await res.json().catch(() => null)) as { error?: string } | null;
          throw new Error(body?.error ?? "McFly couldn't answer just now.");
        }
        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const { events, rest } = splitEvents(buffer);
          buffer = rest;
          for (const e of events) {
            const data = JSON.parse(e.data) as { text?: string; reply?: string; message?: string };
            if (e.event === "delta" && data.text) reply += data.text;
            else if (e.event === "done" && data.reply) reply = data.reply;
            else if (e.event === "error") throw new Error(data.message ?? "McFly couldn't answer just now.");
            if (reply) setWaiting(false);
            setReply(reply);
          }
        }
        if (reply) onReply?.(reply);
      } catch (err) {
        // Stopped on purpose: keep what arrived, say nothing went wrong.
        if (!controller.signal.aborted) setError(err instanceof Error ? err.message : "McFly couldn't answer just now.");
        setOwn((t) => (!t || t.at(-1)?.text ? t : t.slice(0, -2)));
      } finally {
        if (abort.current === controller) abort.current = null;
        setBusy(false);
        setWaiting(false);
      }
    },
    [busy, onReply],
  );

  // Stops the answer that's arriving, keeping what has.
  const stop = useCallback(() => abort.current?.abort(), []);

  // A new conversation: stops any answer and forgets the thread.
  const reset = useCallback(() => {
    abort.current?.abort();
    setOwn([]);
    setError(null);
  }, []);

  return { turns, busy, waiting, error, ask, stop, reset };
}
