// Unit tests for the ingest parser: `deno test ingest/`.

import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import {
  agentKey,
  type Dashboard,
  feedFromBody,
  feedFromPath,
  KEY_SHAPE,
  parse,
  parseBriefs,
  parseDashboards,
  parseEvents,
  parseMetrics,
  parseNews,
  parseProjects,
  parseQuotes,
} from "./parse.ts";

const fail = (r: unknown) => (r as { error?: string }).error;

Deno.test("feedFromPath: the segment after ingest, on Supabase and locally", () => {
  assertEquals(feedFromPath("/ingest/briefs"), "briefs");
  assertEquals(feedFromPath("/functions/v1/ingest/news/"), "news");
  assertEquals(feedFromPath("/ingest"), "");
  assertEquals(feedFromPath("/functions/v1/ingest"), "");
  assertEquals(feedFromPath("/ingest/photos"), null);
  assertEquals(feedFromPath("/ingest/news/extra"), null);
  for (const feed of ["projects", "metrics", "dashboards", "events"]) assertEquals(feedFromPath(`/functions/v1/ingest/${feed}`), feed);
});

Deno.test("feedFromBody: type, feed, or the shape itself", () => {
  assertEquals(feedFromBody({ type: "quotes" }), "quotes");
  assertEquals(feedFromBody({ feed: "news", sections: [] }), "news");
  assertEquals(feedFromBody({ briefs: [] }), "briefs");
  assertEquals(feedFromBody({ brief: { title: "x" } }), "briefs");
  assertEquals(feedFromBody({ quote: { symbol: "A" } }), "quotes");
  assertEquals(feedFromBody({ sections: [] }), "news");
  assertEquals(feedFromBody({ title: "x" }), null);
  assertEquals(feedFromBody([]), null);
  assertEquals(feedFromBody({ projects: [] }), "projects");
  assertEquals(feedFromBody({ project: { key: "k" } }), "projects");
  assertEquals(feedFromBody({ metrics: [], as_of: "x" }), "metrics");
  assertEquals(feedFromBody({ metric: { key: "k", value: 1 } }), "metrics");
  assertEquals(feedFromBody({ dashboards: [] }), "dashboards");
  assertEquals(feedFromBody({ dashboard: { key: "k" } }), "dashboards");
  assertEquals(feedFromBody({ events: [], calendar: "Work", replace: true }), "events");
  assertEquals(feedFromBody({ event: { title: "t" } }), "events");
  assertEquals(feedFromBody({ type: "dashboards", events: [] }), "dashboards");
});

Deno.test("agentKey: bearer or the header, and the key shape", () => {
  assertEquals(agentKey(new Headers({ Authorization: "Bearer mcf_abc" })), "mcf_abc");
  assertEquals(agentKey(new Headers({ "x-agent-key": " mcf_abc " })), "mcf_abc");
  assertEquals(agentKey(new Headers({ Authorization: "Basic xyz" })), null);
  assertEquals(agentKey(new Headers()), null);
  assertMatch("mcf_" + "0".repeat(40), KEY_SHAPE);
  assertEquals(KEY_SHAPE.test("mcf_short"), false);
  assertEquals(KEY_SHAPE.test("sb_secret_" + "0".repeat(40)), false);
});

Deno.test("parseBriefs: the list, one brief, and the bare object", () => {
  const list = parseBriefs({ briefs: [{ id: "a", title: " Hi ", body: "b", kind: "daily", published_at: "2026-10-14T13:00:00Z" }] });
  assertEquals(list, { briefs: [{ id: "a", title: "Hi", body: "b", kind: "daily", published_at: "2026-10-14T13:00:00.000Z" }] });
  assertEquals(parseBriefs({ brief: { title: "x" } }), { briefs: [{ title: "x", body: "", kind: "update" }] });
  assertEquals(parseBriefs({ title: "x", text: "alias" }), { briefs: [{ title: "x", body: "alias", kind: "update" }] });
  assertEquals(parseBriefs([{ title: "x", at: "2026-01-01T00:00:00Z", external_id: "e" }]),
    { briefs: [{ id: "e", title: "x", body: "", kind: "update", published_at: "2026-01-01T00:00:00.000Z" }] });
});

Deno.test("parseBriefs: what it refuses", () => {
  assertEquals(fail(parseBriefs({})), "send { briefs: [{ title, body }] } or one { title, body }");
  assertEquals(fail(parseBriefs({ briefs: [] })), "no briefs in the request");
  assertEquals(fail(parseBriefs({ briefs: ["x"] })), "brief 1 must be an object");
  assertEquals(fail(parseBriefs({ briefs: [{ body: "no title" }] })), "brief 1 needs a title");
  assertEquals(fail(parseBriefs({ briefs: [{ title: "x", kind: "weekly" }] })), "brief 1: kind must be hourly, daily, alert or update");
  assertEquals(fail(parseBriefs({ briefs: [{ title: "x", published_at: "soon" }] })), "brief 1: published_at must be an ISO-8601 timestamp");
  assertEquals(fail(parseBriefs({ briefs: Array.from({ length: 201 }, () => ({ title: "x" })) })), "at most 200 briefs per push");
  const long = parseBriefs({ briefs: [{ title: "t".repeat(300), body: "b".repeat(30000) }] });
  assertEquals(!fail(long) && (long as { briefs: { title: string; body: string }[] }).briefs[0].title.length, 200);
  assertEquals(!fail(long) && (long as { briefs: { title: string; body: string }[] }).briefs[0].body.length, 20000);
});

Deno.test("parseQuotes: numbers from strings, aliases, upper-cased symbols", () => {
  const r = parseQuotes({
    as_of: "2026-10-14T20:00:00Z",
    quotes: [
      { symbol: "aapl", name: "Apple", price: "245.12", change: "+1.42", change_pct: "0.58%", currency: "usd", note: "n" },
      { ticker: "BRK.B", last: 495, changePercent: -0.2, data: { volume: 1 } },
    ],
  });
  assertEquals(r, {
    as_of: "2026-10-14T20:00:00.000Z",
    quotes: [
      { symbol: "AAPL", price: 245.12, name: "Apple", change: 1.42, change_pct: 0.58, currency: "USD", note: "n" },
      { symbol: "BRK.B", price: 495, change_pct: -0.2, data: { volume: 1 } },
    ],
  });
  assertEquals(parseQuotes({ symbol: "spy", price: 1 }), { quotes: [{ symbol: "SPY", price: 1 }] });
  assertEquals(parseQuotes([{ quote: 1, symbol: "X", price: 2, at: "2026-01-01T00:00:00Z" }]),
    { quotes: [{ symbol: "X", price: 2, as_of: "2026-01-01T00:00:00.000Z" }] });
});

Deno.test("parseQuotes: what it refuses", () => {
  assertEquals(fail(parseQuotes({})), "send { quotes: [{ symbol, price }] } or one { symbol, price }");
  assertEquals(fail(parseQuotes({ quotes: [] })), "no quotes in the request");
  assertEquals(fail(parseQuotes({ quotes: [{ symbol: "no price" }] })), "quote 1: symbol must be 1 to 16 letters, digits or . ^ = : -");
  assertEquals(fail(parseQuotes({ quotes: [{ symbol: "MSFT" }] })), "MSFT has no price");
  assertEquals(fail(parseQuotes({ quotes: [{ symbol: "MSFT", price: "lots" }] })), "MSFT: price must be a number");
  assertEquals(fail(parseQuotes({ quotes: [{ symbol: "MSFT", price: 1, change: "up" }] })), "MSFT: change must be a number");
  assertEquals(fail(parseQuotes({ quotes: [{ symbol: "MSFT", price: 1, currency: "dollars" }] })), "MSFT: currency must be a 3-letter code");
  assertEquals(fail(parseQuotes({ as_of: "noon", quotes: [{ symbol: "MSFT", price: 1 }] })), "as_of must be an ISO-8601 timestamp");
  assertEquals(fail(parseQuotes({ quotes: Array.from({ length: 501 }, () => ({ symbol: "A", price: 1 })) })), "at most 500 quotes per push");
});

const PULSE = {
  date: "Oct 14, 2026",
  slug: "2026-10-14",
  hero: "gemini",
  sections: [
    { key: "i", name: "AI Tech", items: [{ id: "gemini", h: "Google launches Gemini 4 Argon", t: "Why.", url: "https://blog.google/x" }] },
    { key: "s", items: [{ headline: "No id", takeaway: " t ", link: "https://x.com/1", image_url: "https://img/1.jpg" }] },
  ],
};

Deno.test("parseNews: the Daily Pulse items JSON, with aliases", () => {
  const r = parseNews(PULSE);
  assertEquals(r, {
    report: {
      slug: "2026-10-14",
      date: "Oct 14, 2026",
      hero: "gemini",
      sections: [
        { key: "i", name: "AI Tech", items: [{ id: "gemini", h: "Google launches Gemini 4 Argon", t: "Why.", url: "https://blog.google/x" }] },
        { key: "s", name: "s", items: [{ h: "No id", t: "t", url: "https://x.com/1", image: "https://img/1.jpg" }] },
      ],
    },
    resolveImages: true,
  });
  const wrapped = parseNews({ report: PULSE, resolve_images: false });
  assertEquals(!fail(wrapped) && (wrapped as { resolveImages: boolean }).resolveImages, false);
  const dated = parseNews({ ...PULSE, report_date: "2026-10-15", published_at: "2026-10-14T13:06:00Z" });
  assertEquals(!fail(dated) && (dated as { report: { report_date?: string; published_at?: string } }).report.report_date, "2026-10-15");
});

Deno.test("parseNews: what it refuses", () => {
  assertEquals(fail(parseNews("x")), "send the Daily Pulse items JSON: { date, slug, hero, sections }");
  assertEquals(fail(parseNews({ ...PULSE, slug: "Oct 14" })), "slug must be like 2026-10-14 (lower-case letters, digits and dashes)");
  assertEquals(fail(parseNews({ ...PULSE, sections: [] })), "sections must be a non-empty list");
  assertEquals(fail(parseNews({ ...PULSE, sections: [{ name: "x", items: [] }] })), "section 1 needs a short key (like s, a or i)");
  assertEquals(fail(parseNews({ ...PULSE, sections: [{ key: "a", name: "Ads" }] })), "section Ads needs items");
  assertEquals(fail(parseNews({ ...PULSE, sections: [{ key: "a", name: "Ads", items: [{ url: "https://a" }] }] })), "Ads item 1 needs a headline (h)");
  assertEquals(fail(parseNews({ ...PULSE, sections: [{ key: "a", name: "Ads", items: [{ h: "H", url: "ftp://a" }] }] })), 'Ads: "H" needs an http(s) source url');
  assertEquals(fail(parseNews({ ...PULSE, sections: [{ key: "a", name: "Ads", items: [{ h: "H", url: "https://a", id: "a b" }] }] })), 'Ads: "H" has an unusable id');
  assertEquals(fail(parseNews({ ...PULSE, sections: [{ key: "a", name: "Ads", items: [] }] })), "the report has no items");
  assertEquals(fail(parseNews({ ...PULSE, report_date: "14/10/2026" })), "report_date must be YYYY-MM-DD");
});

// ───────────── projects ─────────────

Deno.test("parseProjects: the list, one project, defaults and normalisations", () => {
  const r = parseProjects({
    projects: [{
      key: "mcfly", name: " McFly ", kind: "code", status: "blocked", progress: "62.4", sort_order: "1",
      summary: "The agent display.", next_step: "Ship it", link: "https://github.com/x/mcfly", color: "#5b7cf5",
      data: { stars: 3 },
      updates: [
        { kind: "ci", text: "CI green", at: "2026-10-14T19:40:00Z" },
        { text: " #12 opened ", url: "https://github.com/x/mcfly/pull/12" },
      ],
    }],
  });
  assertEquals(r, {
    projects: [{
      key: "mcfly", name: "McFly", kind: "code", status: "blocked", progress: 62, summary: "The agent display.",
      next_step: "Ship it", link: "https://github.com/x/mcfly", color: "#5B7CF5", sort_order: 1, data: { stars: 3 },
      updates: [
        { kind: "ci", text: "CI green", at: "2026-10-14T19:40:00.000Z" },
        { kind: "note", text: "#12 opened", url: "https://github.com/x/mcfly/pull/12" },
      ],
    }],
  });
  // Name defaults to the key; kind and status to other/active; nothing else is sent.
  assertEquals(parseProjects({ key: "a/b.c" }), { projects: [{ key: "a/b.c", name: "a/b.c", kind: "other", status: "active" }] });
  assertEquals(parseProjects({ project: { id: "p1", progress: 0, updates: [] } }),
    { projects: [{ key: "p1", name: "p1", kind: "other", status: "active", progress: 0 }] });
  assertEquals(parseProjects([{ key: "x", summary: "", next_step: " " }]), { projects: [{ key: "x", name: "x", kind: "other", status: "active" }] });
});

Deno.test("parseProjects: what it refuses", () => {
  const one = (p: Record<string, unknown>) => fail(parseProjects({ projects: [{ key: "k", ...p }] }));
  assertEquals(fail(parseProjects({})), "send { projects: [{ key, name }] } or one { key, name }");
  assertEquals(fail(parseProjects("x")), "send { projects: [{ key, name }] } or one { key, name }");
  assertEquals(fail(parseProjects({ projects: [] })), "no projects in the request");
  assertEquals(fail(parseProjects({ projects: ["x"] })), "project 1 must be an object");
  assertEquals(fail(parseProjects({ projects: [{ name: "no key" }] })), "project 1: key must be 1 to 120 letters, digits or . _ / -");
  assertEquals(fail(parseProjects({ projects: [{ key: "bad key!" }] })), "project 1: key must be 1 to 120 letters, digits or . _ / -");
  assertEquals(fail(parseProjects({ projects: [{ key: "-x" }] })), "project 1: key must be 1 to 120 letters, digits or . _ / -");
  assertEquals(one({ kind: "repo" }), "project k: kind must be code, task, launch or other");
  assertEquals(one({ status: "flying" }), "project k: status must be active, blocked, paused or done");
  assertEquals(one({ progress: 120 }), "project k: progress must be a number from 0 to 100");
  assertEquals(one({ progress: -1 }), "project k: progress must be a number from 0 to 100");
  assertEquals(one({ progress: "half" }), "project k: progress must be a number from 0 to 100");
  assertEquals(one({ link: "ftp://x" }), "project k: link must be an http(s) URL");
  assertEquals(one({ color: "blue" }), "project k: color must be #rrggbb");
  assertEquals(one({ sort_order: 1.5 }), "project k: sort_order must be a whole number");
  assertEquals(one({ updates: {} }), "project k: updates must be a list");
  assertEquals(one({ updates: Array.from({ length: 21 }, () => ({ text: "x" })) }), "project k: at most 20 updates");
  assertEquals(one({ updates: ["x"] }), "project k update 1 must be an object");
  assertEquals(one({ updates: [{ kind: "ci" }] }), "project k update 1 needs text");
  assertEquals(one({ updates: [{ text: "x", kind: "merge" }] }), "project k update 1: kind must be note, commit, pr, ci, deploy, alert or done");
  assertEquals(one({ updates: [{ text: "x", url: "x" }] }), "project k update 1: url must be an http(s) URL");
  assertEquals(one({ updates: [{ text: "x", at: "yesterday" }] }), "project k update 1: at must be an ISO-8601 timestamp");
  assertEquals(fail(parseProjects({ projects: Array.from({ length: 101 }, () => ({ key: "k" })) })), "at most 100 projects per push");
  const long = parseProjects({ projects: [{ key: "k", name: "n".repeat(200), summary: "s".repeat(3000), next_step: "x".repeat(600) }] });
  const p = (long as { projects: { name: string; summary: string; next_step: string }[] }).projects[0];
  assertEquals([p.name.length, p.summary.length, p.next_step.length], [120, 2000, 500]);
});

// ───────────── metrics ─────────────

Deno.test("parseMetrics: keys lower-cased, numbers from strings, as_of for the push", () => {
  const r = parseMetrics({
    as_of: "2026-10-14T20:00:00Z",
    metrics: [
      { key: "Sales.Today", label: "Sales today", value: "$4,280", unit: "USD", delta_pct: "12.5%", group: "Store", data: { src: "shopify" } },
      { key: "api.p95", value: 212, delta: "-18", note: "After the cache change.", as_of: "2026-10-14T19:00:00Z" },
    ],
  });
  assertEquals(r, {
    as_of: "2026-10-14T20:00:00.000Z",
    metrics: [
      { key: "sales.today", value: 4280, label: "Sales today", unit: "USD", delta_pct: 12.5, group: "Store", data: { src: "shopify" } },
      { key: "api.p95", value: 212, delta: -18, note: "After the cache change.", as_of: "2026-10-14T19:00:00.000Z" },
    ],
  });
  assertEquals(parseMetrics({ key: "steps", value: 6420 }), { metrics: [{ key: "steps", value: 6420 }] });
  assertEquals(parseMetrics({ metric: { id: "x", name: "X", value: "1", group_name: "G" } }), { metrics: [{ key: "x", value: 1, label: "X", group: "G" }] });
  assertEquals(parseMetrics([{ key: "a", value: 0 }]), { metrics: [{ key: "a", value: 0 }] });
});

Deno.test("parseMetrics: what it refuses", () => {
  assertEquals(fail(parseMetrics({})), "send { metrics: [{ key, value }] } or one { key, value }");
  assertEquals(fail(parseMetrics({ metrics: [] })), "no metrics in the request");
  assertEquals(fail(parseMetrics({ metrics: [1] })), "metric 1 must be an object");
  assertEquals(fail(parseMetrics({ metrics: [{ value: 1 }] })), "metric 1: key must be 1 to 64 lower-case letters, digits or . _ -");
  assertEquals(fail(parseMetrics({ metrics: [{ key: "no value", value: 1 }] })), "metric 1: key must be 1 to 64 lower-case letters, digits or . _ -");
  assertEquals(fail(parseMetrics({ metrics: [{ key: "x" }] })), "x has no value");
  assertEquals(fail(parseMetrics({ metrics: [{ key: "x", value: "lots" }] })), "x: value must be a number");
  assertEquals(fail(parseMetrics({ metrics: [{ key: "x", value: 1, delta: "up" }] })), "x: delta must be a number");
  assertEquals(fail(parseMetrics({ metrics: [{ key: "x", value: 1, delta_pct: "up" }] })), "x: delta_pct must be a number");
  assertEquals(fail(parseMetrics({ metrics: [{ key: "x", value: 1, as_of: "noon" }] })), "x: as_of must be an ISO-8601 timestamp");
  assertEquals(fail(parseMetrics({ as_of: "noon", metrics: [{ key: "x", value: 1 }] })), "as_of must be an ISO-8601 timestamp");
  assertEquals(fail(parseMetrics({ metrics: Array.from({ length: 501 }, () => ({ key: "x", value: 1 })) })), "at most 500 metrics per push");
  const long = parseMetrics({ metrics: [{ key: "x", value: 1, label: "l".repeat(100), unit: "u".repeat(20), note: "n".repeat(3000), group: "g".repeat(100) }] });
  const m = (long as { metrics: { label: string; unit: string; note: string; group: string }[] }).metrics[0];
  assertEquals([m.label.length, m.unit.length, m.note.length, m.group.length], [80, 16, 2000, 80]);
});

// ───────────── dashboards ─────────────

const WIDGETS = [
  { type: "status", label: "API", state: "OK", detail: "All checks passing", extra: "dropped" },
  { type: "metric", label: "Requests", value: "1,240,000", unit: "", delta_pct: 4.2 },
  { type: "progress", label: "Storage", value: 68, unit: "%" },
  { type: "chart", label: "Requests per hour", points: [40, 42, 38], unit: "k" },
  { type: "list", title: "On call", items: [" Ricky ", "", "Pager quiet"] },
  { type: "text", title: "Note", body: " Deploy tonight. " },
];

Deno.test("parseDashboards: every widget type, with only its own fields", () => {
  const r = parseDashboards({ dashboards: [{ key: "OPS", title: "Ops", subtitle: "Production", sort_order: "0", widgets: WIDGETS }] });
  assertEquals(r, {
    dashboards: [{
      key: "ops", title: "Ops", subtitle: "Production", sort_order: 0,
      widgets: [
        { type: "status", label: "API", state: "ok", detail: "All checks passing" },
        { type: "metric", label: "Requests", value: 1240000, delta_pct: 4.2 },
        { type: "progress", label: "Storage", value: 68, max: 100, unit: "%" },
        { type: "chart", label: "Requests per hour", points: [40, 42, 38], unit: "k" },
        { type: "list", title: "On call", items: ["Ricky", "Pager quiet"] },
        { type: "text", title: "Note", body: "Deploy tonight." },
      ],
    }],
  });
  // The title defaults to the key; one dashboard, bare or wrapped.
  assertEquals(parseDashboards({ key: "launch", widgets: [{ type: "metric", label: "Waitlist", value: 812, delta: 46 }] }),
    { dashboards: [{ key: "launch", title: "launch", widgets: [{ type: "metric", label: "Waitlist", value: 812, delta: 46 }] }] });
  assertEquals(parseDashboards({ dashboard: { key: "l", widgets: [{ type: "text", text: "b" }] } }),
    { dashboards: [{ key: "l", title: "l", widgets: [{ type: "text", body: "b" }] }] });
  assertEquals((parseDashboards([{ key: "l", widgets: [{ type: "progress", title: "Checklist", value: 14, max: 20 }] }]) as { dashboards: Dashboard[] })
    .dashboards[0].widgets, [{ type: "progress", label: "Checklist", value: 14, max: 20 }]);
});

Deno.test("parseDashboards: what it refuses", () => {
  const widget = (w: unknown) => fail(parseDashboards({ dashboards: [{ key: "ops", widgets: [w] }] }));
  assertEquals(fail(parseDashboards({})), "send { dashboards: [{ key, title, widgets }] } or one { key, title, widgets }");
  assertEquals(fail(parseDashboards({ dashboards: [] })), "no dashboards in the request");
  assertEquals(fail(parseDashboards({ dashboards: ["x"] })), "dashboard 1 must be an object");
  assertEquals(fail(parseDashboards({ dashboards: [{ widgets: [] }] })), "dashboard 1: key must be 1 to 64 lower-case letters, digits or . _ -");
  assertEquals(fail(parseDashboards({ dashboards: [{ key: "a b", widgets: [] }] })), "dashboard 1: key must be 1 to 64 lower-case letters, digits or . _ -");
  assertEquals(fail(parseDashboards({ dashboards: [{ key: "ops", sort_order: "x", widgets: [] }] })), "dashboard ops: sort_order must be a whole number");
  assertEquals(fail(parseDashboards({ dashboards: [{ key: "ops" }] })), "dashboard ops: widgets must be a list of 1 to 40 widgets");
  assertEquals(fail(parseDashboards({ dashboards: [{ key: "ops", widgets: [] }] })), "dashboard ops: widgets must be a list of 1 to 40 widgets");
  assertEquals(fail(parseDashboards({ dashboards: [{ key: "ops", widgets: Array.from({ length: 41 }, () => ({ type: "text", body: "b" })) }] })),
    "dashboard ops: widgets must be a list of 1 to 40 widgets");
  assertEquals(widget("x"), "dashboard ops widget 1 must be an object");
  assertEquals(widget({ type: "video" }), "dashboard ops widget 1: type must be metric, status, progress, list, text or chart");
  assertEquals(widget({ type: "metric", value: 1 }), "dashboard ops widget 1 needs a label");
  assertEquals(widget({ type: "metric", label: "x" }), "dashboard ops widget 1: value must be a number");
  assertEquals(widget({ type: "metric", label: "x", value: "many" }), "dashboard ops widget 1: value must be a number");
  assertEquals(widget({ type: "metric", label: "x", value: 1, delta: "up" }), "dashboard ops widget 1: delta must be a number");
  assertEquals(widget({ type: "metric", label: "x", value: 1, delta_pct: "up" }), "dashboard ops widget 1: delta_pct must be a number");
  assertEquals(widget({ type: "status", state: "ok" }), "dashboard ops widget 1 needs a label");
  assertEquals(widget({ type: "status", label: "x", state: "fine" }), "dashboard ops widget 1: state must be ok, warn, down or unknown");
  assertEquals(widget({ type: "progress", value: 1 }), "dashboard ops widget 1 needs a label");
  assertEquals(widget({ type: "progress", label: "x" }), "dashboard ops widget 1: value must be a number");
  assertEquals(widget({ type: "progress", label: "x", value: 1, max: 0 }), "dashboard ops widget 1: max must be a number above 0");
  assertEquals(widget({ type: "progress", label: "x", value: 1, max: "all" }), "dashboard ops widget 1: max must be a number above 0");
  assertEquals(widget({ type: "list" }), "dashboard ops widget 1: items must be a list of up to 20 strings");
  assertEquals(widget({ type: "list", items: [1] }), "dashboard ops widget 1: items must be a list of up to 20 strings");
  assertEquals(widget({ type: "list", items: Array.from({ length: 21 }, () => "x") }), "dashboard ops widget 1: items must be a list of up to 20 strings");
  assertEquals(widget({ type: "text", title: "t" }), "dashboard ops widget 1 needs a body");
  assertEquals(widget({ type: "chart", points: [1] }), "dashboard ops widget 1 needs a label");
  assertEquals(widget({ type: "chart", label: "x", points: [] }), "dashboard ops widget 1: points must be a list of 1 to 120 numbers");
  assertEquals(widget({ type: "chart", label: "x", points: ["1"] }), "dashboard ops widget 1: points must be a list of 1 to 120 numbers");
  assertEquals(widget({ type: "chart", label: "x", points: Array.from({ length: 121 }, () => 1) }), "dashboard ops widget 1: points must be a list of 1 to 120 numbers");
  assertEquals(fail(parseDashboards({ dashboards: Array.from({ length: 21 }, () => ({ key: "k", widgets: [{ type: "text", body: "b" }] })) })),
    "at most 20 dashboards per push");
  const long = parseDashboards({ dashboards: [{ key: "k", title: "t".repeat(100), subtitle: "s".repeat(300),
    widgets: [{ type: "text", title: "x".repeat(300), body: "b".repeat(3000) }, { type: "list", items: ["i".repeat(300)] }] }] });
  const d = (long as { dashboards: Dashboard[] }).dashboards[0];
  assertEquals([d.title.length, d.subtitle?.length], [80, 200]);
  const text = d.widgets[0] as { title: string; body: string };
  assertEquals([text.title.length, text.body.length], [200, 2000]);
  assertEquals((d.widgets[1] as { items: string[] }).items[0].length, 200);
});

// ───────────── events ─────────────

Deno.test("parseEvents: calendars from the item, the push or the default; replace", () => {
  const r = parseEvents({
    calendar: " Work ",
    replace: true,
    events: [
      { id: "ev-1", title: "Standup", starts_at: "2026-10-14T14:30:00Z", ends_at: "2026-10-14T14:45:00Z", color: "#5b7cf5", location: "Zoom", url: "https://zoom.us/j/1", data: { rsvp: "yes" } },
      { title: " Dinner ", calendar: "Home", start: "2026-10-15T00:00:00Z", all_day: false, description: "With Lina" },
      { uid: "ev-6", summary: "Launch day", starts_at: "2026-10-20T05:00:00Z", all_day: true },
    ],
  });
  assertEquals(r, {
    calendar: "Work",
    replace: true,
    events: [
      { id: "ev-1", calendar: "Work", title: "Standup", starts_at: "2026-10-14T14:30:00.000Z", ends_at: "2026-10-14T14:45:00.000Z", location: "Zoom", color: "#5B7CF5", url: "https://zoom.us/j/1", data: { rsvp: "yes" } },
      { calendar: "Home", title: "Dinner", starts_at: "2026-10-15T00:00:00.000Z", description: "With Lina" },
      { id: "ev-6", calendar: "Work", title: "Launch day", starts_at: "2026-10-20T05:00:00.000Z", all_day: true },
    ],
  });
  assertEquals(parseEvents({ title: "Gym", starts_at: "2026-10-16T12:00:00Z" }),
    { events: [{ calendar: "Calendar", title: "Gym", starts_at: "2026-10-16T12:00:00.000Z" }], replace: false });
  assertEquals(parseEvents({ event: { title: "Gym", starts_at: "2026-10-16T12:00:00Z" } }),
    { events: [{ calendar: "Calendar", title: "Gym", starts_at: "2026-10-16T12:00:00.000Z" }], replace: false });
  assertEquals(parseEvents([{ title: "Gym", starts_at: "2026-10-16T12:00:00Z" }]),
    { events: [{ calendar: "Calendar", title: "Gym", starts_at: "2026-10-16T12:00:00.000Z" }], replace: false });
  // A calendar without replace only names the events' calendar.
  assertEquals(parseEvents({ calendar: "Home", events: [{ title: "Gym", starts_at: "2026-10-16T12:00:00Z" }] }),
    { calendar: "Home", events: [{ calendar: "Home", title: "Gym", starts_at: "2026-10-16T12:00:00.000Z" }], replace: false });
});

Deno.test("parseEvents: what it refuses", () => {
  const one = (e: Record<string, unknown>) => fail(parseEvents({ events: [{ title: "x", starts_at: "2026-01-02T00:00:00Z", ...e }] }));
  assertEquals(fail(parseEvents({})), "send { events: [{ title, starts_at }] } or one { title, starts_at }");
  assertEquals(fail(parseEvents({ title: "no start" })), "send { events: [{ title, starts_at }] } or one { title, starts_at }");
  assertEquals(fail(parseEvents({ events: [] })), "no events in the request");
  assertEquals(fail(parseEvents({ events: ["x"] })), "event 1 must be an object");
  assertEquals(fail(parseEvents({ events: [{ starts_at: "2026-01-02T00:00:00Z" }] })), "event 1 needs a title");
  assertEquals(fail(parseEvents({ events: [{ title: "x" }] })), "event x needs starts_at");
  assertEquals(one({ starts_at: "tomorrow" }), "event x: starts_at must be an ISO-8601 timestamp");
  assertEquals(one({ ends_at: "later" }), "event x: ends_at must be an ISO-8601 timestamp");
  assertEquals(one({ ends_at: "2026-01-01T00:00:00Z" }), "event x: ends_at must not be before starts_at");
  assertEquals(one({ all_day: "yes" }), "event x: all_day must be true or false");
  assertEquals(one({ color: "red" }), "event x: color must be #rrggbb");
  assertEquals(one({ url: "zoom" }), "event x: url must be an http(s) URL");
  assertEquals(fail(parseEvents({ replace: "yes", events: [{ title: "x", starts_at: "2026-01-02T00:00:00Z" }] })), "replace must be true or false");
  assertEquals(fail(parseEvents({ replace: true, events: [{ title: "x", starts_at: "2026-01-02T00:00:00Z" }] })),
    "replace needs a calendar name: the push is that calendar, whole");
  assertEquals(fail(parseEvents({ events: Array.from({ length: 1001 }, () => ({ title: "x", starts_at: "2026-01-02T00:00:00Z" })) })),
    "at most 1000 events per push");
  const long = parseEvents({ calendar: "c".repeat(100), events: [{ id: "i".repeat(300), title: "t".repeat(400), starts_at: "2026-01-02T00:00:00Z",
    description: "d".repeat(5000), location: "l".repeat(400) }] });
  const e = (long as { calendar: string; events: { id: string; calendar: string; title: string; description: string; location: string }[] });
  assertEquals([e.calendar.length, e.events[0].id.length, e.events[0].calendar.length, e.events[0].title.length, e.events[0].description.length, e.events[0].location.length],
    [80, 200, 80, 300, 4000, 300]);
});

Deno.test("parse: routes by feed", () => {
  assertEquals((parse("briefs", { title: "x" }) as { feed: string }).feed, "briefs");
  assertEquals((parse("quotes", { symbol: "x", price: 1 }) as { feed: string }).feed, "quotes");
  assertEquals((parse("news", PULSE) as { feed: string }).feed, "news");
  assertEquals((parse("projects", { key: "x" }) as { feed: string }).feed, "projects");
  assertEquals((parse("metrics", { key: "x", value: 1 }) as { feed: string }).feed, "metrics");
  assertEquals((parse("dashboards", { key: "x", widgets: [{ type: "text", body: "b" }] }) as { feed: string }).feed, "dashboards");
  assertEquals(parse("events", { title: "x", starts_at: "2026-01-02T00:00:00Z" }),
    { feed: "events", events: [{ calendar: "Calendar", title: "x", starts_at: "2026-01-02T00:00:00.000Z" }], replace: false });
  assertEquals(fail(parse("news", {})), "slug must be like 2026-10-14 (lower-case letters, digits and dashes)");
  assertEquals(fail(parse("metrics", {})), "send { metrics: [{ key, value }] } or one { key, value }");
});
