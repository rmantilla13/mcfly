"use client";

import { KeyboardIcon, MicIcon, RepeatIcon, SquareIcon, Volume2Icon, VolumeXIcon, XIcon } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { cn } from "cn";
import { SpectrumGlow, type GlowInput } from "./SpectrumGlow";
import ShinyText from "@/components/reactbits/ShinyText";
import { kokoro, speakReply, stopSpeaking, storedVoice, storeVoice, VOICES, type KokoroState, type VoiceId } from "./speech";
import { useAsk } from "./useAsk";

// Talking to McFly, full screen: the Homestead voice glow fills the bottom,
// rising with your voice, gathering into a travelling beam while McFly
// thinks, and pulsing while it speaks. Tap the mic and talk; it stops when
// you pause. With "Keep talking" on, it listens again after each answer.
// The mic is only on while the button says so.

type Recognition = {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void) | null;
  onend: (() => void) | null;
  onerror: ((e: { error?: string }) => void) | null;
  start(): void;
  stop(): void;
};
function recognitionClass(): (new () => Recognition) | null {
  const w = globalThis as unknown as { SpeechRecognition?: new () => Recognition; webkitSpeechRecognition?: new () => Recognition };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}
const noSubscribe = () => () => {};
const IDLE: KokoroState = { status: "idle", percent: 0 };

const SUGGESTIONS = ["What's next today?", "How are the markets?", "What's in today's Pulse?", "Anything blocked?"];

export function VoiceScreen() {
  const router = useRouter();
  const canListen = useSyncExternalStore(noSubscribe, () => !!recognitionClass(), () => false);
  const [listening, setListening] = useState(false);
  const [speaking, setSpeaking] = useState(false);
  const [heard, setHeard] = useState("");
  const [speakOn, setSpeakOn] = useState(true);
  const [keepTalking, setKeepTalking] = useState(false);
  const [typing, setTyping] = useState(false);
  const [typed, setTyped] = useState("");
  const [micError, setMicError] = useState<string | null>(null);
  const remembered = useSyncExternalStore(noSubscribe, storedVoice, () => "af_heart" as VoiceId);
  const [voiceChoice, setVoiceChoice] = useState<VoiceId | null>(null);
  const voice = voiceChoice ?? remembered;
  const voiceState = useSyncExternalStore(kokoro().subscribe, kokoro().getState, () => IDLE);
  const voiceRef = useRef(voice);
  useEffect(() => {
    voiceRef.current = voice;
    if (voice !== "system") kokoro().load(); // the one-time download starts now, not at the first answer
  }, [voice]);

  const glow = useRef<GlowInput>({ level: 0, low: 0, mid: 0, high: 0, processing: false, speaking: false });
  const audio = useRef<{ ctx: AudioContext; stream: MediaStream; raf: number } | null>(null);
  const rec = useRef<Recognition | null>(null);
  const heardRef = useRef("");
  const keepRef = useRef(keepTalking);
  const startRef = useRef<() => void>(() => {});
  useEffect(() => {
    keepRef.current = keepTalking;
  }, [keepTalking]);

  const onReply = useCallback(
    (reply: string) => {
      if (!speakOn) {
        if (keepRef.current) setTimeout(() => startRef.current(), 600);
        return;
      }
      setSpeaking(true);
      void speakReply(reply, voiceRef.current).then(() => {
        setSpeaking(false);
        if (keepRef.current) setTimeout(() => startRef.current(), 400);
      });
    },
    [speakOn],
  );
  const { turns, busy, waiting, error, ask } = useAsk(onReply);

  useEffect(() => {
    const g = glow.current;
    g.processing = waiting;
    // Kokoro's own audio drives the glow while it speaks; the browser's voice
    // has no meter, so a spoken rhythm stands in for it.
    const k = kokoro();
    g.speaking = speaking && !k.speaking;
    if (!speaking) return;
    let raf = 0;
    const follow = () => {
      if (k.speaking) Object.assign(g, k.levels(), { speaking: false });
      else g.speaking = true;
      raf = requestAnimationFrame(follow);
    };
    raf = requestAnimationFrame(follow);
    return () => {
      cancelAnimationFrame(raf);
      Object.assign(g, { level: 0, low: 0, mid: 0, high: 0, speaking: false });
    };
  }, [waiting, speaking]);

  // The mic's level, in three bands, for the glow (Web Audio).
  const stopMeter = useCallback(() => {
    const a = audio.current;
    if (!a) return;
    cancelAnimationFrame(a.raf);
    a.stream.getTracks().forEach((t) => t.stop());
    void a.ctx.close();
    audio.current = null;
    Object.assign(glow.current, { level: 0, low: 0, mid: 0, high: 0 });
  }, []);

  const startMeter = useCallback(async () => {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const ctx = new AudioContext();
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 512;
    analyser.smoothingTimeConstant = 0.6;
    ctx.createMediaStreamSource(stream).connect(analyser);
    const bins = new Uint8Array(analyser.frequencyBinCount);
    const avg = (from: number, to: number) => {
      let s = 0;
      for (let i = from; i < to; i++) s += bins[i];
      return Math.min(1, (s / (to - from) / 255) * 1.8);
    };
    const tick = () => {
      analyser.getByteFrequencyData(bins);
      const low = avg(2, 12);
      const mid = avg(12, 48);
      const high = avg(48, 120);
      Object.assign(glow.current, { level: Math.max(low, mid, high), low, mid, high });
      if (audio.current) audio.current.raf = requestAnimationFrame(tick);
    };
    audio.current = { ctx, stream, raf: requestAnimationFrame(tick) };
  }, []);

  const startListening = useCallback(async () => {
    if (listening || busy) return;
    const Ctor = recognitionClass();
    if (!Ctor) return;
    stopSpeaking();
    setSpeaking(false);
    setMicError(null);
    try {
      await startMeter();
    } catch {
      setMicError("McFly needs the microphone. Allow it in the browser's address bar, then try again.");
      return;
    }
    const r = new Ctor();
    rec.current = r;
    heardRef.current = "";
    setHeard("");
    r.lang = navigator.language || "en-US";
    r.interimResults = true;
    r.continuous = false; // ends on its own when you pause
    r.onresult = (e) => {
      heardRef.current = Array.from(e.results, (x) => x[0].transcript).join(" ");
      setHeard(heardRef.current);
    };
    r.onerror = (e) => {
      if (e.error === "not-allowed") setMicError("McFly needs the microphone. Allow it in the browser's address bar, then try again.");
    };
    r.onend = () => {
      setListening(false);
      stopMeter();
      const said = heardRef.current.trim();
      if (said) void ask(said, "quick");
    };
    setListening(true);
    r.start();
  }, [listening, busy, startMeter, stopMeter, ask]);
  useEffect(() => {
    startRef.current = () => void startListening();
  }, [startListening]);

  const stopAll = () => {
    rec.current?.stop();
    stopSpeaking();
    setSpeaking(false);
  };

  // Escape leaves; space talks.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (typing) return;
      if (e.key === "Escape") router.push("/today");
      if (e.key === " " && !listening) {
        e.preventDefault();
        void startListening();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router, typing, listening, startListening]);

  useEffect(() => () => {
    stopMeter();
    stopSpeaking();
  }, [stopMeter]);

  const last = turns.at(-1);
  const answer = last?.role === "assistant" ? last.text : "";
  const question = listening ? heard : turns.at(-2)?.role === "user" ? turns.at(-2)?.text : "";
  const voiceName = VOICES.find((v) => v.id === voice)?.name ?? "Heart";
  const getting =
    voice !== "system" && voiceState.status === "loading"
      ? `Getting ${voiceName} ready${voiceState.percent ? ` · ${voiceState.percent}%` : ""} (one-time download, about 90 MB)`
      : null;
  const status =
    micError ??
    error ??
    (listening ? "Listening…" : waiting ? "Thinking…" : speaking ? "Speaking" : busy ? "" : getting ?? (canListen ? "Tap the mic and talk" : "Type your question"));

  return (
    <main className="fixed inset-0 overflow-hidden bg-[#0D0C10] text-white" data-voice={voiceState.status} data-voice-percent={voiceState.percent}>
      <SpectrumGlow input={glow} className="absolute inset-x-0 bottom-0 h-[62%] w-full" />

      <header className="relative flex items-center gap-3 px-6 py-5">
        <span className="text-sm font-semibold tracking-wide text-white/70">McFly</span>
        <span className="flex-1" />
        <button
          type="button"
          onClick={() => setKeepTalking((k) => !k)}
          aria-pressed={keepTalking}
          className={cn("flex h-9 items-center gap-2 rounded-full px-3.5 text-sm transition-colors", keepTalking ? "bg-white text-[#0D0C10]" : "bg-white/10 text-white/80 hover:bg-white/15")}
        >
          <RepeatIcon className="size-4" /> Keep talking
        </button>
        <select
          value={voice}
          onChange={(e) => {
            const v = e.target.value as VoiceId;
            setVoiceChoice(v);
            storeVoice(v);
          }}
          aria-label="Voice"
          className="h-9 rounded-full border-0 bg-white/10 px-3 text-sm text-white/85 outline-none hover:bg-white/15 [&>option]:text-black"
        >
          {VOICES.map((v) => (
            <option key={v.id} value={v.id}>
              {v.name}
            </option>
          ))}
        </select>
        <button
          type="button"
          onClick={() => {
            setSpeakOn((s) => !s);
            stopSpeaking();
            setSpeaking(false);
          }}
          aria-label={speakOn ? "Don't read answers aloud" : "Read answers aloud"}
          className="grid size-9 place-items-center rounded-full bg-white/10 text-white/80 hover:bg-white/15"
        >
          {speakOn ? <Volume2Icon className="size-4" /> : <VolumeXIcon className="size-4" />}
        </button>
        <Link href="/today" aria-label="Close" className="grid size-9 place-items-center rounded-full bg-white/10 text-white/80 hover:bg-white/15">
          <XIcon className="size-4" />
        </Link>
      </header>

      <section className="relative mx-auto flex h-[calc(100%-180px)] max-w-3xl flex-col justify-center gap-5 px-6 pb-24" aria-live="polite">
        {question ? <p className="text-xl text-white/55 max-md:text-lg">{question}</p> : null}
        {answer ? (
          <p className="max-h-[45vh] overflow-y-auto text-[34px] leading-[1.25] font-medium tracking-[-0.01em] whitespace-pre-wrap max-md:text-2xl">{answer}</p>
        ) : !question ? (
          <div className="flex flex-col gap-6">
            <p className="text-[44px] leading-tight font-medium tracking-[-0.02em] max-md:text-3xl">What would you like to know?</p>
            <div className="flex flex-wrap gap-2.5">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => void ask(s, "quick")}
                  disabled={busy}
                  className="h-11 rounded-full border border-white/20 bg-white/5 px-5 text-[15px] text-white/90 transition-colors hover:bg-white/10"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        ) : null}
      </section>

      <footer className="absolute inset-x-0 bottom-0 flex flex-col items-center gap-3 pb-10">
        <p className={cn("text-sm", micError || error ? "text-[#FF9B8A]" : "text-white/70")}>
          {!micError && !error && (listening || waiting) ? <ShinyText text={status} color="rgba(255, 255, 255, 0.7)" shineColor="#ffffff" speed={1.6} /> : status}
        </p>
        {typing ? (
          <form
            className="flex w-[min(560px,90vw)] items-center gap-2 rounded-full bg-white/10 p-1.5 backdrop-blur"
            onSubmit={(e) => {
              e.preventDefault();
              void ask(typed, "chat");
              setTyped("");
            }}
          >
            <input
              autoFocus
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              onBlur={() => !typed && setTyping(false)}
              placeholder="Ask McFly"
              aria-label="Ask McFly"
              maxLength={2000}
              className="min-w-0 flex-1 bg-transparent px-4 text-[16px] outline-none placeholder:text-white/50"
            />
          </form>
        ) : (
          <div className="flex items-center gap-4">
            <button type="button" onClick={() => setTyping(true)} aria-label="Type instead" className="grid size-12 place-items-center rounded-full bg-white/10 text-white/80 hover:bg-white/15">
              <KeyboardIcon className="size-5" />
            </button>
            {canListen ? (
              <button
                type="button"
                onClick={() => (listening || speaking ? stopAll() : void startListening())}
                disabled={busy && !speaking}
                aria-label={listening ? "Stop listening" : speaking ? "Stop speaking" : "Talk"}
                className={cn(
                  "grid size-20 place-items-center rounded-full transition-transform active:scale-95",
                  listening || speaking ? "bg-white text-[#0D0C10]" : "bg-white/95 text-[#0D0C10] hover:scale-105",
                )}
              >
                {listening || speaking ? <SquareIcon className="size-6" fill="currentColor" /> : <MicIcon className="size-8" />}
              </button>
            ) : null}
            <span className="size-12" aria-hidden="true" />
          </div>
        )}
      </footer>
    </main>
  );
}
