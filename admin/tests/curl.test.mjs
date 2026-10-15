// The curl example shown with a new key (lib/curl.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { curlExample, exampleBody, feedForKind, feedNote, ingestUrl, shellQuote } from "../lib/curl.ts";

const KEY = "mcf_" + "ab".repeat(20);

test("each kind gets the feed it most likely pushes", () => {
  assert.equal(feedForKind("grok"), "briefs");
  assert.equal(feedForKind("other"), "briefs");
  assert.equal(feedForKind("stocks"), "quotes");
  assert.equal(feedForKind("news"), "news");
});

test("the url is the ingest function with the feed in the path", () => {
  assert.equal(ingestUrl("https://abc.supabase.co", "briefs"), "https://abc.supabase.co/functions/v1/ingest/briefs");
  assert.equal(ingestUrl("https://abc.supabase.co/", "news"), "https://abc.supabase.co/functions/v1/ingest/news");
});

test("an agent of kind other is told about the other feeds", () => {
  const note = feedNote("other");
  for (const feed of ["quotes", "news", "projects", "metrics", "dashboards", "events"]) assert.ok(note.includes(feed), feed);
  for (const kind of ["grok", "stocks", "news"]) assert.equal(feedNote(kind), null);
});

test("the productivity feeds have bodies their ingest functions take", () => {
  const projects = JSON.parse(exampleBody("projects"));
  assert.match(projects.projects[0].key, /^[A-Za-z0-9][A-Za-z0-9._/-]{0,119}$/);
  assert.ok(["active", "blocked", "paused", "done"].includes(projects.projects[0].status));
  const metrics = JSON.parse(exampleBody("metrics"));
  assert.match(metrics.metrics[0].key, /^[a-z0-9][a-z0-9._-]{0,63}$/);
  assert.equal(typeof metrics.metrics[0].value, "number");
  const dashboards = JSON.parse(exampleBody("dashboards"));
  for (const w of dashboards.dashboards[0].widgets) assert.ok(["metric", "status", "progress", "list", "text", "chart"].includes(w.type));
  const events = JSON.parse(exampleBody("events"));
  assert.ok(!Number.isNaN(Date.parse(events.events[0].starts_at)));
  for (const feed of ["projects", "metrics", "dashboards", "events"]) {
    assert.equal(ingestUrl("https://abc.supabase.co", feed), `https://abc.supabase.co/functions/v1/ingest/${feed}`);
  }
});

test("the example body is JSON the ingest parser accepts", () => {
  const briefs = JSON.parse(exampleBody("briefs"));
  assert.ok(Array.isArray(briefs.briefs) && briefs.briefs[0].title);
  const quotes = JSON.parse(exampleBody("quotes"));
  assert.ok(Array.isArray(quotes.quotes) && typeof quotes.quotes[0].price === "number");
  assert.match(quotes.quotes[0].symbol, /^[A-Z0-9.^=:-]{1,16}$/);
  const news = JSON.parse(exampleBody("news"));
  assert.match(news.slug, /^[a-z0-9][a-z0-9-]{0,63}$/);
  assert.ok(news.sections.length > 0 && news.sections[0].items[0].url.startsWith("https://"));
});

test("the command carries the key as a bearer token and quotes for a shell", () => {
  const cmd = curlExample({ baseUrl: "https://abc.supabase.co", key: KEY, kind: "stocks" });
  const lines = cmd.split(" \\\n");
  assert.equal(lines[0], "curl -X POST 'https://abc.supabase.co/functions/v1/ingest/quotes'");
  assert.equal(lines[1], `  -H 'Authorization: Bearer ${KEY}'`);
  assert.equal(lines[2], "  -H 'Content-Type: application/json'");
  assert.ok(lines[3].startsWith("  -d '{\"quotes\":"));
  assert.equal(lines.length, 4);
});

test("shellQuote survives a single quote", () => {
  assert.equal(shellQuote("it's"), `'it'\\''s'`);
  assert.equal(shellQuote("plain"), "'plain'");
});
