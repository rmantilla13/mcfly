"use server";

import { listAgents, listBots, listDashboards, listEvents, listMetrics, listProjects, listQuotes, requireAdmin } from "@/lib/data";
import { cssColor } from "@/lib/format";
import { buildSuggestions } from "@/lib/suggestions";
import { formatMetricValue } from "@/lib/widgets";

// What the command bar (⌘K, components/CommandBar.tsx) can find: the
// agents, projects, symbols, metrics, dashboards and bots, each with the
// page it lives on, and a few questions worth asking from what is on the
// feeds right now (lib/suggestions.ts). Read only, and read when the bar
// first opens, not with every page. Only what the bar shows leaves the
// server: names, a hint, a link and a colour.

export type CommandKind = "agent" | "project" | "symbol" | "metric" | "dashboard" | "bot";
export type CommandEntry = { kind: CommandKind; id: string; label: string; hint: string; href: string; color: string | null };
export type CommandIndex = { entries: CommandEntry[]; questions: string[] };

// One feed failing to read leaves the rest findable.
function some<T>(what: string, read: Promise<T[]>): Promise<T[]> {
  return read.catch((err: unknown) => {
    console.error(`command bar: ${what} unavailable:`, err instanceof Error ? err.message : err);
    return [];
  });
}

export async function commandIndexAction(): Promise<CommandIndex> {
  await requireAdmin();
  const [agents, projects, quotes, metrics, dashboards, bots, events] = await Promise.all([
    some("agents", listAgents()),
    some("projects", listProjects()),
    some("quotes", listQuotes()),
    some("metrics", listMetrics()),
    some("dashboards", listDashboards()),
    some("bots", listBots({ runs: false })),
    some("events", listEvents(0, 1)),
  ]);
  const hidden = (h: boolean) => (h ? " · hidden" : "");

  const entries: CommandEntry[] = [
    ...projects.map((p) => ({
      kind: "project" as const,
      id: p.id,
      label: p.name,
      hint: `Project · ${p.status}${p.progress != null && p.status !== "done" ? ` · ${Math.round(p.progress)}%` : ""}`,
      href: `/feed/projects/${p.id}`,
      color: cssColor(p.color) ?? cssColor(p.agent_color),
    })),
    ...quotes.map((q) => ({
      kind: "symbol" as const,
      id: q.symbol,
      label: q.symbol,
      hint: `${q.name && q.name !== q.symbol ? q.name : "Symbol"}${hidden(q.hidden)}`,
      href: "/feed?tab=markets",
      color: null,
    })),
    ...metrics.map((m) => ({
      kind: "metric" as const,
      id: m.key,
      label: m.label,
      hint: `Metric${m.value != null ? ` · ${formatMetricValue(m.value, m.unit)}` : ""}${hidden(m.hidden)}`,
      href: "/feed?tab=metrics",
      color: null,
    })),
    ...dashboards.map((d) => ({
      kind: "dashboard" as const,
      id: d.id,
      label: d.title,
      hint: `Dashboard${d.subtitle ? ` · ${d.subtitle}` : ""}${hidden(d.hidden)}`,
      href: `/feed/dashboards/${d.id}`,
      color: cssColor(d.agent_color),
    })),
    ...agents.map((a) => ({
      kind: "agent" as const,
      id: a.id,
      label: a.name,
      hint: `Agent · ${a.kind}${a.revoked_at ? " · revoked" : ""}`,
      href: "/agents",
      color: cssColor(a.color),
    })),
    ...bots.map((b) => ({
      kind: "bot" as const,
      id: b.id,
      label: b.name,
      hint: `Grok bot${b.enabled ? "" : " · paused"}`,
      href: "/bots",
      color: cssColor(b.color),
    })),
  ];

  const questions = buildSuggestions({
    nowMs: Date.now(),
    blocked: projects.filter((p) => p.status === "blocked"),
    tickers: quotes.filter((q) => !q.hidden && q.price != null).map((q) => ({ symbol: q.symbol, changePct: q.change_pct, asOf: q.as_of })),
    metrics: metrics.filter((m) => !m.hidden),
    events,
  });

  return { entries, questions };
}
