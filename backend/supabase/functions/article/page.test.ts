// Unit tests for fetching a story's page: `deno test article/`.

import { assertEquals } from "jsr:@std/assert@1";
import { fetchPage, publicUrl } from "./page.ts";

Deno.test("publicUrl: public http(s) pages only", () => {
  for (const ok of ["https://www.nytimes.com/2026/10/20/x.html", "http://news.test/a", "https://8.8.8.8/x"]) {
    assertEquals(publicUrl(ok)?.toString(), new URL(ok).toString(), ok);
  }
  for (const bad of [
    "ftp://x.test/a", "file:///etc/passwd", "javascript:alert(1)", "https://user:pw@x.test/", "http://localhost:54321/",
    "http://intranet/", "http://printer.local/", "http://metadata.google.internal/", "http://127.0.0.1/", "http://10.0.0.8/",
    "http://172.20.1.1/", "http://192.168.1.1/", "http://169.254.169.254/latest/meta-data", "http://100.64.0.1/", "http://[::1]/",
    "http://0x7f.0.0.1/", "not a url",
  ]) {
    assertEquals(publicUrl(bad), null, bad);
  }
});

const res = (body: string, status = 200, headers: Record<string, string> = { "content-type": "text/html; charset=utf-8" }) =>
  new Response(status >= 300 && status < 400 ? null : body, { status, headers });

Deno.test("fetchPage: follows redirects, checking every hop", async () => {
  const seen: string[] = [];
  const fetcher = (url: string, init: RequestInit) => {
    seen.push(url);
    assertEquals(init.redirect, "manual");
    if (url === "https://short.test/s") return Promise.resolve(res("", 301, { location: "https://paper.test/story" }));
    if (url === "https://paper.test/story") return Promise.resolve(res("<p>hi</p>"));
    if (url === "https://evil.test/r") return Promise.resolve(res("", 302, { location: "http://169.254.169.254/" }));
    return Promise.resolve(res("", 404));
  };
  assertEquals(await fetchPage("https://short.test/s", fetcher), { html: "<p>hi</p>", url: "https://paper.test/story" });
  assertEquals(await fetchPage("https://evil.test/r", fetcher), { error: "not a public web address" });
  assertEquals(seen, ["https://short.test/s", "https://paper.test/story", "https://evil.test/r"]);
});

Deno.test("fetchPage: errors, non-HTML, redirect loops and timeouts are answers, not throws", async () => {
  assertEquals(await fetchPage("https://x.test/404", () => Promise.resolve(res("", 404))), { error: "the page answered 404" });
  assertEquals(await fetchPage("https://x.test/a.pdf", () => Promise.resolve(res("%PDF", 200, { "content-type": "application/pdf" }))), {
    error: "not a web page",
  });
  assertEquals(await fetchPage("https://x.test/loop", () => Promise.resolve(res("", 302, { location: "/loop" }))), { error: "too many redirects" });
  assertEquals(await fetchPage("https://x.test/down", () => Promise.reject(new TypeError("dns"))), { error: "couldn't reach the page" });
  const hang = (_: string, init: RequestInit) =>
    new Promise<Response>((_, reject) => init.signal!.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))));
  assertEquals(await fetchPage("https://x.test/slow", hang, 20), { error: "the page took too long" });
});
