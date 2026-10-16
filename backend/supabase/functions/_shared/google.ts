// Google Calendar, for the google-calendar function (the sign-in) and
// calendar-sync (the reading): OAuth 2.0 with a read-only scope, the
// account's calendar list, and its events as McFly stores them. The network
// calls are thin; everything that shapes data is pure, so google.test.ts
// can check it without Google.

import type { EventItem } from "../calendar-sync/ics.ts";

export const AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
export const TOKEN_URL = "https://oauth2.googleapis.com/token";
export const REVOKE_URL = "https://oauth2.googleapis.com/revoke";
export const CALENDAR_API = "https://www.googleapis.com/calendar/v3";
export const CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar.readonly";
// openid + email say which account signed in (the id token's email); the
// calendar scope is the only access asked for, and it is read-only.
export const SCOPES = ["openid", "email", CALENDAR_SCOPE];

export const SETUP_MESSAGE =
  "Google sign-in isn't set up: add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET under Edge Functions → Secrets (docs/ADMIN.md, Google Calendar)";
export const REVOKED_MESSAGE = "Google no longer accepts this sign-in; connect the account again on the Calendars page";

export type GoogleConfig = { clientId: string; clientSecret: string; redirectUri: string };

// The OAuth client, from the function secrets. The redirect URI is this
// project's google-calendar function unless GOOGLE_REDIRECT_URI says
// otherwise (a custom domain in front of Supabase); it has to match the one
// registered in Google Cloud to the character.
export function googleConfig(env: (name: string) => string | undefined = (n) => Deno.env.get(n)): GoogleConfig | null {
  const clientId = env("GOOGLE_CLIENT_ID")?.trim() ?? "";
  const clientSecret = env("GOOGLE_CLIENT_SECRET")?.trim() ?? "";
  if (!clientId || !clientSecret) return null;
  const base = (env("SUPABASE_URL") ?? "").trim().replace(/\/+$/, "");
  const redirectUri = env("GOOGLE_REDIRECT_URI")?.trim() || `${base}/functions/v1/google-calendar/callback`;
  return { clientId, clientSecret, redirectUri };
}

// Where the admin's browser goes to sign in. `access_type=offline` asks for
// a refresh token, so McFly can read when nobody is signed in; Google only
// hands one out on a fresh consent, hence `prompt=consent`.
export function authorizationUrl(cfg: GoogleConfig, state: string, loginHint?: string | null): string {
  const u = new URL(AUTH_URL);
  u.searchParams.set("client_id", cfg.clientId);
  u.searchParams.set("redirect_uri", cfg.redirectUri);
  u.searchParams.set("response_type", "code");
  u.searchParams.set("scope", SCOPES.join(" "));
  u.searchParams.set("access_type", "offline");
  u.searchParams.set("prompt", "consent select_account");
  u.searchParams.set("include_granted_scopes", "true");
  u.searchParams.set("state", state);
  if (loginHint) u.searchParams.set("login_hint", loginHint);
  return u.toString();
}

// 32 random bytes as hex: the state that ties Google's redirect to a sign-in
// the admin began.
export function randomState(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) => b.toString(16).padStart(2, "0")).join("");
}

export type Tokens = { access_token: string; refresh_token?: string; scope?: string; id_token?: string; expires_in?: number };
export type TokenFailure = { error: string; revoked: boolean };

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

async function tokenRequest(params: Record<string, string>): Promise<Tokens | { code: string }> {
  let res: Response;
  try {
    res = await fetch(TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(params),
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    return { code: "unreachable" };
  }
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    // Not JSON: the status says enough.
  }
  if (res.ok && isObject(body) && typeof body.access_token === "string") return body as Tokens;
  return { code: isObject(body) && typeof body.error === "string" ? body.error : `HTTP ${res.status}` };
}

// The code Google sent the browser back with, for its tokens.
export async function exchangeCode(cfg: GoogleConfig, code: string): Promise<Tokens | TokenFailure> {
  const got = await tokenRequest({
    code,
    client_id: cfg.clientId,
    client_secret: cfg.clientSecret,
    redirect_uri: cfg.redirectUri,
    grant_type: "authorization_code",
  });
  if ("code" in got) {
    if (got.code === "unreachable") return { error: "couldn't reach Google; try again", revoked: false };
    // invalid_grant here: the code was used or has expired (they are good once, for minutes).
    if (got.code === "invalid_grant") return { error: "that sign-in expired before it finished; try again", revoked: false };
    if (got.code === "redirect_uri_mismatch") {
      return { error: `Google refused the redirect address; register ${cfg.redirectUri} on the OAuth client in Google Cloud`, revoked: false };
    }
    return { error: `Google answered ${got.code}`, revoked: false };
  }
  return got;
}

// A fresh access token from the account's refresh token. `revoked` means the
// sign-in is gone for good (Google account settings, a password change, or
// the OAuth app still in Testing after a week): the account has to be
// connected again.
export async function refreshAccessToken(cfg: GoogleConfig, refreshToken: string): Promise<Tokens | TokenFailure> {
  const got = await tokenRequest({
    refresh_token: refreshToken,
    client_id: cfg.clientId,
    client_secret: cfg.clientSecret,
    grant_type: "refresh_token",
  });
  if ("code" in got) {
    if (got.code === "unreachable") return { error: "couldn't reach Google", revoked: false };
    if (got.code === "invalid_grant") return { error: REVOKED_MESSAGE, revoked: true };
    return { error: `Google answered ${got.code}`, revoked: false };
  }
  return got;
}

// Tells Google to forget McFly (disconnect, or a sign-in we won't keep).
// Best effort: a failure here changes nothing on our side.
export async function revokeToken(token: string): Promise<void> {
  try {
    await fetch(REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token }),
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    // Nothing to do.
  }
}

// The account's email from the id token Google returned with the tokens. It
// came straight from Google's token endpoint over TLS, so its payload is
// read, not verified.
export function emailFromIdToken(idToken: string | undefined | null): string | null {
  if (!idToken) return null;
  const parts = idToken.split(".");
  if (parts.length < 2) return null;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))));
    const email = isObject(payload) && typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
    return /^[^@\s]+@[^@\s]+$/.test(email) && email.length <= 320 ? email : null;
  } catch {
    return null;
  }
}

// Google lets the person untick a scope on the consent screen.
export function hasCalendarScope(scope: string | undefined | null): boolean {
  return (scope ?? "").split(/\s+/).includes(CALENDAR_SCOPE);
}

// ───────────────────────────── The Calendar API ─────────────────────────────

export type ApiFailure = { ok: false; error: string; status: number; revoked: boolean };

// What to tell the person when Google refuses a read, in a sentence the
// console shows under the calendar (≤300 characters, calendar_source_synced).
export function apiMessage(status: number, body: unknown): string {
  let reason = "";
  if (isObject(body) && isObject(body.error)) {
    const first = Array.isArray(body.error.errors) ? body.error.errors[0] : null;
    if (isObject(first) && typeof first.reason === "string") reason = first.reason;
    else if (typeof body.error.status === "string") reason = body.error.status;
  }
  if (status === 401) return REVOKED_MESSAGE;
  if (status === 429 || (status === 403 && /ratelimit|quota|RESOURCE_EXHAUSTED/i.test(reason))) {
    return "Google asked McFly to slow down; it will try again in 15 minutes";
  }
  if (reason.startsWith("push.")) {
    return reason === "push.webhookUrlUnauthorized"
      ? "Google refused the notification channel (push.webhookUrlUnauthorized): the address's domain isn't verified for the Cloud project; docs/ADMIN.md, Instant updates"
      : `Google refused the notification channel (${reason.slice(0, 60)})`;
  }
  if (status === 403 || status === 404) return "Google doesn't show this calendar to the account anymore (unshared, or deleted)";
  return `Google answered ${status}${reason ? ` (${reason.slice(0, 60)})` : ""}`;
}

async function apiGet(accessToken: string, url: URL): Promise<{ ok: true; body: Record<string, unknown> } | ApiFailure> {
  let res: Response;
  try {
    res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` }, signal: AbortSignal.timeout(20_000) });
  } catch {
    return { ok: false, error: "couldn't reach Google", status: 0, revoked: false };
  }
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    // Not JSON.
  }
  if (!res.ok) return { ok: false, error: apiMessage(res.status, body), status: res.status, revoked: res.status === 401 };
  return { ok: true, body: isObject(body) ? body : {} };
}

export type GoogleCalendar = {
  id: string;
  name: string;
  color: string | null;
  primary: boolean;
  access_role: string;
  selected: boolean; // shown in Google Calendar's own list
};

function clean(value: unknown, max: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const v = value.replace(/\s+/g, " ").trim();
  return v ? v.slice(0, max) : undefined;
}

function hexColor(value: unknown): string | null {
  return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value.trim()) ? value.trim().toUpperCase() : null;
}

// calendarList entries → what the console lists: the primary calendar first,
// then the ones shown in Google Calendar, then the rest by name. A
// subscription's own name for a shared calendar (summaryOverride) wins.
export function shapeCalendarList(items: unknown[]): GoogleCalendar[] {
  const out: GoogleCalendar[] = [];
  for (const raw of items) {
    if (!isObject(raw) || typeof raw.id !== "string" || !raw.id || raw.deleted === true) continue;
    out.push({
      id: raw.id.slice(0, 300),
      name: clean(raw.summaryOverride, 80) ?? clean(raw.summary, 80) ?? raw.id.slice(0, 80),
      color: hexColor(raw.backgroundColor),
      primary: raw.primary === true,
      access_role: typeof raw.accessRole === "string" ? raw.accessRole : "reader",
      selected: raw.selected === true && raw.hidden !== true,
    });
  }
  return out.sort((a, b) => Number(b.primary) - Number(a.primary) || Number(b.selected) - Number(a.selected) || a.name.localeCompare(b.name));
}

export async function listCalendars(accessToken: string): Promise<{ ok: true; calendars: GoogleCalendar[] } | ApiFailure> {
  const items: unknown[] = [];
  let pageToken: string | undefined;
  for (let page = 0; page < 10; page++) {
    const u = new URL(`${CALENDAR_API}/users/me/calendarList`);
    u.searchParams.set("maxResults", "250");
    u.searchParams.set("showHidden", "true");
    u.searchParams.set("fields", "items(id,summary,summaryOverride,backgroundColor,primary,accessRole,selected,hidden,deleted),nextPageToken");
    if (pageToken) u.searchParams.set("pageToken", pageToken);
    const got = await apiGet(accessToken, u);
    if (!got.ok) return got;
    if (Array.isArray(got.body.items)) items.push(...got.body.items);
    pageToken = typeof got.body.nextPageToken === "string" ? got.body.nextPageToken : undefined;
    if (!pageToken) break;
  }
  return { ok: true, calendars: shapeCalendarList(items) };
}

export const MAX_GOOGLE_EVENTS = 1000; // what one ingest_events push may carry

// One calendar's events in a window, every occurrence of a repeating event
// as its own item (Google expands them: singleEvents).
export async function listEvents(accessToken: string, calendarId: string, from: Date, to: Date): Promise<{ ok: true; items: unknown[] } | ApiFailure> {
  const items: unknown[] = [];
  let pageToken: string | undefined;
  for (let page = 0; page < 5 && items.length < MAX_GOOGLE_EVENTS; page++) {
    const u = new URL(`${CALENDAR_API}/calendars/${encodeURIComponent(calendarId)}/events`);
    u.searchParams.set("singleEvents", "true");
    u.searchParams.set("orderBy", "startTime");
    u.searchParams.set("maxResults", "2500");
    u.searchParams.set("timeMin", from.toISOString());
    u.searchParams.set("timeMax", to.toISOString());
    u.searchParams.set(
      "fields",
      "items(id,iCalUID,status,eventType,summary,description,location,start,end,htmlLink,attendees(self,responseStatus)),nextPageToken",
    );
    if (pageToken) u.searchParams.set("pageToken", pageToken);
    const got = await apiGet(accessToken, u);
    if (!got.ok) return got;
    if (Array.isArray(got.body.items)) items.push(...got.body.items);
    pageToken = typeof got.body.nextPageToken === "string" ? got.body.nextPageToken : undefined;
    if (!pageToken) break;
  }
  return { ok: true, items };
}

// The day before a YYYY-MM-DD date.
function previousDay(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return date;
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

// Google writes descriptions as HTML as often as not.
export function plainText(html: string): string {
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|tr|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// Google's events → the events McFly stores. Cancelled occurrences, events
// the account declined and working-location markers ("Office", "Home") are
// left out. An all-day event is kept as the iCal path and agents keep them:
// midnight UTC of its first day to 23:59:59 of its last (Google's end date
// is the day after, exclusive).
export function shapeEvents(items: unknown[], opts: { color?: string | null } = {}): EventItem[] {
  const out: EventItem[] = [];
  for (const raw of items) {
    if (out.length >= MAX_GOOGLE_EVENTS) break;
    if (!isObject(raw) || raw.status === "cancelled" || raw.eventType === "workingLocation") continue;
    const attendees = Array.isArray(raw.attendees) ? raw.attendees : [];
    if (attendees.some((a) => isObject(a) && a.self === true && a.responseStatus === "declined")) continue;
    const start = isObject(raw.start) ? raw.start : {};
    const end = isObject(raw.end) ? raw.end : {};
    let startsAt: string;
    let endsAt: string;
    let allDay = false;
    if (typeof start.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(start.date)) {
      allDay = true;
      startsAt = `${start.date}T00:00:00Z`;
      const last = typeof end.date === "string" && end.date > start.date ? previousDay(end.date) : start.date;
      endsAt = `${last}T23:59:59Z`;
    } else if (typeof start.dateTime === "string") {
      const s = Date.parse(start.dateTime);
      if (Number.isNaN(s)) continue;
      const e = typeof end.dateTime === "string" ? Date.parse(end.dateTime) : NaN;
      startsAt = new Date(s).toISOString();
      endsAt = new Date(Number.isNaN(e) || e < s ? s : e).toISOString();
    } else {
      continue;
    }
    const id = typeof raw.id === "string" && raw.id ? raw.id : typeof raw.iCalUID === "string" && raw.iCalUID ? `${raw.iCalUID}@${startsAt}` : "";
    if (!id) continue;
    const location = clean(raw.location, 300);
    const description = typeof raw.description === "string" ? plainText(raw.description).slice(0, 4000) : "";
    const url = typeof raw.htmlLink === "string" && /^https:\/\//i.test(raw.htmlLink) ? raw.htmlLink.slice(0, 2000) : undefined;
    out.push({
      id: id.slice(0, 200),
      title: clean(raw.summary, 300) ?? "Busy",
      starts_at: startsAt,
      ends_at: endsAt,
      all_day: allDay,
      ...(location ? { location } : {}),
      ...(description ? { description } : {}),
      ...(url ? { url } : {}),
      ...(opts.color ? { color: opts.color } : {}),
    });
  }
  return out.sort((a, b) => a.starts_at.localeCompare(b.starts_at));
}

// ───────────────────────────── Push notifications ─────────────────────────────
// Google tells a web hook when a calendar changes (events.watch), and
// calendar-sync reads just that calendar. Channels last about a week.

const DAY_MS = 86_400_000;
export const WATCH_DAYS = 7; // asked for; Google may grant less
export const RENEW_WITHIN_MS = 2 * DAY_MS; // renewed on the run that finds less than this left

// Where Google sends notifications: this project's google-calendar function,
// unless GOOGLE_WEBHOOK_URL names another https address. Google only accepts
// an address whose domain is verified for the Cloud project, which a
// supabase.co subdomain can't be; the console's /api/google/notify on a
// domain of your own forwards here (docs/ADMIN.md, Instant updates).
export function webhookAddress(env: (name: string) => string | undefined = (n) => Deno.env.get(n)): string | null {
  const own = env("GOOGLE_WEBHOOK_URL")?.trim();
  if (own) return /^https:\/\/[^/\s]+/i.test(own) ? own : null;
  const base = (env("SUPABASE_URL") ?? "").trim().replace(/\/+$/, "");
  return base ? `${base}/functions/v1/google-calendar/notify` : null;
}

export type WatchChannel = { channelId: string; resourceId: string; expiresAt: string };

// The events.watch request for one calendar: a channel id of our choosing,
// a token Google echoes back with every notification, and when to stop.
export function watchRequest(
  calendarId: string,
  opts: { address: string; channelId: string; token: string; now?: number },
): { url: string; body: Record<string, string> } {
  const now = opts.now ?? Date.now();
  return {
    url: `${CALENDAR_API}/calendars/${encodeURIComponent(calendarId)}/events/watch`,
    body: { id: opts.channelId, type: "web_hook", address: opts.address, token: opts.token, expiration: String(now + WATCH_DAYS * DAY_MS) },
  };
}

async function apiPost(accessToken: string, url: string, body: unknown): Promise<{ ok: true; body: Record<string, unknown> } | ApiFailure> {
  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    return { ok: false, error: "couldn't reach Google", status: 0, revoked: false };
  }
  let answer: unknown = null;
  try {
    answer = await res.json();
  } catch {
    // 204, or not JSON.
  }
  if (!res.ok) return { ok: false, error: apiMessage(res.status, answer), status: res.status, revoked: res.status === 401 };
  return { ok: true, body: isObject(answer) ? answer : {} };
}

// What Google's answer to events.watch becomes. `expiration` comes as
// milliseconds since the epoch, in a string.
export function shapeChannel(body: Record<string, unknown>, fallback: { channelId: string; now?: number }): WatchChannel | null {
  const resourceId = typeof body.resourceId === "string" ? body.resourceId.trim() : "";
  if (!resourceId) return null;
  const channelId = typeof body.id === "string" && body.id ? body.id : fallback.channelId;
  const ms = Number(body.expiration);
  const expiresAt = Number.isFinite(ms) && ms > 0 ? new Date(ms) : new Date((fallback.now ?? Date.now()) + DAY_MS);
  return { channelId: channelId.slice(0, 128), resourceId: resourceId.slice(0, 200), expiresAt: expiresAt.toISOString() };
}

export async function watchEvents(
  accessToken: string,
  calendarId: string,
  opts: { address: string; channelId: string; token: string },
): Promise<{ ok: true; channel: WatchChannel } | ApiFailure> {
  const { url, body } = watchRequest(calendarId, opts);
  const got = await apiPost(accessToken, url, body);
  if (!got.ok) return got;
  const channel = shapeChannel(got.body, { channelId: opts.channelId });
  if (!channel) return { ok: false, error: "Google made the channel without saying which resource it watches", status: 200, revoked: false };
  return { ok: true, channel };
}

// Tells Google to stop a channel (a renewed one's predecessor). Best effort.
export async function stopChannel(accessToken: string, channel: { channelId: string; resourceId: string }): Promise<void> {
  await apiPost(accessToken, `${CALENDAR_API}/channels/stop`, { id: channel.channelId, resourceId: channel.resourceId });
}

export type Notification = {
  channelId: string;
  resourceId: string;
  state: string; // "sync" when the channel is new, "exists" when something changed
  token: string;
  messageNumber: number | null;
};

// The headers Google sets on a notification; null without a channel id.
export function parseNotification(headers: { get(name: string): string | null }): Notification | null {
  const channelId = (headers.get("x-goog-channel-id") ?? "").trim();
  if (!channelId || channelId.length > 128) return null;
  const number = Number(headers.get("x-goog-message-number"));
  return {
    channelId,
    resourceId: (headers.get("x-goog-resource-id") ?? "").trim().slice(0, 200),
    state: (headers.get("x-goog-resource-state") ?? "").trim().toLowerCase(),
    token: (headers.get("x-goog-channel-token") ?? "").trim().slice(0, 128),
    messageNumber: Number.isFinite(number) && number > 0 ? number : null,
  };
}

// A channel's token against the one Google sent, in constant time.
export function sameToken(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
