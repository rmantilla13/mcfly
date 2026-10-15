import "server-only";

import { getNewsReport, getProjectUpdates, getSettings, listBriefs, listEvents, listNewsReports, listProjects, listQuotes } from "@/lib/data";
import { dayKey, safeTimeZone } from "@/lib/events";
import { cssColor, formatChange, formatPrice, changeDirection } from "@/lib/format";
import { buildTimeline, STATUS_COLOR, type TimelineItem } from "@/lib/today";

// Everything the Today page and the ambient view show, read once on the
// server in the display's time zone. Plain JSON, so it crosses into the
// client components that keep the clock.

export type TodayEvent = { id: string; title: string; calendar: string; location: string | null; starts_at: string; ends_at: string; all_day: boolean; color: string };
export type TodayTicker = { symbol: string; price: string; change: string; direction: "up" | "down" | "flat" };
export type TodayProject = { id: string; name: string; next: string; progress: number | null; color: string };
export type TodayBrief = { agent: string; color: string; publishedAt: string; title: string; summary: string } | null;
export type TodayHero = { reportId: string; source: string; color: string; count: number; headline: string; takeaway: string; imageUrl: string | null } | null;

export type TodayData = {
  nowMs: number;
  timeZone: string;
  displayName: string;
  timeline: TimelineItem[];
  events: TodayEvent[]; // from now on, today and the next week
  tickers: TodayTicker[];
  blocked: TodayProject[];
  brief: TodayBrief;
  hero: TodayHero;
};

export async function loadToday(): Promise<TodayData> {
  const now = new Date();
  const [settings, briefs, quotes, reports, projects, events] = await Promise.all([
    getSettings(),
    listBriefs(1),
    listQuotes(),
    listNewsReports(10),
    listProjects(),
    listEvents(1, 8),
  ]);
  const timeZone = safeTimeZone(settings.timezone);
  const today = dayKey(now, timeZone);

  // Only today's reports and today's project updates need a second read.
  const todaysReports = reports.filter((r) => r.report_date === today);
  const details = await Promise.all(todaysReports.map((r) => getNewsReport(r.id)));
  const fullReports = todaysReports.flatMap((r, i) => {
    const d = details[i];
    return d ? [{ ...r, items: d.items }] : [];
  });
  const movedToday = projects.filter((p) => p.last_update_at && dayKey(p.last_update_at, timeZone) === today);
  const updates = await Promise.all(movedToday.map((p) => getProjectUpdates(p.id, 20)));
  const projectsIn = movedToday.map((p, i) => ({ ...p, updates: updates[i] }));

  const timeline = buildTimeline({ briefs: briefs.rows, reports: fullReports, projects: projectsIn, events, timeZone, now });

  const latest = briefs.rows[0];
  const heroReport = fullReports[0];
  const heroItem = heroReport
    ? ([...heroReport.items].sort((a, b) => a.section_order - b.section_order || a.position - b.position).find(
        (i) => heroReport.hero_item && i.item_key === heroReport.hero_item,
      ) ?? heroReport.items[0])
    : null;

  return {
    nowMs: now.getTime(),
    timeZone,
    displayName: settings.display_name,
    timeline,
    events: events
      .filter((e) => Date.parse(e.ends_at) > now.getTime())
      .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at))
      .map((e) => ({ id: e.id, title: e.title, calendar: e.calendar, location: e.location, starts_at: e.starts_at, ends_at: e.ends_at, all_day: e.all_day, color: cssColor(e.color) ?? "#5B7CF5" })),
    tickers: quotes
      .filter((q) => !q.hidden && q.price != null)
      .sort((a, b) => a.sort_order - b.sort_order)
      .slice(0, 6)
      .map((q) => ({ symbol: q.symbol, price: formatPrice(q.price, q.currency), change: q.change_pct != null ? formatChange(null, q.change_pct) : formatChange(q.change, null), direction: changeDirection(q.change, q.change_pct) })),
    blocked: projects
      .filter((p) => p.status === "blocked")
      .map((p) => ({ id: p.id, name: p.name, next: p.next_step || p.summary || "", progress: p.progress, color: cssColor(p.color) ?? STATUS_COLOR.blocked })),
    brief: latest
      ? { agent: latest.agent_name, color: cssColor(latest.agent_color) ?? "#5B7CF5", publishedAt: latest.published_at, title: latest.title, summary: latest.body.replace(/[#*_`>]/g, "").split(/\n\s*\n/)[0].replace(/\s+/g, " ").trim() }
      : null,
    hero:
      heroReport && heroItem
        ? {
            reportId: heroReport.id,
            source: heroReport.agent_name || "Daily Pulse",
            color: cssColor(heroReport.agent_color) ?? "#5B7CF5",
            count: heroReport.items.length,
            headline: heroItem.headline,
            takeaway: heroItem.takeaway ?? "",
            imageUrl: heroItem.image_url,
          }
        : null,
  };
}
