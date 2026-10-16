import { supabaseProjectUrl } from "@/lib/env";

// Google's push notifications for watched calendars, when the functions'
// GOOGLE_WEBHOOK_URL points here: Google only notifies a domain verified
// for the Cloud project, which this console's is and a supabase.co
// subdomain can't be (docs/ADMIN.md, Instant updates). Forwards the
// headers Google sets to the google-calendar function's /notify route,
// which checks the channel's token; nothing is read or kept here, and
// there is no session (Google is the caller).
export async function POST(req: Request) {
  const base = supabaseProjectUrl();
  if (!base) return new Response(null, { status: 503 });
  const headers = new Headers();
  for (const [name, value] of req.headers) {
    if (name.toLowerCase().startsWith("x-goog-")) headers.set(name, value);
  }
  if (!headers.has("x-goog-channel-id")) return new Response(null, { status: 400 });
  const upstream = await fetch(`${base}/functions/v1/google-calendar/notify`, { method: "POST", headers, signal: AbortSignal.timeout(15_000) }).catch(() => null);
  return new Response(null, { status: upstream ? upstream.status : 503 });
}
