// The picture Grok draws for an opened story, shown with its summary: the
// prompt, the request to xAI's image model and the reading of its answer.
// Free of Deno APIs and I/O so illustration.test.ts covers it.

export const IMAGES_URL = "https://api.x.ai/v1/images/generations";
export const DEFAULT_IMAGE_MODEL = "grok-imagine-image-2.0";
export const BUCKET = "news-illustrations";
// A picture that failed isn't asked for again sooner than this.
export const ILLUSTRATION_RETRY_MS = 10 * 60 * 1000;
// The signed links clients get; reports are kept about two weeks.
export const LINK_SECONDS = 30 * 24 * 3600;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

type Env = { get(name: string): string | undefined };

// The image model: the GROK_IMAGE_MODEL secret, else the default.
export function imageModelName(env: Env): string {
  return env.get("GROK_IMAGE_MODEL")?.trim() || DEFAULT_IMAGE_MODEL;
}

const oneLine = (s: string, n: number) => {
  const t = s.replace(/\s+/g, " ").trim();
  return t.length > n ? t.slice(0, n - 1).trimEnd() + "…" : t;
};

// What to draw: the story's idea as an editorial picture, with no words,
// marks or real people in it (a headline names people; the picture shows the idea).
export function illustrationPrompt(story: { headline: string; takeaway?: string | null; section_name?: string | null }): string {
  return [
    "An editorial illustration for a news story, for a calm home display.",
    `Story: ${oneLine(story.headline, 300)}`,
    story.takeaway ? `What it means: ${oneLine(story.takeaway, 400)}` : "",
    story.section_name ? `Section: ${oneLine(story.section_name, 60)}` : "",
    "Show the idea with objects, places and symbols in a clean, modern style: soft light, a warm gradient palette, gentle depth, one clear subject.",
    "No text, letters, numbers, logos, watermarks, screenshots or user interface. No real or recognizable people.",
  ].filter(Boolean).join("\n");
}

export function illustrationRequest(model: string, prompt: string) {
  return { model, prompt, n: 1, aspect_ratio: "4:3", resolution: "1k", response_format: "b64_json" };
}

// The picture's bytes from xAI's answer, or null.
export function readIllustration(data: unknown): { bytes: Uint8Array; type: string } | null {
  const first = (data as { data?: unknown[] } | null)?.data?.[0] as Record<string, unknown> | undefined;
  const b64 = typeof first?.b64_json === "string" ? first.b64_json.replace(/^data:[^,]*,/, "") : "";
  if (!b64) return null;
  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
  if (bytes.length < 100 || bytes.length > MAX_IMAGE_BYTES) return null;
  // JPEG, PNG or WebP by their first bytes; anything else isn't kept.
  const type = bytes[0] === 0xff && bytes[1] === 0xd8 ? "image/jpeg"
    : bytes[0] === 0x89 && bytes[1] === 0x50 ? "image/png"
    : bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50 ? "image/webp"
    : "";
  return type ? { bytes, type } : null;
}

// The path a story's picture is kept under.
export function illustrationPath(itemId: string, type: string): string {
  return `${itemId}.${type === "image/png" ? "png" : type === "image/webp" ? "webp" : "jpg"}`;
}

// The story has no picture, and the last try (if any) was long enough ago.
export function needsIllustration(a: { illustration?: string | null; illustration_tried_at?: string | null } | null, now = Date.now()): boolean {
  if (!a) return true;
  if (a.illustration) return false;
  const tried = a.illustration_tried_at ? Date.parse(a.illustration_tried_at) : NaN;
  return !(tried > now - ILLUSTRATION_RETRY_MS);
}
