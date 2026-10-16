import type { CalendarSource, GoogleAccount, GoogleCalendar } from "@/lib/types";

// The Calendars page's Google section, shaped for its switches: every
// calendar Google lists for an account, with its subscription when it has
// one, plus the calendars that are subscribed but Google no longer lists
// (unshared, deleted), so they can still be switched off. Pure; tested in
// tests/google-calendars.test.mjs.

export type GoogleCalendarRow = {
  id: string; // Google's calendar id
  name: string; // the subscription's name when there is one, else Google's
  color: string | null; // the subscription's color, else Google's
  primary: boolean;
  access_role: string | null;
  listed: boolean; // Google still lists it for the account
  live: boolean; // Google notifies McFly of changes (a channel open past `now`)
  source: CalendarSource | null;
};

const watching = (s: CalendarSource | null, now: number) => !!s?.watch_expires_at && Date.parse(s.watch_expires_at) > now;

export function googleCalendarRows(account: GoogleAccount, listed: GoogleCalendar[] | null, sources: CalendarSource[], now = Date.now()): GoogleCalendarRow[] {
  const mine = new Map<string, CalendarSource>();
  for (const s of sources) {
    if (s.kind === "google" && s.account_id === account.id && s.google_calendar_id) mine.set(s.google_calendar_id, s);
  }
  const rows: GoogleCalendarRow[] = (listed ?? []).map((c) => {
    const source = mine.get(c.id) ?? null;
    mine.delete(c.id);
    return {
      id: c.id,
      name: source?.name ?? c.name,
      color: source?.color ?? c.color ?? null,
      primary: c.primary,
      access_role: c.access_role,
      listed: true,
      live: watching(source, now),
      source,
    };
  });
  for (const s of mine.values()) {
    rows.push({ id: s.google_calendar_id!, name: s.name, color: s.color, primary: false, access_role: null, listed: false, live: watching(s, now), source: s });
  }
  // The account's own calendar first, then what's shown, then Google's order
  // (its own list, then the hidden ones; the sort is stable).
  return rows.sort((a, b) => Number(b.primary) - Number(a.primary) || Number(!!b.source) - Number(!!a.source));
}

export type GoogleNotice = { kind: "connected" } | { kind: "error"; message: string };

// What the google-calendar function sends the browser back with:
// ?google=connected, or ?google_error=<a sentence>.
export function googleNotice(params: Record<string, string | string[] | undefined>): GoogleNotice | null {
  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";
  if (one(params.google) === "connected") return { kind: "connected" };
  const message = one(params.google_error)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 300);
  return message ? { kind: "error", message } : null;
}

// Where Google sends the admin back: this console's Calendars page, from the
// request's origin. Anything but a bare http(s) origin is refused.
export function googleReturnTo(origin: string | null | undefined): string | null {
  if (!origin) return null;
  let u: URL;
  try {
    u = new URL(origin);
  } catch {
    return null;
  }
  if (!/^https?:$/.test(u.protocol) || u.pathname !== "/" || u.search || u.hash || u.username || u.password) return null;
  return `${u.origin}/calendars`;
}
