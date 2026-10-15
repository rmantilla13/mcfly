import "server-only";
import { buildDemoState, type DemoAgent, type DemoState } from "@/lib/demo/fixtures";
import { DataError } from "@/lib/errors";
import { ONLINE_WINDOW_MS } from "@/lib/format";
import type {
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
