// calendar-sync: reads each calendar subscription and writes its events (the
// next 60 days, the past day) through ingest_events with replace, under the
// built-in "Calendar subscriptions" agent. A subscription is an iCal link
// (migration 20261015000002) or a calendar of a Google account the admin
// signed in with (20261016000011), read through the Calendar API with that
// account's refresh token. The schedule is 20261015000003.
//
//   POST {}                    every enabled source   (pg_cron, every 15 min)
//   POST { source: "<uuid>" }  one source              ("Sync now" in the console)
//
// Who may call: pg_cron, with `x-mcfly-cron: <the Vault secret>` (../_shared/cron.ts), or a
// platform admin with their own JWT (the google-calendar function's /notify
// route calls as the service role, for one source). The links and the
// tokens are read with the service role and never leave this function.
//
// After a Google calendar is read, its notification channel is kept
// (20261016000012): opened when there is none, renewed when under two days
// remain, the old one stopped. Google then calls /notify on a change.
//
// Answers { ok: true, synced: [{ name, count } | { name, error }] }.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { isCronCall } from "../_shared/cron.ts";
import {
  type GoogleConfig,
  googleConfig,
  listEvents,
  randomState,
  refreshAccessToken,
  RENEW_WITHIN_MS,
  SETUP_MESSAGE,
  shapeEvents,
  stopChannel,
  type TokenFailure,
  type Tokens,
  watchEvents,
  webhookAddress,
} from "../_shared/google.ts";
import { bearerToken, isUuid, json, preflight, readJson } from "../_shared/http.ts";
import { type EventItem, MAX_EVENTS, parseIcs } from "./ics.ts";
import { refusedMessage } from "./links.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MAX_ICS_BYTES = 5 * 1024 * 1024;
const DAY = 86_400_000;

const service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

async function isAdmin(jwt: string): Promise<boolean> {
  const db = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data, error } = await db.rpc("is_platform_admin");
  return !error && data === true;
}

// The feed's text, size-capped, or a sentence saying what went wrong.
async function download(url: string): Promise<{ text: string } | { error: string }> {
  let res: Response;
  try {
    res = await fetch(url, { headers: { Accept: "text/calendar, */*" }, redirect: "follow", signal: AbortSignal.timeout(20_000) });
  } catch {
    return { error: "couldn't reach the link" };
  }
  if (res.status === 401 || res.status === 403 || res.status === 404) return { error: refusedMessage(url, res.status) };
  if (!res.ok) return { error: `the link answered ${res.status}` };
  if (Number(res.headers.get("Content-Length")) > MAX_ICS_BYTES) return { error: "the calendar is over 5 MB" };
  const reader = res.body?.getReader();
  if (!reader) return { error: "the link sent nothing" };
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_ICS_BYTES) {
      await reader.cancel().catch(() => {});
      return { error: "the calendar is over 5 MB" };
    }
    chunks.push(value);
  }
  const all = new Uint8Array(size);
  let at = 0;
  for (const c of chunks) {
    all.set(c, at);
    at += c.byteLength;
  }
  const text = new TextDecoder().decode(all);
  if (!text.includes("BEGIN:VCALENDAR")) return { error: "that link isn't an iCal calendar (it should end in .ics)" };
  return { text };
}

type Source = {
  id: string;
  name: string;
  url: string | null;
  color: string | null;
  agent: string;
  kind: "ical" | "google";
  google_calendar_id: string | null;
  account_id: string | null;
  account_email: string | null;
  refresh_token: string | null;
};

type Window = { from: Date; to: Date };
type Read = { items: EventItem[] } | { error: string };

async function readLink(s: Source, w: Window): Promise<Read> {
  if (!s.url) return { error: "this subscription has no link" };
  const got = await download(s.url);
  if ("error" in got) return got;
  try {
    return { items: parseIcs(got.text, { from: w.from, to: w.to, color: s.color }) };
  } catch (err) {
    console.error(`calendar ${s.name} didn't parse:`, err);
    return { error: "the calendar couldn't be read (not valid iCal)" };
  }
}

// One access token per Google account per run, however many of its
// calendars are due.
class AccessTokens {
  private pending = new Map<string, Promise<Tokens | TokenFailure>>();
  constructor(private cfg: GoogleConfig | null) {}
  for(account: string, refreshToken: string): Promise<Tokens | TokenFailure> {
    if (!this.cfg) return Promise.resolve({ error: SETUP_MESSAGE, revoked: false });
    let p = this.pending.get(account);
    if (!p) {
      p = refreshAccessToken(this.cfg, refreshToken);
      this.pending.set(account, p);
    }
    return p;
  }
}

// What the console shows under the account when its sign-in is gone.
async function markAccount(account: string, error: string): Promise<void> {
  const { error: dbError } = await service.rpc("google_account_failed", { account, error });
  if (dbError) console.error("google_account_failed failed:", dbError.message);
}

async function readGoogle(s: Source, w: Window, tokens: AccessTokens): Promise<Read> {
  if (!s.account_id || !s.refresh_token || !s.google_calendar_id) return { error: "this calendar's Google account is gone; connect it and add the calendar again" };
  const token = await tokens.for(s.account_id, s.refresh_token);
  if ("error" in token) {
    if (token.revoked) await markAccount(s.account_id, token.error);
    return { error: token.error };
  }
  const listed = await listEvents(token.access_token, s.google_calendar_id, w.from, w.to);
  if (!listed.ok) {
    if (listed.revoked) await markAccount(s.account_id, listed.error);
    return { error: listed.error };
  }
  return { items: shapeEvents(listed.items, { color: s.color }) };
}

type Watch = { source_id: string; channel_id: string; resource_id: string; expires_at: string };

async function listWatches(): Promise<Map<string, Watch>> {
  const { data, error } = await service.rpc("google_watch_list");
  if (error) console.error("google_watch_list failed:", error.message);
  return new Map(((data ?? []) as Watch[]).map((w) => [w.source_id, w]));
}

// A channel for the calendar: a new one when there is none or the current
// one is nearly over (Google gives about a week), the old one stopped once
// the new one exists. A refusal is kept on the source for the console.
async function keepWatch(s: Source, current: Watch | undefined, tokens: AccessTokens, address: string | null): Promise<void> {
  if (!address || !s.account_id || !s.refresh_token || !s.google_calendar_id) return;
  if (current && Date.parse(current.expires_at) - Date.now() > RENEW_WITHIN_MS) return;
  const token = await tokens.for(s.account_id, s.refresh_token);
  if ("error" in token) return;
  const channelId = crypto.randomUUID();
  const secret = randomState();
  const made = await watchEvents(token.access_token, s.google_calendar_id, { address, channelId, token: secret });
  if (!made.ok) {
    const { error } = await service.rpc("google_watch_failed", { source: s.id, error: made.error });
    if (error) console.error("google_watch_failed failed:", error.message);
    return;
  }
  const { error } = await service.rpc("google_watch_save", {
    source: s.id,
    channel_id: made.channel.channelId,
    resource_id: made.channel.resourceId,
    token: secret,
    expires_at: made.channel.expiresAt,
  });
  if (error) {
    console.error("google_watch_save failed:", error.message);
    await stopChannel(token.access_token, made.channel);
    return;
  }
  if (current && current.channel_id !== made.channel.channelId) {
    await stopChannel(token.access_token, { channelId: current.channel_id, resourceId: current.resource_id });
  }
}

async function syncOne(s: Source, tokens: AccessTokens): Promise<{ name: string; count?: number; error?: string }> {
  const now = Date.now();
  const window = { from: new Date(now - DAY), to: new Date(now + 60 * DAY) };
  const got = s.kind === "google" ? await readGoogle(s, window, tokens) : await readLink(s, window);
  let error: string | null = null;
  let count = 0;
  if ("error" in got) {
    error = got.error;
  } else {
    const { data, error: dbError } = await service.rpc("ingest_events", {
      agent: s.agent,
      items: got.items.slice(0, MAX_EVENTS).map((i) => ({ ...i, calendar: s.name })),
      replace_calendar: s.name,
    });
    if (dbError) error = dbError.message;
    else count = Number(data ?? got.items.length);
  }
  const { error: saveError } = await service.rpc("calendar_source_synced", { source: s.id, count, error });
  if (saveError) console.error("calendar_source_synced failed:", saveError.message);
  return error ? { name: s.name, error } : { name: s.name, count };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const cron = await isCronCall(req, service);
  if (!cron) {
    const jwt = bearerToken(req);
    if (!jwt || !(await isAdmin(jwt))) return json({ error: "sign in as the admin" }, 401);
  }
  const read = await readJson(req);
  if ("error" in read) return read.error;
  const body = (typeof read.body === "object" && read.body !== null ? read.body : {}) as Record<string, unknown>;
  const only = typeof body.source === "string" && isUuid(body.source) ? body.source : null;

  const { data, error } = await service.rpc("calendar_sources_due", { source: only });
  if (error) {
    console.error("calendar_sources_due failed:", error.message);
    return json({ error: "couldn't read the calendar list; try again in a moment" }, 503);
  }
  const sources = (data ?? []) as Source[];
  const tokens = new AccessTokens(googleConfig());
  const watches = sources.some((s) => s.kind === "google") ? await listWatches() : new Map<string, Watch>();
  const address = webhookAddress();
  const synced = [];
  for (const s of sources) {
    const result = await syncOne(s, tokens);
    synced.push(result);
    if (s.kind === "google" && !result.error) await keepWatch(s, watches.get(s.id), tokens, address);
  }
  return json({ ok: true, synced });
});
