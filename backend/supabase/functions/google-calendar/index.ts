// google-calendar: the Google sign-in behind the console's Calendars page,
// and what follows from it. Migration 20261016000011.
//
//   POST { action: "connect", return_to, email? }  → { url }   the admin's browser goes there (Google), and then
//   GET  /callback?code&state                      → 302 to return_to with ?google=connected, or ?google_error=<sentence>
//   POST { action: "calendars", account }          → { ok, email, calendars: [{ id, name, color, primary, access_role, selected }] }
//   POST { action: "disconnect", account }         → { ok, email }   revoked at Google; the account, its calendars and their events go
//
// Who may call: a platform admin with their own JWT (the POSTs). The callback
// is Google sending the admin's browser back: it is tied to a sign-in the
// admin began (google_oauth_begin / google_oauth_finish: a random state, one
// use, ten minutes) and does nothing without one. Secrets: GOOGLE_CLIENT_ID
// and GOOGLE_CLIENT_SECRET (../_shared/google.ts). The refresh token goes to
// google_account_save and is read back only here and in calendar-sync.

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  authorizationUrl,
  emailFromIdToken,
  exchangeCode,
  type GoogleConfig,
  googleConfig,
  hasCalendarScope,
  listCalendars,
  randomState,
  refreshAccessToken,
  revokeToken,
  SETUP_MESSAGE,
} from "../_shared/google.ts";
import { authenticate, bearerToken, isUuid, json, preflight, readJson } from "../_shared/http.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

const asUser = (jwt: string) =>
  createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

type Credentials = { email: string; refresh_token: string };

async function credentials(account: string): Promise<Credentials | null> {
  const { data, error } = await service.rpc("google_account_credentials", { account });
  if (error) {
    console.error("google_account_credentials failed:", error.message);
    return null;
  }
  const row = Array.isArray(data) ? (data[0] as Credentials | undefined) : undefined;
  return row && typeof row.refresh_token === "string" ? row : null;
}

// What the console shows under the account; null clears it.
async function markAccount(account: string, error: string | null): Promise<void> {
  const { error: dbError } = await service.rpc("google_account_failed", { account, error });
  if (dbError) console.error("google_account_failed failed:", dbError.message);
}

const escapeHtml = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

// For the browser when there is nowhere to send it back to.
const page = (text: string, status: number) =>
  new Response(
    `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>McFly</title>` +
      `<p style="font: 17px/1.5 system-ui, sans-serif; max-width: 36em; margin: 3rem auto; padding: 0 1rem">${escapeHtml(text)}</p>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } },
  );

// Back to the console, with one query parameter saying how it went.
function backTo(returnTo: string, params: Record<string, string>): Response {
  const u = new URL(returnTo);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  return new Response(null, { status: 302, headers: { Location: u.toString(), "Cache-Control": "no-store" } });
}

// Google's redirect of the admin's browser.
async function callback(req: Request, cfg: GoogleConfig | null): Promise<Response> {
  const url = new URL(req.url);
  const state = url.searchParams.get("state") ?? "";
  if (state.length < 32 || state.length > 128) return page("This isn't a sign-in McFly began. Go to McFly's Calendars page and connect from there.", 400);
  const { data, error } = await service.rpc("google_oauth_finish", { state });
  if (error) {
    console.error("google_oauth_finish failed:", error.message);
    return page("Couldn't finish the sign-in just now. Go back to McFly's Calendars page and try again.", 503);
  }
  const begun = Array.isArray(data) ? (data[0] as { user_id: string; return_to: string } | undefined) : undefined;
  if (!begun?.return_to) return page("This sign-in link has expired or was used already. Go back to McFly's Calendars page and connect again.", 400);
  const back = (problem?: string) => backTo(begun.return_to, problem ? { google_error: problem } : { google: "connected" });

  if (!cfg) return back(SETUP_MESSAGE);
  const refused = url.searchParams.get("error");
  if (refused) return back(refused === "access_denied" ? "Google's sign-in was cancelled" : `Google answered ${refused.slice(0, 60)}`);
  const code = url.searchParams.get("code");
  if (!code) return back("Google sent no sign-in code");

  const tokens = await exchangeCode(cfg, code);
  if ("error" in tokens) return back(tokens.error);
  if (!tokens.refresh_token) {
    await revokeToken(tokens.access_token);
    return back("Google didn't give McFly a lasting sign-in; try again, and allow access when asked");
  }
  if (!hasCalendarScope(tokens.scope)) {
    await revokeToken(tokens.refresh_token);
    return back("calendar access was left unticked; connect again and allow McFly to see your calendars");
  }
  const email = emailFromIdToken(tokens.id_token);
  if (!email) {
    await revokeToken(tokens.refresh_token);
    return back("couldn't tell which Google account signed in");
  }
  const { error: saveError } = await service.rpc("google_account_save", {
    email,
    refresh_token: tokens.refresh_token,
    scope: tokens.scope ?? null,
    who: begun.user_id,
  });
  if (saveError) {
    console.error("google_account_save failed:", saveError.message);
    await revokeToken(tokens.refresh_token);
    return back(/at most 10/i.test(saveError.message) ? "at most 10 Google accounts" : "couldn't keep the sign-in; try again in a moment");
  }
  return back();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight();
  const cfg = googleConfig();
  if (req.method === "GET") {
    const path = new URL(req.url).pathname.replace(/\/+$/, "");
    return path.endsWith("/callback") ? callback(req, cfg) : json({ error: "not found" }, 404);
  }
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const jwt = bearerToken(req);
  if (!jwt) return json({ error: "sign in required" }, 401);
  const who = await authenticate(service, jwt);
  if ("error" in who) return who.error;
  const db = asUser(jwt);
  const { data: isAdmin } = await db.rpc("is_platform_admin");
  if (isAdmin !== true) return json({ error: "platform admins only" }, 403);

  const read = await readJson(req);
  if ("error" in read) return read.error;
  const body = (typeof read.body === "object" && read.body !== null ? read.body : {}) as Record<string, unknown>;

  try {
    switch (body.action) {
      case "connect": {
        if (!cfg) return json({ error: SETUP_MESSAGE }, 503);
        const returnTo = typeof body.return_to === "string" ? body.return_to.trim() : "";
        if (!/^https?:\/\/[^/\s?#]+/i.test(returnTo) || returnTo.length > 2000) return json({ error: "return_to must be a web address" }, 400);
        const state = randomState();
        const { error } = await service.rpc("google_oauth_begin", { state, who: (who.user as { id: string }).id, return_to: returnTo });
        if (error) {
          console.error("google_oauth_begin failed:", error.message);
          return json({ error: "couldn't begin the sign-in; try again in a moment" }, 503);
        }
        const hint = typeof body.email === "string" && body.email.includes("@") ? body.email.trim().slice(0, 320) : null;
        return json({ ok: true, url: authorizationUrl(cfg, state, hint) });
      }
      case "calendars": {
        if (!isUuid(body.account)) return json({ error: "account must be a uuid" }, 400);
        const account = body.account.toLowerCase();
        const creds = await credentials(account);
        if (!creds) return json({ error: "that Google account isn't connected" }, 404);
        if (!cfg) return json({ error: SETUP_MESSAGE }, 503);
        const token = await refreshAccessToken(cfg, creds.refresh_token);
        if ("error" in token) {
          if (token.revoked) await markAccount(account, token.error);
          return json({ error: token.error }, token.revoked ? 409 : 503);
        }
        const listed = await listCalendars(token.access_token);
        if (!listed.ok) {
          if (listed.revoked) await markAccount(account, listed.error);
          return json({ error: listed.error }, listed.revoked ? 409 : 503);
        }
        await markAccount(account, null);
        return json({ ok: true, email: creds.email, calendars: listed.calendars });
      }
      case "disconnect": {
        if (!isUuid(body.account)) return json({ error: "account must be a uuid" }, 400);
        const account = body.account.toLowerCase();
        // Google forgets McFly first (best effort), then the account goes, as
        // the admin so the audit row is theirs.
        const creds = await credentials(account);
        if (creds) await revokeToken(creds.refresh_token);
        const { data, error } = await db.rpc("admin_delete_google_account", { account });
        if (error) {
          if (/isn't connected/i.test(error.message)) return json({ error: error.message }, 404);
          return json({ error: error.message }, 500);
        }
        return json({ ok: true, email: data });
      }
      default:
        return json({ error: "action must be connect, calendars or disconnect" }, 400);
    }
  } catch (err) {
    console.error(`google-calendar ${String(body.action)} failed:`, err);
    return json({ error: "something went wrong" }, 500);
  }
});
