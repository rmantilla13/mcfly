import "server-only";

import {
  getNewsReport,
  getProjectUpdates,
  getSettings,
  listBriefs,
  listDevices,
  listEvents,
  listIngestSince,
  listMetrics,
  listNewsReports,
  listProjects,
  listQuotes,
  listSeries,
} from "@/lib/data";
import { dayKey, safeTimeZone } from "@/lib/events";
import { buildInsights, type Insight } from "@/lib/insights";
import type { SeriesPoint } from "@/lib/series";
import { displayBackdrop, type Backdrop } from "@/lib/sky";
import { buildSuggestions } from "@/lib/suggestions";
import { buildTimeline, buildTomorrow, metricRows, SERIES_DAYS, tickerRows, todayFacts, type TimelineItem, type TodayFacts } from "@/lib/today";

// Everything the Today page and the ambient view show, read once on the
// server in the display's time zone. Plain JSON, so it crosses into the
// client components that keep the clock. The insights and suggestions are
// worked out here from the same rows, with no model call: the page reads
// this again every 60 s in every open tab.

export type { Insight, InsightKind, InsightTone } from "@/lib/insights";
export type { SeriesPoint } from "@/lib/series";
export type { TodayBrief, TodayEvent, TodayHero, TodayMetric, TodayProject, TodayTicker } from "@/lib/today";

export type TodayData = TodayFacts & {
  nowMs: number;
  timeZone: string;
  displayName: string;
  backdrop: Backdrop; // behind the ambient view: the display's choice (lib/sky.ts displayBackdrop)
  timeline: TimelineItem[];
  tomorrow: TimelineItem[]; // tomorrow's events: the preview under the day
  insights: Insight[]; // ranked, at most 5 (lib/insights.ts)
  suggestions: string[]; // at most 4, each ≤ 42 characters (lib/suggestions.ts)
};

// Sparklines, the insights' history and the push log are extras: a failed
// read logs and leaves them empty rather than taking the page down. The
// history comes from a cache up to an hour old (lib/data.ts listSeries);
// todayFacts puts each latest row on its end.
function extra<T>(what: string, fallback: T) {
  return (err: unknown): T => {
    console.error(`today: ${what} unavailable:`, err instanceof Error ? err.message : err);
    return fallback;
  };
}

export async function loadToday(): Promise<TodayData> {
  const now = new Date();
  const [settings, briefs, quotes, metrics, reports, projects, events, ingest, devices] = await Promise.all([
    getSettings(),
    listBriefs(1),
    listQuotes(),
    listMetrics(),
    listNewsReports(10),
    listProjects(),
    listEvents(1, 8),
    // Only the refused pushes, for the "refused" insight: the ok rows would be
    // up to 1000 a day, every minute, and judging a quiet agent needs a week
    // of them (lib/insights.ts), more than this page should read.
    listIngestSince(24, { status: "error" }).catch(extra("push log", [])),
    // The displays, for the ambient view's backdrop: without them it is the mesh.
    listDevices().catch(extra("displays", [])),
  ]);
  const timeZone = safeTimeZone(settings.timezone);
  const today = dayKey(now, timeZone);

  // Only today's reports and today's project updates need a second read,
  // alongside the history of what the page charts.
  const todaysReports = reports.filter((r) => r.report_date === today);
  const movedToday = projects.filter((p) => p.last_update_at && dayKey(p.last_update_at, timeZone) === today);
  const symbols = tickerRows(quotes).map((q) => q.symbol);
  const keys = metricRows(metrics).map((m) => m.key);
  const none: Record<string, SeriesPoint[]> = {};
  const [details, updates, quoteSeries, metricSeries] = await Promise.all([
    Promise.all(todaysReports.map((r) => getNewsReport(r.id))),
    Promise.all(movedToday.map((p) => getProjectUpdates(p.id, 20))),
    symbols.length ? listSeries("quotes", symbols, SERIES_DAYS).catch(extra("quote history", none)) : none,
    keys.length ? listSeries("metrics", keys, SERIES_DAYS).catch(extra("metric history", none)) : none,
  ]);
  const fullReports = todaysReports.flatMap((r, i) => {
    const d = details[i];
    return d ? [{ ...r, items: d.items }] : [];
  });
  const projectsIn = movedToday.map((p, i) => ({ ...p, updates: updates[i] }));

  const timeline = buildTimeline({ briefs: briefs.rows, reports: fullReports, projects: projectsIn, events, timeZone, now });
  const tomorrow = buildTomorrow({ events, timeZone, now });
  const facts = todayFacts({
    now,
    timeZone,
    quotes,
    metrics,
    series: { quotes: quoteSeries, metrics: metricSeries },
    projects,
    events,
    brief: briefs.rows[0] ?? null,
    report: fullReports[0] ?? null,
  });

  return {
    nowMs: now.getTime(),
    timeZone,
    displayName: settings.display_name,
    backdrop: displayBackdrop(devices),
    timeline,
    tomorrow,
    ...facts,
    insights: buildInsights({ ...facts, timeZone, ingest }, now.getTime()),
    suggestions: buildSuggestions({ ...facts, nowMs: now.getTime() }),
  };
}
