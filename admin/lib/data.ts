import "server-only";
import { FunctionsHttpError, type SupabaseClient } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { cache } from "react";
import { accountVoice, type KokoroVoice } from "@/lib/account-voice";
import type { AskTurn } from "@/lib/ask-turns";
import { EMPTY_OPTIONS, type DashboardPart, type DashboardSourceOptions } from "@/lib/dashboard-sources";
import * as demo from "@/lib/demo/store";
import { demoMode, supabaseConfig, supabaseProjectUrl } from "@/lib/env";
import { DataError } from "@/lib/errors";
import type { QuoteLatestRow } from "@/lib/holdings";
import type { SeriesPoint } from "@/lib/series";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type {
  Admin,
  AgentKind,
  AgentRow,
  AgentScope,
  BackendStatus,
  Bot,
  BotDraft,
  BotRun,
  CalendarSource,
  DisplaySettings,
  MemoryNote,
  AuditEntry,
  Brief,
  DashboardRow,
  Device,
  EventRow,
  GoogleAccount,
  GoogleCalendar,
  IngestEntry,
  MetricRow,
  NewAgent,
  NewsReportDetail,
  NewsReportRow,
  Overview,
  Page,
  ProjectRow,
  ProjectUpdate,
  QuoteRow,
  Settings,
  SettingsPatch,
} from "@/lib/types";

// The console's only door to data. Every page and server action calls these
// functions; each one picks the source per request: the in-memory fixtures in
// demo mode (lib/demo), otherwise Supabase as the signed-in admin. The
// database enforces admin rights itself (every admin_* RPC checks
// is_platform_admin()), so nothing here relies on the proxy having run.
// This app never holds the service role key: the two things that need it
// (finishing a display's auth user, pairing) go through the edge functions
// with the admin's own JWT.

export { DataError };
export const PAGE_SIZE = 50;

type Source = { demo: true } | { demo: false; db: SupabaseClient };

const NOT_CONFIGURED =
  "Supabase isn't configured. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY (see admin/README.md).";
export const NOT_ADMIN = "That account isn't a McFly admin. The first account to sign up becomes the admin.";

// One source per request. connection() keeps every caller out of static
// prerendering, so the environment is always read at request time.
const source = cache(async (): Promise<Source> => {
  await connection();
  if (demoMode()) return { demo: true };
  const config = supabaseConfig();
  if (!config) throw new DataError(NOT_CONFIGURED);
  return { demo: false, db: await createSupabaseServerClient(config) };
});

export async function isDemo(): Promise<boolean> {
  await connection();
  return demoMode();
}

async function rpc<T>(db: SupabaseClient, fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) {
    console.error(`rpc ${fn} failed:`, error.message);
    throw new DataError(error.message);
  }
  return data as T;
}

// Calls an edge function (`admin`, `pair-device`; spec §2.2 and §2.3) with
// the admin's own JWT: the SSR client attaches the session's access token.
// The function holds the service role key; this app never does.
async function invokeFunction<T>(db: SupabaseClient, name: string, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.functions.invoke(name, { body });
  if (error) {
    let message = error.message;
    if (error instanceof FunctionsHttpError) {
      try {
        const payload = (await error.context.json()) as { error?: string };
        if (payload.error) message = payload.error;
      } catch {
        // Not JSON; keep the generic message.
      }
    }
    console.error(`${name} ${String(body.action)} failed:`, message);
    throw new DataError(message);
  }
  return data as T;
}

const num = (v: unknown) => (typeof v === "number" ? v : Number(v ?? 0) || 0);
const numOrNull = (v: unknown) => (v == null || v === "" ? null : Number.isFinite(Number(v)) ? Number(v) : null);

function record<T extends object>(value: unknown, fn: string): T {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new DataError(`${fn} didn't come back from the database. Apply the platform migrations (supabase db push).`);
  }
  return value as T;
}

function list<T>(value: unknown, fn: string): T[] {
  if (value == null) return [];
  if (!Array.isArray(value)) {
    throw new DataError(`${fn} didn't come back as a list. Apply the platform migrations (supabase db push).`);
  }
  return value as T[];
}

const pageArgs = (page: number, size: number) => ({ lim: size + 1, off: Math.max(page - 1, 0) * size });
function paged<T>(rows: T[], page: number, size: number): Page<T> {
  return { rows: rows.slice(0, size), page, hasMore: rows.length > size };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ───────────────────────────── Auth ─────────────────────────────

type AdminState = { status: "admin"; admin: Admin } | { status: "signed_out" } | { status: "not_admin" };

const adminState = cache(async (): Promise<AdminState> => {
  const src = await source();
  if (src.demo) return { status: "admin", admin: demo.demoAdmin() };
  const { data } = await src.db.auth.getClaims();
  const claims = data?.claims;
  if (!claims?.sub) return { status: "signed_out" };
  const { data: isAdmin, error } = await src.db.rpc("is_platform_admin");
  if (error || isAdmin !== true) return { status: "not_admin" };
  return { status: "admin", admin: { id: claims.sub, email: typeof claims.email === "string" ? claims.email : "" } };
});

// The signed-in platform admin, or a redirect to /login.
export async function requireAdmin(): Promise<Admin> {
  let state: AdminState;
  try {
    state = await adminState();
  } catch (err) {
    // Only a missing project config is a sign-in problem. Other DataErrors
    // (a failed session read, for example) keep their sentence on the page.
    if (err instanceof DataError && err.message === NOT_CONFIGURED) redirect("/login?error=config");
    throw err;
  }
  if (state.status === "signed_out") redirect("/login");
  if (state.status === "not_admin") redirect("/login?error=not_admin");
  return state.admin;
}

// Signs in with email and password; only platform admins may stay signed in.
export async function signIn(email: string, password: string): Promise<{ error?: string }> {
  await connection();
  if (demoMode()) return {};
  const config = supabaseConfig();
  if (!config) return { error: NOT_CONFIGURED };
  const db = await createSupabaseServerClient(config);
  const { error } = await db.auth.signInWithPassword({ email, password });
  if (error) {
    return { error: error.code === "invalid_credentials" ? "Wrong email or password." : error.message };
  }
  const { data: isAdmin } = await db.rpc("is_platform_admin");
  if (isAdmin !== true) {
    await db.auth.signOut({ scope: "local" });
    return { error: NOT_ADMIN };
  }
  return {};
}

export async function signOut(): Promise<void> {
  const src = await source();
  if (!src.demo) await src.db.auth.signOut({ scope: "local" });
}

// ───────────────────────────── Reads ─────────────────────────────

export async function getOverview(): Promise<Overview> {
  const src = await source();
  const o = src.demo ? demo.demoOverview() : record<Overview>(await rpc(src.db, "admin_overview"), "admin_overview");
  return {
    agents: num(o.agents),
    agents_revoked: num(o.agents_revoked),
    pushes_24h: num(o.pushes_24h),
    errors_24h: num(o.errors_24h),
    briefs: num(o.briefs),
    briefs_24h: num(o.briefs_24h),
    symbols: num(o.symbols),
    quotes: num(o.quotes),
    news_reports: num(o.news_reports),
    latest_report: typeof o.latest_report === "string" ? o.latest_report : null,
    projects: num(o.projects),
    projects_blocked: num(o.projects_blocked),
    metrics: num(o.metrics),
    dashboards: num(o.dashboards),
    events_upcoming: num(o.events_upcoming),
    devices: num(o.devices),
    devices_online: num(o.devices_online),
    last_push_at: typeof o.last_push_at === "string" ? o.last_push_at : null,
  };
}

export async function listAgents(): Promise<AgentRow[]> {
  const src = await source();
  const rows = src.demo ? demo.demoListAgents() : list<AgentRow>(await rpc(src.db, "admin_list_agents"), "admin_list_agents");
  return rows.map((a) => ({
    ...a,
    kind: (["grok", "stocks", "news", "other"].includes(a.kind) ? a.kind : "other") as AgentKind,
    pushes_7d: num(a.pushes_7d),
    scopes: Array.isArray(a.scopes) ? a.scopes.filter((x): x is AgentScope => SCOPES.includes(x as AgentScope)) : [],
    memory_count: num(a.memory_count),
    key_prefix: a.key_prefix ?? null,
    key_created_at: a.key_created_at ?? null,
    last_error: a.last_error ?? null,
  }));
}

export async function listIngest(page: number, pageSize = PAGE_SIZE): Promise<Page<IngestEntry>> {
  const src = await source();
  const { lim, off } = pageArgs(page, pageSize);
  const rows = src.demo
    ? demo.demoListIngest(lim, off)
    : list<IngestEntry>(await rpc(src.db, "admin_list_ingest", { lim, off }), "admin_list_ingest");
  return paged(
    rows.map((e) => ({ ...e, id: num(e.id), count: num(e.count), status: e.status === "error" ? "error" : "ok" })),
    page,
    pageSize,
  );
}

export async function listBriefs(page: number): Promise<Page<Brief>> {
  const src = await source();
  const { lim, off } = pageArgs(page, PAGE_SIZE);
  const rows = src.demo
    ? demo.demoListBriefs(lim, off)
    : list<Brief>(await rpc(src.db, "admin_list_briefs", { lim, off }), "admin_list_briefs");
  return paged(rows, page, PAGE_SIZE);
}

export async function listQuotes(): Promise<QuoteRow[]> {
  const src = await source();
  const rows = src.demo ? demo.demoListQuotes() : list<QuoteRow>(await rpc(src.db, "admin_list_quotes"), "admin_list_quotes");
  // numeric comes back as a JSON number from PostgREST; an older backend
  // could send strings, so read whichever arrives.
  return rows.map((q) => ({
    ...q,
    sort_order: num(q.sort_order),
    hidden: q.hidden === true,
    price: numOrNull(q.price),
    change: numOrNull(q.change),
    change_pct: numOrNull(q.change_pct),
    history_count: num(q.history_count),
  }));
}

// Each symbol's newest push with what its agent added (`data`: the holding,
// signals and the day's numbers; lib/holdings.ts shapes it). A direct select
// of the quotes_latest view, as the display reads it: RLS lets the admin
// read it, so no migration. Optional: without it the prices still show.
export async function listQuoteData(): Promise<QuoteLatestRow[]> {
  const src = await source();
  if (src.demo) return demo.demoListQuoteData();
  const { data, error } = await src.db.from("quotes_latest").select("symbol,agent_id,as_of,created_at,data");
  if (error) {
    console.error("quotes_latest failed:", error.message);
    return [];
  }
  return Array.isArray(data) ? (data as QuoteLatestRow[]) : [];
}

export async function listNewsReports(lim = 30): Promise<NewsReportRow[]> {
  const src = await source();
  const rows = src.demo
    ? demo.demoListNewsReports(lim)
    : list<NewsReportRow>(await rpc(src.db, "admin_list_news_reports", { lim }), "admin_list_news_reports");
  return rows.map((r) => ({
    ...r,
    report_date: String(r.report_date).slice(0, 10),
    item_count: num(r.item_count),
    sections: Array.isArray(r.sections) ? r.sections.filter((s): s is string => typeof s === "string") : [],
  }));
}

// Cached per request: the page and its generateMetadata both ask.
export const getNewsReport = cache(async (id: string): Promise<NewsReportDetail | null> => {
  if (!UUID.test(id)) return null;
  const src = await source();
  if (src.demo) return demo.demoNewsReport(id);
  const { data, error } = await src.db.rpc("admin_news_report", { report: id });
  if (error) {
    if (/report not found/i.test(error.message)) return null;
    console.error("rpc admin_news_report failed:", error.message);
    throw new DataError(error.message);
  }
  const d = record<NewsReportDetail>(data, "admin_news_report");
  if (!d.report) throw new DataError("admin_news_report didn't include the report. Apply the platform migrations (supabase db push).");
  return {
    report: { ...d.report, report_date: String(d.report.report_date).slice(0, 10) },
    items: (d.items ?? []).map((i) => ({ ...i, section_order: num(i.section_order), position: num(i.position) })),
  };
});

export async function listDevices(): Promise<Device[]> {
  const src = await source();
  const rows = src.demo ? demo.demoListDevices() : list<Device>(await rpc(src.db, "admin_list_devices"), "admin_list_devices");
  return rows.map((d) => ({ ...d, settings: d.settings && typeof d.settings === "object" ? d.settings : {} }));
}

export async function updateDeviceSettings(id: string, patch: DisplaySettings): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoUpdateDeviceSettings(id, patch);
  await rpc(src.db, "admin_update_device_settings", { device: id, patch });
}

// The account's voice (lib/account-voice.ts): the displays' voice, or null
// with no display to hold it.
export async function getAccountVoice(): Promise<KokoroVoice | null> {
  return accountVoice(await listDevices());
}

// A Kokoro voice picked on the web: every display gets it, so the Pi, this
// console and the app all speak with it. Returns how many displays hold it
// (0: no display yet, the browser keeps the choice to itself).
export async function setAccountVoice(voice: KokoroVoice): Promise<number> {
  const devices = await listDevices();
  for (const d of devices) await updateDeviceSettings(d.id, { voice });
  return devices.length;
}

export async function getSettings(): Promise<Settings> {
  const src = await source();
  const s = src.demo ? demo.demoSettings() : record<Settings>(await rpc(src.db, "admin_get_settings"), "admin_get_settings");
  return {
    display_name: String(s.display_name ?? ""),
    timezone: String(s.timezone ?? ""),
    briefs_keep_days: num(s.briefs_keep_days),
    quotes_keep_days: num(s.quotes_keep_days),
    news_keep_reports: num(s.news_keep_reports),
    assistant_provider: s.assistant_provider === "grok" ? "grok" : "claude",
    metrics_keep_days: num(s.metrics_keep_days) || 90,
    events_keep_days: num(s.events_keep_days) || 60,
    updated_at: s.updated_at ?? null,
    updated_by: s.updated_by ?? null,
  };
}

export async function listAudit(page: number, pageSize = PAGE_SIZE): Promise<Page<AuditEntry>> {
  const src = await source();
  const { lim, off } = pageArgs(page, pageSize);
  const rows = src.demo
    ? demo.demoListAudit(lim, off)
    : list<AuditEntry>(await rpc(src.db, "admin_list_audit", { lim, off }), "admin_list_audit");
  return paged(
    rows.map((e) => ({ ...e, id: num(e.id), details: e.details && typeof e.details === "object" ? e.details : {} })),
    page,
    pageSize,
  );
}

// ───────────────────── History: series and the push log ─────────────────────
// Direct selects, not admin_* RPCs. RLS already lets the admin read these
// rows (quotes_read and metrics_read through can_read(), ingest_log_read
// through is_platform_admin()), the same rows the display reads for its
// sparklines (display/src/models/FeedStore.cpp), so the database still decides
// who sees what and no migration is needed. Reads only: nothing to audit.

// Supabase answers at most this many rows per request (its default Max Rows),
// so asking for more would be cut without a word. A key pushed every 15
// minutes fills it in about ten days; a series' first point says how far back
// it really reaches.
const HISTORY_ROW_LIMIT = 1000;
const SERIES_MAX_KEYS = 24;
const SERIES_TABLES = {
  quotes: { table: "quotes", key: "symbol", value: "price" },
  metrics: { table: "metrics", key: "key", value: "value" },
} as const;

// A month of history barely moves in an hour, but the Today page asks again
// every minute in every open tab, and a full read is up to 1000 rows a key
// (about 60 KB). So each server instance keeps what it read for an hour,
// per admin and per key. The page adds the latest row to the end itself
// (lib/today.ts toTicker / toMetric), so a sparkline still ends on the
// current value. Only an admin's reads are kept, under their own id, and
// served back only to them after this request's own admin check: rows never
// cross from one session to another. A view or RPC that thinned the rows in
// the database would cut the full read too, but that is a migration.
const HISTORY_TTL_MS = 60 * 60_000;
const HISTORY_MAX_ENTRIES = 256;
type HistoryEntry = { at: number; kind: "quotes" | "metrics"; key: string; points: Promise<SeriesPoint[]> };
const historyCache = new Map<string, HistoryEntry>();

// The cached promise is shared, so two tabs refreshing together make one
// read; a failed read isn't kept. listSeries hands out copies.
function rememberSeries(cacheKey: string, kind: HistoryEntry["kind"], key: string, now: number, read: () => Promise<SeriesPoint[]>) {
  const hit = historyCache.get(cacheKey);
  if (hit && now - hit.at < HISTORY_TTL_MS) return hit.points;
  for (const [k, e] of historyCache) if (k === cacheKey || now - e.at >= HISTORY_TTL_MS) historyCache.delete(k);
  while (historyCache.size >= HISTORY_MAX_ENTRIES) historyCache.delete(historyCache.keys().next().value!);
  const points = read();
  historyCache.set(cacheKey, { at: now, kind, key, points });
  points.catch(() => {
    if (historyCache.get(cacheKey)?.points === points) historyCache.delete(cacheKey);
  });
  return points;
}

// After the console deletes rows (a symbol, a metric, an agent and every row
// it pushed), so this instance doesn't draw them for another hour.
function forgetSeries(match: (e: HistoryEntry) => boolean) {
  for (const [k, e] of historyCache) if (match(e)) historyCache.delete(k);
}

const clampTo = (n: number, lo: number, hi: number, fallback: number) => (Number.isFinite(n) ? Math.min(Math.max(n, lo), hi) : fallback);

// Rows newest first in, points oldest → newest out; unreadable rows dropped.
function toSeries(rows: unknown, valueColumn: string): SeriesPoint[] {
  if (!Array.isArray(rows)) return [];
  const out: SeriesPoint[] = [];
  for (const row of rows as Record<string, unknown>[]) {
    const t = Date.parse(String(row.as_of));
    const v = numOrNull(row[valueColumn]);
    if (Number.isFinite(t) && v != null) out.push({ t, v });
  }
  return out.reverse();
}

// Each key's history over the last `days`, oldest → newest. Every key asked
// for is in the result, with [] when it has no rows in the window. Up to an
// hour old (see HISTORY_TTL_MS): the latest row is the caller's to add.
export async function listSeries(kind: "quotes" | "metrics", keys: string[], days: number): Promise<Record<string, SeriesPoint[]>> {
  const wanted = [...new Set(keys.filter((k) => typeof k === "string" && k.length > 0 && k.length <= 64))].slice(0, SERIES_MAX_KEYS);
  const span = clampTo(days, 1, 365, 30);
  const src = await source();
  if (src.demo) return demo.demoListSeries(kind, wanted, span, HISTORY_ROW_LIMIT);
  const { db } = src;
  const state = await adminState();
  const owner = state.status === "admin" ? state.admin.id : null;
  const { table, key, value } = SERIES_TABLES[kind];
  const now = Date.now();
  // One request per key, newest first: the row limit then trims the old end
  // of a busy key, and a busy key can't crowd a quiet one out.
  const read = async (k: string) => {
    const { data, error } = await db
      .from(table)
      .select(`${value},as_of`)
      .eq(key, k)
      .gte("as_of", new Date(Date.now() - span * 86_400_000).toISOString())
      .order("as_of", { ascending: false })
      .order("id", { ascending: false })
      .limit(HISTORY_ROW_LIMIT);
    if (error) {
      console.error(`${table} history failed:`, error.message);
      throw new DataError(error.message);
    }
    return toSeries(data, value);
  };
  // A copy of each kept series: whatever the caller does to it, the next
  // refresh still gets the history as read.
  const entries = await Promise.all(
    wanted.map(async (k) => [k, owner ? (await rememberSeries(`${owner}\n${kind}\n${span}\n${k}`, kind, k, now, () => read(k))).slice() : await read(k)] as const),
  );
  return Object.fromEntries(entries);
}

// Every push in the last `hours`, newest first, with its agent's name and
// colour (the same rows listIngest pages through). `status` narrows it: the
// Today page wants only the refused ones, a handful where a day of ok rows
// can be 1000 (about 200 KB with the agents) every minute.
export async function listIngestSince(hours: number, opts: { status?: "ok" | "error" } = {}): Promise<IngestEntry[]> {
  // Up to two weeks: judging a quiet agent takes a week and a bit of it.
  const span = clampTo(hours, 1, 24 * 14, 24);
  const src = await source();
  if (src.demo) return demo.demoListIngestSince(span, HISTORY_ROW_LIMIT, opts.status);
  const since = new Date(Date.now() - span * 3_600_000).toISOString();
  let query = src.db
    .from("ingest_log")
    .select("id,created_at,agent_id,feed,count,status,message,agents(name,color)")
    .gte("created_at", since);
  if (opts.status) query = query.eq("status", opts.status);
  const { data, error } = await query
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(HISTORY_ROW_LIMIT);
  if (error) {
    console.error("ingest_log read failed:", error.message);
    throw new DataError(error.message);
  }
  return (Array.isArray(data) ? (data as Record<string, unknown>[]) : []).map((e) => {
    const embedded = Array.isArray(e.agents) ? e.agents[0] : e.agents;
    const agent = embedded && typeof embedded === "object" ? (embedded as { name?: unknown; color?: unknown }) : null;
    return {
      id: num(e.id),
      created_at: String(e.created_at),
      agent_id: typeof e.agent_id === "string" ? e.agent_id : null,
      agent_name: typeof agent?.name === "string" ? agent.name : null,
      agent_color: typeof agent?.color === "string" ? agent.color : null,
      feed: String(e.feed ?? ""),
      count: num(e.count),
      status: e.status === "error" ? "error" : "ok",
      message: typeof e.message === "string" ? e.message : null,
    };
  });
}

// ─────────────────────────── Mutations ───────────────────────────
// Server actions call these after requireAdmin(); the RPCs and the functions
// check admin rights again and write the audit log.

export async function createAgent(name: string, kind: AgentKind, color: string | null): Promise<NewAgent> {
  const src = await source();
  if (src.demo) return demo.demoCreateAgent(name, kind, color);
  const rows = await rpc<NewAgent[] | NewAgent>(src.db, "admin_create_agent", { name, kind, color });
  const agent = Array.isArray(rows) ? rows[0] : rows;
  if (!agent?.key) throw new DataError("The agent wasn't created.");
  return agent;
}

// Returns the new key, shown once. Revives a revoked agent.
export async function rotateAgentKey(id: string): Promise<string> {
  const src = await source();
  if (src.demo) return demo.demoRotateAgentKey(id);
  const key = await rpc<string>(src.db, "admin_rotate_agent_key", { agent: id });
  if (typeof key !== "string" || !key) throw new DataError("The key wasn't rotated.");
  return key;
}

export async function updateAgent(id: string, patch: { name?: string; kind?: AgentKind; color?: string }): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoUpdateAgent(id, patch);
  await rpc(src.db, "admin_update_agent", {
    agent: id,
    name: patch.name ?? null,
    kind: patch.kind ?? null,
    color: patch.color ?? null,
  });
}

export async function revokeAgent(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoRevokeAgent(id);
  await rpc(src.db, "admin_revoke_agent", { agent: id });
}

export async function deleteAgent(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteAgent(id);
  await rpc(src.db, "admin_delete_agent", { agent: id });
  forgetSeries(() => true); // its quotes and metrics went with it
}

export async function deleteBrief(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteBrief(id);
  await rpc(src.db, "admin_delete_brief", { brief: id });
}

export async function setSymbol(symbol: string, patch: { hidden?: boolean; sort_order?: number; name?: string }): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoSetSymbol(symbol, patch);
  await rpc(src.db, "admin_set_symbol", {
    symbol,
    hidden: patch.hidden ?? null,
    sort_order: patch.sort_order ?? null,
    name: patch.name ?? null,
  });
}

export async function deleteSymbol(symbol: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteSymbol(symbol);
  await rpc(src.db, "admin_delete_symbol", { symbol });
  forgetSeries((e) => e.kind === "quotes" && e.key === symbol);
}

export async function deleteNewsReport(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteNewsReport(id);
  await rpc(src.db, "admin_delete_news_report", { report: id });
}

export async function renameDevice(id: string, name: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoRenameDevice(id, name);
  await rpc(src.db, "admin_rename_device", { device: id, name });
}

// Through the `admin` edge function (spec §2.3): admin_revoke_device drops
// the row as this admin, and the function removes the display's auth user
// with the service role when the database could not.
export async function revokeDevice(id: string): Promise<{ authUserRemoved: boolean }> {
  const src = await source();
  if (src.demo) return { authUserRemoved: demo.demoRevokeDevice(id).auth_user_removed };
  const result = await invokeFunction<{ ok?: boolean; auth_user_removed?: boolean }>(src.db, "admin", {
    action: "revoke_device",
    device_id: id,
  });
  return { authUserRemoved: result?.auth_user_removed === true };
}

// Through the `pair-device` edge function (spec §2.2, `claim`), as this
// admin: the function checks is_platform_admin with the same JWT.
export async function claimDevice(code: string, name: string | null): Promise<{ deviceId: string }> {
  const src = await source();
  if (src.demo) return demo.demoClaimDevice(code, name);
  const result = await invokeFunction<{ deviceId?: string }>(src.db, "pair-device", {
    action: "claim",
    code,
    ...(name ? { name } : {}),
  });
  if (!result?.deviceId) throw new DataError("The display wasn't paired.");
  return { deviceId: result.deviceId };
}

export async function updateSettings(patch: SettingsPatch): Promise<void> {
  const src = await source();
  if (src.demo) {
    demo.demoUpdateSettings(patch);
    return;
  }
  await rpc(src.db, "admin_update_settings", {
    display_name: patch.display_name ?? null,
    timezone: patch.timezone ?? null,
    briefs_keep_days: patch.briefs_keep_days ?? null,
    quotes_keep_days: patch.quotes_keep_days ?? null,
    news_keep_reports: patch.news_keep_reports ?? null,
    assistant_provider: patch.assistant_provider ?? null,
    metrics_keep_days: patch.metrics_keep_days ?? null,
    events_keep_days: patch.events_keep_days ?? null,
  });
}

// ───────────────────── Productivity feeds ─────────────────────
// (backend/supabase/migrations/20261014000003_productivity.sql)

const PROJECT_KINDS = ["code", "task", "launch", "other"];
const PROJECT_STATUSES = ["active", "blocked", "paused", "done"];

export async function listProjects(): Promise<ProjectRow[]> {
  const src = await source();
  const rows = src.demo ? demo.demoListProjects() : list<ProjectRow>(await rpc(src.db, "admin_list_projects"), "admin_list_projects");
  return rows.map((p) => ({
    ...p,
    kind: (PROJECT_KINDS.includes(p.kind) ? p.kind : "other") as ProjectRow["kind"],
    status: (PROJECT_STATUSES.includes(p.status) ? p.status : "active") as ProjectRow["status"],
    progress: numOrNull(p.progress),
    summary: p.summary ?? "",
    sort_order: num(p.sort_order),
    update_count: num(p.update_count),
    last_update: p.last_update ?? null,
    last_update_at: p.last_update_at ?? null,
  }));
}

// There is no single-project RPC; the list is small and already carries
// everything the page shows.
export const getProject = cache(async (id: string): Promise<ProjectRow | null> => {
  if (!UUID.test(id)) return null;
  return (await listProjects()).find((p) => p.id === id) ?? null;
});

export async function getProjectUpdates(id: string, lim = 50): Promise<ProjectUpdate[]> {
  const src = await source();
  const rows = src.demo
    ? demo.demoProjectUpdates(id, lim)
    : list<ProjectUpdate>(await rpc(src.db, "admin_project_updates", { project: id, lim }), "admin_project_updates");
  return rows.map((u) => ({ ...u, id: num(u.id), url: u.url ?? null }));
}

export async function deleteProject(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteProject(id);
  await rpc(src.db, "admin_delete_project", { project: id });
}

export async function listMetrics(): Promise<MetricRow[]> {
  const src = await source();
  const rows = src.demo ? demo.demoListMetrics() : list<MetricRow>(await rpc(src.db, "admin_list_metrics"), "admin_list_metrics");
  return rows.map((m) => ({
    ...m,
    label: m.label ?? m.key,
    group_name: m.group_name ?? null,
    sort_order: num(m.sort_order),
    hidden: m.hidden === true,
    value: numOrNull(m.value),
    delta: numOrNull(m.delta),
    delta_pct: numOrNull(m.delta_pct),
    history_count: num(m.history_count),
  }));
}

export async function setMetric(
  key: string,
  patch: { hidden?: boolean; sort_order?: number; label?: string; group_name?: string },
): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoSetMetric(key, patch);
  await rpc(src.db, "admin_set_metric", {
    metric: key,
    hidden: patch.hidden ?? null,
    sort_order: patch.sort_order ?? null,
    label: patch.label ?? null,
    group_name: patch.group_name ?? null,
  });
}

export async function deleteMetric(key: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteMetric(key);
  await rpc(src.db, "admin_delete_metric", { metric: key });
  forgetSeries((e) => e.kind === "metrics" && e.key === key);
}

export async function listDashboards(): Promise<DashboardRow[]> {
  const src = await source();
  const rows = src.demo ? demo.demoListDashboards() : list<DashboardRow>(await rpc(src.db, "admin_list_dashboards"), "admin_list_dashboards");
  return rows.map((d) => ({
    ...d,
    subtitle: d.subtitle ?? null,
    widgets: Array.isArray(d.widgets) ? d.widgets : [],
    sort_order: num(d.sort_order),
    hidden: d.hidden === true,
    template: typeof d.template === "string" ? d.template : null,
    sources: Array.isArray(d.sources) ? d.sources : null,
  }));
}

// As with projects: the list carries the widgets, so one row is a filter.
export const getDashboard = cache(async (id: string): Promise<DashboardRow | null> => {
  if (!UUID.test(id)) return null;
  return (await listDashboards()).find((d) => d.id === id) ?? null;
});

export async function setDashboard(id: string, patch: { hidden?: boolean; sort_order?: number }): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoSetDashboard(id, patch);
  await rpc(src.db, "admin_set_dashboard", { dashboard: id, hidden: patch.hidden ?? null, sort_order: patch.sort_order ?? null });
}

export async function deleteDashboard(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteDashboard(id);
  await rpc(src.db, "admin_delete_dashboard", { dashboard: id });
}

// What a made board can pull from, for the builder's pickers.
export async function getDashboardSourceOptions(): Promise<DashboardSourceOptions> {
  const src = await source();
  const raw = src.demo ? demo.demoDashboardSources() : record<Partial<DashboardSourceOptions>>(await rpc(src.db, "admin_dashboard_sources"), "admin_dashboard_sources");
  const arr = <T,>(v: T[] | undefined) => (Array.isArray(v) ? v : []);
  return {
    symbols: arr(raw.symbols),
    metrics: arr(raw.metrics),
    projects: arr(raw.projects),
    calendars: arr(raw.calendars).filter((c): c is string => typeof c === "string"),
    news_sections: arr(raw.news_sections),
    agents: arr(raw.agents),
    timezone: typeof raw.timezone === "string" ? raw.timezone : EMPTY_OPTIONS.timezone,
  };
}

// The widgets a recipe draws right now, before it is saved.
export async function previewDashboard(parts: DashboardPart[]): Promise<unknown[]> {
  const src = await source();
  if (src.demo) return demo.demoPreviewDashboard(parts);
  return list<unknown>(await rpc(src.db, "admin_preview_dashboard", { sources: parts }), "admin_preview_dashboard");
}

// Makes a board (no id) or changes a made one; the database draws it and
// keeps it drawn. Returns its id.
export async function saveDashboard(input: { id: string | null; title: string; subtitle: string | null; template: string | null; parts: DashboardPart[] }): Promise<string> {
  const src = await source();
  if (src.demo) return demo.demoSaveDashboard(input);
  const id = await rpc<string>(src.db, "admin_save_dashboard", {
    dashboard: input.id,
    title: input.title,
    sources: input.parts,
    subtitle: input.subtitle,
    template: input.template,
  });
  if (typeof id !== "string") throw new DataError("admin_save_dashboard didn't come back from the database. Apply the platform migrations (supabase db push).");
  return id;
}

export async function listEvents(daysBack = 7, daysAhead = 60): Promise<EventRow[]> {
  const src = await source();
  const rows = src.demo
    ? demo.demoListEvents(daysBack, daysAhead)
    : list<EventRow>(await rpc(src.db, "admin_list_events", { days_back: daysBack, days_ahead: daysAhead }), "admin_list_events");
  return rows.map((e) => ({ ...e, all_day: e.all_day === true, location: e.location ?? null, color: e.color ?? null, url: e.url ?? null }));
}

export async function deleteEvent(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteEvent(id);
  await rpc(src.db, "admin_delete_event", { event: id });
}

// Returns how many events went with it.
export async function deleteCalendar(agentId: string, calendar: string): Promise<number> {
  const src = await source();
  if (src.demo) return demo.demoDeleteCalendar(agentId, calendar);
  return num(await rpc(src.db, "admin_delete_calendar", { agent: agentId, calendar }));
}

// ───────────────────────────── Scopes and memory ─────────────────────────────

const SCOPES: AgentScope[] = ["memory:read", "memory:write", "calendar:read"];

export async function setAgentScopes(id: string, scopes: AgentScope[]): Promise<AgentScope[]> {
  const src = await source();
  if (src.demo) return demo.demoSetAgentScopes(id, scopes);
  const saved = await rpc<string[]>(src.db, "admin_set_agent_scopes", { agent: id, scopes });
  return (Array.isArray(saved) ? saved : []).filter((x): x is AgentScope => SCOPES.includes(x as AgentScope));
}

export async function listMemories(): Promise<MemoryNote[]> {
  const src = await source();
  const rows = src.demo ? demo.demoListMemories() : list<MemoryNote>(await rpc(src.db, "admin_list_memories"), "admin_list_memories");
  return rows.map((m) => ({ ...m, pinned: m.pinned === true, source: m.source === "agent" ? "agent" : "admin", key: m.key ?? null }));
}

export async function saveMemory(note: { id?: string | null; text?: string | null; pinned?: boolean | null; agentId?: string | null }): Promise<string> {
  const src = await source();
  if (src.demo) return demo.demoSaveMemory(note.id ?? null, note.text ?? null, note.pinned ?? null, note.agentId ?? null);
  return rpc<string>(src.db, "admin_save_memory", {
    id: note.id ?? null,
    text: note.text ?? null,
    pinned: note.pinned ?? null,
    agent: note.agentId ?? null,
  });
}

export async function deleteMemory(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteMemory(id);
  await rpc(src.db, "admin_delete_memory", { memory: id });
}

// ───────────────────────────── Calendar subscriptions ─────────────────────────────

export async function listCalendarSources(): Promise<CalendarSource[]> {
  const src = await source();
  const rows = src.demo
    ? demo.demoListCalendarSources()
    : list<CalendarSource>(await rpc(src.db, "admin_list_calendar_sources"), "admin_list_calendar_sources");
  return rows.map((c) => ({
    ...c,
    enabled: c.enabled !== false,
    event_count: num(c.event_count),
    color: c.color ?? null,
    kind: c.kind === "google" ? "google" : "ical",
    account_id: c.account_id ?? null,
    account_email: c.account_email ?? null,
    google_calendar_id: c.google_calendar_id ?? null,
    watch_expires_at: c.watch_expires_at ?? null,
    watch_error: c.watch_error ?? null,
  }));
}

export async function addCalendarSource(name: string, url: string, color: string | null): Promise<string> {
  const src = await source();
  if (src.demo) return demo.demoAddCalendarSource(name, url, color);
  return rpc<string>(src.db, "admin_add_calendar_source", { name, url, color });
}

export async function updateCalendarSource(id: string, patch: { name?: string; color?: string; enabled?: boolean }): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoUpdateCalendarSource(id, patch);
  await rpc(src.db, "admin_update_calendar_source", { source: id, name: patch.name ?? null, color: patch.color ?? null, enabled: patch.enabled ?? null });
}

export async function deleteCalendarSource(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteCalendarSource(id);
  await rpc(src.db, "admin_delete_calendar_source", { source: id });
}

// Reads the link now (the calendar-sync function, with the admin's JWT).
export async function syncCalendarSource(id: string): Promise<{ count?: number; error?: string }> {
  const src = await source();
  if (src.demo) return demo.demoSyncCalendarSource(id);
  const res = await invokeFunction<{ synced?: { count?: number; error?: string }[] }>(src.db, "calendar-sync", { source: id });
  return res.synced?.[0] ?? { error: "that calendar is paused or gone" };
}

// ───────────────────────────── Google accounts ─────────────────────────────
// The sign-in itself happens in the google-calendar function (spec §2.5):
// this app sends the admin there and reads back what it may see.

export async function listGoogleAccounts(): Promise<GoogleAccount[]> {
  const src = await source();
  const rows = src.demo
    ? demo.demoListGoogleAccounts()
    : list<GoogleAccount>(await rpc(src.db, "admin_list_google_accounts"), "admin_list_google_accounts");
  return rows.map((a) => ({ ...a, calendars: num(a.calendars), last_error: a.last_error ?? null }));
}

// The account's calendars, from Google (the function refreshes the token and
// asks). A failure is a sentence for the page, not an exception, so the rest
// of the page still renders with what is subscribed.
export async function listGoogleCalendars(accountId: string): Promise<{ calendars: GoogleCalendar[] } | { error: string }> {
  const src = await source();
  if (src.demo) return demo.demoListGoogleCalendars(accountId);
  try {
    const res = await invokeFunction<{ calendars?: GoogleCalendar[] }>(src.db, "google-calendar", { action: "calendars", account: accountId });
    return { calendars: Array.isArray(res.calendars) ? res.calendars : [] };
  } catch (err) {
    return { error: err instanceof DataError ? err.message : "couldn't reach Google" };
  }
}

// Where the admin's browser goes to sign in. `returnTo` is this console's
// Calendars page; `email` preselects an account (connecting one again).
export async function beginGoogleConnect(returnTo: string, email: string | null): Promise<string> {
  const src = await source();
  if (src.demo) return demo.demoConnectGoogle(returnTo);
  const res = await invokeFunction<{ url?: string }>(src.db, "google-calendar", { action: "connect", return_to: returnTo, ...(email ? { email } : {}) });
  if (typeof res.url !== "string" || !/^https:\/\/accounts\.google\.com\//.test(res.url)) {
    throw new DataError("Google's sign-in didn't start; check Settings → Backend.");
  }
  return res.url;
}

// Revokes at Google and removes the account, its calendars and their events.
export async function disconnectGoogleAccount(id: string): Promise<string> {
  const src = await source();
  if (src.demo) return demo.demoDisconnectGoogleAccount(id);
  const res = await invokeFunction<{ email?: string }>(src.db, "google-calendar", { action: "disconnect", account: id });
  return typeof res.email === "string" ? res.email : "The account";
}

export async function addGoogleCalendar(account: string, calendarId: string, name: string, color: string | null): Promise<string> {
  const src = await source();
  if (src.demo) return demo.demoAddGoogleCalendar(account, calendarId, name, color);
  return rpc<string>(src.db, "admin_add_google_calendar", { account, calendar_id: calendarId, name, color });
}

// ───────────────────────────── Grok bots ─────────────────────────────

// The runs are a read per bot; `runs: false` skips them (the ⌘K index only
// needs the names) and leaves each bot's list empty.
export async function listBots({ runs: withRuns = true }: { runs?: boolean } = {}): Promise<Bot[]> {
  const src = await source();
  if (src.demo) return demo.demoListBots();
  const rows = list<Omit<Bot, "runs">>(await rpc(src.db, "admin_list_bots"), "admin_list_bots");
  const runs = withRuns
    ? await Promise.all(rows.map((b) => rpc<BotRun[]>(src.db, "admin_list_bot_runs", { bot: b.id, lim: 5 }).catch(() => [])))
    : rows.map(() => []);
  return rows.map((b, i) => ({
    ...b,
    scopes: Array.isArray(b.scopes) ? b.scopes.filter((x): x is AgentScope => SCOPES.includes(x as AgentScope)) : [],
    every_minutes: num(b.every_minutes),
    at_minute: b.at_minute == null ? null : num(b.at_minute),
    runs_7d: num(b.runs_7d),
    runs: (Array.isArray(runs[i]) ? runs[i] : []).map((r) => ({ ...r, id: num(r.id), sources: num(r.sources) })),
  }));
}

export async function saveBot(id: string | null, draft: Partial<BotDraft> & { enabled?: boolean }): Promise<string> {
  const src = await source();
  if (src.demo) return demo.demoSaveBot(id, draft);
  return rpc<string>(src.db, "admin_save_bot", {
    id,
    name: draft.name ?? null,
    color: draft.color ?? null,
    prompt: draft.prompt ?? null,
    output: draft.output ?? null,
    every_minutes: draft.every_minutes ?? null,
    at_minute: draft.at_minute ?? null,
    clear_at_minute: "at_minute" in draft && draft.at_minute === null,
    web_search: draft.web_search ?? null,
    x_search: draft.x_search ?? null,
    model: draft.model ?? null,
    enabled: draft.enabled ?? null,
    scopes: draft.scopes ?? null,
  });
}

export async function deleteBot(id: string): Promise<void> {
  const src = await source();
  if (src.demo) return demo.demoDeleteBot(id);
  await rpc(src.db, "admin_delete_bot", { bot: id });
}

// Runs a bot now (the bots function, with the admin's JWT). Up to ~2 minutes.
export async function runBot(id: string): Promise<{ title?: string; error?: string }> {
  const src = await source();
  if (src.demo) return demo.demoRunBot(id);
  const res = await invokeFunction<{ ran?: { title?: string; error?: string }[] }>(src.db, "bots", { bot: id });
  return res.ran?.[0] ?? { error: "the bot didn't run" };
}

// ───────────────────────────── Assistant (web voice and chat) ─────────────────────────────

export type { AskTurn };

// The assistant's answer as a text/event-stream (delta…, then done or error),
// asked with the admin's own JWT, so it sees what they see. The token stays on
// the server: the browser talks to /api/ask, never to Supabase.
// chat: a few sentences (Today's Ask bar). quick: spoken (/voice). read: the
// full-screen Ask (/ask), longer and in Markdown.
export type AskMode = "chat" | "quick" | "read";

export async function askAssistant(message: string, history: AskTurn[], mode: AskMode): Promise<Response> {
  const src = await source();
  if (src.demo) return demo.demoAsk(message, mode);
  const { data } = await src.db.auth.getSession();
  const token = data.session?.access_token;
  const config = supabaseConfig();
  if (!token || !config) throw new DataError("sign in again");
  return fetch(`${config.url}/functions/v1/assistant`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, apikey: config.anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ message, history, mode, stream: true }),
  });
}

// ───────────────────────────── Backend status ─────────────────────────────

// The newest migration this console was built for (backend/supabase/migrations).
export const EXPECTED_MIGRATION = "20261016000011";
const FUNCTIONS = ["ingest", "pair-device", "admin", "assistant", "calendar-sync", "bots", "google-calendar"];

export async function getBackendStatus(): Promise<BackendStatus> {
  const src = await source();
  if (src.demo) return demo.demoBackendStatus(EXPECTED_MIGRATION);
  const base = supabaseProjectUrl()!;
  const [db, fn, functions] = await Promise.all([
    rpc<Record<string, unknown>>(src.db, "admin_backend_status").catch(() => null),
    invokeFunction<{ secrets?: Record<string, boolean> }>(src.db, "admin", { action: "status" }).catch(() => null),
    Promise.all(
      FUNCTIONS.map(async (name) => {
        // A deployed function answers the CORS preflight; a missing one is a 404.
        const res = await fetch(`${base}/functions/v1/${name}`, { method: "OPTIONS", signal: AbortSignal.timeout(8000) }).catch(() => null);
        return { name, ok: !!res && res.ok };
      }),
    ),
  ]);
  const cron = Array.isArray(db?.cron) ? (db.cron as BackendStatus["cron"]) : null;
  const vault = db?.vault && typeof db.vault === "object" ? (db.vault as BackendStatus["vault"]) : null;
  return {
    functions,
    secrets: fn?.secrets ?? null,
    latestMigration: typeof db?.latest_migration === "string" ? db.latest_migration : null,
    expectedMigration: EXPECTED_MIGRATION,
    cron,
    vault,
    calendars: num(db?.calendars),
    lastCalendarSync: typeof db?.last_calendar_sync === "string" ? db.last_calendar_sync : null,
    bots: num(db?.bots),
    lastBotRun: typeof db?.last_bot_run === "string" ? db.last_bot_run : null,
    projectRef: new URL(base).host.split(".")[0] ?? null,
  };
}
