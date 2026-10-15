// pair-device: binds a display to McFly.
//
//   1. start   (display, no auth)  { secretHash }     -> { code, expiresAt }
//   2. claim   (admin, user JWT)   { code, name? }    -> { deviceId }
//   3. redeem  (display, no auth)  { code, secret }   -> { status: "pending" }
//                                                     |  { status: "paired", session, deviceId }
//
// The display keeps `secret` private and only ever sends its SHA-256 at
// start, so seeing the 6-digit code on screen is not enough to steal the
// session. An admin enters the code in the console (Displays → Pair).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { authenticate, bearerToken, json, preflight, readJson } from "../_shared/http.ts";
import { CODE, deviceName, randomCode, SECRET_HASH } from "./pairing.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

function randomPassword(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function start(body: { secretHash?: string }) {
  if (!body.secretHash || !SECRET_HASH.test(body.secretHash)) {
    return json({ error: "secretHash must be a hex SHA-256" }, 400);
  }
  // Clear out expired codes opportunistically.
  await admin.from("pairing_codes").delete().lt("expires_at", new Date().toISOString());

  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomCode();
    const { data, error } = await admin
      .from("pairing_codes")
      .insert({ code, secret_hash: body.secretHash })
      .select("code, expires_at")
      .single();
    if (!error) return json({ code: data.code, expiresAt: data.expires_at });
    if (error.code !== "23505") return json({ error: error.message }, 500); // not a collision
  }
  return json({ error: "could not allocate a code, try again" }, 503);
}

async function claim(req: Request, body: { code?: string; name?: string }) {
  const jwt = bearerToken(req);
  if (!jwt) return json({ error: "sign in required" }, 401);
  const who = await authenticate(admin, jwt);
  if ("error" in who) return who.error;
  const user = who.user as { id: string };

  // Admin rights are checked by the database with the caller's own token.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: isAdmin, error: adminErr } = await asUser.rpc("is_platform_admin");
  if (adminErr) return json({ error: adminErr.message }, 500);
  if (isAdmin !== true) return json({ error: "only a platform admin can pair displays" }, 403);

  const code = typeof body.code === "string" ? body.code.replace(/\D/g, "") : "";
  if (!CODE.test(code)) return json({ error: "code must be the 6 digits on the screen" }, 400);

  const { data: pc } = await admin
    .from("pairing_codes")
    .select("*")
    .eq("code", code)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (!pc) return json({ error: "code not found or expired; the display shows a new one every 10 minutes" }, 404);
  if (pc.device_id) return json({ error: "code already used" }, 409);

  const deviceUserId = crypto.randomUUID();
  const { data: created, error: userErr } = await admin.auth.admin.createUser({
    id: deviceUserId,
    email: `device-${deviceUserId}@devices.mcfly.invalid`,
    password: randomPassword(),
    email_confirm: true,
    app_metadata: { kind: "device" },
  });
  if (userErr) return json({ error: userErr.message }, 500);

  const { data: device, error: devErr } = await admin
    .from("devices")
    .insert({ user_id: created.user.id, name: deviceName(body.name) })
    .select("id")
    .single();
  if (devErr) {
    await admin.auth.admin.deleteUser(created.user.id);
    return json({ error: devErr.message }, 500);
  }

  await admin.from("pairing_codes").update({ device_id: device.id, claimed_by: user.id }).eq("code", code);
  await admin.from("admin_audit_log").insert({
    admin_id: user.id,
    action: "pair_device",
    target_type: "device",
    target_id: device.id,
    details: { name: deviceName(body.name) },
  });
  return json({ deviceId: device.id });
}

async function redeem(body: { code?: string; secret?: string }) {
  if (!body.code || !body.secret) return json({ error: "code and secret required" }, 400);

  const { data: pc } = await admin.from("pairing_codes").select("*").eq("code", body.code).maybeSingle();
  if (!pc || pc.secret_hash !== (await sha256Hex(body.secret))) {
    return json({ error: "invalid code" }, 404);
  }
  if (!pc.device_id) {
    if (new Date(pc.expires_at) < new Date()) return json({ error: "code expired" }, 410);
    return json({ status: "pending" });
  }

  const { data: device } = await admin.from("devices").select("id, user_id").eq("id", pc.device_id).single();
  if (!device) return json({ error: "device missing" }, 500);

  // Rotate the device password and sign in once to mint the session.
  const password = randomPassword();
  const { data: u, error: updErr } = await admin.auth.admin.updateUserById(device.user_id, { password });
  if (updErr || !u.user.email) return json({ error: updErr?.message ?? "device user missing" }, 500);

  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data: signIn, error: signErr } = await anon.auth.signInWithPassword({ email: u.user.email, password });
  if (signErr || !signIn.session) return json({ error: signErr?.message ?? "sign-in failed" }, 500);

  await admin.from("pairing_codes").delete().eq("code", body.code);

  return json({
    status: "paired",
    deviceId: device.id,
    session: {
      accessToken: signIn.session.access_token,
      refreshToken: signIn.session.refresh_token,
      expiresAt: signIn.session.expires_at,
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const read = await readJson(req);
  if ("error" in read) return read.error;
  if (typeof read.body !== "object" || read.body === null || Array.isArray(read.body)) {
    return json({ error: "body must be a JSON object" }, 400);
  }
  const body = read.body as Record<string, string>;
  try {
    switch (body.action) {
      case "start":
        return await start(body);
      case "claim":
        return await claim(req, body);
      case "redeem":
        return await redeem(body);
      default:
        return json({ error: "action must be start, claim or redeem" }, 400);
    }
  } catch (err) {
    console.error(`pair-device ${body.action} failed:`, err);
    return json({ error: "something went wrong" }, 500);
  }
});
