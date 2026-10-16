// Who reads a reply aloud in the browser. McFly's voice is Kokoro on the Pi,
// the iPhone and here, so a Kokoro voice waits for the model rather than
// letting the browser's own voice stand in while it downloads. The browser's
// voice speaks only when it's the voice chosen ("system"), or when Kokoro has
// failed here and its one retry is spent. Pure, so
// tests/speech-engine.test.mjs can check it.

export type KokoroStatus = "idle" | "loading" | "ready" | "failed";

// "load": start (or retry) Kokoro's load, wait for it, then ask again.
export type ReplySpeaker = "kokoro" | "load" | "browser";

export function replySpeaker(voice: string, status: KokoroStatus, canRetry: boolean): ReplySpeaker {
  if (voice === "system") return "browser";
  if (status === "ready") return "kokoro";
  if (status === "failed") return canRetry ? "load" : "browser";
  return "load";
}
