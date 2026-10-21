// Fetching a story's page for the reader. The address comes from the story
// row, never from the caller, and still has to be a public http(s) one on
// every redirect hop: no local, private or link-local hosts. At most
// MAX_PAGE_BYTES of HTML is read. Free of Deno APIs so page.test.ts can use
// a fake fetch.

import { readSome } from "../ingest/images.ts";

export const MAX_PAGE_BYTES = 3 * 1024 * 1024;
export const PAGE_TIMEOUT_MS = 8000;
export const MAX_REDIRECTS = 5;

export type Fetcher = (url: string, init: RequestInit) => Promise<Response>;

const HEADERS = {
  "Accept": "text/html,application/xhtml+xml",
  "Accept-Language": "en-US,en;q=0.8",
  "User-Agent": "Mozilla/5.0 (compatible; McFlyBot/1.0; +https://mcfly.bot)",
};

// The address when it is a public web page's, else null.
export function publicUrl(raw: string): URL | null {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return null;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return null;
  if (u.username || u.password) return null;
  const host = u.hostname.toLowerCase().replace(/\.$/, "");
  // localhost, intranet names, mDNS and the like.
  if (!host.includes(".") || /\.(local|localhost|internal|intranet|lan|home|arpa)$/.test(host)) return null;
  // IPv6 literals are never a news site.
  if (host.startsWith("[")) return null;
  const v4 = host.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (v4) {
    const [a, b] = [Number(v4[1]), Number(v4[2])];
    if (a === 0 || a === 10 || a === 127 || a >= 224 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127)) return null;
  }
  return u;
}

export type Page = { html: string; url: string } | { error: string };

// The page's HTML and its final address, or why there's none. Never throws.
export async function fetchPage(url: string, fetcher: Fetcher, timeoutMs = PAGE_TIMEOUT_MS): Promise<Page> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    let current = url;
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      const u = publicUrl(current);
      if (!u) return { error: "not a public web address" };
      const res = await fetcher(u.toString(), { redirect: "manual", signal: controller.signal, headers: HEADERS });
      if (res.status >= 300 && res.status < 400) {
        const location = res.headers.get("location");
        await res.body?.cancel().catch(() => {});
        if (!location) return { error: `the page answered ${res.status} without a location` };
        current = new URL(location, u).toString();
        continue;
      }
      if (!res.ok) {
        await res.body?.cancel().catch(() => {});
        return { error: `the page answered ${res.status}` };
      }
      const type = res.headers.get("content-type") ?? "";
      if (type && !/html|xml/i.test(type)) {
        await res.body?.cancel().catch(() => {});
        return { error: "not a web page" };
      }
      return { html: await readSome(res, MAX_PAGE_BYTES), url: u.toString() };
    }
    return { error: "too many redirects" };
  } catch {
    return { error: controller.signal.aborted ? "the page took too long" : "couldn't reach the page" };
  } finally {
    clearTimeout(timer);
  }
}
