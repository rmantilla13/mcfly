// Calendar events grouped by day in the display's time zone (platform
// settings), with the time range as the calendar tab shows it. Pure, so
// tests/events.test.mjs can check it.

type Timed = { starts_at: string; ends_at: string; all_day: boolean };

export function safeTimeZone(tz: string | null | undefined): string {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz ?? undefined });
    return tz || "UTC";
  } catch {
    return "UTC";
  }
}

// Formatters by locale, options and zone, each made once: building one is
// far dearer than using it, and Today's clock and Ambient ask every second
// (Ambient once per event), buildTimeline once per row.
const FORMATTERS = new Map<string, Intl.DateTimeFormat>();
export function dateFormat(locale: string, options: Intl.DateTimeFormatOptions): Intl.DateTimeFormat {
  const key = `${locale}|${JSON.stringify(options)}`;
  let f = FORMATTERS.get(key);
  if (!f) {
    f = new Intl.DateTimeFormat(locale, options);
    FORMATTERS.set(key, f);
  }
  return f;
}

function parts(date: Date, timeZone: string): Record<string, number> {
  const out: Record<string, number> = {};
  const f = dateFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  for (const p of f.formatToParts(date)) if (p.type !== "literal") out[p.type] = Number(p.value);
  return out;
}

// YYYY-MM-DD of an instant in a zone.
export function dayKey(iso: string | Date, timeZone: string): string {
  const d = typeof iso === "string" ? new Date(iso) : iso;
  if (Number.isNaN(d.getTime())) return "invalid";
  const p = parts(d, timeZone);
  return `${p.year}-${String(p.month).padStart(2, "0")}-${String(p.day).padStart(2, "0")}`;
}

// The UTC instant of midnight on a zone's day (a fixture's all-day event
// starts there, as the calendar agents send them).
export function zonedMidnightUtc(day: string, timeZone: string): string {
  const [y, m, d] = day.split("-").map(Number);
  const guess = Date.UTC(y, m - 1, d);
  const offset = (at: number) => {
    const p = parts(new Date(at), timeZone);
    return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - at;
  };
  // One correction handles a DST change on the day itself.
  const first = guess - offset(guess);
  return new Date(guess - offset(first)).toISOString();
}

const DAY_LABEL = new Map<string, Intl.DateTimeFormat>();
function dayFormat(timeZone: string) {
  let f = DAY_LABEL.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone, weekday: "short", month: "short", day: "numeric" });
    DAY_LABEL.set(timeZone, f);
  }
  return f;
}

// "Today", "Tomorrow", "Yesterday", else "Thu, Oct 16".
export function dayLabel(day: string, timeZone: string, now = new Date()): string {
  const today = dayKey(now, timeZone);
  if (day === today) return "Today";
  const [y, m, d] = day.split("-").map(Number);
  const noon = Date.UTC(y, m - 1, d, 12);
  const todayNoon = (() => {
    const [ty, tm, td] = today.split("-").map(Number);
    return Date.UTC(ty, tm - 1, td, 12);
  })();
  const diff = Math.round((noon - todayNoon) / 86_400_000);
  if (diff === 1) return "Tomorrow";
  if (diff === -1) return "Yesterday";
  return dayFormat(timeZone).format(new Date(noon));
}

export type DayGroup<T> = { day: string; label: string; past: boolean; events: T[] };

// Events in start order, bucketed by the day they start (in the zone).
export function groupEventsByDay<T extends Timed>(events: T[], timeZone: string, now = new Date()): DayGroup<T>[] {
  const today = dayKey(now, timeZone);
  const groups = new Map<string, T[]>();
  for (const e of [...events].sort((a, b) => a.starts_at.localeCompare(b.starts_at))) {
    const key = dayKey(e.starts_at, timeZone);
    const list = groups.get(key) ?? [];
    list.push(e);
    groups.set(key, list);
  }
  return [...groups.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([day, list]) => ({ day, label: dayLabel(day, timeZone, now), past: day < today, events: list }));
}

const TIME = new Map<string, Intl.DateTimeFormat>();
function timeFormat(timeZone: string) {
  let f = TIME.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" });
    TIME.set(timeZone, f);
  }
  return f;
}

// "All day", "2:30 – 2:45 PM", or across days "2:30 PM – Oct 15, 1:00 AM".
export function formatEventTime(e: Timed, timeZone: string): string {
  if (e.all_day) return "All day";
  const start = new Date(e.starts_at);
  const end = new Date(e.ends_at);
  if (Number.isNaN(start.getTime())) return e.starts_at;
  const f = timeFormat(timeZone);
  const a = f.format(start);
  if (Number.isNaN(end.getTime()) || end.getTime() <= start.getTime()) return a;
  const sameDay = dayKey(start, timeZone) === dayKey(end, timeZone);
  if (!sameDay) return `${a} – ${dayFormat(timeZone).format(end).replace(/^\w+, /, "")}, ${f.format(end)}`;
  const b = f.format(end);
  // "2:30 PM – 2:45 PM" reads better as "2:30 – 2:45 PM" when the period matches.
  const period = (s: string) => s.slice(-2);
  return period(a) === period(b) ? `${a.slice(0, -3)} – ${b}` : `${a} – ${b}`;
}
