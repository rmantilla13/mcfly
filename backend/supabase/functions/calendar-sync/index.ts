// calendar-sync: reads each calendar subscription's iCal link and writes its
// events (the next 60 days, the past day) through ingest_events with replace,
// under the built-in "Calendar subscriptions" agent. Migrations
// 20261015000002 (the sources) and 20261015000003 (the schedule).
//
//   POST {}                    every enabled source   (pg_cron, every 15 min)
//   POST { source: "<uuid>" }  one source              ("Sync now" in the console)
//
// Who may call: pg_cron, with `x-mcfly-cron: <the Vault secret>` (../_shared/cron.ts), or a
// platform admin with their own JWT. The links are read with the service
// role and never leave this function.
//
// Answers { ok: true, synced: [{ name, count } | { name, error }] }.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { isCronCall } from "../_shared/cron.ts";
import { bearerToken, isUuid, json, preflight, readJson } from "../_shared/http.ts";
import { MAX_EVENTS, parseIcs } from "./ics.ts";

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
  if (res.status === 401 || res.status === 403 || res.status === 404) return { error: `the link answered ${res.status}; it may have been reset` };
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

type Source = { id: string; name: string; url: string; color: string | null; agent: string };

async function syncOne(s: Source): Promise<{ name: string; count?: number; error?: string }> {
  const got = await download(s.url);
  let error: string | null = null;
  let count = 0;
  if ("error" in got) {
    error = got.error;
  } else {
    try {
      const now = Date.now();
      const items = parseIcs(got.text, { from: new Date(now - DAY), to: new Date(now + 60 * DAY), color: s.color });
      const { data, error: dbError } = await service.rpc("ingest_events", {
        agent: s.agent,
        items: items.slice(0, MAX_EVENTS).map((i) => ({ ...i, calendar: s.name })),
        replace_calendar: s.name,
      });
      if (dbError) error = dbError.message;
      else count = Number(data ?? items.length);
    } catch (err) {
      console.error(`calendar ${s.name} didn't parse:`, err);
      error = "the calendar couldn't be read (not valid iCal)";
    }
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
  const synced = [];
  for (const s of sources) synced.push(await syncOne(s));
  return json({ ok: true, synced });
});
