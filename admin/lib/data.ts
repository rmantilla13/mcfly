import "server-only";
import { FunctionsHttpError, type SupabaseClient } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { cache } from "react";
import * as demo from "@/lib/demo/store";
import { demoMode, supabaseConfig } from "@/lib/env";
import { DataError } from "@/lib/errors";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type {
  Admin,
  AgentKind,
  AgentRow,
  AuditEntry,
  Brief,
  DashboardRow,
  Device,
  EventRow,
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
  return src.demo ? demo.demoListDevices() : list<Device>(await rpc(src.db, "admin_list_devices"), "admin_list_devices");
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
