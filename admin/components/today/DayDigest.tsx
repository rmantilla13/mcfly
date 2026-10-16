"use client";

import { RefreshCwIcon, SparklesIcon } from "lucide-react";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { Button } from "@/components/ui/button";
import { splitEvents } from "@/lib/sse";
import { formatClock } from "@/lib/today";
import { StreamingText } from "./StreamingText";
import { ThinkingText } from "./ThinkingText";

// "Summarize my day": one short spoken-style answer from the assistant
// (/api/ask, quick mode), only when asked; the page never asks a model on
// its own, since it refreshes every minute in every open tab. The words come
// into focus as they stream. The answer is kept for the tab and the day
// (sessionStorage, keyed by the display's day), so it is still there after
// a reload, until Refresh asks again.
//
// Asked here rather than through useAsk: this is one question with no
// conversation around it, so each ask starts clean (no history) and a
// Refresh can't send the last answer back as context.

const QUESTION = "Summarize my day";
const noSubscribe = () => () => {};
type Saved = { text: string; at: number };
type Run = { status: "waiting" | "streaming" | "done" | "error"; text: string; at?: number; error?: string };

const storageKey = (day: string) => `mcfly.digest.${day}`;

function readSaved(day: string): string | null {
  try {
    return sessionStorage.getItem(storageKey(day));
  } catch {
    return null; // storage blocked: nothing kept
  }
}

function parseSaved(raw: string | null): Saved | null {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as Partial<Saved>;
    return typeof v.text === "string" && v.text && typeof v.at === "number" ? { text: v.text, at: v.at } : null;
  } catch {
    return null;
  }
}

export function DayDigest({ day, timeZone }: { day: string; timeZone: string }) {
  // Read once the page is in the browser (none on the server).
  const savedRaw = useSyncExternalStore(noSubscribe, () => readSaved(day), () => null);
  const saved = useMemo(() => parseSaved(savedRaw), [savedRaw]);
  const [run, setRun] = useState<Run | null>(null);
  const abort = useRef<AbortController | null>(null);
  useEffect(() => () => abort.current?.abort(), []);

  const summarize = async () => {
    abort.current?.abort();
    const controller = new AbortController();
    abort.current = controller;
    setRun({ status: "waiting", text: "" });
    let text = "";
    try {
      const res = await fetch("/api/ask", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: QUESTION, history: [], mode: "quick" }),
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
          if (e.event === "delta" && data.text) text += data.text;
          // The whole answer, as the assistant settled it: it can differ
          // from what streamed (a refusal), and StreamingText starts over.
          else if (e.event === "done" && data.reply) text = data.reply;
          else if (e.event === "error") throw new Error(data.message ?? "McFly couldn't answer just now.");
          if (text) setRun({ status: "streaming", text });
        }
      }
      if (!text.trim()) throw new Error("McFly had nothing to say just now. Try again in a moment.");
      const at = Date.now();
      setRun({ status: "done", text, at });
      try {
        sessionStorage.setItem(storageKey(day), JSON.stringify({ text, at }));
      } catch {
        // Kept on the page only.
      }
    } catch (err) {
      if (controller.signal.aborted) return;
      setRun({ status: "error", text: "", error: err instanceof Error ? err.message : "McFly couldn't answer just now." });
    } finally {
      if (abort.current === controller) abort.current = null;
    }
  };

  const shown: (Run & { kept?: boolean }) | null = run ?? (saved ? { status: "done", text: saved.text, at: saved.at, kept: true } : null);
  const busy = shown?.status === "waiting" || shown?.status === "streaming";

  return (
    <div className="flex min-h-[112px] flex-col gap-3 rounded-[20px] bg-muted/70 p-4 ring-1 ring-foreground/[0.04]" aria-live="polite" aria-busy={busy}>
      {!shown || shown.status === "error" ? (
        <>
          <div className="flex items-start gap-3">
            <span className="grid size-9 shrink-0 place-items-center rounded-full bg-primary/12 text-primary" aria-hidden="true">
              <SparklesIcon className="size-[18px]" />
            </span>
            <span className="min-w-0 text-sm text-muted-foreground">
              {shown?.error ? (
                <span className="text-destructive">{shown.error}</span>
              ) : (
                "A few sentences on what stands out today, from everything on this page."
              )}
            </span>
          </div>
          <Button size="lg" className="mt-auto self-start rounded-full px-4" onClick={() => void summarize()}>
            <SparklesIcon data-icon="inline-start" />
            {shown?.error ? "Try again" : "Summarize my day"}
          </Button>
        </>
      ) : shown.status === "waiting" ? (
        <p className="my-auto text-[15px]">
          <ThinkingText text="Thinking…" />
        </p>
      ) : (
        <>
          <p className="text-[15px] leading-relaxed">
            <StreamingText text={shown.text} still={shown.kept} />
          </p>
          <div className="mt-auto flex items-center gap-2 text-xs text-muted-foreground">
            <SparklesIcon className="size-3.5" aria-hidden="true" />
            <span>{shown.status === "streaming" ? "Writing…" : shown.at ? `Your day at ${formatClock(shown.at, timeZone)}` : "Your day"}</span>
            <Button size="xs" variant="ghost" className="ml-auto rounded-full" onClick={() => void summarize()} disabled={busy} aria-label="Summarize my day again">
              <RefreshCwIcon data-icon="inline-start" />
              Refresh
            </Button>
          </div>
        </>
      )}
    </div>
  );
}
