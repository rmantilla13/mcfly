// Shapes returned by the admin_* RPCs and the two edge functions the console
// calls (docs/PLATFORM_SPEC.md §1.6, §2.2, §2.3; the productivity feeds in
// backend/supabase/migrations/20261014000003_productivity.sql). Fields the
// spec doesn't name are optional so the console tolerates an older backend.

export type Admin = { id: string; email: string };

export type AgentKind = "grok" | "stocks" | "news" | "other";
export const AGENT_KINDS: AgentKind[] = ["grok", "stocks", "news", "other"];

// The ingest function's feeds: POST /functions/v1/ingest/<feed>.
export type Feed = "briefs" | "quotes" | "news" | "projects" | "metrics" | "dashboards" | "events";
export const FEEDS: Feed[] = ["briefs", "quotes", "news", "projects", "metrics", "dashboards", "events"];

export type Overview = {
  agents: number;
  agents_revoked: number;
  pushes_24h: number;
  errors_24h: number;
  briefs: number;
  briefs_24h: number;
  symbols: number;
  quotes: number;
  news_reports: number;
  latest_report: string | null;
  projects: number; // not done
  projects_blocked: number;
  metrics: number; // not hidden
  dashboards: number; // not hidden
  events_upcoming: number; // in the next 7 days
  devices: number;
  devices_online: number;
  last_push_at: string | null;
};

export type AgentRow = {
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
  pushes_7d: number;
  last_error: string | null;
  scopes: AgentScope[];
  memory_count: number;
};

// What an agent may read back through ingest, beyond pushing (migration
// 20261015000001). Granted by the admin; off by default.
export type AgentScope = "memory:read" | "memory:write" | "calendar:read";
export const AGENT_SCOPES: AgentScope[] = ["memory:read", "memory:write", "calendar:read"];

// A note McFly keeps: shared (about the user) when agent_id is null, else an
// agent's own working note.
export type MemoryNote = {
  id: string;
  agent_id: string | null;
  agent_name: string | null;
  agent_color: string | null;
  key: string | null;
  text: string;
  pinned: boolean;
  source: "admin" | "agent";
  created_at: string;
  updated_at: string;
};

// admin_create_agent: the key is shown once and never stored in the clear.
export type NewAgent = { id: string; slug: string; key: string };

export type BriefKind = "hourly" | "daily" | "alert" | "update";

export type Brief = {
  id: string;
  agent_id: string;
  agent_name: string;
  agent_color: string;
  external_id: string | null;
  title: string;
  body: string;
  kind: BriefKind;
  published_at: string;
  expires_at: string | null;
  created_at: string;
};

export type QuoteRow = {
  symbol: string;
  name: string | null;
  sort_order: number;
  hidden: boolean;
  price: number | null; // null when the symbol has no quote rows left
  change: number | null;
  change_pct: number | null;
  currency: string | null;
  note: string | null;
  as_of: string | null;
  agent_name: string | null;
  agent_color: string | null;
  history_count: number;
};

export type NewsReportRow = {
  id: string;
  slug: string;
  report_date: string; // YYYY-MM-DD
  display_date: string | null;
  hero_item: string | null;
  published_at: string;
  agent_name: string;
  agent_color: string;
  item_count: number;
  sections: string[];
};

export type NewsReport = {
  id: string;
  agent_id: string;
  slug: string;
  report_date: string;
  display_date: string | null;
  hero_item: string | null;
  published_at: string;
  created_at: string;
};

export type NewsItem = {
  id: string;
  report_id: string;
  section_key: string;
  section_name: string;
  section_order: number;
  item_key: string;
  position: number;
  headline: string;
  takeaway: string;
  url: string;
  image_url: string | null;
  source_domain: string | null;
  created_at: string;
};

export type NewsReportDetail = { report: NewsReport; items: NewsItem[] };

// ───────────────────────── Productivity feeds ─────────────────────────

export type ProjectKind = "code" | "task" | "launch" | "other";
export type ProjectStatus = "active" | "blocked" | "paused" | "done";

export type ProjectRow = {
  id: string;
  agent_id: string;
  agent_name: string;
  agent_color: string;
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
  update_count: number;
  last_update: string | null;
  last_update_at: string | null;
};

export type ProjectUpdateKind = "note" | "commit" | "pr" | "ci" | "deploy" | "alert" | "done";

export type ProjectUpdate = {
  id: number;
  kind: ProjectUpdateKind;
  text: string;
  url: string | null;
  happened_at: string;
};

export type MetricRow = {
  key: string;
  label: string;
  group_name: string | null;
  sort_order: number;
  hidden: boolean;
  value: number | null; // null when the metric has no rows left
  unit: string | null;
  delta: number | null;
  delta_pct: number | null;
  note: string | null;
  as_of: string | null;
  agent_name: string | null;
  agent_color: string | null;
  history_count: number;
};

// A dashboard's widgets as the agent sent them; lib/widgets.ts reads them.
export type Widget =
  | { type: "metric"; label: string; value: number; unit?: string; delta?: number; delta_pct?: number }
  | { type: "status"; label: string; state: "ok" | "warn" | "down" | "unknown"; detail?: string }
  | { type: "progress"; label: string; value: number; max: number; unit?: string }
  | { type: "list"; title?: string; items: string[] }
  | { type: "text"; title?: string; body: string }
  | { type: "chart"; label: string; points: number[]; unit?: string };

export type DashboardRow = {
  id: string;
  key: string;
  title: string;
  subtitle: string | null;
  widgets: unknown[]; // raw jsonb; parsed by lib/widgets.ts when rendered
  sort_order: number;
  hidden: boolean;
  updated_at: string;
  agent_name: string;
  agent_color: string;
};

export type EventRow = {
  id: string;
  agent_id: string;
  agent_name: string;
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

// ───────────────────────────── Rest ─────────────────────────────

export type IngestEntry = {
  id: number;
  created_at: string;
  agent_id: string | null;
  agent_name: string | null;
  agent_color: string | null;
  feed: string;
  count: number;
  status: "ok" | "error";
  message: string | null;
};

export type Device = {
  id: string;
  user_id: string;
  name: string;
  last_seen_at: string | null;
  created_at: string;
  settings: DisplaySettings;
};

// A display's own settings, kept on the server so the console and the screen
// edit the same thing (clean_device_settings: migrations 20261015000004,
// 20261015000008, 20261016000001 and 20261016000003).
export type DisplaySettings = Partial<{
  screensaver: "ambient" | "clock" | "headlines";
  backdrop: "mesh" | "arc" | "ribbons" | "dawn" | "silk" | "pillars"; // behind Ambient and Clock: the gradient (an aurora at night), or a sky of its own
  homeLayout: "today" | "bento" | "assistant"; // Home: the day as a timeline, a grid of tiles, or McFly's summary first
  darkMode: boolean;
  animatedTiles: boolean;
  idleSeconds: number;
  offAfterSeconds: number;
  offAtNight: boolean;
  bedtime: number; // minutes after midnight
  wakeTime: number;
  assistantProvider: "" | "claude" | "grok";
  speakReplies: boolean;
  wakeword: boolean;
  wakewordModel: "hey_mcfly" | "hey_jarvis" | "alexa" | "hey_mycroft" | "hey_rhasspy"; // hey_mcfly: McFly's own
  voice: "af_heart" | "af_bella" | "am_michael" | "am_fenrir"; // Kokoro: Homestead's voices
  voiceSpeed: number;
  volume: number;
}>;

export type AssistantProvider = "claude" | "grok";
export const ASSISTANT_PROVIDERS: AssistantProvider[] = ["claude", "grok"];

export type Settings = {
  display_name: string;
  timezone: string;
  briefs_keep_days: number;
  quotes_keep_days: number;
  news_keep_reports: number;
  assistant_provider: AssistantProvider;
  metrics_keep_days: number;
  events_keep_days: number;
  updated_at: string | null;
  updated_by: string | null;
};

export type SettingsPatch = Partial<Omit<Settings, "updated_at" | "updated_by">>;

export type AuditEntry = {
  id: number;
  created_at: string;
  admin_email: string | null;
  action: string;
  target_type: string | null;
  target_id: string | null;
  details: Record<string, unknown>;
};

export type Page<T> = { rows: T[]; page: number; hasMore: boolean };

// A calendar subscription McFly reads every 15 minutes: an iCal link, or a
// calendar of a Google account the admin signed in with (read through the
// Calendar API). Neither the link nor the sign-in reaches the console: a
// link shows its host, a Google calendar its account's email.
export type CalendarSourceKind = "ical" | "google";
export type CalendarSource = {
  id: string;
  name: string;
  host: string;
  color: string | null;
  enabled: boolean;
  last_synced_at: string | null;
  last_error: string | null;
  event_count: number;
  created_at: string;
  kind: CalendarSourceKind;
  account_id: string | null; // kind google: the connected account
  account_email: string | null;
  google_calendar_id: string | null;
};

// A Google account the admin signed in with (migration 20261016000011). The
// refresh token stays on the server; this is all the console sees.
export type GoogleAccount = {
  id: string;
  email: string;
  connected_at: string;
  last_error: string | null; // "Google no longer accepts this sign-in…"
  calendars: number; // subscribed from it
};

// One calendar of a connected account, as Google lists it.
export type GoogleCalendar = {
  id: string;
  name: string;
  color: string | null;
  primary: boolean;
  access_role: string;
  selected: boolean; // shown in Google Calendar's own list
};

// A Grok bot: an agent McFly runs itself on a schedule, through xAI's API
// with web and X search (migration 20261015000005).
export type BotOutput = "brief" | "news";
export type Bot = {
  id: string;
  agent_id: string;
  name: string;
  color: string;
  scopes: AgentScope[];
  prompt: string;
  output: BotOutput;
  every_minutes: number;
  at_minute: number | null;
  web_search: boolean;
  x_search: boolean;
  model: string;
  enabled: boolean;
  next_run_at: string;
  last_run_at: string | null;
  last_status: "ok" | "error" | null;
  last_error: string | null;
  runs_7d: number;
  runs: BotRun[];
};
export type BotRun = {
  id: number;
  started_at: string;
  finished_at: string | null;
  status: "running" | "ok" | "error";
  title: string | null;
  error: string | null;
  sources: number;
  model: string | null;
};
export type BotDraft = {
  name: string;
  color: string | null;
  prompt: string;
  output: BotOutput;
  every_minutes: number;
  at_minute: number | null;
  web_search: boolean;
  x_search: boolean;
  model: string;
  scopes: AgentScope[];
};

// Settings → Backend: what's deployed and configured (never a secret's value).
export type BackendStatus = {
  functions: { name: string; ok: boolean }[];
  secrets: Record<string, boolean> | null; // null: the admin function didn't answer
  latestMigration: string | null;
  expectedMigration: string;
  cron: { name: string; schedule: string; active: boolean }[] | null; // null: no pg_cron
  vault: { project_url: boolean; cron_secret: boolean } | null;
  calendars: number;
  lastCalendarSync: string | null;
  bots: number;
  lastBotRun: string | null;
  projectRef: string | null;
};
