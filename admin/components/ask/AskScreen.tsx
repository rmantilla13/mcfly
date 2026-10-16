"use client";

import { ArrowDownIcon, ArrowUpRightIcon, AudioLinesIcon, CheckIcon, CopyIcon, RotateCcwIcon, SquarePenIcon, Volume2Icon, VolumeXIcon, XIcon } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useEffectEvent, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";
import { cn } from "cn";
import { BrandMark } from "@/components/Brand";
import { Button } from "@/components/ui/button";
import PromptBar from "@/components/reactbits/PromptBar";
import ThoughtLine from "@/components/reactbits/ThoughtLine";
import VoicePill from "@/components/reactbits/VoicePill";
import { recognitionClass, type Recognition } from "@/components/voice/recognition";
import { speakReply, stopSpeaking, storedVoice, useVoice } from "@/components/voice/speech";
import { useAsk, type Turn } from "@/components/voice/useAsk";
import { plainText } from "@/lib/markdown";
import { Markdown } from "./Markdown";

// Ask McFly, full screen: room for the assistant to answer properly (read
// mode: longer answers with headings, lists and tables) and for you to take
// them in. Each question opens at the top of the page and its answer is laid
// out below it as it arrives; the page holds still while you read. Type, or
// tap the mic and speak. The thread stays for the tab, and Today's Ask bar
// hands its conversation over when it expands to here. /ask?q=… (a card's
// "Ask about this") asks that question on arrival.

const SPEAK_KEY = "mcfly.ask.speak"; // shared with Today's Ask bar
const noSubscribe = () => () => {};
function storedSpeak(): boolean {
  try {
    return localStorage.getItem(SPEAK_KEY) === "1";
  } catch {
    return false;
  }
}

// Questions that want a full screen, after the ones Today builds from what's
// on it.
const DEEPER = [
  "Catch me up on everything today",
  "Compare my watchlist in a table",
  "Where does every project stand?",
  "What needs my attention this week?",
];

type Exchange = { q: string | null; a: Turn | null };

function exchanges(turns: Turn[]): Exchange[] {
  const out: Exchange[] = [];
  for (const t of turns) {
    if (t.role === "user") out.push({ q: t.text, a: null });
    else if (out.length && !out[out.length - 1].a) out[out.length - 1].a = t;
    else out.push({ q: null, a: t });
  }
  return out;
}

export function AskScreen({ suggestions, question }: { suggestions: string[]; question?: string }) {
  const router = useRouter();
  const canListen = useSyncExternalStore(noSubscribe, () => !!recognitionClass(), () => false);
  const remembered = useSyncExternalStore(noSubscribe, storedSpeak, () => false);
  const [speakChoice, setSpeak] = useState<boolean | null>(null);
  const speak = speakChoice ?? remembered;
  useVoice(speak); // read aloud in the account's voice, kept up while replies are spoken
  const speakRef = useRef(speak);
  useEffect(() => {
    speakRef.current = speak;
  }, [speak]);

  const onReply = useCallback((reply: string) => {
    if (speakRef.current) void speakReply(plainText(reply), storedVoice());
  }, []);
  const { turns, busy, waiting, error, ask, stop, reset } = useAsk(onReply, { persist: true });
  const thread = exchanges(turns);

  const [input, setInput] = useState("");
  const [listening, setListening] = useState(false);
  const [atEnd, setAtEnd] = useState(true);
  const [copied, setCopied] = useState<number | null>(null);
  const [lastAsked, setLastAsked] = useState("");
  // A question was asked here, so the latest exchange shows how long McFly
  // thought (React Bits' ThoughtLine); a thread read back from the tab has
  // no timing to show.
  const [thinking, setThinking] = useState(false);
  const rec = useRef<Recognition | null>(null);
  const heard = useRef("");
  const scroller = useRef<HTMLDivElement>(null);
  const latest = useRef<HTMLElement>(null);
  const field = useRef<HTMLTextAreaElement>(null);

  const send = (text: string) => {
    const q = text.trim();
    if (!q || busy) return;
    setLastAsked(q);
    setThinking(true);
    stopSpeaking();
    setInput("");
    void ask(q, "read");
  };

  // A question handed over in the address is asked once, then dropped from
  // it, so a reload or Back doesn't ask it again. A tick later, so the kept
  // thread is in and the question joins it.
  const askOnArrival = useEffectEvent((q: string) => {
    window.history.replaceState(null, "", "/ask");
    send(q);
  });
  useEffect(() => {
    if (!question) return;
    const id = setTimeout(() => askOnArrival(question), 0);
    return () => clearTimeout(id);
  }, [question]);

  // The newest question goes to the top of the page; the answer fills in
  // below it without moving the page. Opening on a kept thread shows its
  // last exchange the same way.
  const count = thread.length;
  const shown = useRef(0);
  useLayoutEffect(() => {
    if (count > shown.current && latest.current) latest.current.scrollIntoView({ block: "start", behavior: shown.current ? "smooth" : "instant" });
    shown.current = count;
  }, [count]);

  // The page's height as a variable, so the newest exchange can be at least
  // a screen tall and its question can sit at the top.
  useEffect(() => {
    const el = scroller.current;
    if (!el) return;
    const measure = () => el.style.setProperty("--ask-view", `${el.clientHeight}px`);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const onScroll = () => {
    const el = scroller.current;
    if (el) setAtEnd(el.scrollHeight - el.scrollTop - el.clientHeight < 96);
  };
  const toEnd = () => scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: "smooth" });

  // Tap the mic and speak; it stops when you pause and asks what it heard.
  const listen = () => {
    if (listening) {
      rec.current?.stop();
      return;
    }
    const Ctor = recognitionClass();
    if (!Ctor || busy) return;
    stopSpeaking();
    const r = new Ctor();
    rec.current = r;
    heard.current = "";
    r.lang = navigator.language || "en-US";
    r.interimResults = true;
    r.continuous = false;
    r.onresult = (e) => {
      heard.current = Array.from(e.results, (x) => x[0].transcript).join(" ");
      setInput(heard.current);
    };
    r.onerror = () => setListening(false);
    r.onend = () => {
      setListening(false);
      if (heard.current.trim()) send(heard.current);
    };
    setListening(true);
    r.start();
  };

  const toggleSpeak = () => {
    const next = !speak;
    setSpeak(next);
    if (!next) stopSpeaking();
    try {
      localStorage.setItem(SPEAK_KEY, next ? "1" : "0");
    } catch {
      // Remembered for this page only.
    }
  };

  const newChat = () => {
    stopSpeaking();
    reset();
    setThinking(false);
    setInput("");
    field.current?.focus();
  };

  const copy = async (i: number, text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(i);
      setTimeout(() => setCopied((c) => (c === i ? null : c)), 1600);
    } catch {
      window.prompt("Copy this:", text);
    }
  };

  // Escape stops an answer, then leaves; / goes to the composer.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const typing = e.target instanceof HTMLElement && (e.target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName));
      if (e.key === "Escape") {
        if (busy) stop();
        else if (listening) rec.current?.stop();
        else if (!(typing && input)) router.push("/today");
      } else if (e.key === "/" && !typing) {
        e.preventDefault();
        field.current?.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [busy, listening, input, stop, router]);

  useEffect(() => () => {
    rec.current?.stop();
    stopSpeaking();
  }, []);

  const chips = [...new Set([...suggestions, ...DEEPER])].slice(0, 6);
  const failed = !!error && !busy;

  return (
    <main className="fixed inset-0 flex flex-col bg-background text-foreground">
      <header className="relative z-10 flex items-center gap-3 border-b border-border/60 bg-background/80 px-5 py-3 backdrop-blur max-sm:px-4">
        <BrandMark className="size-8 rounded-[10px]" />
        <div className="grid min-w-0 leading-tight">
          <h1 className="text-[15px] font-semibold tracking-tight">Ask McFly</h1>
          <p className="truncate text-xs text-muted-foreground max-sm:hidden">Answers from your briefs, markets, projects, calendar and today&apos;s Pulse</p>
        </div>
        <span className="flex-1" />
        {turns.length ? (
          <Button type="button" variant="ghost" size="lg" onClick={newChat} className="text-muted-foreground">
            <SquarePenIcon data-icon="inline-start" />
            <span className="max-sm:hidden">New chat</span>
          </Button>
        ) : null}
        <Button type="button" variant="ghost" size="lg" asChild className="text-muted-foreground">
          <Link href="/voice" aria-label="Talk to McFly">
            <AudioLinesIcon data-icon="inline-start" />
            <span className="max-sm:hidden">Talk</span>
          </Link>
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon-lg"
          onClick={toggleSpeak}
          aria-pressed={speak}
          aria-label={speak ? "Stop reading answers aloud" : "Read answers aloud"}
          className="text-muted-foreground"
        >
          {speak ? <Volume2Icon /> : <VolumeXIcon />}
        </Button>
        <Button type="button" variant="ghost" size="icon-lg" asChild className="text-muted-foreground">
          <Link href="/today" aria-label="Close">
            <XIcon />
          </Link>
        </Button>
      </header>

      <div ref={scroller} onScroll={onScroll} className="relative flex-1 overflow-y-auto overscroll-contain">
        <div className="mx-auto flex min-h-full w-full max-w-[46rem] flex-col px-6 max-sm:px-4">
          {thread.length === 0 ? (
            <section className="flex flex-1 flex-col justify-center py-14">
              <p className="text-[44px] leading-[1.05] font-semibold tracking-[-0.03em] max-md:text-[34px]">What would you like to know?</p>
              <p className="mt-4 max-w-[52ch] text-lg leading-relaxed text-muted-foreground max-md:text-base">
                Ask for the whole picture. McFly answers from what&apos;s on your display, laid out to read: the headline first, then the detail.
              </p>
              <div className="mt-10 grid gap-3 sm:grid-cols-2">
                {chips.map((s) => (
                  <button
                    key={s}
                    type="button"
                    onClick={() => send(s)}
                    disabled={busy}
                    className="group flex items-start justify-between gap-3 rounded-2xl border bg-card px-5 py-4 text-left text-[15px] leading-snug shadow-xs transition-colors hover:border-foreground/20 hover:bg-muted/40 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                  >
                    <span>{s}</span>
                    <ArrowUpRightIcon className="mt-0.5 size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                  </button>
                ))}
              </div>
            </section>
          ) : (
            <div className="flex flex-col pt-8 pb-10" aria-live="polite" aria-busy={busy}>
              {thread.map((x, i) => {
                const last = i === thread.length - 1;
                const streaming = last && busy;
                const answer = x.a?.text ?? "";
                return (
                  <article
                    key={i}
                    ref={last ? latest : undefined}
                    className={cn("scroll-mt-6 border-border/70", i > 0 && "mt-10 border-t pt-10", last && "min-h-[calc(var(--ask-view,80vh)-4rem)]")}
                  >
                    {x.q ? <h2 className="text-[26px] leading-tight font-semibold tracking-[-0.02em] text-balance max-md:text-[22px]">{x.q}</h2> : null}
                    <div className="mt-5">
                      {/* While McFly thinks, the line shimmers with a clock
                          beside it; as the answer starts it settles to how
                          long that took, and stays above the answer. */}
                      {last && thinking && !failed ? (
                        <ThoughtLine
                          working={streaming && !answer}
                          label={waiting ? "Reading your feeds…" : "Thinking…"}
                          color="var(--muted-foreground)"
                          glyphColor="var(--primary)"
                          fontSize={15}
                          className={answer ? "mb-4" : undefined}
                        />
                      ) : null}
                      {answer ? <Markdown text={answer} className="text-[17px] leading-[1.7] text-foreground/90 max-md:text-base" /> : null}
                      {streaming && answer ? <span className="mt-3 inline-block h-1.5 w-10 animate-pulse rounded-full bg-glow opacity-70" aria-hidden="true" /> : null}
                    </div>
                    {answer && !streaming ? (
                      <div className="mt-5 flex items-center gap-1 text-muted-foreground">
                        <Button type="button" variant="ghost" size="sm" onClick={() => void copy(i, answer)}>
                          {copied === i ? <CheckIcon data-icon="inline-start" /> : <CopyIcon data-icon="inline-start" />}
                          {copied === i ? "Copied" : "Copy"}
                        </Button>
                        <Button type="button" variant="ghost" size="sm" onClick={() => void speakReply(plainText(answer), storedVoice())}>
                          <Volume2Icon data-icon="inline-start" />
                          Read aloud
                        </Button>
                      </div>
                    ) : null}
                    {last && failed ? (
                      <div className="mt-5 flex flex-wrap items-center gap-3 rounded-xl border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm">
                        <span className="text-destructive">{error}</span>
                        {lastAsked ? (
                          <Button type="button" variant="outline" size="sm" onClick={() => send(lastAsked)}>
                            <RotateCcwIcon data-icon="inline-start" />
                            Try again
                          </Button>
                        ) : null}
                      </div>
                    ) : null}
                  </article>
                );
              })}
            </div>
          )}
          {/* A first question that failed leaves no exchange to hang this on. */}
          {failed && thread.length === 0 ? <p className="pb-6 text-sm text-destructive">{error}</p> : null}
        </div>
      </div>

      <footer className="relative px-6 pt-2 pb-5 max-sm:px-3 max-sm:pb-3">
        {!atEnd && thread.length ? (
          <button
            type="button"
            onClick={toEnd}
            className="absolute -top-12 left-1/2 flex h-9 -translate-x-1/2 items-center gap-1.5 rounded-full border bg-background/95 px-3.5 text-sm text-muted-foreground shadow-md backdrop-blur transition-colors hover:text-foreground"
          >
            <ArrowDownIcon className="size-4" /> Latest
          </button>
        ) : null}
        <div className="relative mx-auto w-full max-w-[46rem]">
          <div
            className={cn(
              "pointer-events-none absolute inset-x-[10%] -bottom-3 h-12 rounded-full bg-glow blur-2xl transition-opacity duration-500",
              busy || listening ? "opacity-60" : "opacity-0",
            )}
            aria-hidden="true"
          />
          {/* The composer is React Bits' PromptBar: its send button morphs
              into Stop while an answer streams, and the mic is a VoicePill
              that opens into a capsule of the voice's own bars and a clock
              while it listens. The draft is the page's `input`, so dictation
              writes into it as it is heard. */}
          <PromptBar
            value={input}
            onChange={setInput}
            inputRef={field}
            autoFocus
            placeholder={listening ? "Listening…" : thread.length ? "Ask a follow-up" : "Ask McFly anything"}
            busy={busy}
            onSend={(text) => send(text)}
            onStop={stop}
            sources={[]}
            commands={[]}
            models={[]}
            efforts={[]}
            background="var(--card)"
            color="var(--foreground)"
            menuBackground="var(--popover)"
            width={736}
            radius={26}
            className={cn("rounded-[26px] shadow-lg shadow-black/5 ring-1 ring-border transition-shadow", listening && "ring-primary/60")}
            dictateControl={
              canListen ? (
                <VoicePill
                  size={28}
                  reactive="mic"
                  listening={listening}
                  disabled={busy}
                  background="var(--muted)"
                  iconColor="var(--muted-foreground)"
                  accentColor="var(--primary)"
                  ariaLabel={listening ? "Stop listening" : "Speak your question"}
                  onStart={() => {
                    if (!listening) listen();
                  }}
                  onStop={({ reason }) => {
                    if (reason !== "sync") rec.current?.stop();
                  }}
                />
              ) : null
            }
          />
          <p className="mt-2 text-center text-xs text-muted-foreground max-sm:hidden">
            Enter to ask · Shift+Enter for a new line · Esc to {busy ? "stop" : "close"}
          </p>
        </div>
      </footer>
    </main>
  );
}
