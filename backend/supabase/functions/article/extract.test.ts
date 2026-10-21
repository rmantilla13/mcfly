// Unit tests for reading an article out of a page: `deno test article/`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { articleText, bodyParagraphs, extractArticle, FULL_WORDS, fromSrcset, pictureKey, videoArticle, videoFor } from "./extract.ts";

const para = (n: number, word = "story") => Array.from({ length: n }, (_, i) => `${word}${i}`).join(" ") + ".";

Deno.test("fromSrcset: the widest candidate up to 2000w, commas inside URLs kept", () => {
  assertEquals(fromSrcset("a.jpg 640w, b.jpg 1280w, c.jpg 2400w"), "b.jpg");
  assertEquals(fromSrcset("https://res.cloudinary.com/x/w_640,h_360/a.jpg 640w, https://res.cloudinary.com/x/w_1280,h_720/a.jpg 1280w"),
    "https://res.cloudinary.com/x/w_1280,h_720/a.jpg");
  assertEquals(fromSrcset("a.jpg 1x, b.jpg 2x"), "b.jpg");
  assertEquals(fromSrcset(""), null);
});

Deno.test("videoFor: YouTube and Vimeo embeds as watch links, files kept, anything else not", () => {
  assertEquals(videoFor("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0", "https://x.test"), {
    type: "video",
    provider: "youtube",
    url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    poster: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
  });
  assertEquals(videoFor("https://player.vimeo.com/video/76979871?h=1", "https://x.test"), { type: "video", provider: "vimeo", url: "https://vimeo.com/76979871" });
  assertEquals(videoFor("/media/clip.mp4", "https://x.test/a/b"), { type: "video", provider: "file", url: "https://x.test/media/clip.mp4" });
  assertEquals(videoFor("https://www.google.com/maps/embed?pb=1", "https://x.test"), null);
});

Deno.test("pictureKey: one picture at any size is one key", () => {
  assertEquals(pictureKey("https://cdn.mos.cms.futurecdn.net/npK5HC-1920-80.jpg"), "npk5hc");
  assertEquals(pictureKey("https://cdn.mos.cms.futurecdn.net/npK5HC-1200-80.jpg.webp?x=1"), "npk5hc");
  assertEquals(pictureKey("https://x.test/a/hero-1200x630.png"), "hero");
  assertEquals(pictureKey("https://x.test/a/hero_800w.jpg"), "hero");
  assertEquals(pictureKey("https://x.test/a/2026-10-20.jpg"), "2026");
});

Deno.test("videoArticle: a YouTube story is its video", () => {
  const a = videoArticle("https://youtu.be/dQw4w9WgXcQ")!;
  assertEquals(a.status, "partial");
  assertEquals(a.blocks[0].type, "video");
  assertEquals(a.lead_image, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg");
  assertEquals(videoArticle("https://example.com/news"), null);
});

const page = (body: string, head = "") => `<!doctype html><html><head><title>Site title</title>
  <meta property="og:title" content="The Headline">
  <meta property="og:site_name" content="The Paper">
  <meta property="og:image" content="https://cdn.paper.test/lead-1200.jpg">
  <meta property="article:published_time" content="2026-10-20T09:30:00-05:00">
  <meta name="author" content="Pat Writer">
  ${head}</head><body><header><nav><a href="/">Home</a></nav></header>${body}<footer>© The Paper</footer></body></html>`;

Deno.test("extractArticle: text, headings, quotes, lists, pictures and videos in page order", () => {
  const html = page(`<main><article>
    <h1>The Headline</h1>
    <p>${para(60, "first")}</p>
    <figure><img src="https://cdn.paper.test/lead-1200.jpg" alt=""><figcaption>The lead again</figcaption></figure>
    <h2>What changed</h2>
    <p>${para(60, "second")}</p>
    <figure><img src="/img/chart-small.png" srcset="/img/chart-640.png 640w, /img/chart-1280.png 1280w" alt="chart"><figcaption>Sales by month</figcaption></figure>
    <blockquote><p>We are thrilled, said a spokesperson.</p></blockquote>
    <ul><li>One thing</li><li>Another thing</li></ul>
    <p>Advertisement</p>
    <p>Sign up to the Paper's AI Guide weekly newsletter summing up all the biggest AI news you need to know.</p>
    <p>Read the docs<span class="sr-only"> (opens in a new window)</span> today and every day of the week to come.</p>
    <iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ"></iframe>
    <img src="/pixel.gif" width="1" height="1">
    <p>${para(60, "third")}</p>
  </article></main>`);
  const a = extractArticle(html, "https://paper.test/2026/10/story");
  assertEquals(a.status, "ready");
  assertEquals(a.title, "The Headline");
  assertEquals(a.site_name, "The Paper");
  assertEquals(a.byline, "Pat Writer");
  assertEquals(a.published_at, "2026-10-20T14:30:00.000Z");
  assertEquals(a.lead_image, "https://cdn.paper.test/lead-1200.jpg");
  assertEquals(a.blocks.map((b) => b.type), ["p", "h", "p", "image", "quote", "list", "p", "video", "p"]);
  assertEquals(a.blocks[3], { type: "image", url: "https://paper.test/img/chart-1280.png", caption: "Sales by month" });
  assertEquals(a.blocks[5], { type: "list", items: ["One thing", "Another thing"] });
  assert(a.word_count >= 180, `${a.word_count} words`);
  assert(!a.blocks.some((b) => b.type === "p" && (b.text === "Advertisement" || b.text.startsWith("Sign up"))), "chrome is dropped");
  assert(!JSON.stringify(a.blocks).includes("pixel.gif"), "tracking pixels are dropped");
  assert(!JSON.stringify(a.blocks).includes("opens in a new window"), "screen-reader text is dropped");
});

Deno.test("extractArticle: the JSON-LD body wins when the page draws less of it, keeping the pictures", () => {
  const body = [para(50, "alpha"), para(50, "beta"), para(50, "gamma"), para(50, "delta")].join("\n\n");
  const ld = { "@context": "https://schema.org", "@graph": [{ "@type": "WebPage" }, {
    "@type": ["NewsArticle"],
    headline: "LD headline",
    articleBody: body,
    author: [{ "@type": "Person", name: "Lee Reporter" }],
    datePublished: "2026-10-19T12:00:00Z",
  }] };
  const html = `<html><head><script type="application/ld+json">${JSON.stringify(ld)}</script></head><body><article>
    <p>${para(20, "teaser")}</p><p>${para(20, "teaser2")}</p>
    <figure><img src="https://cdn.test/inline.jpg"><figcaption>Inline</figcaption></figure>
    <p>${para(10, "middle")}</p>
    <figure><img src="https://cdn.test/second.jpg"><figcaption>Second</figcaption></figure>
    <p>Subscribe to keep reading.</p></article></body></html>`;
  const a = extractArticle(html, "https://news.test/a");
  assertEquals(a.status, "ready");
  assertEquals(a.title, "LD headline");
  assertEquals(a.byline, "Lee Reporter");
  assertEquals(a.published_at, "2026-10-19T12:00:00.000Z");
  assertEquals(a.blocks.filter((b) => b.type === "p").length, 4);
  assert(a.blocks.some((b) => b.type === "image" && b.caption === "Second"), "the page's pictures are kept");
  assertEquals(a.lead_image, "https://cdn.test/inline.jpg", "with no og:image the first picture leads");
  assert(!a.blocks.some((b) => b.type === "image" && b.url === a.lead_image), "and isn't drawn twice");
});

Deno.test("extractArticle: a picture opening the story leads, at the page's size", () => {
  const html = page(`<article><figure><img src="https://cdn.paper.test/lead-1920-80.jpg"><figcaption>Credit</figcaption></figure>
    <p>${para(80)}</p><p>${para(80, "more")}</p></article>`);
  const a = extractArticle(html, "https://paper.test/x");
  assertEquals(a.lead_image, "https://cdn.paper.test/lead-1920-80.jpg");
  assertEquals(a.blocks.map((b) => b.type), ["p", "p"]);
});

Deno.test("extractArticle: a paywall keeps the description and the pictures as partial", () => {
  const html = page(`<article><p>Subscribe to read the full story.</p><img src="https://cdn.paper.test/inside.jpg"></article>`,
    `<meta property="og:description" content="The short version of the story.">`);
  const a = extractArticle(html, "https://paper.test/x");
  assertEquals(a.status, "partial");
  assertEquals(a.blocks[0], { type: "p", text: "The short version of the story." });
  assert(a.word_count < FULL_WORDS);
});

Deno.test("extractArticle: nothing usable is unavailable, and junk never throws", () => {
  const a = extractArticle("<html><body><div id=app></div><script>render()</script></body></html>", "https://spa.test/");
  assertEquals(a.status, "unavailable");
  assertEquals(a.blocks, []);
  assertEquals(extractArticle("", "https://x.test").status, "unavailable");
  assertEquals(extractArticle("\u0000<<<>>>", "https://x.test").status, "unavailable");
});

Deno.test("bodyParagraphs: line breaks, tags and entities, and one long run in threes", () => {
  assertEquals(bodyParagraphs("One.\n\nTwo &amp; three.<br>Four"), ["One.", "Two & three.", "Four"]);
  const long = Array.from({ length: 30 }, (_, i) => `Sentence number ${i} goes on for a while to make it long enough.`).join(" ");
  const out = bodyParagraphs(long);
  assertEquals(out.length, 10);
  assert(out[0].startsWith("Sentence number 0") && out[0].endsWith("number 2 goes on for a while to make it long enough."));
});

Deno.test("articleText: the title, then each block as text", () => {
  const text = articleText({
    status: "ready", title: "T", byline: null, site_name: null, published_at: null, lead_image: null, word_count: 3,
    blocks: [{ type: "p", text: "Hello." }, { type: "h", text: "Part" }, { type: "list", items: ["a", "b"] }, { type: "image", url: "https://x/i.jpg", caption: "A chart" }],
  });
  assertEquals(text, "T\n\nHello.\n\n## Part\n\n- a\n- b\n\n[image: A chart]");
});
