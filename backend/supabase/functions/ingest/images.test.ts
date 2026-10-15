// Unit tests for the picture lookup: `deno test ingest/`.

import { assertEquals } from "jsr:@std/assert@1";
import { extractImage, imageFor, resolveImages, youtubeThumbnail } from "./images.ts";
import type { NewsItem } from "./parse.ts";

Deno.test("youtubeThumbnail: watch, short, embed and youtu.be links", () => {
  const thumb = "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg";
  assertEquals(youtubeThumbnail("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1s"), thumb);
  assertEquals(youtubeThumbnail("https://youtu.be/dQw4w9WgXcQ?si=x"), thumb);
  assertEquals(youtubeThumbnail("https://youtube.com/shorts/dQw4w9WgXcQ"), thumb);
  assertEquals(youtubeThumbnail("https://m.youtube.com/embed/dQw4w9WgXcQ"), thumb);
  assertEquals(youtubeThumbnail("https://www.youtube.com/@channel"), null);
  assertEquals(youtubeThumbnail("https://example.com/watch?v=dQw4w9WgXcQ"), null);
  assertEquals(youtubeThumbnail("not a url"), null);
});

Deno.test("extractImage: og:image first, any attribute order, made absolute", () => {
  const html = `<html><head>
    <meta name="twitter:image" content="/t.jpg">
    <meta content="https://cdn.example.com/og.jpg?a=1&amp;b=2" property="og:image" />
    </head></html>`;
  assertEquals(extractImage(html, "https://example.com/post"), "https://cdn.example.com/og.jpg?a=1&b=2");
  assertEquals(extractImage(`<meta name="twitter:image" content="/t.jpg">`, "https://example.com/post"), "https://example.com/t.jpg");
  assertEquals(extractImage(`<meta property="og:image:secure_url" content="https://s/1.png"><meta property="og:image" content="http://p/1.png">`, "https://x"), "https://s/1.png");
  assertEquals(extractImage(`<meta property="og:image" content="">`, "https://x"), null);
  assertEquals(extractImage(`<meta property="og:image" content="javascript:alert(1)">`, "https://x"), null);
  assertEquals(extractImage("<p>no metas</p>", "https://x"), null);
});

const page = (html: string, type = "text/html", status = 200) =>
  new Response(html, { status, headers: { "content-type": type } });

Deno.test("imageFor: fetches the page, follows the final URL, skips non-HTML and errors", async () => {
  const calls: string[] = [];
  const fetcher = (url: string) => {
    calls.push(url);
    if (url === "https://a.test/post") return Promise.resolve(page(`<meta property="og:image" content="img/1.jpg">`));
    if (url === "https://b.test/pdf") return Promise.resolve(page("%PDF", "application/pdf"));
    if (url === "https://c.test/404") return Promise.resolve(page("<meta property='og:image' content='https://x/1.jpg'>", "text/html", 404));
    return Promise.reject(new Error("network"));
  };
  assertEquals(await imageFor("https://a.test/post", fetcher), "https://a.test/img/1.jpg");
  assertEquals(await imageFor("https://b.test/pdf", fetcher), null);
  assertEquals(await imageFor("https://c.test/404", fetcher), null);
  assertEquals(await imageFor("https://d.test/down", fetcher), null);
  assertEquals(await imageFor("https://youtu.be/dQw4w9WgXcQ", fetcher), "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg");
  assertEquals(calls.includes("https://youtu.be/dQw4w9WgXcQ"), false);
});

Deno.test("imageFor: gives up after the timeout", async () => {
  const fetcher = (_url: string, init: { signal: AbortSignal }) =>
    new Promise<Response>((_resolve, reject) => init.signal.addEventListener("abort", () => reject(new Error("aborted"))));
  assertEquals(await imageFor("https://slow.test/", fetcher, 20), null);
});

Deno.test("resolveImages: fills only the empty ones, once per URL", async () => {
  let fetched = 0;
  const fetcher = (url: string) => {
    fetched++;
    return Promise.resolve(page(`<meta property="og:image" content="${url}/og.jpg">`));
  };
  const items: NewsItem[] = [
    { h: "a", t: "", url: "https://a.test" },
    { h: "b", t: "", url: "https://a.test" },
    { h: "c", t: "", url: "https://c.test", image: "https://keep/me.jpg" },
    { h: "d", t: "", url: "https://d.test" },
  ];
  assertEquals(await resolveImages(items, fetcher), 3);
  assertEquals(fetched, 2);
  assertEquals(items.map((i) => i.image), ["https://a.test/og.jpg", "https://a.test/og.jpg", "https://keep/me.jpg", "https://d.test/og.jpg"]);
});
