// admin: the one console action that needs Supabase Auth's admin API, and so
// the service role key, which never leaves the server.
//
//   { action: "revoke_device", device_id } -> { ok: true, auth_user_removed }
//
// The caller is checked with their own JWT (admin_revoke_device refuses
// non-admins and writes the audit row); the auth user is then removed with
// the service role when the database could not.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { authenticate, bearerToken, isUuid, json, preflight, readJson } from "../_shared/http.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const service = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const jwt = bearerToken(req);
  if (!jwt) return json({ error: "sign in required" }, 401);
  const who = await authenticate(service, jwt);
  if ("error" in who) return who.error;

  const read = await readJson(req);
  if ("error" in read) return read.error;
  const body = (typeof read.body === "object" && read.body !== null ? read.body : {}) as Record<string, unknown>;

  const db = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  try {
    switch (body.action) {
      case "revoke_device": {
        if (!isUuid(body.device_id)) return json({ error: "device_id must be a uuid" }, 400);
        const { data, error } = await db.rpc("admin_revoke_device", { device: body.device_id.toLowerCase() });
        if (error) {
          if (/admin only/i.test(error.message)) return json({ error: "platform admins only" }, 403);
          if (/device not found/i.test(error.message)) return json({ error: "device not found" }, 404);
          return json({ error: error.message }, 500);
        }
        const result = (data ?? {}) as { user_id?: string; auth_user_removed?: boolean };
        let removed = result.auth_user_removed === true;
        if (!removed && result.user_id) {
          const { error: delErr } = await service.auth.admin.deleteUser(result.user_id);
          if (delErr && delErr.status !== 404) console.error("deleting the device user failed:", delErr.message);
          removed = !delErr || delErr.status === 404;
        }
        return json({ ok: true, auth_user_removed: removed });
      }
      default:
        return json({ error: "action must be revoke_device" }, 400);
    }
  } catch (err) {
    console.error(`admin ${String(body.action)} failed:`, err);
    return json({ error: "something went wrong" }, 500);
  }
});
