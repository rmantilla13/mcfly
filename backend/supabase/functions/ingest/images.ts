// Pictures for stories that came without one, the way the Daily Pulse
// pipeline picks them: a YouTube thumbnail for a YouTube link, otherwise the
// page's og:image or twitter:image. Free of Deno APIs so it can be tested
// with a fake fetch (images.test.ts).

import type { NewsItem } from "./parse.ts";

export type Fetcher = (url: string, init: { signal: AbortSignal; headers: Record<string, string> }) => Promise<Response>;

export const MAX_HTML_BYTES = 512 * 1024;
export const DEFAULT_TIMEOUT_MS = 5000;
export const CONCURRENCY = 4;

const YOUTUBE_ID = /^[A-Za-z0-9_-]{11}$/;

// The thumbnail of a YouTube watch, short or youtu.be link, or null.
export function youtubeThumbnail(url: string): string | null {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  const host = u.hostname.replace(/^www\.|^m\./, "");
  let id: string | null = null;
  if (host === "youtu.be") id = u.pathname.slice(1).split("/")[0];
  else if (host === "youtube.com" || host === "youtube-nocookie.com") {
    if (u.pathname === "/watch") id = u.searchParams.get("v");
    else {
      const m = u.pathname.match(/^\/(?:shorts|embed|live|v)\/([^/?#]+)/);
      if (m) id = m[1];
    }
  }
  return id && YOUTUBE_ID.test(id) ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : null;
}

// The first og:image / twitter:image in a page, made absolute. Attribute
// order in the tag doesn't matter; html entities in the URL are decoded.
export function extractImage(html: string, pageUrl: string): string | null {
  const head = html.slice(0, MAX_HTML_BYTES);
  const metas = head.match(/<meta\b[^>]*>/gi) ?? [];
  const wanted = ["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"];
  const found = new Map<string, string>();
  for (const tag of metas) {
    const name = (tag.match(/\b(?:property|name)\s*=\s*["']([^"']+)["']/i)?.[1] ?? "").toLowerCase();
    if (!wanted.includes(name) || found.has(name)) continue;
    const content = tag.match(/\bcontent\s*=\s*["']([^"']*)["']/i)?.[1]?.trim();
    if (content) found.set(name, decodeEntities(content));
  }
  for (const name of wanted) {
    const value = found.get(name);
    if (!value) continue;
    try {
      const abs = new URL(value, pageUrl);
      if (abs.protocol === "http:" || abs.protocol === "https:") return abs.toString();
    } catch {
      // not a URL; try the next one
    }
  }
  return null;
}

function decodeEntities(s: string): string {
  return s.replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
}

// Reads at most maxBytes of a response body as text.
export async function readSome(res: Response, maxBytes: number): Promise<string> {
  if (!res.body) return "";
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    size += value.byteLength;
    if (size >= maxBytes) {
      await reader.cancel().catch(() => {});
      break;
    }
  }
  const all = new Uint8Array(Math.min(size, maxBytes));
  let at = 0;
  for (const c of chunks) {
    const take = Math.min(c.byteLength, all.byteLength - at);
    all.set(c.subarray(0, take), at);
    at += take;
    if (at >= all.byteLength) break;
  }
  return new TextDecoder("utf-8", { fatal: false }).decode(all);
}

// The picture for one story URL, or null. Never throws.
export async function imageFor(url: string, fetcher: Fetcher, timeoutMs = DEFAULT_TIMEOUT_MS): Promise<string | null> {
  const thumb = youtubeThumbnail(url);
  if (thumb) return thumb;
  if (!/^https?:\/\//i.test(url)) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetcher(url, {
      signal: controller.signal,
      headers: { "Accept": "text/html,application/xhtml+xml", "User-Agent": "McFlyBot/1.0 (+https://mcfly.bot)" },
    });
    if (!res.ok) return null;
    const type = res.headers.get("content-type") ?? "";
    if (type && !/html|xml/i.test(type)) return null;
    return extractImage(await readSome(res, MAX_HTML_BYTES), res.url || url);
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// Fills `image` on the items that have none, a few at a time. Items that
// share a URL share the lookup. Returns how many pictures were found.
export async function resolveImages(items: NewsItem[], fetcher: Fetcher, timeoutMs = DEFAULT_TIMEOUT_MS): Promise<number> {
  const pending = items.filter((i) => !i.image);
  const urls = [...new Set(pending.map((i) => i.url))];
  const results = new Map<string, string | null>();
  let next = 0;
  const worker = async () => {
    while (next < urls.length) {
      const url = urls[next++];
      results.set(url, await imageFor(url, fetcher, timeoutMs));
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, urls.length) }, worker));
  let found = 0;
  for (const item of pending) {
    const image = results.get(item.url);
    if (image) {
      item.image = image;
      found++;
    }
  }
  return found;
}
