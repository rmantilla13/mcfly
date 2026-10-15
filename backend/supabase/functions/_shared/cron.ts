// Is this request pg_cron's? It carries `x-mcfly-cron: <secret>`; the secret
// lives in Vault and the database checks it (cron_secret_matches), so no
// function keeps a copy. A MCFLY_CRON_SECRET function secret, if set, is
// accepted too.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function isCronCall(req: Request, service: SupabaseClient): Promise<boolean> {
  const given = req.headers.get("x-mcfly-cron") ?? "";
  if (given.length < 32) return false;
  const own = Deno.env.get("MCFLY_CRON_SECRET") ?? "";
  if (own && sameSecret(given, own)) return true;
  const { data, error } = await service.rpc("cron_secret_matches", { candidate: given });
  if (error) console.error("cron_secret_matches failed:", error.message);
  return data === true;
}
