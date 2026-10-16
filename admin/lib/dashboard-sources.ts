// Dashboards made here, not pushed: a template to start from, and for each
// part of the board, where it pulls from. The database draws the parts into
// the six widgets every screen already knows (20261016000010, dashboard_part)
// and redraws them as the feeds change; this file is the console's side of
// that recipe: the kinds of part, the templates, and a tolerant reader that
// turns whatever the builder (or an old row) holds into parts the database
// accepts. Pure, so tests/dashboard-sources.test.mjs can check it.

import type { BriefKind } from "./types.ts";

export type QuotesPart = { from: "quotes"; symbols: string[]; show: "tiles" | "chart"; limit?: number; title?: string };
export type MetricsPart = { from: "metrics"; keys: string[]; group?: string; show: "tiles" | "chart"; limit?: number; title?: string };
export type ProjectsPart = { from: "projects"; projects: string[]; show: "progress" | "list"; limit?: number; title?: string };
export type CalendarPart = { from: "calendar"; calendars: string[]; days: number; limit?: number; title?: string };
export type TodosPart = { from: "todos"; kind: "all" | "todo" | "reminder"; limit?: number; title?: string };
export type NewsPart = { from: "news"; section?: string; limit?: number; title?: string };
export type BriefPart = { from: "brief"; kind?: BriefKind; agent?: string; title?: string };
export type AgentsPart = { from: "agents"; agents: string[]; hours: number; title?: string };
export type NotePart = { from: "note"; title?: string; body: string };

export type DashboardPart = QuotesPart | MetricsPart | ProjectsPart | CalendarPart | TodosPart | NewsPart | BriefPart | AgentsPart | NotePart;
export type PartKind = DashboardPart["from"];

// The kinds of part, in the order the builder offers them: where a part can
// pull from.
export const PART_KINDS: { kind: PartKind; label: string; description: string; color: string }[] = [
  { kind: "quotes", label: "Markets", description: "Prices and the day's move, for the symbols you pick.", color: "#3DB37A" },
  { kind: "metrics", label: "Metrics", description: "Numbers an agent reports, as tiles or a chart.", color: "#F6B94A" },
  { kind: "projects", label: "Projects", description: "Progress and next steps.", color: "#5B7CF5" },
  { kind: "calendar", label: "Calendar", description: "What's coming up, from the calendars you pick.", color: "#14C2C2" },
  { kind: "todos", label: "Todos", description: "What's open, and reminders.", color: "#E86A92" },
  { kind: "news", label: "News", description: "Headlines from the newest Daily Pulse.", color: "#E2725B" },
  { kind: "brief", label: "Brief", description: "The newest brief, whole.", color: "#7A64E8" },
  { kind: "agents", label: "Agents", description: "Whether each agent is still pushing.", color: "#8F95A1" },
  { kind: "note", label: "Note", description: "Words of your own.", color: "#A78BFA" },
];

export const partKind = (kind: PartKind) => PART_KINDS.find((k) => k.kind === kind) ?? PART_KINDS[0];

export const CALENDAR_DAYS = [1, 2, 3, 7, 14, 31] as const;
export const AGENT_HOURS = [1, 6, 24, 72, 168] as const;
export const BRIEF_KINDS: BriefKind[] = ["daily", "hourly", "alert", "update"];

// A new part of each kind, as the builder's "Add" puts it on the board.
export function blankPart(kind: PartKind): DashboardPart {
  switch (kind) {
    case "quotes":
      return { from: "quotes", symbols: [], show: "tiles" };
    case "metrics":
      return { from: "metrics", keys: [], show: "tiles" };
    case "projects":
      return { from: "projects", projects: [], show: "progress" };
    case "calendar":
      return { from: "calendar", calendars: [], days: 7 };
    case "todos":
      return { from: "todos", kind: "all" };
    case "news":
      return { from: "news", limit: 5 };
    case "brief":
      return { from: "brief" };
    case "agents":
      return { from: "agents", agents: [], hours: 24 };
    case "note":
      return { from: "note", body: "" };
  }
}

export type DashboardTemplate = {
  id: string;
  label: string;
  description: string;
  color: string;
  title: string;
  subtitle?: string;
  parts: DashboardPart[];
};

// Starting points. An empty list of symbols, keys, projects, calendars or
// agents means "all of them", so a template works before anything is picked.
export const DASHBOARD_TEMPLATES: DashboardTemplate[] = [
  {
    id: "today",
    label: "Today",
    description: "The day's calendar, what's open, the morning brief and your symbols.",
    color: "#F2A33A",
    title: "Today",
    parts: [
      { from: "calendar", calendars: [], days: 1 },
      { from: "todos", kind: "all", limit: 6 },
      { from: "quotes", symbols: [], show: "tiles", limit: 4 },
      { from: "brief", kind: "daily" },
    ],
  },
  {
    id: "markets",
    label: "Markets",
    description: "A chart for the symbol that matters, tiles for the rest.",
    color: "#3DB37A",
    title: "Markets",
    subtitle: "The last 30 days",
    parts: [
      { from: "quotes", symbols: [], show: "chart", limit: 1 },
      { from: "quotes", symbols: [], show: "tiles", limit: 8 },
    ],
  },
  {
    id: "numbers",
    label: "Numbers",
    description: "The metrics you pick as tiles, with charts for the first two.",
    color: "#F6B94A",
    title: "Numbers",
    parts: [
      { from: "metrics", keys: [], show: "tiles", limit: 8 },
      { from: "metrics", keys: [], show: "chart", limit: 2 },
    ],
  },
  {
    id: "projects",
    label: "Projects",
    description: "Every active project's progress, and what's next on each.",
    color: "#5B7CF5",
    title: "Projects",
    parts: [
      { from: "projects", projects: [], show: "progress" },
      { from: "projects", projects: [], show: "list", title: "Next steps" },
    ],
  },
  {
    id: "week",
    label: "Week ahead",
    description: "Seven days of calendar, with todos and reminders beside them.",
    color: "#14C2C2",
    title: "Week ahead",
    parts: [
      { from: "calendar", calendars: [], days: 7, limit: 12 },
      { from: "todos", kind: "todo", limit: 8 },
      { from: "todos", kind: "reminder", limit: 6 },
    ],
  },
  {
    id: "health",
    label: "Agent health",
    description: "Which agents are pushing, which went quiet, and which failed.",
    color: "#8F95A1",
    title: "Agent health",
    subtitle: "Quiet after a day",
    parts: [{ from: "agents", agents: [], hours: 24 }],
  },
  {
    id: "reading",
    label: "Reading",
    description: "The newest brief and the day's headlines.",
    color: "#E2725B",
    title: "Reading",
    parts: [
      { from: "brief" },
      { from: "news", limit: 6 },
    ],
  },
  {
    id: "blank",
    label: "Blank",
    description: "Start from a note and add what you want.",
    color: "#A78BFA",
    title: "My board",
    parts: [{ from: "note", title: "Note", body: "Add parts below: markets, metrics, projects, the calendar…" }],
  },
];

export const findTemplate = (id: string | null | undefined) => DASHBOARD_TEMPLATES.find((t) => t.id === id) ?? null;

// A copy the builder may change without touching the template.
export const templateParts = (t: DashboardTemplate): DashboardPart[] => structuredClone(t.parts);

// ─────────────────────────── Reading a recipe ───────────────────────────

export const MAX_PARTS = 20;
const MAX_NAMES = 20;

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

function words(v: unknown, max: number): string | undefined {
  if (typeof v !== "string") return undefined;
  const s = v.trim().slice(0, max);
  return s || undefined;
}

function names(v: unknown, transform: (s: string) => string = (s) => s): string[] {
  if (!Array.isArray(v)) return [];
  const out: string[] = [];
  for (const item of v) {
    if (typeof item !== "string") continue;
    const s = transform(item.trim()).slice(0, 200);
    if (s && !out.includes(s)) out.push(s);
    if (out.length === MAX_NAMES) break;
  }
  return out;
}

function whole(v: unknown, lo: number, hi: number): number | undefined {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  if (!Number.isFinite(n)) return undefined;
  return Math.min(hi, Math.max(lo, Math.round(n)));
}

function nearest(v: unknown, choices: readonly number[], fallback: number): number {
  const n = whole(v, choices[0], choices[choices.length - 1]);
  if (n === undefined) return fallback;
  return choices.reduce((best, c) => (Math.abs(c - n) < Math.abs(best - n) ? c : best), choices[0]);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Only the fields that are set, so a part round-trips without nulls.
function compact<T extends Record<string, unknown>>(part: T): T {
  return Object.fromEntries(Object.entries(part).filter(([, v]) => v !== undefined && v !== "")) as T;
}

// One part from whatever it was; null when it can't be one (an unknown
// kind, a note with no words).
export function readPart(raw: unknown): DashboardPart | null {
  if (!isObject(raw)) return null;
  const title = words(raw.title, 80);
  switch (raw.from) {
    case "quotes":
      return compact({
        from: "quotes",
        symbols: names(raw.symbols, (s) => s.toUpperCase()).filter((s) => /^[A-Z0-9.^=:-]{1,16}$/.test(s)),
        show: raw.show === "chart" ? "chart" : "tiles",
        limit: whole(raw.limit, 1, 12),
        title,
      }) as QuotesPart;
    case "metrics":
      return compact({
        from: "metrics",
        keys: names(raw.keys, (s) => s.toLowerCase()),
        group: words(raw.group, 80),
        show: raw.show === "chart" ? "chart" : "tiles",
        limit: whole(raw.limit, 1, 12),
        title,
      }) as MetricsPart;
    case "projects":
      return compact({
        from: "projects",
        projects: names(raw.projects, (s) => s.toLowerCase()).filter((s) => UUID.test(s)),
        show: raw.show === "list" ? "list" : "progress",
        limit: whole(raw.limit, 1, 12),
        title,
      }) as ProjectsPart;
    case "calendar":
      return compact({
        from: "calendar",
        calendars: names(raw.calendars),
        days: nearest(raw.days, CALENDAR_DAYS, 7),
        limit: whole(raw.limit, 1, 20),
        title,
      }) as CalendarPart;
    case "todos":
      return compact({
        from: "todos",
        kind: raw.kind === "todo" || raw.kind === "reminder" ? raw.kind : "all",
        limit: whole(raw.limit, 1, 20),
        title,
      }) as TodosPart;
    case "news":
      return compact({ from: "news", section: words(raw.section, 32), limit: whole(raw.limit, 1, 20), title }) as NewsPart;
    case "brief":
      return compact({
        from: "brief",
        kind: BRIEF_KINDS.includes(raw.kind as BriefKind) ? (raw.kind as BriefKind) : undefined,
        agent: typeof raw.agent === "string" && UUID.test(raw.agent) ? raw.agent.toLowerCase() : undefined,
        title,
      }) as BriefPart;
    case "agents":
      return compact({
        from: "agents",
        agents: names(raw.agents, (s) => s.toLowerCase()).filter((s) => UUID.test(s)),
        hours: nearest(raw.hours, AGENT_HOURS, 24),
        title,
      }) as AgentsPart;
    case "note": {
      const body = words(raw.body, 2000);
      return body ? (compact({ from: "note", title, body }) as NotePart) : null;
    }
    default:
      return null;
  }
}

// A whole recipe: the parts that can be read, at most twenty.
export function readParts(raw: unknown): DashboardPart[] {
  if (!Array.isArray(raw)) return [];
  return raw.map(readPart).filter((p): p is DashboardPart => p !== null).slice(0, MAX_PARTS);
}

// ─────────────────────────── Saying what a part shows ───────────────────────────

// What the pickers offer: admin_dashboard_sources() (the database's lists).
export type DashboardSourceOptions = {
  symbols: { symbol: string; name: string | null; hidden: boolean }[];
  metrics: { key: string; label: string; group: string | null; unit: string | null; hidden: boolean }[];
  projects: { id: string; name: string; status: string; agent_name: string }[];
  calendars: string[];
  news_sections: { key: string; name: string }[];
  agents: { id: string; name: string; color: string; has_key: boolean }[];
  timezone: string;
};

export const EMPTY_OPTIONS: DashboardSourceOptions = {
  symbols: [],
  metrics: [],
  projects: [],
  calendars: [],
  news_sections: [],
  agents: [],
  timezone: "UTC",
};

function listed(picked: string[], label: (v: string) => string, all: string, max = 3): string {
  if (picked.length === 0) return all;
  const shown = picked.slice(0, max).map(label);
  return picked.length > max ? `${shown.join(", ")} and ${picked.length - max} more` : shown.join(", ");
}

const DAYS_LABEL: Record<number, string> = { 1: "today", 2: "today and tomorrow" };
export const daysLabel = (days: number) => DAYS_LABEL[days] ?? `the next ${days} days`;
export const hoursLabel = (hours: number) => (hours % 24 === 0 ? (hours === 24 ? "a day" : `${hours / 24} days`) : hours === 1 ? "an hour" : `${hours} hours`);

// One line on where a part pulls from, for the dashboard's page and the
// builder's collapsed part: "AAPL, NVDA as tiles", "Work, the next 7 days".
export function describePart(part: DashboardPart, options: DashboardSourceOptions = EMPTY_OPTIONS): string {
  const most = (limit: number | undefined) => (limit ? `, up to ${limit}` : "");
  switch (part.from) {
    case "quotes":
      return `${listed(part.symbols, (s) => s, "Every symbol")} as ${part.show === "chart" ? "charts" : "tiles"}${most(part.limit)}`;
    case "metrics": {
      const label = (k: string) => options.metrics.find((m) => m.key === k)?.label ?? k;
      const all = part.group ? `Every ${part.group} metric` : "Every metric";
      return `${listed(part.keys, label, all)} as ${part.show === "chart" ? "charts" : "tiles"}${most(part.limit)}`;
    }
    case "projects": {
      const label = (id: string) => options.projects.find((p) => p.id === id)?.name ?? "a project";
      return `${listed(part.projects, label, "Active projects")}, ${part.show === "list" ? "as a list" : "their progress"}`;
    }
    case "calendar":
      return `${listed(part.calendars, (c) => c, "Every calendar")}, ${daysLabel(part.days)}`;
    case "todos":
      return part.kind === "reminder" ? "Reminders" : part.kind === "todo" ? "Open todos" : "Open todos and reminders";
    case "news": {
      const section = part.section ? (options.news_sections.find((s) => s.key === part.section)?.name ?? part.section) : null;
      return `${section ? `${section} headlines` : "The top headlines"}${most(part.limit)}`;
    }
    case "brief": {
      const agent = part.agent ? options.agents.find((a) => a.id === part.agent)?.name : null;
      return `The newest ${part.kind ? `${part.kind} ` : ""}brief${agent ? ` from ${agent}` : ""}`;
    }
    case "agents": {
      const label = (id: string) => options.agents.find((a) => a.id === id)?.name ?? "an agent";
      return `${listed(part.agents, label, "Every agent with a key")}, quiet after ${hoursLabel(part.hours)}`;
    }
    case "note":
      return part.title ? `A note: ${part.title}` : "A note";
  }
}
