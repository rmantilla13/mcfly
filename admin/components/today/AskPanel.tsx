"use client";

import { Maximize2Icon, MicIcon, SendIcon, SparklesIcon, Volume2Icon, VolumeXIcon } from "lucide-react";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import Link from "next/link";
import { speakReply, stopSpeaking, storedVoice } from "@/components/voice/speech";
import { useAsk } from "@/components/voice/useAsk";
import { cn } from "cn";
import { Button } from "@/components/ui/button";
import ShinyText from "@/components/reactbits/ShinyText";

// Ask McFly on the web, like the display's ask bar: type, or hold the mic and
// speak (the browser's own speech recognition, where it has one). The answer
// streams in from the assistant (/api/ask) and, if you like, is read aloud.
// The conversation lives in this page only.


type Recognition = {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }> }) => void) | null;
  onend: (() => void) | null;
  onerror: (() => void) | null;
  start(): void;
  stop(): void;
};

function recognitionClass(): (new () => Recognition) | null {
  const w = globalThis as unknown as { SpeechRecognition?: new () => Recognition; webkitSpeechRecognition?: new () => Recognition };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

// Made only when the mic is pressed: making one can ask for the microphone.
function makeRecognition(): Recognition | null {
  const Ctor = recognitionClass();
  return Ctor ? new Ctor() : null;
}

const SPEAK_KEY = "mcfly.ask.speak";
const noSubscribe = () => () => {};
function storedSpeak(): boolean {
  try {
    return localStorage.getItem(SPEAK_KEY) === "1";
  } catch {
    return false; // storage blocked: replies stay silent
  }
}

export function AskPanel() {
  const [input, setInput] = useState("");
  const [listening, setListening] = useState(false);
  // Browser-only facts: false while rendering on the server.
  const canListen = useSyncExternalStore(noSubscribe, () => !!recognitionClass(), () => false);
  const remembered = useSyncExternalStore(noSubscribe, storedSpeak, () => false);
  const [speakChoice, setSpeak] = useState<boolean | null>(null);
  const speak = speakChoice ?? remembered;
  const speakRef = useRef(speak);
  useEffect(() => {
    speakRef.current = speak;
  }, [speak]);
  const onReply = useCallback((reply: string) => {
    if (speakRef.current) void speakReply(reply, storedVoice());
  }, []);
  const { turns, busy, error, ask: askRaw } = useAsk(onReply);
  const ask = (q: string, mode: "chat" | "quick") => {
    setInput("");
    return askRaw(q, mode);
  };
  const recRef = useRef<Recognition | null>(null);
  const heard = useRef("");
  const log = useRef<HTMLDivElement>(null);

  useEffect(() => {
    log.current?.scrollTo({ top: log.current.scrollHeight, behavior: "smooth" });
  }, [turns]);

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

  // Hold to talk: listening while pressed, asked when let go.
  const startListening = () => {
    if (busy || listening) return;
    const rec = makeRecognition();
    if (!rec) return;
    recRef.current = rec;
    heard.current = "";
    rec.lang = navigator.language || "en-US";
    rec.interimResults = true;
    rec.continuous = true;
    rec.onresult = (e) => {
      heard.current = Array.from(e.results, (r) => r[0].transcript).join(" ");
      setInput(heard.current);
    };
    rec.onerror = () => setListening(false);
    rec.onend = () => {
      setListening(false);
      if (heard.current.trim()) void ask(heard.current, "quick");
    };
    setListening(true);
    rec.start();
  };
  const stopListening = () => recRef.current?.stop();

  return (
    <div className="relative overflow-hidden rounded-[28px] bg-[#1B1A1F] text-white">
      <div
        className={cn("pointer-events-none absolute inset-x-[8%] -bottom-10 h-20 rounded-full blur-2xl transition-opacity", busy || listening ? "opacity-90" : "opacity-50")}
        style={{ background: "linear-gradient(90deg, #db47b3, #8f57e6, #4280f5, #24c2c2, #4dc266, #f5a83d, #f56161)" }}
        aria-hidden="true"
      />
      {turns.length ? (
        <div ref={log} className="relative flex max-h-72 flex-col gap-3 overflow-y-auto px-5 pt-4" aria-live="polite">
          {turns.map((t, i) => (
            <p key={i} className={cn("text-[15px] leading-relaxed whitespace-pre-wrap", t.role === "user" ? "text-white/60" : "text-white")}>
              {t.text || (busy && i === turns.length - 1 ? <ShinyText text="Thinking…" color="rgba(255, 255, 255, 0.5)" shineColor="#ffffff" speed={1.6} /> : "")}
            </p>
          ))}
        </div>
      ) : null}
      <form
        className="relative flex items-center gap-2 px-3 py-3"
        onSubmit={(e) => {
          e.preventDefault();
          void ask(input, "chat");
        }}
      >
        <SparklesIcon className="ml-2 size-5 shrink-0 text-white/80" aria-hidden="true" />
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder={listening ? "Listening…" : "Ask McFly"}
          aria-label="Ask McFly"
          maxLength={2000}
          className="min-w-0 flex-1 bg-transparent px-2 py-2 text-[16px] text-white outline-none placeholder:text-white/60"
        />
        <Button type="button" size="icon-sm" variant="ghost" className="text-white hover:bg-white/10 hover:text-white" onClick={toggleSpeak} aria-label={speak ? "Stop reading replies aloud" : "Read replies aloud"}>
          {speak ? <Volume2Icon /> : <VolumeXIcon />}
        </Button>
        {canListen ? (
          <button
            type="button"
            onPointerDown={startListening}
            onPointerUp={stopListening}
            onPointerLeave={stopListening}
            aria-label="Hold to talk"
            className={cn("grid size-11 place-items-center rounded-full bg-white/15 transition-colors", listening && "bg-white text-[#1B1A1F]")}
          >
            <MicIcon className="size-5" />
          </button>
        ) : null}
        <Button type="button" size="icon-sm" variant="ghost" className="text-white hover:bg-white/10 hover:text-white" asChild>
          <Link href="/voice" aria-label="Talk to McFly full screen">
            <Maximize2Icon />
          </Link>
        </Button>
        <Button type="submit" size="icon" className="rounded-full" disabled={busy || !input.trim()} aria-label="Ask">
          <SendIcon />
        </Button>
      </form>
      {error ? <p className="relative px-5 pb-3 text-sm text-[#FF9B8A]">{error}</p> : null}
    </div>
  );
}
