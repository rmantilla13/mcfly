// An iCal (.ics) feed → the events McFly stores, for one window of time.
// Recurring events are expanded (with their moved and cancelled
// occurrences), times are read in the feed's own zones, all-day events stay
// all-day. Pure, so ics.test.ts can check it.

import ICAL from "npm:ical.js@2.1.0";

export type EventItem = {
  id: string;
  title: string;
  starts_at: string;
  ends_at: string;
  all_day: boolean;
  location?: string;
  description?: string;
  url?: string;
  color?: string;
};

export const MAX_EVENTS = 1000;
const MAX_OCCURRENCES_PER_EVENT = 400;

// ICAL.Time → ISO. An all-day date becomes midnight UTC of that day, the way
// ingest_events stores agents' all-day events; a floating time is read as UTC.
function iso(t: ICAL.Time): string {
  if (t.isDate) return `${String(t.year).padStart(4, "0")}-${String(t.month).padStart(2, "0")}-${String(t.day).padStart(2, "0")}T00:00:00Z`;
  return t.toJSDate().toISOString();
}

function clean(value: unknown, max: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const v = value.replace(/\s+/g, " ").trim();
  return v ? v.slice(0, max) : undefined;
}

export function parseIcs(text: string, opts: { from: Date; to: Date; color?: string | null }): EventItem[] {
  const root = new ICAL.Component(ICAL.parse(text));
  // The feed's own time zones, so TZID=... times read correctly.
  for (const tz of root.getAllSubcomponents("vtimezone")) {
    try {
      ICAL.TimezoneService.register(tz);
    } catch {
      // A broken zone falls back to UTC for its events.
    }
  }
  const from = ICAL.Time.fromJSDate(opts.from, true);
  const to = ICAL.Time.fromJSDate(opts.to, true);
  const out: EventItem[] = [];

  const vevents = root.getAllSubcomponents("vevent");
  // Moved or edited occurrences (RECURRENCE-ID) attach to their series.
  const exceptions = vevents.filter((v) => v.hasProperty("recurrence-id"));
  for (const v of vevents) {
    if (v.hasProperty("recurrence-id")) continue;
    if (String(v.getFirstPropertyValue("status") ?? "").toUpperCase() === "CANCELLED") continue;
    const event = new ICAL.Event(v);
    for (const ex of exceptions) {
      if (ex.getFirstPropertyValue("uid") === event.uid) {
        try {
          event.relateException(ex);
        } catch {
          // An exception that doesn't fit its series is skipped.
        }
      }
    }
    const base = {
      title: clean(event.summary, 300) ?? "Busy",
      location: clean(event.location, 300),
      description: typeof event.description === "string" && event.description.trim() ? event.description.trim().slice(0, 4000) : undefined,
      url: (() => {
        const u = clean(v.getFirstPropertyValue("url"), 2000);
        return u && /^https?:\/\//i.test(u) ? u : undefined;
      })(),
    };
    const push = (id: string, start: ICAL.Time, end: ICAL.Time | null, summary?: string, location?: string) => {
      if (out.length >= MAX_EVENTS) return;
      const allDay = start.isDate;
      let finish = end ?? start;
      // DTEND of an all-day event is the next day (exclusive); store the end
      // of the last day, as agents' all-day events are.
      let endsAt = iso(finish);
      if (allDay) {
        const last = finish.clone();
        if (end && end.compare(start) > 0) last.adjust(-1, 0, 0, 0);
        endsAt = iso(last).replace("T00:00:00Z", "T23:59:59Z");
      } else if (finish.compare(start) < 0) {
        finish = start;
        endsAt = iso(finish);
      }
      out.push({
        id: id.slice(0, 200),
        title: clean(summary, 300) ?? base.title,
        starts_at: iso(start),
        ends_at: endsAt,
        all_day: allDay,
        ...(location ?? base.location ? { location: location ?? base.location } : {}),
        ...(base.description ? { description: base.description } : {}),
        ...(base.url ? { url: base.url } : {}),
        ...(opts.color ? { color: opts.color } : {}),
      });
    };
    const uid = String(event.uid ?? `${base.title}-${event.startDate?.toString()}`);

    if (!event.isRecurring()) {
      if (!event.startDate) continue;
      const end = event.endDate ?? event.startDate;
      if (end.compare(from) < 0 || event.startDate.compare(to) > 0) continue;
      push(uid, event.startDate, event.endDate);
      continue;
    }
    const it = event.iterator();
    let next: ICAL.Time | null;
    let n = 0;
    while ((next = it.next()) && n < MAX_OCCURRENCES_PER_EVENT) {
      n++;
      if (next.compare(to) > 0) break;
      const occ = event.getOccurrenceDetails(next);
      if (occ.endDate.compare(from) < 0) continue;
      const item = occ.item as ICAL.Event;
      if (String(item.component.getFirstPropertyValue("status") ?? "").toUpperCase() === "CANCELLED") continue;
      push(`${uid}@${occ.recurrenceId.toString()}`, occ.startDate, occ.endDate, item.summary, item.location);
    }
  }
  return out.sort((a, b) => a.starts_at.localeCompare(b.starts_at));
}
