// The ready-to-paste push for a new agent's key: one request to the ingest
// function with the smallest body that feed accepts (backend/supabase/
// functions/ingest/parse.ts and the ingest_* functions' comments). Pure, so
// tests/curl.test.mjs can check it.

import type { AgentKind, Feed } from "@/lib/types";

// Which feed an agent of this kind most likely pushes. Any agent may push
// to any feed; this only picks the example.
export function feedForKind(kind: AgentKind): Feed {
  switch (kind) {
    case "stocks":
      return "quotes";
    case "news":
      return "news";
    default:
      return "briefs";
  }
}

// For an agent whose kind says nothing about its feed, a line naming the
// others. Null for the kinds the example already matches.
export function feedNote(kind: AgentKind): string | null {
  if (kind !== "other") return null;
  const others = (Object.keys(BODIES) as Feed[]).filter((f) => f !== "briefs").join(", ");
  return `The example pushes a brief. The same key also pushes ${others}: change the last part of the URL and the body.`;
}

// The smallest body each feed accepts; the keys are the seven feeds.
const BODIES: Record<Feed, unknown> = {
  briefs: {
    briefs: [{ id: "morning", title: "Morning briefing", body: "Three things for today.\n\n- The first one.", kind: "daily" }],
  },
  quotes: {
    quotes: [
      {
        symbol: "AAPL",
        name: "Apple",
        price: 247.9,
        change: 2.78,
        change_pct: 1.13,
        data: {
          position: { shares: 40, avg_cost: 178.25, value: 9916, day_change: 111.2, total_change: 2786 },
          signals: [{ text: "Earnings Thursday after the close", tone: "watch" }],
          stats: { open: 245.6, high: 248.4, low: 244.9, prev_close: 245.12, volume: 52300000, avg_volume: 48100000, low_52w: 169.2, high_52w: 260.1 },
        },
      },
    ],
  },
  news: {
    slug: "2026-10-14",
    date: "Oct 14, 2026",
    hero: "first",
    sections: [
      {
        key: "i",
        name: "AI Tech",
        items: [{ id: "first", h: "A headline", t: "The one-line takeaway.", url: "https://example.com/story" }],
      },
    ],
  },
  projects: {
    projects: [
      {
        key: "mcfly",
        name: "McFly",
        kind: "code",
        status: "active",
        progress: 62,
        summary: "What it is, in a line.",
        next_step: "The next thing to do",
        updates: [{ kind: "ci", text: "CI green on main" }],
      },
    ],
  },
  metrics: {
    metrics: [{ key: "sales.today", label: "Sales today", value: 4280, unit: "USD", delta_pct: 12.5, group: "Store" }],
  },
  dashboards: {
    dashboards: [
      {
        key: "ops",
        title: "Ops",
        widgets: [
          { type: "status", label: "API", state: "ok" },
          { type: "metric", label: "Requests", value: 1240000, delta_pct: 4.2 },
        ],
      },
    ],
  },
  events: {
    events: [{ id: "ev-1", calendar: "Work", title: "Standup", starts_at: "2026-10-14T14:30:00Z", ends_at: "2026-10-14T14:45:00Z" }],
  },
};

export function exampleBody(feed: Feed): string {
  return JSON.stringify(BODIES[feed]);
}

// Single-quoted for a POSIX shell: the only character that needs care inside
// '…' is the quote itself.
export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

export function ingestUrl(baseUrl: string, feed: Feed): string {
  return `${baseUrl.replace(/\/+$/, "")}/functions/v1/ingest/${feed}`;
}

export function curlExample({ baseUrl, key, kind, feed: chosen }: { baseUrl: string; key: string; kind: AgentKind; feed?: Feed }): string {
  const feed = chosen ?? feedForKind(kind);
  return [
    `curl -X POST ${shellQuote(ingestUrl(baseUrl, feed))}`,
    `  -H ${shellQuote(`Authorization: Bearer ${key}`)}`,
    `  -H 'Content-Type: application/json'`,
    `  -d ${shellQuote(exampleBody(feed))}`,
  ].join(" \\\n");
}
