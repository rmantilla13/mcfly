"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { splitEvents } from "@/lib/sse";

// Asking McFly from the web (/api/ask, streamed). Shared by the Today page's
// Ask panel and the full-page voice screen. The conversation lives in the
// page only.

export type Turn = { role: "user" | "assistant"; text: string };

export function useAsk(onReply?: (reply: string) => void) {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [busy, setBusy] = useState(false);
  const [waiting, setWaiting] = useState(false); // asked, nothing back yet
  const [error, setError] = useState<string | null>(null);
  const turnsRef = useRef<Turn[]>([]);
  useEffect(() => {
    turnsRef.current = turns;
  }, [turns]);

  const ask = useCallback(
    async (question: string, mode: "chat" | "quick") => {
      const q = question.trim();
      if (!q || busy) return;
      setError(null);
      setBusy(true);
      setWaiting(true);
      const history = turnsRef.current.slice(-10);
      setTurns((t) => [...t, { role: "user", text: q }, { role: "assistant", text: "" }]);
      let reply = "";
      try {
        const res = await fetch("/api/ask", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: q, history, mode }),
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
            setTurns((t) => [...t.slice(0, -1), { role: "assistant", text: reply }]);
          }
        }
        if (reply) onReply?.(reply);
      } catch (err) {
        setError(err instanceof Error ? err.message : "McFly couldn't answer just now.");
        setTurns((t) => (t.at(-1)?.text ? t : t.slice(0, -2)));
      } finally {
        setBusy(false);
        setWaiting(false);
      }
    },
    [busy, onReply],
  );

  return { turns, busy, waiting, error, ask };
}
