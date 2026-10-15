import "server-only";
import { zonedMidnightUtc } from "@/lib/events";
import type {
  Admin,
  AgentKind,
  AuditEntry,
  BriefKind,
  Device,
  IngestEntry,
  NewsItem,
  NewsReport,
  ProjectKind,
  ProjectStatus,
  ProjectUpdate,
  Settings,
} from "@/lib/types";

// Fixture data for demo mode (NEXT_PUBLIC_ADMIN_DEMO=1), shaped like
// backend/supabase/seed.sql: the same six agents, briefs, symbols, Pulse
// report, projects, metrics, dashboards and events, plus a little history so
// the tables have something to show. Deterministic (seeded) and relative to
// when the server started, so screenshots always look fresh. Nothing here is
// a real account or key.

export type DemoAgent = {
  scopes?: import("@/lib/types").AgentScope[];
  id: string;
  name: string;
  slug: string;
  kind: AgentKind;
  color: string;
  created_at: string;
  last_seen_at: string | null;
  revoked_at: string | null;
  key_prefix: string | null;
  key_created_at: string | null;
};

export type DemoBrief = {
  id: string;
  agent_id: string;
  external_id: string | null;
  title: string;
  body: string;
  kind: BriefKind;
  published_at: string;
  expires_at: string | null;
  created_at: string;
};

export type DemoQuote = {
  id: number;
  agent_id: string;
  symbol: string;
  name: string | null;
  price: number;
  change: number | null;
  change_pct: number | null;
  currency: string;
  note: string | null;
  as_of: string;
};

export type DemoSymbol = { symbol: string; name: string | null; sort_order: number; hidden: boolean; updated_at: string };

export type DemoProject = {
  id: string;
  agent_id: string;
  key: string;
  name: string;
  kind: ProjectKind;
  status: ProjectStatus;
  progress: number | null;
  summary: string;
  next_step: string | null;
  link: string | null;
  color: string | null;
  sort_order: number;
  updated_at: string;
  updates: ProjectUpdate[]; // newest first
};

export type DemoMetric = {
  id: number;
  agent_id: string;
  key: string;
  label: string | null;
  value: number;
  unit: string | null;
  delta: number | null;
  delta_pct: number | null;
  note: string | null;
  as_of: string;
};

export type DemoMetricSetting = { key: string; label: string | null; group_name: string | null; sort_order: number; hidden: boolean };

export type DemoDashboard = {
  id: string;
  agent_id: string;
  key: string;
  title: string;
  subtitle: string | null;
  widgets: unknown[];
  sort_order: number;
  hidden: boolean;
  updated_at: string;
};

export type DemoEvent = {
  id: string;
  agent_id: string;
  calendar: string;
  external_id: string;
  title: string;
  location: string | null;
  starts_at: string;
  ends_at: string;
  all_day: boolean;
  color: string | null;
  url: string | null;
};

export type DemoState = {
  bots: import("@/lib/types").Bot[];
  calendarSources: import("@/lib/types").CalendarSource[];
  memories: import("@/lib/types").MemoryNote[];
  admin: Admin;
  agents: DemoAgent[];
  briefs: DemoBrief[];
  quotes: DemoQuote[];
  nextQuoteId: number;
  symbols: DemoSymbol[];
  reports: NewsReport[];
  items: NewsItem[];
  projects: DemoProject[];
  nextUpdateId: number;
  metrics: DemoMetric[];
  nextMetricId: number;
  metricSettings: DemoMetricSetting[];
  dashboards: DemoDashboard[];
  events: DemoEvent[];
  ingest: IngestEntry[];
  nextIngestId: number;
  devices: Device[];
  settings: Settings;
  audit: AuditEntry[];
  nextAuditId: number;
};

// The seed's ids, so a demo link looks like a real one.
export const GROK_ID = "00000000-0000-0000-0000-00000000a001";
export const STOCKS_ID = "00000000-0000-0000-0000-00000000a002";
export const PULSE_ID = "00000000-0000-0000-0000-00000000a003";
export const GITHUB_ID = "00000000-0000-0000-0000-00000000a004";
export const OPS_ID = "00000000-0000-0000-0000-00000000a005";
export const CALENDAR_ID = "00000000-0000-0000-0000-00000000a006";
const WEATHER_ID = "00000000-0000-0000-0000-00000000a007";

const TIMEZONE = "America/Chicago";

// mulberry32: tiny seeded PRNG, good enough for fixtures.
function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

type QuoteSpec = { symbol: string; name: string; price: number; change: number; change_pct: number; note?: string; sort: number };

const QUOTES: QuoteSpec[] = [
  { symbol: "SPY", name: "S&P 500 ETF", price: 668.42, change: 2.11, change_pct: 0.32, sort: 0 },
  { symbol: "AAPL", name: "Apple", price: 247.9, change: 2.78, change_pct: 1.13, note: "Services beat; iPhone 18 demand steady.", sort: 1 },
  { symbol: "NVDA", name: "NVIDIA", price: 191.25, change: 2.85, change_pct: 1.51, sort: 2 },
  { symbol: "TSLA", name: "Tesla", price: 402.1, change: -5.3, change_pct: -1.3, sort: 3 },
];

const PULSE_SECTIONS: { key: string; name: string; items: { id: string; h: string; t: string; url: string; image?: string }[] }[] = [
  {
    key: "s",
    name: "Social",
    items: [
      {
        id: "reels",
        h: "Instagram puts Reels first on the home tab",
        t: "Short video is now the default feed; static posts need to earn their reach.",
        url: "https://about.instagram.com/blog",
        image: "/demo-thumb.svg",
      },
      {
        id: "tiktok",
        h: "TikTok Shop adds live auctions in the US",
        t: "Live commerce keeps growing; brands with hosts win.",
        url: "https://newsroom.tiktok.com/",
      },
    ],
  },
  {
    key: "a",
    name: "Paid Ads",
    items: [
      {
        id: "pmax",
        h: "Google adds channel-level reporting to Performance Max",
        t: "You can finally see where the spend goes.",
        url: "https://blog.google/products/ads-commerce/",
      },
      {
        id: "meta",
        h: "Meta Advantage+ gets a creative-only mode",
        t: "Hand it the assets and it builds the campaign.",
        url: "https://www.facebook.com/business/news",
      },
    ],
  },
  {
    key: "i",
    name: "AI Tech",
    items: [
      {
        id: "gemini",
        h: "Google launches Gemini 4 Argon",
        t: "A stronger model in Search changes how brands surface in AI answers.",
        url: "https://blog.google/innovation-and-ai/models-and-research/gemini-models/",
        image: "/demo-thumb.svg",
      },
      {
        id: "claude",
        h: "Anthropic ships Claude 5 to everyone",
        t: "Computer use is on by default; expect agents in every workflow tool.",
        url: "https://www.anthropic.com/news",
      },
    ],
  },
];

// The seed's metrics: today's values and the unit/group each one carries.
const METRICS: { key: string; label: string; value: number; unit?: string; delta?: number; delta_pct?: number; group: string; note?: string; sort: number }[] = [
  { key: "sales.today", label: "Sales today", value: 4280, unit: "USD", delta_pct: 12.5, group: "Store", sort: 0 },
  { key: "orders.open", label: "Open orders", value: 17, delta: -3, group: "Store", sort: 1 },
  { key: "site.uptime", label: "Uptime", value: 99.98, unit: "%", group: "Ops", sort: 0 },
  { key: "api.p95", label: "API p95", value: 212, unit: "ms", delta: -18, group: "Ops", note: "After the cache change.", sort: 1 },
  { key: "steps", label: "Steps", value: 6420, delta_pct: -8, group: "Me", sort: 0 },
];

// The seed's two dashboards, as the agent pushes them.
const OPS_WIDGETS = [
  { type: "status", label: "API", state: "ok", detail: "All checks passing" },
  { type: "status", label: "Workers", state: "warn", detail: "1 of 4 behind" },
  { type: "metric", label: "Requests", value: 1240000, unit: "", delta_pct: 4.2 },
  { type: "metric", label: "Errors", value: 0.12, unit: "%", delta_pct: -30 },
  { type: "progress", label: "Storage", value: 68, max: 100, unit: "%" },
  { type: "chart", label: "Requests per hour", points: [40, 42, 38, 51, 60, 58, 64, 70, 66, 72, 75, 71], unit: "k" },
  { type: "list", title: "On call", items: ["Ricky (primary)", "Pager: quiet since Mon"] },
  { type: "text", title: "Note", body: "Deploy window tonight 9–10 PM CT." },
];
const LAUNCH_WIDGETS = [
  { type: "progress", label: "Checklist", value: 14, max: 20 },
  { type: "list", title: "Left to do", items: ["App Store screenshots", "Press list", "Support page"] },
  { type: "metric", label: "Waitlist", value: 812, delta: 46 },
];

function hostOf(url: string): string | null {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}

export function buildDemoState(now = Date.now()): DemoState {
  const rand = rng(20261014);
  const ago = (ms: number) => new Date(now - ms).toISOString();
  const minutes = (m: number) => ago(m * 60_000);
  const hours = (h: number) => ago(h * 3_600_000);
  const days = (d: number) => ago(d * 86_400_000);
  const uuid = () => {
    const hex = Array.from({ length: 32 }, () => Math.floor(rand() * 16).toString(16)).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
  };

  const admin: Admin = { id: uuid(), email: "marty@mcfly.example" };

  const agents: DemoAgent[] = [
    {
      id: GROK_ID, name: "Grok", slug: "grok", kind: "grok", color: "#7A64E8", scopes: ["calendar:read", "memory:read"],
      created_at: days(61), last_seen_at: minutes(20), revoked_at: null, key_prefix: "mcf_00000000", key_created_at: days(61),
    },
    {
      id: STOCKS_ID, name: "Market desk", slug: "market-desk", kind: "stocks", color: "#3DB37A",
      created_at: days(60), last_seen_at: minutes(4), revoked_at: null, key_prefix: "mcf_00000000", key_created_at: days(12),
    },
    {
      id: PULSE_ID, name: "Daily Pulse", slug: "daily-pulse", kind: "news", color: "#E2725B",
      created_at: days(58), last_seen_at: hours(6), revoked_at: null, key_prefix: "mcf_00000000", key_created_at: days(58),
    },
    {
      id: GITHUB_ID, name: "GitHub watcher", slug: "github-watcher", kind: "other", color: "#5B7CF5", scopes: ["memory:read", "memory:write"],
      created_at: days(30), last_seen_at: minutes(35), revoked_at: null, key_prefix: "mcf_00000000", key_created_at: days(30),
    },
    {
      id: OPS_ID, name: "Ops metrics", slug: "ops-metrics", kind: "other", color: "#F6B94A",
      created_at: days(28), last_seen_at: minutes(9), revoked_at: null, key_prefix: "mcf_00000000", key_created_at: days(28),
    },
    {
      id: CALENDAR_ID, name: "Calendar sync", slug: "calendar-sync", kind: "other", color: "#14C2C2",
      created_at: days(25), last_seen_at: minutes(14), revoked_at: null, key_prefix: "mcf_00000000", key_created_at: days(25),
    },
    {
      id: WEATHER_ID, name: "Weather (old)", slug: "weather-old", kind: "other", color: "#4F7CF7",
      created_at: days(45), last_seen_at: days(11), revoked_at: days(10), key_prefix: null, key_created_at: null,
    },
  ];
  const byId = (id: string) => agents.find((a) => a.id === id)!;

  const brief = (p: Omit<DemoBrief, "id" | "created_at" | "expires_at"> & { expires_at?: string | null }): DemoBrief => ({
    id: uuid(), created_at: p.published_at, expires_at: null, ...p,
  });
  const briefs: DemoBrief[] = [
    brief({
      agent_id: GROK_ID, external_id: "seed-hourly", title: "Hourly check-in", kind: "hourly", published_at: minutes(20),
      body: "Quiet hour. NVDA is leading the Nasdaq, and the Pulse report for today has landed with 6 stories.",
    }),
    brief({
      agent_id: GROK_ID, external_id: "seed-daily", title: "Morning briefing", kind: "daily", published_at: hours(3),
      body: "Three things for today.\n\n- The Fed minutes land at 1 PM CT; markets are pricing a hold.\n- Your 3 PM call moved to 3:30.\n- Rain clears by noon, 71° this afternoon.",
    }),
    brief({
      agent_id: STOCKS_ID, external_id: "alert-tsla", title: "TSLA down 1.3% at the open", kind: "alert", published_at: hours(5),
      body: "Deliveries guidance came in light. Watching 395 as support.", expires_at: hours(-19),
    }),
    brief({
      agent_id: GROK_ID, external_id: "hourly-1", title: "Hourly check-in", kind: "hourly", published_at: hours(21),
      body: "Markets closed flat. Two emails from the school are waiting; nothing urgent.",
    }),
    brief({
      agent_id: GROK_ID, external_id: "daily-1", title: "Morning briefing", kind: "daily", published_at: hours(27),
      body: "Three things for today.\n\n- Dentist at 10.\n- The Pulse report has 11 stories; the hero is the Gemini launch.\n- 68° and sunny.",
    }),
    brief({
      agent_id: WEATHER_ID, external_id: "storm", title: "Storm warning lifted", kind: "update", published_at: days(11),
      body: "The county lifted the warning at 6 PM. Clear skies through the weekend.",
    }),
    brief({
      agent_id: GROK_ID, external_id: "daily-2", title: "Morning briefing", kind: "daily", published_at: days(2),
      body: "Three things for today.\n\n- Rent is due.\n- The 2 PM call is now a video call.\n- Rain all afternoon.",
    }),
  ];

  // Thirty days of quotes per symbol; the newest row is the seed's price and
  // the older ones drift behind it.
  const quotes: DemoQuote[] = [];
  let nextQuoteId = 1;
  for (const spec of QUOTES) {
    let price = spec.price;
    for (let day = 0; day < 30; day++) {
      const asOf = day === 0 ? minutes(4) : days(day);
      quotes.push({
        id: nextQuoteId++, agent_id: STOCKS_ID, symbol: spec.symbol, name: spec.name,
        price: Math.round(price * 100) / 100,
        change: day === 0 ? spec.change : Math.round((rand() - 0.5) * 600) / 100,
        change_pct: day === 0 ? spec.change_pct : Math.round((rand() - 0.5) * 300) / 100,
        currency: "USD", note: day === 0 ? (spec.note ?? null) : null, as_of: asOf,
      });
      price = price * (1 - (rand() - 0.48) * 0.03);
    }
  }
  const symbols: DemoSymbol[] = QUOTES.map((q) => ({ symbol: q.symbol, name: q.name, sort_order: q.sort, hidden: false, updated_at: days(12) }));

  const reports: NewsReport[] = [
    {
      id: uuid(), agent_id: PULSE_ID, slug: "2026-10-14", report_date: "2026-10-14", display_date: "Oct 14, 2026",
      hero_item: "gemini", published_at: hours(6), created_at: hours(6),
    },
    {
      id: uuid(), agent_id: PULSE_ID, slug: "2026-10-13", report_date: "2026-10-13", display_date: "Oct 13, 2026",
      hero_item: "reels", published_at: hours(30), created_at: hours(30),
    },
  ];
  const items: NewsItem[] = [];
  for (const report of reports) {
    PULSE_SECTIONS.forEach((section, s) => {
      section.items.forEach((item, i) => {
        items.push({
          id: uuid(), report_id: report.id, section_key: section.key, section_name: section.name, section_order: s,
          item_key: item.id, position: i, headline: item.h, takeaway: item.t, url: item.url,
          image_url: item.image ?? null, source_domain: hostOf(item.url), created_at: report.published_at,
        });
      });
    });
  }

  // Projects, as the GitHub watcher reports them (the seed's three).
  let nextUpdateId = 1;
  const update = (kind: ProjectUpdate["kind"], text: string, at: string, url: string | null = null): ProjectUpdate => ({
    id: nextUpdateId++, kind, text, url, happened_at: at,
  });
  const projects: DemoProject[] = [
    {
      id: uuid(), agent_id: GITHUB_ID, key: "mcfly", name: "McFly", kind: "code", status: "active", progress: 62, sort_order: 0,
      summary: "The agent display: Pi app, console and the iPhone app.", next_step: "Ship the dashboards screen",
      link: "https://github.com/rmantilla13/mcfly", color: null, updated_at: minutes(35),
      updates: [
        update("ci", "CI green on main (14 checks)", minutes(35)),
        update("pr", "#12 Dashboards screen: opened by Ricky", hours(2), "https://github.com/rmantilla13/mcfly/pull/12"),
        update("commit", "console: productivity tabs", hours(5)),
        update("deploy", "Console deployed to mcfly.bot", hours(26)),
        update("note", "Started the productivity feeds", days(2)),
      ],
    },
    {
      id: uuid(), agent_id: GITHUB_ID, key: "onyx", name: "Onyx", kind: "code", status: "blocked", progress: 80, sort_order: 1,
      summary: "Collections and the Mac app.", next_step: "App Review answer on the FSKit entitlement",
      link: null, color: null, updated_at: hours(22),
      updates: [update("alert", "App Review: waiting on the FSKit entitlement", hours(22)), update("ci", "CI green on claude/collections", days(1.2))],
    },
    {
      id: uuid(), agent_id: GITHUB_ID, key: "homestead", name: "Homestead", kind: "launch", status: "paused", progress: 95, sort_order: 2,
      summary: "Voice handbook app; launch copy is done.", next_step: null, link: null, color: "#F07F5A", updated_at: days(4),
      updates: [update("done", "Launch copy approved", days(4))],
    },
  ];

  // Metrics: today's row plus a week of history for each.
  const metrics: DemoMetric[] = [];
  let nextMetricId = 1;
  for (const m of METRICS) {
    let value = m.value;
    for (let day = 0; day < 8; day++) {
      metrics.push({
        id: nextMetricId++, agent_id: OPS_ID, key: m.key, label: m.label, value: Math.round(value * 100) / 100,
        unit: m.unit ?? null, delta: day === 0 ? (m.delta ?? null) : null, delta_pct: day === 0 ? (m.delta_pct ?? null) : null,
        note: day === 0 ? (m.note ?? null) : null, as_of: day === 0 ? minutes(9) : days(day),
      });
      value = value * (1 - (rand() - 0.5) * (m.unit === "%" ? 0.001 : 0.15));
    }
  }
  const metricSettings: DemoMetricSetting[] = METRICS.map((m) => ({ key: m.key, label: m.label, group_name: m.group, sort_order: m.sort, hidden: false }));

  const dashboards: DemoDashboard[] = [
    { id: uuid(), agent_id: OPS_ID, key: "ops", title: "Ops", subtitle: "Production, last 24 h", widgets: OPS_WIDGETS, sort_order: 0, hidden: false, updated_at: minutes(9) },
    { id: uuid(), agent_id: OPS_ID, key: "launch", title: "Launch week", subtitle: null, widgets: LAUNCH_WIDGETS, sort_order: 1, hidden: false, updated_at: hours(3) },
  ];

  // Events around today in the display's zone: the seed's six, moved to
  // this week so the calendar tab always has today and tomorrow.
  const today = new Date(now);
  const dayOf = (offset: number) => {
    const d = new Date(today.getTime() + offset * 86_400_000);
    // The day in the display's zone, as a YYYY-MM-DD key.
    const p = new Intl.DateTimeFormat("en-CA", { timeZone: TIMEZONE, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
    return p;
  };
  const at = (dayOffset: number, hour: number, minute = 0) => {
    const midnight = Date.parse(zonedMidnightUtc(dayOf(dayOffset), TIMEZONE));
    return new Date(midnight + (hour * 60 + minute) * 60_000).toISOString();
  };
  const event = (p: Omit<DemoEvent, "id" | "agent_id" | "url" | "location"> & { location?: string | null }): DemoEvent => ({
    id: uuid(), agent_id: CALENDAR_ID, url: null, location: null, ...p,
  });
  const events: DemoEvent[] = [
    event({ calendar: "Work", external_id: "ev-1", title: "Standup", starts_at: at(0, 9, 30), ends_at: at(0, 9, 45), all_day: false, color: "#5B7CF5" }),
    event({ calendar: "Work", external_id: "ev-2", title: "Pulse review with the team", starts_at: at(0, 15, 30), ends_at: at(0, 16), all_day: false, color: "#5B7CF5", location: "Zoom" }),
    event({ calendar: "Home", external_id: "ev-3", title: "Dinner with Lina", starts_at: at(0, 19), ends_at: at(0, 21), all_day: false, color: "#F07F5A", location: "Maria's" }),
    event({ calendar: "Work", external_id: "ev-4", title: "Investor call", starts_at: at(1, 11), ends_at: at(1, 12), all_day: false, color: "#5B7CF5" }),
    event({ calendar: "Home", external_id: "ev-5", title: "Flight to Austin", starts_at: at(3, 8), ends_at: at(3, 11), all_day: false, color: "#F07F5A" }),
    event({ calendar: "Home", external_id: "ev-6", title: "Launch day", starts_at: at(6, 0), ends_at: at(6, 23, 59), all_day: true, color: "#F6B94A" }),
  ];

  // The last day of pushes: Grok every hour, the market desk every 15
  // minutes (one of them refused), the Pulse report once, the new agents
  // on their own rhythms.
  const ingestRaw: Omit<IngestEntry, "id">[] = [];
  const push = (agent: DemoAgent, feed: string, count: number, when: string, status: "ok" | "error" = "ok", message: string | null = null) =>
    ingestRaw.push({ created_at: when, agent_id: agent.id, agent_name: agent.name, agent_color: agent.color, feed, count, status, message });
  for (let m = 4; m < 24 * 60; m += 15) push(byId(STOCKS_ID), "quotes", 4, minutes(m));
  push(byId(STOCKS_ID), "quotes", 0, minutes(49), "error", "quote 3: price must be a number");
  for (let h = 0; h < 24; h++) push(byId(GROK_ID), "briefs", 1, minutes(20 + h * 60));
  push(byId(PULSE_ID), "news", 6, hours(6));
  push(byId(PULSE_ID), "news", 0, hours(6.1), "error", "sections must be a non-empty list");
  push(byId(PULSE_ID), "news", 6, hours(30));
  for (let m = 9; m < 24 * 60; m += 30) push(byId(OPS_ID), "metrics", 5, minutes(m));
  push(byId(OPS_ID), "dashboards", 2, minutes(9));
  push(byId(OPS_ID), "dashboards", 0, hours(3.1), "error", "dashboard x: each widget needs a type of metric, status, progress, list, text or chart");
  for (let m = 35; m < 24 * 60; m += 120) push(byId(GITHUB_ID), "projects", 3, minutes(m));
  for (let m = 14; m < 24 * 60; m += 60) push(byId(CALENDAR_ID), "events", 6, minutes(m));
  push(byId(GROK_ID), "briefs", 1, days(2));
  ingestRaw.sort((a, b) => b.created_at.localeCompare(a.created_at));
  const ingest: IngestEntry[] = ingestRaw.map((e, i) => ({ id: ingestRaw.length - i, ...e }));

  const devices: Device[] = [
    { id: uuid(), user_id: uuid(), name: "Kitchen wall", last_seen_at: minutes(2), created_at: days(40),
      settings: { screensaver: "ambient", darkMode: false, animatedTiles: true, idleSeconds: 120, offAfterSeconds: 0, offAtNight: true,
                  bedtime: 1320, wakeTime: 390, assistantProvider: "", speakReplies: true, wakeword: true } },
    { id: uuid(), user_id: uuid(), name: "Office", last_seen_at: days(3), created_at: days(9), settings: {} },
  ];

  const settings: Settings = {
    display_name: "McFly", timezone: TIMEZONE, briefs_keep_days: 30, quotes_keep_days: 90, news_keep_reports: 14,
    assistant_provider: "claude", metrics_keep_days: 90, events_keep_days: 60,
    updated_at: days(5), updated_by: admin.id,
  };

  const a = (when: string, action: string, target_type: string | null, target_id: string | null, details: Record<string, unknown>) => ({
    created_at: when, admin_email: admin.email, action, target_type, target_id, details,
  });
  const auditRaw = [
    a(hours(8), "set_metric", "metric", "sales.today", { sort_order: 0 }),
    a(days(1), "delete_event", "event", uuid(), { title: "Dentist (cancelled)" }),
    a(days(3), "set_dashboard", "dashboard", dashboards[0].id, { sort_order: 0 }),
    a(days(5), "update_settings", "settings", null, { quotes_keep_days: 90 }),
    a(days(6), "delete_brief", "brief", uuid(), { title: "Test push from laptop" }),
    a(days(9), "pair_device", "device", devices[1].id, { name: "Office" }),
    a(days(10), "revoke_agent", "agent", WEATHER_ID, {}),
    a(days(12), "rotate_agent_key", "agent", STOCKS_ID, {}),
    a(days(12), "set_symbol", "symbol", "SPY", { sort_order: 0 }),
    a(days(25), "create_agent", "agent", CALENDAR_ID, { name: "Calendar sync", slug: "calendar-sync", kind: "other" }),
    a(days(28), "create_agent", "agent", OPS_ID, { name: "Ops metrics", slug: "ops-metrics", kind: "other" }),
    a(days(30), "create_agent", "agent", GITHUB_ID, { name: "GitHub watcher", slug: "github-watcher", kind: "other" }),
    a(days(30), "rename_device", "device", devices[0].id, { name: "Kitchen wall" }),
    a(days(40), "pair_device", "device", devices[0].id, { name: "Display" }),
    a(days(45), "create_agent", "agent", WEATHER_ID, { name: "Weather (old)", slug: "weather-old", kind: "other" }),
    a(days(58), "create_agent", "agent", PULSE_ID, { name: "Daily Pulse", slug: "daily-pulse", kind: "news" }),
    a(days(60), "create_agent", "agent", STOCKS_ID, { name: "Market desk", slug: "market-desk", kind: "stocks" }),
    a(days(61), "create_agent", "agent", GROK_ID, { name: "Grok", slug: "grok", kind: "grok" }),
  ];
  const audit: AuditEntry[] = auditRaw.map((e, i) => ({ id: auditRaw.length - i, ...e }));

  const note = (agentId: string | null, text: string, pinned: boolean, key: string | null, ago: string) => ({
    id: uuid(), agent_id: agentId, agent_name: agents.find((a) => a.id === agentId)?.name ?? null,
    agent_color: agents.find((a) => a.id === agentId)?.color ?? null, key, text, pinned,
    source: (agentId ? "agent" : "admin") as "admin" | "agent", created_at: ago, updated_at: ago,
  });
  const memories = [
    note(null, "Ricky lives in Austin and works on Onyx and McFly.", true, null, days(20)),
    note(null, "Prefers short briefs: three bullets, no filler.", true, null, days(12)),
    note(null, "Follows NVDA, TSLA and the Fed closely.", false, null, days(5)),
    note(GITHUB_ID, "Last reported: CI green on main, PR #12 opened.", false, "last-run", minutes(35)),
  ];

  const calendarSources = [
    { id: uuid(), name: "Work", host: "calendar.google.com", color: "#5B7CF5", enabled: true, last_synced_at: minutes(9),
      last_error: null, event_count: 14, created_at: days(10) },
    { id: uuid(), name: "Family", host: "p52-caldav.icloud.com", color: "#F07F5A", enabled: true, last_synced_at: hours(3),
      last_error: "the link answered 404; it may have been reset, or the calendar isn't shared", event_count: 6, created_at: days(4) },
  ];

  const bots: import("@/lib/types").Bot[] = [
    {
      id: uuid(), agent_id: GROK_ID, name: "Grok", color: "#7A64E8", scopes: ["calendar:read", "memory:read"],
      prompt: "Every morning, brief me on what matters today: markets before the open, the AI and tech news worth knowing, and anything on X about my projects. Three short sections.",
      output: "brief", every_minutes: 1440, at_minute: 420, web_search: true, x_search: true, model: "", enabled: true,
      next_run_at: hours(-20), last_run_at: hours(4), last_status: "ok", last_error: null, runs_7d: 7,
      runs: [
        { id: 3, started_at: hours(4), finished_at: hours(4), status: "ok", title: "Morning briefing", error: null, sources: 9, model: "grok-4.7" },
        { id: 2, started_at: days(1), finished_at: days(1), status: "ok", title: "Morning briefing", error: null, sources: 7, model: "grok-4.7" },
      ],
    },
  ];

  return {
    bots,
    calendarSources,
    memories,
    admin,
    agents,
    briefs,
    quotes,
    nextQuoteId,
    symbols,
    reports,
    items,
    projects,
    nextUpdateId,
    metrics,
    nextMetricId,
    metricSettings,
    dashboards,
    events,
    ingest,
    nextIngestId: ingest.length + 1,
    devices,
    settings,
    audit,
    nextAuditId: audit.length + 1,
  };
}
