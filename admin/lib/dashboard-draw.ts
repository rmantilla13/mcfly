// The demo's twin of the database's drawing (20261016000010: dashboard_part,
// dashboard_widgets): a made board's parts, drawn from a snapshot of the
// feeds into the six widgets. The real console never runs this; the
// database draws and redraws made boards itself. Kept to the same rules and
// words so the demo shows what a real board would. Pure, so
// tests/dashboard-draw.test.mjs can check it.

import type { DashboardPart } from "./dashboard-sources.ts";
import { dayKey, zonedMidnightUtc } from "./events.ts";

export type DrawData = {
  now: number;
  timeZone: string;
  symbols: { symbol: string; sort_order: number; hidden: boolean }[];
  quotes: { id: number; symbol: string; name: string | null; price: number; change: number | null; change_pct: number | null; currency: string; as_of: string }[];
  metricSettings: { key: string; label: string | null; group_name: string | null; sort_order: number; hidden: boolean }[];
  metrics: { id: number; key: string; label: string | null; value: number; unit: string | null; delta: number | null; delta_pct: number | null; as_of: string }[];
  projects: { id: string; name: string; status: string; progress: number | null; summary: string; next_step: string | null; sort_order: number }[];
  events: { calendar: string; title: string; starts_at: string; ends_at: string; all_day: boolean }[];
  todos: { id: string; kind: "todo" | "reminder"; title: string; due_at: string | null; all_day: boolean; done_at: string | null; created_at: string }[];
  news: { section_key: string; section_name: string; section_order: number; position: number; headline: string }[]; // the newest report's
  briefs: { agent_id: string; title: string; body: string; kind: string; published_at: string; expires_at: string | null }[];
  agents: { id: string; name: string; has_key: boolean; revoked: boolean; last: { created_at: string; status: "ok" | "error"; message: string | null } | null }[];
};

type Raw = Record<string, unknown>;
const DAY = 86_400_000;

const strip = (o: Raw): Raw => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== null && v !== undefined));
const waiting = (title: string | null | undefined, body: string): Raw[] => [strip({ type: "text", title: title ?? null, body })];
const byText = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

function newest<T extends { as_of: string; id: number }>(rows: T[]): T | undefined {
  return rows.reduce<T | undefined>((best, r) => (!best || r.as_of > best.as_of || (r.as_of === best.as_of && r.id > best.id) ? r : best), undefined);
}

// The newest `n`, oldest first: a chart's points.
function history<T extends { as_of: string; id: number }>(rows: T[], n: number, since?: number): T[] {
  return rows
    .filter((r) => since === undefined || Date.parse(r.as_of) > since)
    .sort((a, b) => byText(b.as_of, a.as_of) || b.id - a.id)
    .slice(0, n)
    .reverse();
}

const WEEKDAY = new Map<string, Intl.DateTimeFormat>();
function formatter(timeZone: string, kind: "date" | "time"): Intl.DateTimeFormat {
  const key = `${timeZone}|${kind}`;
  let f = WEEKDAY.get(key);
  if (!f) {
    f = new Intl.DateTimeFormat(
      "en-US",
      kind === "date" ? { timeZone, weekday: "short", month: "short", day: "numeric" } : { timeZone, hour: "numeric", minute: "2-digit", hour12: true },
    );
    WEEKDAY.set(key, f);
  }
  return f;
}

// "Today 9:30 AM", "Tomorrow", "Tue Oct 20 2:00 PM": dashboard_when's words.
export function whenLabel(iso: string, allDay: boolean, timeZone: string, now: number): string {
  const day = dayKey(iso, timeZone);
  const today = dayKey(new Date(now), timeZone);
  const utc = (k: string) => {
    const [y, m, d] = k.split("-").map(Number);
    return Date.UTC(y, m - 1, d);
  };
  const diff = Math.round((utc(day) - utc(today)) / DAY);
  let label: string;
  if (diff === 0) label = "Today";
  else if (diff === 1) label = "Tomorrow";
  else if (diff === -1) label = "Yesterday";
  else {
    const p = Object.fromEntries(formatter(timeZone, "date").formatToParts(new Date(iso)).map((x) => [x.type, x.value]));
    label = `${p.weekday} ${p.month} ${p.day}`;
  }
  if (allDay) return label;
  return `${label} ${formatter(timeZone, "time").format(new Date(iso)).replace(/\s/g, " ")}`;
}

function drawPart(part: DashboardPart, d: DrawData): Raw[] {
  const heading = part.title?.trim() ? part.title.trim().slice(0, 80) : null;
  switch (part.from) {
    case "quotes": {
      const chart = part.show === "chart";
      const limit = part.limit ?? (chart ? 1 : 8);
      const picked = part.symbols.length
        ? part.symbols
        : d.symbols.filter((s) => !s.hidden).sort((a, b) => a.sort_order - b.sort_order || byText(a.symbol, b.symbol)).map((s) => s.symbol);
      const out: Raw[] = [];
      for (const symbol of picked) {
        const rows = d.quotes.filter((q) => q.symbol === symbol);
        const q = newest(rows);
        if (!q) continue;
        out.push(
          chart
            ? { type: "chart", label: q.name ? `${q.name} (${q.symbol})` : q.symbol, unit: q.currency, points: history(rows, 120, d.now - 30 * DAY).map((r) => r.price) }
            : strip({ type: "metric", label: q.symbol, value: q.price, unit: q.currency, delta: q.change, delta_pct: q.change_pct }),
        );
        if (out.length === limit) break;
      }
      return out.length ? out : waiting(heading ?? "Markets", part.symbols.length ? `No quotes yet for ${part.symbols.join(", ")}.` : "No quotes yet.");
    }
    case "metrics": {
      const chart = part.show === "chart";
      const limit = part.limit ?? (chart ? 2 : 8);
      const picked = part.keys.length
        ? part.keys
        : d.metricSettings
            .filter((s) => !s.hidden && (!part.group || s.group_name === part.group))
            .sort((a, b) => a.sort_order - b.sort_order || byText(a.key, b.key))
            .map((s) => s.key);
      const out: Raw[] = [];
      for (const key of picked) {
        const rows = d.metrics.filter((m) => m.key === key);
        const m = newest(rows);
        if (!m) continue;
        const label = d.metricSettings.find((s) => s.key === key)?.label ?? m.label ?? key;
        out.push(
          chart
            ? strip({ type: "chart", label, unit: m.unit, points: history(rows, 120).map((r) => r.value) })
            : strip({ type: "metric", label, value: m.value, unit: m.unit, delta: m.delta, delta_pct: m.delta_pct }),
        );
        if (out.length === limit) break;
      }
      return out.length ? out : waiting(heading ?? part.group ?? "Metrics", "No numbers yet.");
    }
    case "projects": {
      const limit = part.limit ?? 6;
      const shown = (
        part.projects.length
          ? part.projects.map((id) => d.projects.find((p) => p.id === id)).filter((p): p is DrawData["projects"][number] => !!p)
          : d.projects.filter((p) => p.status === "active" || p.status === "blocked").sort((a, b) => a.sort_order - b.sort_order || byText(a.name, b.name))
      ).slice(0, limit);
      if (!shown.length) return waiting(heading ?? "Projects", "No projects yet.");
      if (part.show === "list") {
        return [{ type: "list", title: heading ?? "Projects", items: shown.map((p) => p.name + (p.next_step ? ` · ${p.next_step}` : "")) }];
      }
      return shown.map((p) =>
        p.progress !== null
          ? { type: "progress", label: p.name, value: p.progress, max: 100, unit: "%" }
          : strip({
              type: "status",
              label: p.name,
              state: p.status === "blocked" ? "warn" : p.status === "paused" ? "unknown" : "ok",
              detail: (p.next_step ?? (p.summary || null))?.slice(0, 300),
            }),
      );
    }
    case "calendar": {
      const limit = part.limit ?? 8;
      const title = heading ?? (part.days === 1 ? "Today" : part.days === 2 ? "Today and tomorrow" : `Next ${part.days} days`);
      const start = Date.parse(zonedMidnightUtc(dayKey(new Date(d.now), d.timeZone), d.timeZone));
      // The window's end, as a wall-clock midnight in the zone (a DST change
      // inside the window moves it by the hour, as Postgres does).
      const endDay = new Date(start + part.days * DAY + 12 * 3_600_000);
      const end = Date.parse(zonedMidnightUtc(dayKey(endDay, d.timeZone), d.timeZone));
      const items = d.events
        .filter((e) => Date.parse(e.ends_at) > d.now && Date.parse(e.starts_at) < end && (!part.calendars.length || part.calendars.includes(e.calendar)))
        .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at) || byText(a.title, b.title))
        .slice(0, limit)
        .map((e) => `${whenLabel(e.starts_at, e.all_day, d.timeZone, d.now)} · ${e.title}`);
      return items.length ? [{ type: "list", title, items }] : waiting(title, "Nothing on the calendar.");
    }
    case "todos": {
      const limit = part.limit ?? 8;
      const title = heading ?? (part.kind === "reminder" ? "Reminders" : "To do");
      const items = d.todos
        .filter((t) => !t.done_at && (part.kind === "all" || t.kind === part.kind))
        .sort(
          (a, b) =>
            (a.due_at === null ? 1 : 0) - (b.due_at === null ? 1 : 0) ||
            byText(a.due_at ?? "", b.due_at ?? "") ||
            byText(a.created_at, b.created_at) ||
            byText(a.id, b.id),
        )
        .slice(0, limit)
        .map((t) => t.title + (t.due_at ? ` · ${whenLabel(t.due_at, t.all_day, d.timeZone, d.now)}` : ""));
      return items.length ? [{ type: "list", title, items }] : waiting(title, part.kind === "reminder" ? "No reminders set." : "Nothing open.");
    }
    case "news": {
      const rows = d.news
        .filter((i) => !part.section || i.section_key === part.section)
        .sort((a, b) => a.section_order - b.section_order || a.position - b.position)
        .slice(0, part.limit ?? 5);
      if (!rows.length) return waiting(heading ?? "Headlines", "No headlines yet.");
      const sectionName = rows.map((r) => r.section_name).sort(byText)[0];
      return [{ type: "list", title: heading ?? (part.section ? sectionName : "Headlines"), items: rows.map((r) => r.headline) }];
    }
    case "brief": {
      const b = d.briefs
        .filter((x) => (!x.expires_at || Date.parse(x.expires_at) > d.now) && (!part.kind || x.kind === part.kind) && (!part.agent || x.agent_id === part.agent))
        .sort((x, y) => byText(y.published_at, x.published_at))[0];
      return b ? [{ type: "text", title: (heading ?? b.title).slice(0, 80), body: b.body.slice(0, 2000) }] : waiting(heading ?? "Brief", "No brief yet.");
    }
    case "agents": {
      const quiet = d.now - part.hours * 3_600_000;
      const picked = part.agents.length
        ? part.agents.map((id) => d.agents.find((a) => a.id === id)).filter((a): a is DrawData["agents"][number] => !!a)
        : d.agents.filter((a) => !a.revoked && a.has_key).sort((a, b) => byText(a.name, b.name));
      const out = picked.slice(0, 12).map((a) => {
        const l = a.last;
        const at = l ? whenLabel(l.created_at, false, d.timeZone, d.now) : "";
        const old = l ? Date.parse(l.created_at) < quiet : false;
        return {
          type: "status",
          label: a.name,
          state: !l ? "unknown" : l.status === "error" ? "down" : old ? "warn" : "ok",
          detail: !l
            ? "No pushes yet"
            : l.status === "error"
              ? `Last push failed: ${l.message ?? "no reason given"}`.slice(0, 300)
              : old
                ? `Quiet since ${at}`
                : `Last push ${at}`,
        };
      });
      return out.length ? out : waiting(heading ?? "Agents", "No agents yet.");
    }
    case "note":
      return waiting(heading, part.body.trim().slice(0, 2000) || " ");
  }
}

// A made board's widgets: every part in order, at most 40, never none.
export function drawDashboard(parts: DashboardPart[], data: DrawData): Raw[] {
  const out = parts.flatMap((p) => drawPart(p, data));
  return out.length ? out.slice(0, 40) : waiting(null, "Nothing to show yet.");
}
