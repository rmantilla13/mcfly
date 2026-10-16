import "server-only";
import { buildDemoState, type DemoAgent, type DemoState } from "@/lib/demo/fixtures";
import { DataError } from "@/lib/errors";
import { dayKey, dayLabel, safeTimeZone } from "@/lib/events";
import { formatPrice, ONLINE_WINDOW_MS } from "@/lib/format";
import type { QuoteLatestRow } from "@/lib/holdings";
import { agoLabel, buildInsights, clip } from "@/lib/insights";
import { rangeOf, windowChange, type SeriesPoint } from "@/lib/series";
import { metricRows, SERIES_DAYS, tickerRows, todayFacts, toTicker, untilLabel, type TodayFacts } from "@/lib/today";
import { formatMetricValue } from "@/lib/widgets";
import type {
  BackendStatus,
  Bot,
  BotDraft,
  AgentScope,
  CalendarSource,
  DisplaySettings,
  MemoryNote,
  AgentKind,
  AgentRow,
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
  ProjectRow,
  ProjectUpdate,
  QuoteRow,
  Settings,
  SettingsPatch,
} from "@/lib/types";

// The in-memory backend behind demo mode. It mirrors the admin_* RPCs and
// the two edge functions closely enough to click through every flow;
// changes live in this server process only and reset on restart.

const globalForDemo = globalThis as typeof globalThis & { __mcflyAdminDemo?: DemoState };

function state(): DemoState {
  globalForDemo.__mcflyAdminDemo ??= buildDemoState();
  return globalForDemo.__mcflyAdminDemo;
}

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const since = (iso: string | null | undefined, ms: number) => !!iso && Date.now() - Date.parse(iso) < ms;

function audit(action: string, targetType: string | null, targetId: string | null, details: Record<string, unknown>) {
  const s = state();
  s.audit.unshift({
    id: s.nextAuditId++,
    created_at: new Date().toISOString(),
    admin_email: s.admin.email,
    action,
    target_type: targetType,
    target_id: targetId,
    details,
  });
}

function findAgent(id: string): DemoAgent {
  const agent = state().agents.find((a) => a.id === id);
  if (!agent) throw new DataError("agent not found");
  return agent;
}

// A fake key with the real shape: mcf_ plus 40 hex characters.
function newKey(): string {
  return "mcf_" + Array.from(crypto.getRandomValues(new Uint8Array(20)), (b) => b.toString(16).padStart(2, "0")).join("");
}

const slugify = (name: string) => name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40);

// The newest quote per symbol (the quotes_latest view).
function latestQuote(symbol: string) {
  return state()
    .quotes.filter((q) => q.symbol === symbol)
    .sort((a, b) => b.as_of.localeCompare(a.as_of) || b.id - a.id)[0];
}

// ───────────────────────────── Reads ─────────────────────────────

export function demoAdmin() {
  return state().admin;
}

export function demoOverview(): Overview {
  const s = state();
  const okPushes = s.ingest.filter((e) => e.status === "ok");
  const newestReport = [...s.reports].sort((a, b) => b.report_date.localeCompare(a.report_date) || b.published_at.localeCompare(a.published_at))[0];
  return {
    agents: s.agents.filter((a) => !a.revoked_at).length,
    agents_revoked: s.agents.filter((a) => a.revoked_at).length,
    pushes_24h: okPushes.filter((e) => since(e.created_at, DAY)).length,
    errors_24h: s.ingest.filter((e) => e.status === "error" && since(e.created_at, DAY)).length,
    briefs: s.briefs.length,
    briefs_24h: s.briefs.filter((b) => since(b.published_at, DAY)).length,
    symbols: s.symbols.filter((x) => !x.hidden).length,
    quotes: s.quotes.length,
    news_reports: s.reports.length,
    latest_report: newestReport?.slug ?? null,
    projects: s.projects.filter((p) => p.status !== "done").length,
    projects_blocked: s.projects.filter((p) => p.status === "blocked").length,
    metrics: s.metricSettings.filter((m) => !m.hidden).length,
    dashboards: s.dashboards.filter((d) => !d.hidden).length,
    events_upcoming: s.events.filter((e) => Date.parse(e.ends_at) >= Date.now() && Date.parse(e.starts_at) < Date.now() + 7 * DAY).length,
    devices: s.devices.length,
    devices_online: s.devices.filter((d) => since(d.last_seen_at, ONLINE_WINDOW_MS)).length,
    last_push_at: okPushes[0]?.created_at ?? null,
  };
}

export function demoListAgents(): AgentRow[] {
  const s = state();
  return [...s.agents]
    .sort((a, b) => Number(!!a.revoked_at) - Number(!!b.revoked_at) || a.created_at.localeCompare(b.created_at))
    .map((a) => ({
      ...a,
      scopes: a.scopes ?? [],
      memory_count: s.memories.filter((m) => m.agent_id === a.id).length,
      pushes_7d: s.ingest.filter((e) => e.agent_id === a.id && e.status === "ok" && since(e.created_at, 7 * DAY)).length,
      last_error: s.ingest.find((e) => e.agent_id === a.id && e.status === "error")?.message ?? null,
    }));
}

export function demoListBriefs(lim: number, off: number): Brief[] {
  const s = state();
  return [...s.briefs]
    .sort((a, b) => b.published_at.localeCompare(a.published_at))
    .slice(off, off + lim)
    .map((b) => {
      const agent = s.agents.find((a) => a.id === b.agent_id);
      return { ...b, agent_name: agent?.name ?? "?", agent_color: agent?.color ?? "#4F7CF7" };
    });
}

// The quotes_latest view's extras: what the stocks agent sent with each
// symbol's newest push. The demo has no created_at; its newest as_of is the push.
export function demoListQuoteData(): QuoteLatestRow[] {
  return state().symbols.flatMap((sym) => {
    const q = latestQuote(sym.symbol);
    return q ? [{ symbol: q.symbol, agent_id: q.agent_id, as_of: q.as_of, created_at: null, data: q.data ?? {} }] : [];
  });
}

export function demoListQuotes(): QuoteRow[] {
  const s = state();
  return [...s.symbols]
    .sort((a, b) => Number(a.hidden) - Number(b.hidden) || a.sort_order - b.sort_order || a.symbol.localeCompare(b.symbol))
    .map((sym) => {
      const latest = latestQuote(sym.symbol);
      const agent = latest ? s.agents.find((a) => a.id === latest.agent_id) : undefined;
      return {
        symbol: sym.symbol,
        name: sym.name ?? latest?.name ?? null,
        sort_order: sym.sort_order,
        hidden: sym.hidden,
        price: latest?.price ?? null,
        change: latest?.change ?? null,
        change_pct: latest?.change_pct ?? null,
        currency: latest?.currency ?? null,
        note: latest?.note ?? null,
        as_of: latest?.as_of ?? null,
        agent_name: agent?.name ?? null,
        agent_color: agent?.color ?? null,
        history_count: s.quotes.filter((q) => q.symbol === sym.symbol).length,
      };
    });
}

export function demoListNewsReports(lim: number): NewsReportRow[] {
  const s = state();
  return [...s.reports]
    .sort((a, b) => b.report_date.localeCompare(a.report_date) || b.published_at.localeCompare(a.published_at))
    .slice(0, lim)
    .map((r) => {
      const agent = s.agents.find((a) => a.id === r.agent_id);
      const items = s.items.filter((i) => i.report_id === r.id);
      return {
        id: r.id,
        slug: r.slug,
        report_date: r.report_date,
        display_date: r.display_date,
        hero_item: r.hero_item,
        published_at: r.published_at,
        agent_name: agent?.name ?? "?",
        agent_color: agent?.color ?? "#4F7CF7",
        item_count: items.length,
        sections: [...new Set(items.map((i) => i.section_name))].sort(),
      };
    });
}

export function demoNewsReport(id: string): NewsReportDetail | null {
  const s = state();
  const report = s.reports.find((r) => r.id === id);
  if (!report) return null;
  const items = s.items.filter((i) => i.report_id === id).sort((a, b) => a.section_order - b.section_order || a.position - b.position);
  return { report: { ...report }, items };
}

export function demoListIngest(lim: number, off: number): IngestEntry[] {
  return state().ingest.slice(off, off + lim);
}

export function demoListDevices(): Device[] {
  return [...state().devices].sort((a, b) => a.created_at.localeCompare(b.created_at));
}

export function demoSettings(): Settings {
  return { ...state().settings };
}

export function demoListAudit(lim: number, off: number): AuditEntry[] {
  return state().audit.slice(off, off + lim);
}

// listSeries: each key's rows in the window, the newest `limit` of them,
// oldest → newest (the fixtures hold thirty days of both).
export function demoListSeries(kind: "quotes" | "metrics", keys: string[], days: number, limit: number): Record<string, SeriesPoint[]> {
  const s = state();
  const from = Date.now() - days * DAY;
  const rows =
    kind === "quotes"
      ? s.quotes.map((q) => ({ key: q.symbol, id: q.id, t: Date.parse(q.as_of), v: q.price }))
      : s.metrics.map((m) => ({ key: m.key, id: m.id, t: Date.parse(m.as_of), v: m.value }));
  return Object.fromEntries(
    keys.map((k) => [
      k,
      rows
        .filter((r) => r.key === k && r.t >= from)
        .sort((a, b) => b.t - a.t || b.id - a.id)
        .slice(0, limit)
        .reverse()
        .map(({ t, v }) => ({ t, v })),
    ]),
  );
}

// listIngestSince: the push log is kept newest first already.
export function demoListIngestSince(hours: number, limit: number, status?: "ok" | "error"): IngestEntry[] {
  return state()
    .ingest.filter((e) => since(e.created_at, hours * HOUR) && (!status || e.status === status))
    .slice(0, limit);
}

// ─────────────────────────── Mutations ───────────────────────────

export function demoCreateAgent(name: string, kind: AgentKind, color: string | null): NewAgent {
  const s = state();
  const base = slugify(name) || "agent";
  let slug = base;
  for (let i = 1; s.agents.some((a) => a.slug === slug); i++) slug = `${base.slice(0, 36)}-${i}`;
  const key = newKey();
  const now = new Date().toISOString();
  const agent: DemoAgent = {
    id: crypto.randomUUID(),
    name,
    slug,
    kind,
    color: color ?? "#4F7CF7",
    created_at: now,
    last_seen_at: null,
    revoked_at: null,
    key_prefix: key.slice(0, 12),
    key_created_at: now,
  };
  s.agents.push(agent);
  audit("create_agent", "agent", agent.id, { name, slug, kind });
  return { id: agent.id, slug, key };
}

export function demoRotateAgentKey(id: string): string {
  const agent = findAgent(id);
  const key = newKey();
  agent.revoked_at = null;
  agent.key_prefix = key.slice(0, 12);
  agent.key_created_at = new Date().toISOString();
  audit("rotate_agent_key", "agent", id, {});
  return key;
}

export function demoUpdateAgent(id: string, patch: { name?: string; kind?: AgentKind; color?: string }) {
  const agent = findAgent(id);
  if (patch.name) agent.name = patch.name;
  if (patch.kind) agent.kind = patch.kind;
  if (patch.color) agent.color = patch.color;
  audit("update_agent", "agent", id, { ...patch });
}

export function demoRevokeAgent(id: string) {
  const agent = findAgent(id);
  agent.revoked_at ??= new Date().toISOString();
  agent.key_prefix = null;
  agent.key_created_at = null;
  audit("revoke_agent", "agent", id, {});
}

export function demoDeleteAgent(id: string) {
  const s = state();
  const agent = findAgent(id);
  s.agents = s.agents.filter((a) => a.id !== id);
  s.briefs = s.briefs.filter((b) => b.agent_id !== id);
  s.quotes = s.quotes.filter((q) => q.agent_id !== id);
  const gone = new Set(s.reports.filter((r) => r.agent_id === id).map((r) => r.id));
  s.reports = s.reports.filter((r) => !gone.has(r.id));
  s.items = s.items.filter((i) => !gone.has(i.report_id));
  s.ingest = s.ingest.filter((e) => e.agent_id !== id);
  s.projects = s.projects.filter((p) => p.agent_id !== id);
  s.metrics = s.metrics.filter((m) => m.agent_id !== id);
  s.dashboards = s.dashboards.filter((d) => d.agent_id !== id);
  s.events = s.events.filter((e) => e.agent_id !== id);
  audit("delete_agent", "agent", id, { name: agent.name, slug: agent.slug });
}

export function demoDeleteBrief(id: string) {
  const s = state();
  const brief = s.briefs.find((b) => b.id === id);
  if (!brief) throw new DataError("brief not found");
  s.briefs = s.briefs.filter((b) => b.id !== id);
  audit("delete_brief", "brief", id, { title: brief.title });
}

export function demoSetSymbol(symbol: string, patch: { hidden?: boolean; sort_order?: number; name?: string }) {
  const sym = state().symbols.find((x) => x.symbol === symbol);
  if (!sym) throw new DataError("symbol not found");
  if (patch.hidden !== undefined) sym.hidden = patch.hidden;
  if (patch.sort_order !== undefined) sym.sort_order = patch.sort_order;
  if (patch.name) sym.name = patch.name;
  sym.updated_at = new Date().toISOString();
  audit("set_symbol", "symbol", symbol, { ...patch });
}

export function demoDeleteSymbol(symbol: string) {
  const s = state();
  if (!s.symbols.some((x) => x.symbol === symbol)) throw new DataError("symbol not found");
  const before = s.quotes.length;
  s.quotes = s.quotes.filter((q) => q.symbol !== symbol);
  s.symbols = s.symbols.filter((x) => x.symbol !== symbol);
  audit("delete_symbol", "symbol", symbol, { quotes_removed: before - s.quotes.length });
}

export function demoDeleteNewsReport(id: string) {
  const s = state();
  const report = s.reports.find((r) => r.id === id);
  if (!report) throw new DataError("report not found");
  s.reports = s.reports.filter((r) => r.id !== id);
  s.items = s.items.filter((i) => i.report_id !== id);
  audit("delete_news_report", "news_report", id, { slug: report.slug });
}

export function demoRenameDevice(id: string, name: string) {
  const device = state().devices.find((d) => d.id === id);
  if (!device) throw new DataError("device not found");
  device.name = name;
  audit("rename_device", "device", id, { name });
}

export function demoRevokeDevice(id: string): { auth_user_removed: boolean } {
  const s = state();
  const device = s.devices.find((d) => d.id === id);
  if (!device) throw new DataError("device not found");
  s.devices = s.devices.filter((d) => d.id !== id);
  audit("revoke_device", "device", id, { name: device.name, auth_user_removed: true });
  return { auth_user_removed: true };
}

// Any six digits pair in demo mode; there is no display waiting.
export function demoClaimDevice(code: string, name: string | null): { deviceId: string } {
  const s = state();
  if (!/^[0-9]{6}$/.test(code)) throw new DataError("code must be the 6 digits on the screen");
  const device: Device = {
    id: crypto.randomUUID(),
    user_id: crypto.randomUUID(),
    name: name || "Display",
    last_seen_at: null,
    created_at: new Date().toISOString(),
    settings: {},
  };
  s.devices.push(device);
  audit("pair_device", "device", device.id, { name: device.name });
  return { deviceId: device.id };
}

export function demoUpdateSettings(patch: SettingsPatch): Settings {
  const s = state();
  s.settings = { ...s.settings, ...patch, updated_at: new Date().toISOString(), updated_by: s.admin.id };
  audit("update_settings", "settings", null, { ...patch });
  return { ...s.settings };
}

// ───────────────────── Productivity feeds ─────────────────────

export function demoListProjects(): ProjectRow[] {
  const s = state();
  return [...s.projects]
    .sort((a, b) => Number(a.status === "done") - Number(b.status === "done") || a.sort_order - b.sort_order || b.updated_at.localeCompare(a.updated_at))
    .map((p) => {
      const agent = s.agents.find((a) => a.id === p.agent_id);
      const { updates, ...rest } = p;
      const newest = [...updates].sort((a, b) => b.happened_at.localeCompare(a.happened_at) || b.id - a.id)[0];
      return {
        ...rest,
        agent_name: agent?.name ?? "?",
        agent_color: agent?.color ?? "#4F7CF7",
        update_count: updates.length,
        last_update: newest?.text ?? null,
        last_update_at: newest?.happened_at ?? null,
      };
    });
}

export function demoProjectUpdates(id: string, lim: number): ProjectUpdate[] {
  const project = state().projects.find((p) => p.id === id);
  if (!project) throw new DataError("project not found");
  return [...project.updates].sort((a, b) => b.happened_at.localeCompare(a.happened_at) || b.id - a.id).slice(0, lim);
}

export function demoDeleteProject(id: string) {
  const s = state();
  const project = s.projects.find((p) => p.id === id);
  if (!project) throw new DataError("project not found");
  s.projects = s.projects.filter((p) => p.id !== id);
  audit("delete_project", "project", id, { name: project.name });
}

// The newest row per key (the metrics_latest view).
function latestMetric(key: string) {
  return state()
    .metrics.filter((m) => m.key === key)
    .sort((a, b) => b.as_of.localeCompare(a.as_of) || b.id - a.id)[0];
}

export function demoListMetrics(): MetricRow[] {
  const s = state();
  return [...s.metricSettings]
    .sort(
      (a, b) =>
        Number(a.hidden) - Number(b.hidden) ||
        (a.group_name ?? "\uffff").localeCompare(b.group_name ?? "\uffff") ||
        a.sort_order - b.sort_order ||
        a.key.localeCompare(b.key),
    )
    .map((m) => {
      const latest = latestMetric(m.key);
      const agent = latest ? s.agents.find((a) => a.id === latest.agent_id) : undefined;
      return {
        key: m.key,
        label: m.label ?? latest?.label ?? m.key,
        group_name: m.group_name,
        sort_order: m.sort_order,
        hidden: m.hidden,
        value: latest?.value ?? null,
        unit: latest?.unit ?? null,
        delta: latest?.delta ?? null,
        delta_pct: latest?.delta_pct ?? null,
        note: latest?.note ?? null,
        as_of: latest?.as_of ?? null,
        agent_name: agent?.name ?? null,
        agent_color: agent?.color ?? null,
        history_count: s.metrics.filter((x) => x.key === m.key).length,
      };
    });
}

export function demoSetMetric(key: string, patch: { hidden?: boolean; sort_order?: number; label?: string; group_name?: string }) {
  const m = state().metricSettings.find((x) => x.key === key);
  if (!m) throw new DataError("metric not found");
  if (patch.hidden !== undefined) m.hidden = patch.hidden;
  if (patch.sort_order !== undefined) m.sort_order = patch.sort_order;
  if (patch.label) m.label = patch.label;
  if (patch.group_name) m.group_name = patch.group_name;
  audit("set_metric", "metric", key, { ...patch });
}

export function demoDeleteMetric(key: string) {
  const s = state();
  if (!s.metricSettings.some((x) => x.key === key)) throw new DataError("metric not found");
  const before = s.metrics.length;
  s.metrics = s.metrics.filter((m) => m.key !== key);
  s.metricSettings = s.metricSettings.filter((m) => m.key !== key);
  audit("delete_metric", "metric", key, { rows_removed: before - s.metrics.length });
}

export function demoListDashboards(): DashboardRow[] {
  const s = state();
  return [...s.dashboards]
    .sort((a, b) => Number(a.hidden) - Number(b.hidden) || a.sort_order - b.sort_order || a.title.localeCompare(b.title))
    .map((d) => {
      const agent = s.agents.find((a) => a.id === d.agent_id);
      const { agent_id: _agent, ...rest } = d;
      void _agent;
      return { ...rest, agent_name: agent?.name ?? "?", agent_color: agent?.color ?? "#4F7CF7" };
    });
}

export function demoSetDashboard(id: string, patch: { hidden?: boolean; sort_order?: number }) {
  const d = state().dashboards.find((x) => x.id === id);
  if (!d) throw new DataError("dashboard not found");
  if (patch.hidden !== undefined) d.hidden = patch.hidden;
  if (patch.sort_order !== undefined) d.sort_order = patch.sort_order;
  d.updated_at = new Date().toISOString();
  audit("set_dashboard", "dashboard", id, { ...patch });
}

export function demoDeleteDashboard(id: string) {
  const s = state();
  const d = s.dashboards.find((x) => x.id === id);
  if (!d) throw new DataError("dashboard not found");
  s.dashboards = s.dashboards.filter((x) => x.id !== id);
  audit("delete_dashboard", "dashboard", id, { key: d.key });
}

export function demoListEvents(daysBack: number, daysAhead: number): EventRow[] {
  const s = state();
  const now = Date.now();
  const from = now - Math.max(daysBack, 0) * DAY;
  const to = now + Math.max(daysAhead, 1) * DAY;
  return s.events
    .filter((e) => Date.parse(e.ends_at) >= from && Date.parse(e.starts_at) < to)
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at))
    .map((e) => ({ ...e, agent_name: s.agents.find((a) => a.id === e.agent_id)?.name ?? "?" }));
}

export function demoDeleteEvent(id: string) {
  const s = state();
  const e = s.events.find((x) => x.id === id);
  if (!e) throw new DataError("event not found");
  s.events = s.events.filter((x) => x.id !== id);
  audit("delete_event", "event", id, { title: e.title });
}

export function demoDeleteCalendar(agentId: string, calendar: string): number {
  const s = state();
  const before = s.events.length;
  s.events = s.events.filter((e) => !(e.agent_id === agentId && e.calendar === calendar));
  const removed = before - s.events.length;
  audit("delete_calendar", "calendar", calendar, { agent: agentId, events_removed: removed });
  return removed;
}

// ───────────────────────────── Scopes and memory ─────────────────────────────

const SCOPES: AgentScope[] = ["memory:read", "memory:write", "calendar:read"];

export function demoSetAgentScopes(id: string, scopes: AgentScope[]): AgentScope[] {
  const agent = findAgent(id);
  const clean = [...new Set(scopes)].filter((x) => SCOPES.includes(x)).sort();
  agent.scopes = clean;
  audit("set_agent_scopes", "agent", id, { scopes: clean });
  return clean;
}

export function demoListMemories(): MemoryNote[] {
  return [...state().memories].sort((a, b) => Number(b.pinned) - Number(a.pinned) || b.updated_at.localeCompare(a.updated_at));
}

export function demoSaveMemory(id: string | null, text: string | null, pinned: boolean | null, agentId: string | null): string {
  const s = state();
  const now = new Date().toISOString();
  if (!id) {
    if (!text) throw new DataError("a note is 1 to 2000 characters");
    if (s.memories.length >= 500) throw new DataError("memory is full (500 notes); delete some first");
    const agent = agentId ? findAgent(agentId) : null;
    const note: MemoryNote = {
      id: crypto.randomUUID(), agent_id: agent?.id ?? null, agent_name: agent?.name ?? null, agent_color: agent?.color ?? null,
      key: null, text, pinned: pinned ?? false, source: "admin", created_at: now, updated_at: now,
    };
    s.memories.unshift(note);
    audit("save_memory", "memory", note.id, {});
    return note.id;
  }
  const note = s.memories.find((m) => m.id === id);
  if (!note) throw new DataError("note not found");
  if (text) note.text = text;
  if (pinned !== null) note.pinned = pinned;
  note.updated_at = now;
  audit("save_memory", "memory", id, pinned === null ? {} : { pinned });
  return id;
}

export function demoDeleteMemory(id: string) {
  const s = state();
  const at = s.memories.findIndex((m) => m.id === id);
  if (at < 0) throw new DataError("note not found");
  s.memories.splice(at, 1);
  audit("delete_memory", "memory", id, {});
}

// ───────────────────────────── Calendar subscriptions ─────────────────────────────

export function demoListCalendarSources(): CalendarSource[] {
  return [...state().calendarSources];
}

function findSource(id: string): CalendarSource {
  const c = state().calendarSources.find((x) => x.id === id);
  if (!c) throw new DataError("calendar not found");
  return c;
}

export function demoAddCalendarSource(name: string, url: string, color: string | null): string {
  const s = state();
  const link = url.replace(/^webcal:\/\//i, "https://");
  if (!/^https?:\/\/[^/]+/i.test(link)) throw new DataError("paste the calendar's iCal link (it starts with https:// or webcal://)");
  if (s.calendarSources.some((c) => c.name === name)) throw new DataError(`there is already a calendar called ${name}`);
  const id = crypto.randomUUID();
  s.calendarSources.push({
    id, name, host: new URL(link).host, color, enabled: true, last_synced_at: null, last_error: null, event_count: 0,
    created_at: new Date().toISOString(), kind: "ical", account_id: null, account_email: null, google_calendar_id: null,
    watch_expires_at: null, watch_error: null,
  });
  audit("add_calendar_source", "calendar_source", id, { name });
  return id;
}

export function demoUpdateCalendarSource(id: string, patch: { name?: string; color?: string; enabled?: boolean }) {
  const c = findSource(id);
  if (patch.name) c.name = patch.name;
  if (patch.color) c.color = patch.color;
  if (patch.enabled !== undefined) c.enabled = patch.enabled;
  audit("update_calendar_source", "calendar_source", id, patch);
}

export function demoDeleteCalendarSource(id: string) {
  const s = state();
  findSource(id);
  s.calendarSources = s.calendarSources.filter((c) => c.id !== id);
  audit("delete_calendar_source", "calendar_source", id, {});
}

export function demoSyncCalendarSource(id: string): { count?: number; error?: string } {
  const c = findSource(id);
  if (!c.enabled) return { error: "that calendar is paused" };
  c.last_synced_at = new Date().toISOString();
  c.last_error = null;
  c.event_count = Math.max(c.event_count, 3);
  return { count: c.event_count };
}

// ───────────────────────────── Google accounts ─────────────────────────────

function findGoogleAccount(id: string): GoogleAccount {
  const a = state().googleAccounts.find((x) => x.id === id);
  if (!a) throw new DataError("that Google account isn't connected");
  return a;
}

export function demoListGoogleAccounts(): GoogleAccount[] {
  const s = state();
  return s.googleAccounts.map((a) => ({ ...a, calendars: s.calendarSources.filter((c) => c.account_id === a.id).length }));
}

export function demoListGoogleCalendars(accountId: string): { calendars: GoogleCalendar[] } | { error: string } {
  const s = state();
  const account = s.googleAccounts.find((a) => a.id === accountId);
  if (!account) return { error: "that Google account isn't connected" };
  if (account.last_error) return { error: account.last_error };
  return { calendars: s.googleCalendars[accountId] ?? [] };
}

// Demo: "signing in" connects a sample account on the spot and comes
// straight back, the way Google's redirect would.
export function demoConnectGoogle(returnTo: string): string {
  const s = state();
  const email = "demo@example.com";
  let account = s.googleAccounts.find((a) => a.email === email);
  if (account) {
    account.last_error = null;
    account.connected_at = new Date().toISOString();
  } else {
    account = { id: crypto.randomUUID(), email, connected_at: new Date().toISOString(), last_error: null, calendars: 0 };
    s.googleAccounts.push(account);
    s.googleCalendars[account.id] = [
      { id: email, name: "Demo", color: "#0B8043", primary: true, access_role: "owner", selected: true },
      { id: "c_demo_team@group.calendar.google.com", name: "Team", color: "#7A64E8", primary: false, access_role: "writer", selected: true },
    ];
  }
  audit("connect_google_account", "google_account", account.id, { email });
  return `${returnTo}?google=connected`;
}

export function demoDisconnectGoogleAccount(id: string): string {
  const s = state();
  const account = findGoogleAccount(id);
  s.googleAccounts = s.googleAccounts.filter((a) => a.id !== id);
  delete s.googleCalendars[id];
  s.calendarSources = s.calendarSources.filter((c) => c.account_id !== id);
  audit("disconnect_google_account", "google_account", id, { email: account.email });
  return account.email;
}

export function demoAddGoogleCalendar(accountId: string, calendarId: string, name: string, color: string | null): string {
  const s = state();
  const account = findGoogleAccount(accountId);
  if (s.calendarSources.some((c) => c.account_id === accountId && c.google_calendar_id === calendarId)) throw new DataError("that calendar is already added");
  let wanted = name.trim().slice(0, 80) || "Google";
  if (s.calendarSources.some((c) => c.name === wanted)) wanted = `${wanted} (${account.email})`.slice(0, 80);
  const id = crypto.randomUUID();
  s.calendarSources.push({
    id, name: wanted, host: "calendar.google.com", color, enabled: true, last_synced_at: null, last_error: null, event_count: 0,
    created_at: new Date().toISOString(), kind: "google", account_id: accountId, account_email: account.email, google_calendar_id: calendarId,
    watch_expires_at: null, watch_error: null,
  });
  audit("add_calendar_source", "calendar_source", id, { name: wanted, kind: "google", account: account.email });
  return id;
}

export function demoUpdateDeviceSettings(id: string, patch: DisplaySettings) {
  const d = state().devices.find((x) => x.id === id);
  if (!d) throw new DataError("display not found");
  d.settings = { ...d.settings, ...patch };
  audit("update_device_settings", "device", id, patch);
}

// ───────────────────────────── Grok bots ─────────────────────────────

export function demoListBots(): Bot[] {
  return [...state().bots];
}

export function demoSaveBot(id: string | null, draft: Partial<BotDraft> & { enabled?: boolean }): string {
  const s = state();
  if (!id) {
    if (!draft.prompt || draft.prompt.trim().length < 10) throw new DataError("write what the bot should do (at least a sentence)");
    const agent = demoCreateAgent(draft.name || "Grok bot", "grok", draft.color ?? null);
    const bot: Bot = {
      id: crypto.randomUUID(), agent_id: agent.id, name: draft.name || "Grok bot", color: draft.color ?? "#7A64E8", scopes: draft.scopes ?? [],
      prompt: draft.prompt.trim(), output: draft.output ?? "brief", every_minutes: draft.every_minutes ?? 60, at_minute: draft.at_minute ?? null,
      web_search: draft.web_search ?? true, x_search: draft.x_search ?? true, model: draft.model ?? "", enabled: true,
      next_run_at: new Date().toISOString(), last_run_at: null, last_status: null, last_error: null, runs_7d: 0, runs: [],
    };
    s.bots.push(bot);
    if (bot.scopes.length) demoSetAgentScopes(agent.id, bot.scopes);
    audit("save_bot", "bot", bot.id, {});
    return bot.id;
  }
  const bot = s.bots.find((b) => b.id === id);
  if (!bot) throw new DataError("bot not found");
  Object.assign(bot, Object.fromEntries(Object.entries(draft).filter(([, v]) => v !== undefined)));
  audit("save_bot", "bot", id, { enabled: draft.enabled });
  return id;
}

export function demoDeleteBot(id: string) {
  const s = state();
  const bot = s.bots.find((b) => b.id === id);
  if (!bot) throw new DataError("bot not found");
  s.bots = s.bots.filter((b) => b.id !== id);
  s.agents = s.agents.filter((a) => a.id !== bot.agent_id);
}

export function demoRunBot(id: string): { title?: string; error?: string } {
  const bot = state().bots.find((b) => b.id === id);
  if (!bot) throw new DataError("bot not found");
  return { error: "demo mode doesn't call Grok; deploy McFly and add XAI_API_KEY to run bots" };
}

// ───────────────────────────── Assistant ─────────────────────────────
// Demo mode has no model. It answers from the fixtures with a keyword
// matcher, as the display's demo does (display/src/models/Assistant.cpp
// demoAnswer): names first (a symbol or company, a project, a metric, an
// event, a story, an agent), then topics. The phrasing stays templated and the
// fallback says so, so nobody mistakes it for the real assistant.

const COUNT_WORDS = ["Nothing", "One thing", "Two things", "Three things", "Four things", "Five things"];

// Other names for the fixtures' symbols and metric keys, as norm() leaves
// them ("S&P" becomes "s p"). Whole phrases, not each word of a label: "open"
// from "Open orders" or "today" from "Sales today" would catch questions
// meant for the calendar or the brief.
const ALIASES: Record<string, string[]> = {
  SPY: ["s p", "s p 500", "the index", "spx"],
  "sales.today": ["sales", "revenue", "takings"],
  "orders.open": ["orders"],
  "site.uptime": ["up time", "the site", "outage"],
  "api.p95": ["api", "latency"],
  steps: ["walked", "walking", "step count"],
};

// Lowercase words with single spaces and a space at each end, so a phrase
// matches whole words only (" apple " is not in " pineapple ").
const norm = (text: string) =>
  ` ${text
    .toLowerCase()
    .replace(/[^a-z0-9.%^]+/g, " ")
    .replace(/\.+(?= |$)/g, "")
    .trim()} `;
const mentions = (q: string, phrase: string | null | undefined) => {
  const p = phrase ? norm(phrase).trim() : "";
  return p.length > 1 && q.includes(` ${p} `);
};
// A title, or (for chips that clipped it) its first three words.
const mentionsTitle = (q: string, title: string) => {
  const words = norm(title).trim().split(" ");
  return mentions(q, title) || (words.length > 3 && mentions(q, words.slice(0, 3).join(" ")));
};
const sentence = (text: string) => {
  const t = text.trim().replace(/[\s.;:,]+$/, "");
  return t ? `${t}.` : "";
};
const signed = (n: number, digits = 2) => `${n > 0 ? "+" : n < 0 ? "−" : ""}${Math.abs(n).toFixed(digits)}%`;

function demoToday(now: number) {
  const s = state();
  const timeZone = safeTimeZone(s.settings.timezone);
  const quotes = demoListQuotes();
  const metrics = demoListMetrics();
  const series = {
    quotes: demoListSeries("quotes", tickerRows(quotes).map((q) => q.symbol), SERIES_DAYS, Infinity),
    metrics: demoListSeries("metrics", metricRows(metrics).map((m) => m.key), SERIES_DAYS, Infinity),
  };
  const today = dayKey(new Date(now), timeZone);
  const reportRow = demoListNewsReports(10).find((r) => r.report_date === today) ?? null;
  const report = reportRow ? demoNewsReport(reportRow.id) : null;
  const facts = todayFacts({
    now: new Date(now),
    timeZone,
    quotes,
    metrics,
    series,
    projects: demoListProjects(),
    events: demoListEvents(1, 8),
    brief: demoListBriefs(1, 0)[0] ?? null,
    report: reportRow && report ? { ...reportRow, items: report.items } : null,
  });
  return { timeZone, quotes, report, facts };
}

function spanDays(points: SeriesPoint[]): number {
  return points.length > 1 ? Math.max(1, Math.round((points[points.length - 1].t - points[0].t) / DAY)) : 0;
}

function trend(points: SeriesPoint[], unit: string | null | undefined, money?: (n: number) => string): string {
  const change = windowChange(points);
  const range = rangeOf(points);
  const days = spanDays(points);
  if (!change || !range || days < 2) return "";
  const fmt = money ?? ((n: number) => formatMetricValue(n, unit));
  const where = range.position >= 0.85 ? ", and it's near the top of that range" : range.position <= 0.15 ? ", and it's near the bottom of that range" : "";
  const dir = change.abs >= 0 ? "up" : "down";
  const moved =
    change.pct == null ? `${dir} ${fmt(Math.abs(change.abs))}` : Math.abs(change.pct) < 0.05 ? "about flat" : `${dir} ${Math.abs(change.pct).toFixed(1)}%`;
  return `Over the last ${days} days it's ${moved}, ranging ${fmt(range.min)} to ${fmt(range.max)}${where}.`;
}

function digest(facts: TodayFacts, timeZone: string, now: number): string {
  // The same input as loadToday: refused pushes only.
  const insights = buildInsights({ ...facts, timeZone, ingest: demoListIngestSince(24, Infinity, "error") }, now);
  if (!insights.length) return "A quiet day so far: nothing is blocked, nothing moved much and nothing is about to start.";
  const clauses = insights.map((i) => {
    if (i.kind === "pulse") return `today's Pulse leads with “${i.title}”`;
    if ((i.kind === "blocked" || i.kind === "metric") && i.detail) return `${i.title} (${i.detail})`;
    return i.title;
  });
  const n = insights.length;
  const first = `${clauses[0][0].toUpperCase()}${clauses[0].slice(1)}${clauses[1] ? `, and ${clauses[1]}` : ""}.`;
  const rest = clauses.length > 2 ? ` Also: ${clauses.slice(2).join("; ")}.` : "";
  return `${COUNT_WORDS[n] ?? `${n} things`} stand${n === 1 ? "s" : ""} out today. ${first}${rest}`;
}

function projectAnswer(p: ProjectRow, now: number): string {
  const parts = [`${p.name} is ${p.status}${p.progress != null && p.status !== "done" ? ` at ${Math.round(p.progress)}%` : ""}.`];
  if (p.next_step) parts.push(`Next: ${sentence(p.next_step)}`);
  if (p.last_update && p.last_update_at) parts.push(`Last update ${agoLabel(Date.parse(p.last_update_at), now)}: ${sentence(p.last_update)}`);
  return parts.join(" ");
}

function demoAnswer(question: string, now: number): string {
  // "Hey McFly, …" or "…, McFly?" is talking to the assistant, not asking
  // about the project of the same name.
  const raw = norm(question);
  const q = raw.replace(/^ (?:(?:hey|hi|ok|okay) )?mcfly /, " ").replace(/ mcfly $/, " ");
  const { timeZone, quotes, report, facts } = demoToday(now);
  const projects = demoListProjects();
  const events = demoListEvents(1, 8);
  const at = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" });
  const when = (iso: string) => {
    const day = dayLabel(dayKey(iso, timeZone), timeZone, new Date(now));
    return `${day === "Today" ? "today" : day === "Tomorrow" ? "tomorrow" : `on ${day}`} at ${at.format(new Date(iso))}`;
  };

  const quoteAnswer = (quote: QuoteRow) => {
    const series = demoListSeries("quotes", [quote.symbol], SERIES_DAYS, Infinity)[quote.symbol];
    const t = toTicker(quote, series, timeZone);
    const ratio = t.changePct != null && t.swingPct ? Math.abs(t.changePct) / t.swingPct : null;
    const move = t.changePct != null ? `, ${t.changePct >= 0 ? "up" : "down"} ${Math.abs(t.changePct).toFixed(2)}% today` : "";
    const usual = ratio != null && ratio >= 1.5 ? `, about ${ratio.toFixed(1)}× its usual daily move` : "";
    const name = t.name && t.name !== t.symbol ? `${t.name} (${t.symbol})` : t.symbol;
    return [`${name} is at ${t.price}${move}${usual}.`, trend(series, null, (n) => formatPrice(n, quote.currency)), t.note ? sentence(t.note) : ""].filter(Boolean).join(" ");
  };
  const metricAnswer = (metric: TodayFacts["metrics"][number]) => {
    const series = demoListSeries("metrics", [metric.key], SERIES_DAYS, Infinity)[metric.key];
    const parts = [`${metric.label}: ${metric.valueLabel}${metric.deltaLabel ? ` (${metric.deltaLabel} since the reading before)` : ""}.`];
    if (metric.z != null && Math.abs(metric.z) >= 3 && metric.usual != null) {
      parts.push(`That's unusually ${metric.z > 0 ? "high" : "low"} for it: it usually sits around ${formatMetricValue(metric.usual, metric.unit)}${metric.good == null ? "" : metric.good ? ", and here that's good news" : ", and here that's bad news"}.`);
    } else {
      parts.push(trend(series, metric.unit));
    }
    if (metric.note) parts.push(sentence(metric.note));
    return parts.filter(Boolean).join(" ");
  };
  const shown = quotes.filter((x) => !x.hidden && x.price != null);

  // A symbol or a company.
  const quote = shown.find((x) => mentions(q, x.symbol) || mentions(q, x.name));
  if (quote) return quoteAnswer(quote);

  // A project by name.
  const project = projects.find((p) => mentions(q, p.name));
  if (project) return projectAnswer(project, now);
  if (/ next steps? /.test(q)) {
    const open = projects.filter((p) => p.status !== "done" && p.next_step);
    return open.length ? `Next steps: ${open.map((p) => `${p.name}, ${p.next_step!.replace(/[.\s]+$/, "")}`).join("; ")}.` : "None of the projects has a next step written down.";
  }

  // A metric by label or key.
  const metric = facts.metrics.find((m) => mentions(q, m.label) || mentions(q, m.key));
  if (metric) return metricAnswer(metric);

  // An event, a story or an agent, by name.
  const event = events.find((e) => mentionsTitle(q, e.title));
  if (event) {
    const range = event.all_day ? `all day ${when(event.starts_at).replace(/ at .*$/, "")}` : when(event.starts_at);
    const soon = !event.all_day && Date.parse(event.starts_at) > now ? ` That's ${untilLabel(Date.parse(event.starts_at), now, true)}.` : "";
    return `${event.title} is ${range}${event.location ? ` at ${event.location}` : ""}, on the ${event.calendar} calendar.${soon} The demo calendar has no notes for it, so there's nothing more to prepare from here.`;
  }
  const other = demoListNewsReports(10).find((r) => r.id !== report?.report.id);
  const stories = [...(report?.items ?? []), ...(other ? (demoNewsReport(other.id)?.items ?? []) : [])];
  const story = stories.find((i) => mentionsTitle(q, i.headline));
  if (story) {
    const which = report?.items.includes(story) ? "today's" : "yesterday's";
    return `From ${which} Pulse, under ${story.section_name}: ${sentence(story.headline)} ${sentence(story.takeaway)}${story.source_domain ? ` Source: ${story.source_domain}.` : ""}`;
  }
  const briefs = demoListBriefs(50, 0);
  const author = state().agents.find((a) => mentions(q, a.name) && briefs.some((b) => b.agent_id === a.id));
  if (author) {
    const b = briefs.find((x) => x.agent_id === author.id)!;
    return `${author.name} posted “${b.title}” ${agoLabel(Date.parse(b.published_at), now)}. ${clip(b.body.replace(/^- /gm, "").split(/\n+/).map(sentence).join(" "), 400)}`;
  }

  // What people call a fixture when it isn't its full name ("the S&P",
  // "sales"), once nothing matched in full.
  const aliased = (key: string) => (ALIASES[key] ?? []).some((a) => mentions(q, a));
  const quoteByAlias = shown.find((x) => aliased(x.symbol));
  if (quoteByAlias) return quoteAnswer(quoteByAlias);
  const metricByAlias = facts.metrics.find((m) => aliased(m.key));
  if (metricByAlias) return metricAnswer(metricByAlias);

  // Topics.
  if (/ (news|pulse|story|stories|headline|headlines) /.test(q)) {
    if (!report || !facts.hero) return "There's no Pulse report yet today.";
    const others = report.items.filter((i) => i.headline !== facts.hero!.headline).slice(0, 2).map((i) => i.headline);
    return `Today's Pulse has ${report.items.length} stories. It leads with “${facts.hero.headline}”${others.length ? `; also ${others.map((h) => `“${h}”`).join(" and ")}` : ""}.`;
  }
  if (/summar|my day|should (i )?know|catch me up|what matters|anything new|overview/.test(q)) return digest(facts, timeZone, now);
  if (/ (blocked|blocking|stuck|blocker|blockers) /.test(q)) {
    const blocked = projects.filter((p) => p.status === "blocked");
    if (!blocked.length) return "Nothing is blocked right now.";
    return blocked.map((p) => `${p.name} is blocked${p.next_step ? `, waiting on: ${p.next_step.replace(/[.\s]+$/, "")}` : ""}.`).join(" ");
  }
  if (/ (market|markets|stock|stocks|portfolio|watchlist|movers|mover|trading|tickers) /.test(q)) {
    const movers = [...facts.tickers].sort((a, b) => Math.abs(b.changePct ?? 0) - Math.abs(a.changePct ?? 0));
    if (!movers.length) return "No quotes have come in yet.";
    const top = movers[0];
    return `Biggest movers first: ${movers.map((t) => `${t.symbol} ${t.changePct != null ? signed(t.changePct) : t.change} at ${t.price}`).join(", ")}.${top.note ? ` On ${top.symbol}: ${sentence(top.note)}` : ""}`;
  }
  if (/ (metric|metrics|kpi|kpis|numbers|dashboard|dashboards) /.test(q)) {
    if (!facts.metrics.length) return "No metrics have come in yet.";
    const odd = facts.metrics.find((m) => m.z != null && Math.abs(m.z) >= 3);
    return `${facts.metrics.map((m) => `${m.label} ${m.valueLabel}${m.deltaLabel ? ` (${m.deltaLabel})` : ""}`).join(", ")}.${odd ? ` ${odd.label} stands out: unusually ${odd.z! > 0 ? "high" : "low"} for it.` : ""}`;
  }
  if (/ (calendar|meeting|meetings|next|schedule|event|events|agenda|appointment) /.test(q)) {
    const on = facts.events.find((e) => !e.all_day && Date.parse(e.starts_at) <= now);
    const upcoming = facts.events.filter((e) => Date.parse(e.starts_at) > now || e.all_day).slice(0, 3);
    const lead = on ? `On now: ${on.title}${on.location ? ` at ${on.location}` : ""}, until ${at.format(new Date(on.ends_at))}. ` : "";
    if (!upcoming.length) return `${lead}Nothing else is on the calendar this week.`;
    return `${lead}Next up: ${upcoming.map((e) => `${e.title} ${e.all_day ? `(all day ${when(e.starts_at).replace(/ at .*$/, "")})` : when(e.starts_at)}${e.location ? ` at ${e.location}` : ""}`).join(", then ")}.`;
  }
  if (/ (brief|briefs|briefing|today|latest|update|updates) /.test(q)) {
    const b = briefs[0];
    if (!b) return "No briefs have come in yet.";
    return `From ${b.agent_name}, ${agoLabel(Date.parse(b.published_at), now)}: ${sentence(b.title)} ${clip(b.body.replace(/^- /gm, "").split(/\n+/).map(sentence).join(" "), 400)}`;
  }
  if (/ (project|projects|working on|progress) /.test(q)) {
    return `${projects.length} projects: ${projects.map((p) => `${p.name} is ${p.status}${p.progress != null && p.status !== "done" ? ` at ${Math.round(p.progress)}%` : ""}`).join("; ")}.`;
  }

  // Nothing else asked for: "How's McFly?" was about the project after all.
  const named = projects.find((p) => mentions(raw, p.name));
  if (named) return projectAnswer(named, now);

  const symbol = [...facts.tickers].sort((a, b) => Math.abs(b.changePct ?? 0) - Math.abs(a.changePct ?? 0))[0]?.symbol ?? "NVDA";
  const name = (facts.blocked[0] ?? projects[0])?.name ?? "a project";
  const label = (facts.metrics.find((m) => m.z != null && Math.abs(m.z) >= 3) ?? facts.metrics[0])?.label ?? "a metric";
  return `This is the demo, so I answer from the sample feeds with simple keyword matching, not a model. Ask about a symbol (${symbol}), a project (${name}), a metric (${label}), your calendar or today's Pulse, or say “summarize my day”.`;
}

// The first `n` sentences: quick mode is one or two spoken sentences.
function firstSentences(text: string, n: number): string {
  const parts = text.split(/(?<=[.!?”])\s+(?=[A-Z“])/);
  return parts.slice(0, n).join(" ");
}

// Streams like the assistant function: a beat to think, then delta events a
// word at a time, then done with the whole reply (model "demo").
export function demoAsk(message: string, mode: "chat" | "quick" | "read" = "chat"): Response {
  const full = demoAnswer(message, Date.now());
  const reply = mode === "quick" ? firstSentences(full, 2) : full;
  const words = reply.split(/(?<= )/);
  const encoder = new TextEncoder();
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  let cancelled = false;
  const body = new ReadableStream({
    async start(controller) {
      await wait(400);
      for (const w of words) {
        if (cancelled) return;
        controller.enqueue(encoder.encode(`event: delta\ndata: ${JSON.stringify({ text: w })}\n\n`));
        await wait(25);
      }
      if (cancelled) return;
      controller.enqueue(encoder.encode(`event: done\ndata: ${JSON.stringify({ reply, model: "demo" })}\n\n`));
      controller.close();
    },
    // The page went away mid-answer: stop writing to a closed stream.
    cancel() {
      cancelled = true;
    },
  });
  return new Response(body, { headers: { "Content-Type": "text/event-stream" } });
}

export function demoBackendStatus(expected: string): BackendStatus {
  const s = state();
  return {
    functions: ["ingest", "pair-device", "admin", "assistant", "calendar-sync", "bots", "google-calendar"].map((name) => ({ name, ok: true })),
    secrets: { ANTHROPIC_API_KEY: true, XAI_API_KEY: false, MCFLY_CRON_SECRET: true, GOOGLE_CLIENT_ID: true, GOOGLE_CLIENT_SECRET: true },
    latestMigration: expected,
    expectedMigration: expected,
    cron: [
      { name: "mcfly-bots", schedule: "*/5 * * * *", active: true },
      { name: "mcfly-calendar-sync", schedule: "*/15 * * * *", active: true },
    ],
    vault: { project_url: true, cron_secret: true },
    calendars: s.calendarSources.length,
    lastCalendarSync: s.calendarSources[0]?.last_synced_at ?? null,
    bots: s.bots.length,
    lastBotRun: s.bots[0]?.last_run_at ?? null,
    projectRef: null,
  };
}
