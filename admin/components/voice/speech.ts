"use client";

// Speaking McFly's replies in the browser, with the voice Homestead uses:
// Kokoro-82M ("Heart" by default; Bella, Michael and Fenrir too), rendered
// a sentence ahead in a worker and played through Web Audio, whose level
// drives the voice glow. A reply waits for the model to load (the first
// time, a download) rather than letting the browser's own voice stand in, so
// it sounds as it does on the Pi and the iPhone; the browser's voice speaks
// only when chosen, or when Kokoro can't run here (lib/speech-engine.ts).

import { useEffect, useSyncExternalStore } from "react";
import { accountVoiceAction, setAccountVoiceAction } from "@/app/(console)/actions";
import { followVoice } from "@/lib/account-voice";
import { speechPieces } from "@/lib/sentences";
import { replySpeaker } from "@/lib/speech-engine";

export type VoiceId = "af_heart" | "af_bella" | "am_michael" | "am_fenrir" | "system";
export const VOICES: { id: VoiceId; name: string }[] = [
  { id: "af_heart", name: "Heart" },
  { id: "af_bella", name: "Bella" },
  { id: "am_michael", name: "Michael" },
  { id: "am_fenrir", name: "Fenrir" },
  { id: "system", name: "This device's voice" },
];
export type KokoroState = { status: "idle" | "loading" | "ready" | "failed"; percent: number };

// The voice is the account's (lib/account-voice.ts): picked here, on the Pi
// or in the app, the others follow. This browser keeps a copy so the first
// reply needn't wait for the server; "This device's voice" is kept here only.
const VOICE_KEY = "mcfly.voice";

function readVoice(): VoiceId {
  try {
    const v = localStorage.getItem(VOICE_KEY) as VoiceId | null;
    return v && VOICES.some((x) => x.id === v) ? v : "af_heart";
  } catch {
    return "af_heart";
  }
}

let voice: VoiceId | null = null;
const voiceListeners = new Set<() => void>();
let picks = 0; // a pick made while a sync was reading wins over what it read
let saving: Promise<unknown> = Promise.resolve();

export function storedVoice(): VoiceId {
  return (voice ??= readVoice());
}
export function subscribeVoice(fn: () => void) {
  voiceListeners.add(fn);
  return () => {
    voiceListeners.delete(fn);
  };
}
function setVoice(v: VoiceId) {
  if (v === storedVoice()) return;
  voice = v;
  try {
    localStorage.setItem(VOICE_KEY, v);
  } catch {
    // Remembered for this page only.
  }
  for (const fn of voiceListeners) fn();
}

// Catches up with the account's voice. "This device's voice" stays.
export async function syncVoice(): Promise<void> {
  const pick = picks;
  await saving;
  const account = await accountVoiceAction().catch(() => null);
  if (pick === picks) setVoice(followVoice(storedVoice(), account));
}

// A voice picked here. A Kokoro voice goes to every display, so the Pi and
// the app speak with it too; "This device's voice" is this browser's alone.
export function chooseVoice(v: VoiceId) {
  picks++;
  setVoice(v);
  if (v === "system") return;
  saving = setAccountVoiceAction(v)
    .then((r) => {
      if (r && !r.ok) console.warn("The voice wasn't saved for the displays:", r.error);
    })
    .catch(() => console.warn("The voice wasn't saved for the displays."));
}

// The voice to speak with, kept up with the account while `live`: now, when
// the page is looked at again, and every minute.
export function useVoice(live = true): VoiceId {
  const v = useSyncExternalStore(subscribeVoice, storedVoice, () => "af_heart" as VoiceId);
  useEffect(() => {
    if (!live) return;
    const sync = () => {
      if (document.visibilityState === "visible") void syncVoice();
    };
    sync();
    document.addEventListener("visibilitychange", sync);
    const timer = setInterval(sync, 60_000);
    return () => {
      document.removeEventListener("visibilitychange", sync);
      clearInterval(timer);
    };
  }, [live]);
  return v;
}

class KokoroPlayer {
  state: KokoroState = { status: "idle", percent: 0 };
  private listeners = new Set<() => void>();
  private worker: Worker | null = null;
  private ctx: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private bins: Uint8Array<ArrayBuffer> | null = null;
  private sources = new Set<AudioBufferSourceNode>();
  private nextStart = 0;
  private generation = 0;
  private pending = new Map<number, (r: { samples?: Float32Array; rate?: number; error?: string }) => void>();
  private nextId = 1;
  // A failed load (a dropped download, say) is tried once more.
  private retries = 1;
  speaking = false;

  subscribe = (fn: () => void) => {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  };
  getState = () => this.state;
  private set(state: Partial<KokoroState>) {
    this.state = { ...this.state, ...state };
    for (const fn of this.listeners) fn();
  }

  private ensureWorker(): Worker | null {
    if (this.worker || typeof Worker === "undefined") return this.worker;
    try {
      this.worker = new Worker(new URL("./kokoro.worker.ts", import.meta.url), { type: "module" });
    } catch {
      this.set({ status: "failed" });
      return null;
    }
    this.worker.onmessage = (e: MessageEvent) => {
      const m = e.data as { type: string; id?: number; percent?: number; samples?: Float32Array; rate?: number; error?: string };
      if (m.type === "progress") this.set({ status: "loading", percent: m.percent ?? 0 });
      else if (m.type === "ready") this.set({ status: "ready", percent: 100 });
      else if (m.type === "failed") {
        console.warn("Kokoro voice unavailable:", m.error);
        this.set({ status: "failed" });
      } else if ((m.type === "audio" || m.type === "error") && m.id != null) {
        this.pending.get(m.id)?.(m);
        this.pending.delete(m.id);
      }
    };
    this.worker.onerror = () => this.set({ status: "failed" });
    return this.worker;
  }

  // Starts the one-time download early (the voice page does on open).
  load() {
    if (this.state.status !== "idle") return;
    const w = this.ensureWorker();
    if (!w) return;
    this.set({ status: "loading", percent: 0 });
    w.postMessage({ type: "load" });
  }

  get canRetry() {
    return this.retries > 0;
  }

  // Resolves once the voice is ready or has failed, loading it first, or
  // once more after a failure while a retry is left.
  ready(): Promise<void> {
    if (this.state.status === "failed" && this.retries > 0) {
      this.retries--;
      this.worker?.terminate();
      this.worker = null;
      this.set({ status: "idle", percent: 0 });
    }
    this.load();
    return new Promise((resolve) => {
      const settled = () => this.state.status === "ready" || this.state.status === "failed";
      if (settled()) return resolve();
      const off = this.subscribe(() => {
        if (!settled()) return;
        off();
        resolve();
      });
    });
  }

  private render(text: string, voice: VoiceId, speed: number) {
    const id = this.nextId++;
    return new Promise<{ samples?: Float32Array; rate?: number; error?: string }>((resolve) => {
      this.pending.set(id, resolve);
      this.worker?.postMessage({ type: "speak", id, text, voice, speed });
    });
  }

  private audio(): AudioContext {
    if (!this.ctx) {
      this.ctx = new AudioContext();
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = 512;
      this.analyser.smoothingTimeConstant = 0.55;
      this.analyser.connect(this.ctx.destination);
      this.bins = new Uint8Array(new ArrayBuffer(this.analyser.frequencyBinCount));
    }
    return this.ctx;
  }

  // The playing voice's level in three bands, for the glow (0..1).
  levels(): { level: number; low: number; mid: number; high: number } {
    if (!this.analyser || !this.bins || !this.sources.size) return { level: 0, low: 0, mid: 0, high: 0 };
    this.analyser.getByteFrequencyData(this.bins);
    const avg = (a: number, b: number) => {
      let s = 0;
      for (let i = a; i < b; i++) s += this.bins![i];
      return Math.min(1, (s / (b - a) / 255) * 2.2);
    };
    const low = avg(2, 12);
    const mid = avg(12, 48);
    const high = avg(48, 120);
    return { level: Math.max(low, mid, high), low, mid, high };
  }

  // Speaks `text`, a piece ahead; resolves when it has all played (or was stopped).
  async speak(text: string, voice: VoiceId, speed = 1): Promise<void> {
    this.stop();
    const gen = ++this.generation;
    const ctx = this.audio();
    if (ctx.state === "suspended") await ctx.resume().catch(() => {});
    this.speaking = true;
    this.nextStart = ctx.currentTime + 0.05;
    const pieces = speechPieces(text);
    let ahead = pieces.length ? this.render(pieces[0], voice, speed) : null;
    for (let i = 0; i < pieces.length && ahead; i++) {
      const result = await ahead;
      if (gen !== this.generation) return;
      ahead = i + 1 < pieces.length ? this.render(pieces[i + 1], voice, speed) : null;
      if (!result.samples || !result.rate) continue;
      const buffer = ctx.createBuffer(1, result.samples.length, result.rate);
      buffer.copyToChannel(new Float32Array(result.samples), 0);
      const src = ctx.createBufferSource();
      src.buffer = buffer;
      src.connect(this.analyser!);
      const at = Math.max(ctx.currentTime, this.nextStart);
      src.start(at);
      this.nextStart = at + buffer.duration + 0.08;
      this.sources.add(src);
      src.onended = () => this.sources.delete(src);
    }
    // Wait for the last piece to finish.
    while (gen === this.generation && (this.sources.size || ctx.currentTime < this.nextStart - 0.08)) {
      await new Promise((r) => setTimeout(r, 120));
    }
    if (gen === this.generation) this.speaking = false;
  }

  stop() {
    this.generation++;
    for (const s of this.sources) {
      try {
        s.stop();
      } catch {
        // Already stopped.
      }
    }
    this.sources.clear();
    this.speaking = false;
  }
}

let player: KokoroPlayer | null = null;
export function kokoro(): KokoroPlayer {
  player ??= new KokoroPlayer();
  return player;
}

// The latest speakReply; a newer one, or stopSpeaking, drops a reply still
// waiting for the voice to load.
let replyGeneration = 0;

// Speaks a reply in the chosen voice: Kokoro, once it has loaded, or the
// browser's when that's the choice (lib/speech-engine.ts). Resolves when done
// speaking.
export async function speakReply(text: string, voice: VoiceId, speed = 1): Promise<void> {
  const gen = ++replyGeneration;
  const k = kokoro();
  if (replySpeaker(voice, k.state.status, k.canRetry) === "load") await k.ready();
  if (gen !== replyGeneration) return;
  if (replySpeaker(voice, k.state.status, false) === "kokoro") return k.speak(text, voice, speed);
  if (voice !== "system") console.warn("Kokoro can't run here; the browser's voice reads this reply.");
  if (typeof speechSynthesis === "undefined") return;
  speechSynthesis.cancel();
  await new Promise<void>((resolve) => {
    const u = new SpeechSynthesisUtterance(text.replace(/[*_#`>[\]()]/g, ""));
    u.rate = speed;
    u.onend = () => resolve();
    u.onerror = () => resolve();
    speechSynthesis.speak(u);
  });
}

// Whether a reply is being read out right now, in either voice.
export function isSpeaking(): boolean {
  return !!player?.speaking || (typeof speechSynthesis !== "undefined" && speechSynthesis.speaking);
}

export function stopSpeaking() {
  replyGeneration++;
  kokoro().stop();
  if (typeof speechSynthesis !== "undefined") speechSynthesis.cancel();
}
