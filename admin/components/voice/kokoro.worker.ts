/// <reference lib="webworker" />
// Runs Kokoro-82M (the voice Homestead speaks with) off the main thread, so
// the glow keeps moving while a sentence renders. The runtime comes from
// McFly itself (/voice-runtime/, copied at build time); the model's weights
// (~90 MB, q8) come from Hugging Face once and then from the browser's cache.
//
//   in:  { type: "load" } | { type: "speak", id, text, voice, speed }
//   out: { type: "progress", percent } | { type: "ready" } | { type: "failed", error }
//        | { type: "audio", id, samples: Float32Array, rate } | { type: "error", id, error }

import { KokoroTTS, env } from "kokoro-js";

env.wasmPaths = "/voice-runtime/";

const MODEL = "onnx-community/Kokoro-82M-v1.0-ONNX";
let loading: Promise<KokoroTTS> | null = null;
const files = new Map<string, number>();

function load(): Promise<KokoroTTS> {
  loading ??= KokoroTTS.from_pretrained(MODEL, {
    dtype: "q8",
    device: "wasm",
    progress_callback: (p: { status?: string; file?: string; loaded?: number; total?: number }) => {
      if (p.status !== "progress" || !p.file || !p.total) return;
      files.set(p.file, (p.loaded ?? 0) / p.total);
      const values = [...files.values()];
      self.postMessage({ type: "progress", percent: Math.round((100 * values.reduce((a, b) => a + b, 0)) / values.length) });
    },
  }).catch((err) => {
    loading = null;
    throw err;
  });
  return loading;
}

self.onmessage = async (e: MessageEvent) => {
  const msg = e.data as { type: string; id?: number; text?: string; voice?: string; speed?: number };
  if (msg.type === "load") {
    try {
      await load();
      self.postMessage({ type: "ready" });
    } catch (err) {
      self.postMessage({ type: "failed", error: err instanceof Error ? err.message : String(err) });
    }
    return;
  }
  if (msg.type === "speak") {
    try {
      const tts = await load();
      const audio = await tts.generate(msg.text ?? "", {
        voice: (msg.voice ?? "af_heart") as "af_heart",
        speed: msg.speed ?? 1,
      });
      const samples = audio.audio as Float32Array;
      self.postMessage({ type: "audio", id: msg.id, samples, rate: audio.sampling_rate }, [samples.buffer]);
    } catch (err) {
      self.postMessage({ type: "error", id: msg.id, error: err instanceof Error ? err.message : String(err) });
    }
  }
};
