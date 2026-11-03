// notify: a message from home, on the person's phones (PLATFORM_SPEC §2.7).
//
//   POST { message }          pg_net, after a display's message is in (the
//                             messages_notify trigger), with `x-mcfly-cron` →
//                             { ok, sent, failed, gone }; the outcome is kept
//                             on the message (message_notified)
//   POST { action: "test" }   the person's JWT → { ok, results: [{ token (its
//                             end), environment, status, reason, outcome }] }:
//                             a test notification on each of their phones
//
// The phones are the push_tokens the app registered; Apple's push service
// takes each over HTTP/2 with a provider token from APNS_KEY_ID,
// APNS_TEAM_ID and APNS_PRIVATE_KEY (apns.ts). A token Apple calls no good
// is forgotten (push_token_gone).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { isCronCall } from "../_shared/cron.ts";
import { authenticate, bearerToken, isUuid, json, preflight, readJson } from "../_shared/http.ts";
import { apnsConfig, deliverAll, describe, messagePayload, type PushMessage, type Result, type Target, testPayload, TokenCache } from "./apns.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const service = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const tokens = new TokenCache();

const NOT_SET_UP = "notifications aren't set up on the server yet";

// Forgets the tokens Apple called no good; logs the rest of what failed.
async function settle(results: Result[]): Promise<void> {
  for (const r of results) {
    if (r.outcome === "gone") {
      const { error } = await service.rpc("push_token_gone", { token: r.token });
      if (error) console.error("push_token_gone failed:", error.message);
    } else if (r.outcome !== "sent") {
      console.error(`push to …${r.token.slice(-6)} (${r.environment}) failed:`, r.status, r.reason);
    }
  }
}

async function notifyMessage(message: string): Promise<Response> {
  const { data, error } = await service.rpc("message_push", { message });
  if (error) {
    console.error("message_push failed:", error.message);
    return json({ error: "couldn't read the message" }, 503);
  }
  if (!data) return json({ ok: true, sent: 0, failed: 0, gone: 0, skipped: "not a message from home" });
  const push = data as PushMessage & { tokens: Target[] };
  const noted = async (why: string | null) => {
    const { error } = await service.rpc("message_notified", { message, error: why });
    if (error) console.error("message_notified failed:", error.message);
  };
  const config = apnsConfig((name) => Deno.env.get(name));
  if (!config) {
    await noted(NOT_SET_UP);
    return json({ ok: true, sent: 0, failed: 0, gone: 0, skipped: NOT_SET_UP });
  }
  if (push.tokens.length === 0) {
    await noted("no phone has turned on notifications yet");
    return json({ ok: true, sent: 0, failed: 0, gone: 0 });
  }
  let results: Result[];
  try {
    results = await deliverAll(fetch, tokens, config, push.tokens, messagePayload(push));
  } catch (e) {
    // The key itself couldn't be read.
    const why = e instanceof Error ? e.message : String(e);
    console.error("push key:", why);
    await noted(why);
    return json({ ok: false, error: why }, 500);
  }
  await settle(results);
  const sent = results.filter((r) => r.outcome === "sent").length;
  const gone = results.filter((r) => r.outcome === "gone").length;
  const first = results.find((r) => r.outcome !== "sent");
  await noted(sent > 0 ? null : first ? describe(first.outcome, first.status, first.reason) : "no phone took it");
  return json({ ok: true, sent, failed: results.length - sent - gone, gone });
}

async function sendTest(req: Request): Promise<Response> {
  const jwt = bearerToken(req);
  if (!jwt) return json({ error: "sign in required" }, 401);
  const who = await authenticate(service, jwt);
  if ("error" in who) return who.error;
  const db = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: isAdmin } = await db.rpc("is_platform_admin");
  if (isAdmin !== true) return json({ error: "platform admins only" }, 403);
  const config = apnsConfig((name) => Deno.env.get(name));
  if (!config) return json({ error: NOT_SET_UP }, 503);
  const user = (who.user as { id: string }).id;
  const { data, error } = await service.from("push_tokens").select("token,environment,bundle_id").eq("user_id", user);
  if (error) return json({ error: "couldn't read your phones" }, 503);
  const targets = (data ?? []) as Target[];
  if (targets.length === 0) return json({ error: "no phone of yours has turned on notifications yet" }, 404);
  let results: Result[];
  try {
    results = await deliverAll(fetch, tokens, config, targets, testPayload());
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
  await settle(results);
  return json({
    ok: results.some((r) => r.outcome === "sent"),
    results: results.map((r) => ({
      token: `…${r.token.slice(-6)}`,
      environment: r.environment,
      status: r.status,
      reason: r.reason,
      outcome: r.outcome,
      message: r.outcome === "sent" ? null : describe(r.outcome, r.status, r.reason),
    })),
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const read = await readJson(req);
  if ("error" in read) return read.error;
  const body = (typeof read.body === "object" && read.body !== null ? read.body : {}) as Record<string, unknown>;
  try {
    if (body.action === "test") return await sendTest(req);
    if (!(await isCronCall(req, service))) return json({ error: "not allowed" }, 401);
    if (!isUuid(body.message)) return json({ error: "message must be a uuid" }, 400);
    return await notifyMessage(body.message.toLowerCase());
  } catch (e) {
    console.error("notify failed:", e);
    return json({ error: "notify failed" }, 500);
  }
});
