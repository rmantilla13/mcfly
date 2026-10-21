// A story's page read into an article: its text, pictures and videos as
// blocks in page order, the shapes the clients draw. Three sources, best
// first: the page's JSON-LD articleBody (many news sites embed the whole
// story there, even ones that draw it with script), Mozilla's Readability
// over the page, and what the page says about itself (og:description). Free
// of Deno APIs so extract.test.ts can feed it pages.

/// <reference lib="dom" />

import { Readability } from "npm:@mozilla/readability@0.6.0";
import { parseHTML } from "npm:linkedom@0.18.12";
import { extractImage, youtubeThumbnail } from "../ingest/images.ts";

export type Block =
  | { type: "p"; text: string }
  | { type: "h"; text: string }
  | { type: "quote"; text: string; cite?: string }
  | { type: "list"; items: string[]; ordered?: boolean }
  | { type: "image"; url: string; caption?: string }
  | { type: "video"; url: string; provider: "youtube" | "vimeo" | "file"; poster?: string; caption?: string };

export type Status = "ready" | "partial" | "unavailable";

export interface Article {
  status: Status;
  title: string | null;
  byline: string | null;
  site_name: string | null;
  published_at: string | null;
  lead_image: string | null;
  blocks: Block[];
  word_count: number;
}

export const LIMITS = { blocks: 300, media: 40, chars: 80_000, block: 4000, items: 40 };
// Fewer words than this and the page didn't give us the story (a paywall, a
// teaser, a cookie wall): what it has is kept as partial.
export const FULL_WORDS = 120;
// A partial article keeps this many of the page's pictures and videos.
const PARTIAL_MEDIA = 6;

// Elements that never hold the story.
const SKIP = new Set(["script", "style", "noscript", "template", "table", "form", "button", "input", "select", "svg", "nav", "aside", "footer", "header"]);
// Short paragraphs that are the page talking, not the story.
const CHROME = /^(advertisement|sponsored|read more|related|subscribe|sign up|newsletter|share this|follow us|recommended|most read|copied|copy link)\b/i;
// A plug for the site's own newsletter, up to a few sentences long.
const PROMO = /^(sign up|subscribe|get our|join our)\b.*\b(newsletter|inbox|email|briefing)\b/i;
// Text for screen readers only ("opens in a new window") and hidden parts.
const HIDDEN = ".sr-only, .visually-hidden, .screen-reader-text, .screenreader-only, [aria-hidden='true'], [hidden]";

const clean = (s: string | null | undefined): string => (s ?? "").replace(/\s+/g, " ").trim();
const countWords = (s: string): number => (s.match(/\S+/g) ?? []).length;
const clip = (s: string, n: number): string => (s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s);

// An http(s) URL made absolute against the page, or null.
export function absolute(url: string | null | undefined, base: string): string | null {
  const value = clean(url);
  if (!value || /^(data|blob|javascript):/i.test(value)) return null;
  try {
    const u = new URL(value, base);
    return u.protocol === "http:" || u.protocol === "https:" ? u.toString() : null;
  } catch {
    return null;
  }
}

// The widest candidate in a srcset ("a.jpg 640w, b.jpg 1280w") up to 2000w,
// else the last one. Candidates split on a comma and a space, since some
// image CDNs put bare commas in the URL itself.
export function fromSrcset(srcset: string | null | undefined): string | null {
  if (!srcset) return null;
  let best: { url: string; w: number } | null = null;
  let last: string | null = null;
  for (const part of srcset.split(/,\s+/)) {
    const [url, descriptor = ""] = part.trim().split(/\s+/);
    if (!url) continue;
    last = url;
    const w = descriptor.endsWith("w") ? parseInt(descriptor, 10) : descriptor.endsWith("x") ? parseFloat(descriptor) * 1000 : 0;
    if (w <= 2000 && (!best || w > best.w)) best = { url, w };
  }
  return best?.url ?? last;
}

// A YouTube, Vimeo or video-file address as a video block, or null.
export function videoFor(src: string | null | undefined, base: string): Extract<Block, { type: "video" }> | null {
  const url = absolute(src, base);
  if (!url) return null;
  const poster = youtubeThumbnail(url);
  if (poster) {
    const id = poster.split("/vi/")[1].split("/")[0];
    return { type: "video", provider: "youtube", url: `https://www.youtube.com/watch?v=${id}`, poster };
  }
  const vimeo = url.match(/^https?:\/\/(?:www\.|player\.)?vimeo\.com\/(?:video\/)?(\d+)/);
  if (vimeo) return { type: "video", provider: "vimeo", url: `https://vimeo.com/${vimeo[1]}` };
  if (/\.(mp4|m4v|mov|webm)(\?|#|$)/i.test(url)) return { type: "video", provider: "file", url };
  return null;
}

// What the clients get for a story that is itself a video.
export function videoArticle(url: string): Article | null {
  const video = videoFor(url, url);
  if (!video || video.provider === "file") return null;
  return {
    status: "partial",
    title: null,
    byline: null,
    site_name: video.provider === "youtube" ? "YouTube" : "Vimeo",
    published_at: null,
    lead_image: video.poster ?? null,
    blocks: [video],
    word_count: 0,
  };
}

// Blocks gathered under the limits; a picture or video appears once.
class Collector {
  blocks: Block[] = [];
  private chars = 0;
  private media = 0;
  private seen = new Set<string>();

  constructor(readonly base: string) {}

  get full(): boolean {
    return this.blocks.length >= LIMITS.blocks || this.chars >= LIMITS.chars;
  }

  text(type: "p" | "h", raw: string | null | undefined) {
    const text = clean(raw);
    if (!text || this.full) return;
    if (type === "p" && ((countWords(text) <= 8 && CHROME.test(text)) || (countWords(text) <= 60 && PROMO.test(text)))) return;
    this.chars += text.length;
    this.blocks.push({ type, text: clip(text, LIMITS.block) });
  }

  add(block: Block) {
    if (this.full) return;
    if (block.type === "image" || block.type === "video") {
      if (this.media >= LIMITS.media || this.seen.has(block.url)) return;
      this.seen.add(block.url);
      this.media++;
    } else if (block.type === "quote") {
      this.chars += block.text.length;
    } else if (block.type === "list") {
      this.chars += block.items.join(" ").length;
    }
    this.blocks.push(block);
  }
}

// An element's picture: its srcset, a lazy loader's data-* source, or src.
// Icons, spacers and tracking pixels are left out.
function imageOf(el: Element, base: string): string | null {
  const img = el.tagName.toLowerCase() === "img" ? el : el.querySelector("img");
  const source = el.querySelector?.("source[srcset], source[data-srcset]");
  const tiny = (name: string) => {
    const n = parseInt(img?.getAttribute(name) ?? "", 10);
    return Number.isFinite(n) && n > 0 && n < 60;
  };
  if (img && (tiny("width") || tiny("height"))) return null;
  const candidates = [
    fromSrcset(img?.getAttribute("srcset") ?? img?.getAttribute("data-srcset")),
    fromSrcset(source?.getAttribute("srcset") ?? source?.getAttribute("data-srcset")),
    img?.getAttribute("data-src"),
    img?.getAttribute("data-lazy-src"),
    img?.getAttribute("data-original"),
    img?.getAttribute("src"),
  ];
  for (const c of candidates) {
    const url = absolute(c, base);
    if (url && !/\.svg(\?|#|$)/i.test(url) && !/(spacer|pixel|blank|1x1)\.(gif|png)/i.test(url)) return url;
  }
  return null;
}

function mediaOf(el: Element, base: string, caption?: string): Block | null {
  const tag = el.tagName.toLowerCase();
  const cap = caption ? { caption: clip(caption, 500) } : {};
  if (tag === "iframe" || tag === "embed") {
    const v = videoFor(el.getAttribute("src") ?? el.getAttribute("data-src"), base);
    return v ? { ...v, ...cap } : null;
  }
  if (tag === "video") {
    const v = videoFor(el.getAttribute("src") ?? el.querySelector("source[src]")?.getAttribute("src"), base);
    const poster = absolute(el.getAttribute("poster"), base);
    return v ? { ...v, ...(poster && !v.poster ? { poster } : {}), ...cap } : null;
  }
  const url = imageOf(el, base);
  return url ? { type: "image", url, ...cap } : null;
}

// Pictures and videos inside an element, in order.
function mediaWithin(el: Element, out: Collector, caption?: string) {
  for (const m of Array.from(el.querySelectorAll("picture, img, iframe, embed, video"))) {
    // An <img> inside a <picture> or <video> is drawn by its parent.
    if (m.tagName.toLowerCase() === "img" && m.parentElement?.closest("picture, video")) continue;
    const block = mediaOf(m, out.base, caption);
    if (block) out.add(block);
  }
}

function walk(el: Element, out: Collector) {
  for (const child of Array.from(el.children)) {
    if (out.full) return;
    const tag = child.tagName.toLowerCase();
    if (SKIP.has(tag)) continue;
    if (tag === "p" || tag === "pre") {
      out.text("p", child.textContent);
      mediaWithin(child, out);
    } else if (/^h[1-6]$/.test(tag)) {
      out.text("h", child.textContent);
    } else if (tag === "blockquote") {
      const text = clean(child.textContent);
      if (!text) continue;
      const tweet = /twitter-tweet|x-post/.test(child.getAttribute("class") ?? "");
      out.add({ type: "quote", text: clip(text, LIMITS.block), ...(tweet ? { cite: "X" } : {}) });
    } else if (tag === "ul" || tag === "ol") {
      const items = Array.from(child.children)
        .filter((li) => li.tagName.toLowerCase() === "li")
        .map((li) => clip(clean(li.textContent), 600))
        .filter(Boolean)
        .slice(0, LIMITS.items);
      if (items.length) out.add({ type: "list", items, ...(tag === "ol" ? { ordered: true } : {}) });
    } else if (tag === "figure") {
      const caption = clean(child.querySelector("figcaption")?.textContent) || undefined;
      const before = out.blocks.length;
      mediaWithin(child, out, caption);
      // A figure of words (a pull quote, a chart's table) keeps its text.
      if (out.blocks.length === before && caption) out.text("p", caption);
    } else if (tag === "img" || tag === "picture" || tag === "iframe" || tag === "embed" || tag === "video") {
      const block = mediaOf(child, out.base);
      if (block) out.add(block);
    } else {
      walk(child, out);
    }
  }
}

// ─────────────────────────────── JSON-LD ───────────────────────────────

interface LdArticle {
  body: string;
  headline: string;
  author: string;
  published: string;
  image: string;
  publisher: string;
}

const ARTICLE_TYPE = /Article|BlogPosting|Report|NewsArticle/;

function* ldNodes(data: unknown): Generator<Record<string, unknown>> {
  if (Array.isArray(data)) {
    for (const d of data) yield* ldNodes(d);
  } else if (data && typeof data === "object") {
    const node = data as Record<string, unknown>;
    yield node;
    if (node["@graph"]) yield* ldNodes(node["@graph"]);
    if (node.mainEntity) yield* ldNodes(node.mainEntity);
  }
}

const ldText = (v: unknown): string => {
  if (typeof v === "string") return v;
  if (Array.isArray(v)) return v.map(ldText).filter(Boolean).join(", ");
  if (v && typeof v === "object") {
    const o = v as Record<string, unknown>;
    return ldText(o.name ?? o.url ?? o["@id"] ?? "");
  }
  return "";
};

const ldImage = (v: unknown): string => {
  if (typeof v === "string") return v;
  if (Array.isArray(v)) return ldImage(v[0]);
  if (v && typeof v === "object") return ldImage((v as Record<string, unknown>).url);
  return "";
};

function ldArticle(doc: Document): LdArticle | null {
  let found: LdArticle | null = null;
  for (const script of Array.from(doc.querySelectorAll('script[type="application/ld+json"]'))) {
    let data: unknown;
    try {
      data = JSON.parse(script.textContent ?? "");
    } catch {
      continue;
    }
    for (const node of ldNodes(data)) {
      const types = ([] as unknown[]).concat(node["@type"] ?? []).map(String);
      if (!types.some((t) => ARTICLE_TYPE.test(t))) continue;
      const article: LdArticle = {
        body: typeof node.articleBody === "string" ? node.articleBody : "",
        headline: ldText(node.headline),
        author: ldText(node.author),
        published: ldText(node.datePublished),
        image: ldImage(node.image),
        publisher: ldText((node.publisher as Record<string, unknown> | undefined)?.name ?? ""),
      };
      // The one with the story wins; else the first that describes it.
      if (article.body) return article;
      found ??= article;
    }
  }
  return found;
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", "#39": "'" };

// articleBody as paragraphs: its own line breaks, or, for one long run of
// text, groups of three sentences.
export function bodyParagraphs(body: string): string[] {
  const text = body
    .replace(/<\/?(p|br|div|h\d)[^>]*>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&(#?\w+);/g, (m, e: string) => ENTITIES[e] ?? (e.startsWith("#") ? String.fromCodePoint(parseInt(e.slice(1), 10) || 32) : m));
  const lines = text.split(/\n+/).map(clean).filter(Boolean);
  if (lines.length > 1 || (lines[0] ?? "").length < 1500) return lines;
  const sentences = lines[0].match(/[^.!?]+[.!?]+["')\]]*\s*|[^.!?]+$/g) ?? [lines[0]];
  const out: string[] = [];
  for (let i = 0; i < sentences.length; i += 3) out.push(clean(sentences.slice(i, i + 3).join(" ")));
  return out;
}

// ─────────────────────────────── The page ───────────────────────────────

function meta(doc: Document, ...names: string[]): string {
  for (const name of names) {
    const el = doc.querySelector(`meta[property="${name}"], meta[name="${name}"]`);
    const content = clean(el?.getAttribute("content"));
    if (content) return content;
  }
  return "";
}

function isoTime(value: string): string | null {
  if (!value) return null;
  const t = Date.parse(value);
  return Number.isFinite(t) ? new Date(t).toISOString() : null;
}

const textWords = (blocks: Block[]): number =>
  blocks.reduce((n, b) => n + (b.type === "p" || b.type === "h" || b.type === "quote" ? countWords(b.text) : b.type === "list" ? countWords(b.items.join(" ")) : 0), 0);

// A picture's file name without its query, extension or size suffix
// ("hero-1920-80.jpg", "hero-1200x630.jpg", "hero_800w.jpg" are all "hero"),
// for spotting the lead again.
export const pictureKey = (url: string): string => {
  let name: string;
  try {
    name = new URL(url).pathname.split("/").pop()?.toLowerCase() ?? url;
  } catch {
    name = url;
  }
  return name.replace(/(\.[a-z0-9]{2,5})+$/, "").replace(/([-_](\d+(x\d+)?|\d+w))+$/, "");
};

// Readability's pictures and videos placed through the JSON-LD paragraphs at
// the same share of the way through the story.
function interleave(paragraphs: string[], read: Block[]): Block[] {
  const total = Math.max(1, textWords(read));
  const placed: { at: number; block: Block }[] = [];
  let words = 0;
  for (const b of read) {
    if (b.type === "image" || b.type === "video") placed.push({ at: Math.round((words / total) * paragraphs.length), block: b });
    else words += textWords([b]);
  }
  const out: Block[] = [];
  paragraphs.forEach((text, i) => {
    for (const p of placed) if (p.at === i) out.push(p.block);
    out.push({ type: "p", text: clip(text, LIMITS.block) });
  });
  for (const p of placed) if (p.at >= paragraphs.length) out.push(p.block);
  return out.slice(0, LIMITS.blocks);
}

// The article in a page's HTML. Never throws: a page it can't read is
// "unavailable".
export function extractArticle(html: string, pageUrl: string): Article {
  let doc: Document;
  try {
    doc = parseHTML(html).document as unknown as Document;
  } catch {
    return { status: "unavailable", title: null, byline: null, site_name: null, published_at: null, lead_image: null, blocks: [], word_count: 0 };
  }
  const ld = ldArticle(doc);
  const description = meta(doc, "og:description", "twitter:description", "description");

  // Readability changes the document it reads, so it gets its own copy.
  let read: ReturnType<Readability["parse"]> = null;
  try {
    const copy = parseHTML(html).document as unknown as Document;
    for (const el of Array.from(copy.querySelectorAll(HIDDEN))) el.remove();
    read = new Readability(copy, { charThreshold: 300 }).parse();
  } catch {
    read = null;
  }
  const collector = new Collector(pageUrl);
  if (read?.content) walk(parseHTML(`<div>${read.content}</div>`).document.querySelector("div") as unknown as Element, collector);
  let blocks = collector.blocks;

  const ldParagraphs = ld?.body ? bodyParagraphs(ld.body) : [];
  const ldWords = countWords(ldParagraphs.join(" "));
  if (ldWords >= FULL_WORDS && ldWords > textWords(blocks) * 1.3) blocks = interleave(ldParagraphs, blocks);

  const title = clean(meta(doc, "og:title", "twitter:title") || ld?.headline || read?.title || doc.querySelector("title")?.textContent) || null;
  // Readability repeats the title as the first heading.
  if (title && blocks[0]?.type === "h" && blocks[0].text.toLowerCase() === title.toLowerCase()) blocks = blocks.slice(1);

  // A picture opening the story is its lead: the page's own choice, at the
  // page's size. Else the share picture, the JSON-LD one, or the first.
  let lead: string | null = null;
  if (blocks[0]?.type === "image") {
    lead = blocks[0].url;
    blocks = blocks.slice(1);
  }
  lead ??= extractImage(html, pageUrl) ?? absolute(ld?.image, pageUrl) ??
    (blocks.find((b) => b.type === "image") as { url: string } | undefined)?.url ?? null;
  // The lead is drawn above the story; it isn't drawn again inside it.
  if (lead) {
    const key = pictureKey(lead);
    const i = blocks.findIndex((b) => b.type === "image" && pictureKey(b.url) === key);
    if (i >= 0) blocks = [...blocks.slice(0, i), ...blocks.slice(i + 1)];
  }

  let words = textWords(blocks);
  let status: Status = "ready";
  if (words < FULL_WORDS) {
    const media = blocks.filter((b) => b.type === "image" || b.type === "video").slice(0, PARTIAL_MEDIA);
    const teaser = description || clean(read?.excerpt);
    blocks = [...(teaser ? [{ type: "p", text: clip(teaser, LIMITS.block) } as Block] : []), ...media];
    words = textWords(blocks);
    status = blocks.length ? "partial" : "unavailable";
  }

  return {
    status,
    title: title ? clip(title, 300) : null,
    byline: clip(clean(ld?.author || read?.byline || meta(doc, "author", "article:author")), 200) || null,
    site_name: clip(clean(meta(doc, "og:site_name") || read?.siteName || ld?.publisher), 120) || null,
    published_at: isoTime(meta(doc, "article:published_time", "og:published_time") || ld?.published || read?.publishedTime || ""),
    lead_image: lead,
    blocks,
    word_count: words,
  };
}

// The article's words for the summary: the title, then each block's text.
export function articleText(article: Article): string {
  const lines: string[] = [];
  if (article.title) lines.push(article.title);
  for (const b of article.blocks) {
    if (b.type === "p") lines.push(b.text);
    else if (b.type === "h") lines.push(`## ${b.text}`);
    else if (b.type === "quote") lines.push(`> ${b.text}`);
    else if (b.type === "list") lines.push(b.items.map((i) => `- ${i}`).join("\n"));
    else if (b.caption) lines.push(`[${b.type}: ${b.caption}]`);
  }
  return lines.join("\n\n");
}
