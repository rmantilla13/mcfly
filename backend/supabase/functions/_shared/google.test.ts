import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  apiMessage,
  authorizationUrl,
  CALENDAR_SCOPE,
  emailFromIdToken,
  googleConfig,
  hasCalendarScope,
  parseNotification,
  plainText,
  randomState,
  REVOKED_MESSAGE,
  sameToken,
  shapeCalendarList,
  shapeChannel,
  shapeEvents,
  WATCH_DAYS,
  watchRequest,
  webhookAddress,
} from "./google.ts";

const cfg = { clientId: "id.apps.googleusercontent.com", clientSecret: "shh", redirectUri: "https://x.supabase.co/functions/v1/google-calendar/callback" };

Deno.test("the config comes from the secrets, the redirect from the project", () => {
  const env = (vars: Record<string, string>) => (n: string) => vars[n];
  assertEquals(googleConfig(env({})), null);
  assertEquals(googleConfig(env({ GOOGLE_CLIENT_ID: "a" })), null, "both halves are needed");
  assertEquals(googleConfig(env({ GOOGLE_CLIENT_ID: " a ", GOOGLE_CLIENT_SECRET: "b", SUPABASE_URL: "https://ref.supabase.co/" })), {
    clientId: "a",
    clientSecret: "b",
    redirectUri: "https://ref.supabase.co/functions/v1/google-calendar/callback",
  });
  assertEquals(
    googleConfig(env({ GOOGLE_CLIENT_ID: "a", GOOGLE_CLIENT_SECRET: "b", SUPABASE_URL: "https://ref.supabase.co", GOOGLE_REDIRECT_URI: "https://api.mcfly.bot/google" }))?.redirectUri,
    "https://api.mcfly.bot/google",
  );
});

Deno.test("the sign-in URL asks for offline, read-only calendar access with the state", () => {
  const u = new URL(authorizationUrl(cfg, "abc123", "ricky@example.com"));
  assertEquals(u.origin + u.pathname, "https://accounts.google.com/o/oauth2/v2/auth");
  assertEquals(u.searchParams.get("client_id"), cfg.clientId);
  assertEquals(u.searchParams.get("redirect_uri"), cfg.redirectUri);
  assertEquals(u.searchParams.get("response_type"), "code");
  assertEquals(u.searchParams.get("access_type"), "offline");
  assertEquals(u.searchParams.get("prompt"), "consent select_account");
  assertEquals(u.searchParams.get("state"), "abc123");
  assertEquals(u.searchParams.get("login_hint"), "ricky@example.com");
  const scopes = (u.searchParams.get("scope") ?? "").split(" ");
  assert(scopes.includes(CALENDAR_SCOPE));
  assert(scopes.includes("email"));
  assert(!scopes.some((s) => /calendar$|calendar\.events$/.test(s)), "never a scope that could write");
  assertEquals(new URL(authorizationUrl(cfg, "s")).searchParams.has("login_hint"), false);
});

Deno.test("a state is 64 hex characters and never repeats", () => {
  const a = randomState();
  const b = randomState();
  assert(/^[0-9a-f]{64}$/.test(a));
  assert(a !== b);
});

const idToken = (payload: Record<string, unknown>) => {
  const b64 = (s: string) => btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${b64(JSON.stringify({ alg: "RS256" }))}.${b64(JSON.stringify(payload))}.sig`;
};

Deno.test("the account's email comes from the id token", () => {
  assertEquals(emailFromIdToken(idToken({ email: " Ricky@Example.com ", email_verified: true })), "ricky@example.com");
  assertEquals(emailFromIdToken(idToken({ sub: "123" })), null, "no email, no account");
  assertEquals(emailFromIdToken(idToken({ email: "not an email" })), null);
  assertEquals(emailFromIdToken("garbage"), null);
  assertEquals(emailFromIdToken(undefined), null);
});

Deno.test("the calendar scope has to be in what Google granted", () => {
  assert(hasCalendarScope(`openid email ${CALENDAR_SCOPE}`));
  assert(!hasCalendarScope("openid email"), "unticked on the consent screen");
  assert(!hasCalendarScope(undefined));
});

Deno.test("the calendar list: primary first, override names, Google's colors, deleted gone", () => {
  const list = shapeCalendarList([
    { id: "en.usa#holiday@group.v.calendar.google.com", summary: "Holidays in United States", backgroundColor: "#0b8043", accessRole: "reader", selected: true },
    { id: "ricky@example.com", summary: "ricky@example.com", summaryOverride: "  Ricky  ", backgroundColor: "#4f7cf7", primary: true, accessRole: "owner", selected: true },
    { id: "c_work@group.calendar.google.com", summary: "Work", backgroundColor: "not a color", accessRole: "writer", selected: true, hidden: true },
    { id: "old@group.calendar.google.com", summary: "Old", deleted: true },
    { id: "", summary: "nameless" },
    "junk",
  ]);
  assertEquals(list.map((c) => c.name), ["Ricky", "Holidays in United States", "Work"]);
  assertEquals(list[0], { id: "ricky@example.com", name: "Ricky", color: "#4F7CF7", primary: true, access_role: "owner", selected: true });
  assertEquals(list[2].color, null);
  assertEquals(list[2].selected, false, "hidden in Google Calendar's list");
});

Deno.test("events: timed, all-day, and what is left out", () => {
  const items = shapeEvents(
    [
      {
        id: "standup_20261015T143000Z",
        status: "confirmed",
        summary: "Standup",
        location: "  Zoom ",
        start: { dateTime: "2026-10-15T09:30:00-05:00" },
        end: { dateTime: "2026-10-15T09:45:00-05:00" },
        htmlLink: "https://www.google.com/calendar/event?eid=abc",
        attendees: [{ self: true, responseStatus: "accepted" }],
      },
      { id: "launch", summary: "Launch day", start: { date: "2026-10-20" }, end: { date: "2026-10-21" } },
      { id: "offsite", summary: "Offsite", start: { date: "2026-11-02" }, end: { date: "2026-11-04" }, description: "<p>Agenda:<br>Day one &amp; two</p>" },
      { id: "gone", status: "cancelled", summary: "Cancelled", start: { dateTime: "2026-10-16T10:00:00Z" } },
      { id: "declined", summary: "Declined", start: { dateTime: "2026-10-16T11:00:00Z" }, end: { dateTime: "2026-10-16T12:00:00Z" }, attendees: [{ self: true, responseStatus: "declined" }, { responseStatus: "accepted" }] },
      { id: "office", eventType: "workingLocation", summary: "Office", start: { date: "2026-10-16" }, end: { date: "2026-10-17" } },
      { id: "nostart", summary: "No start" },
      { id: "secret", start: { dateTime: "2026-10-14T10:00:00Z" }, end: { dateTime: "2026-10-14T09:00:00Z" } },
    ],
    { color: "#5B7CF5" },
  );
  assertEquals(items.map((i) => i.id), ["secret", "standup_20261015T143000Z", "launch", "offsite"], "sorted by start, the rest left out");
  assertEquals(items[1], {
    id: "standup_20261015T143000Z",
    title: "Standup",
    starts_at: "2026-10-15T14:30:00.000Z",
    ends_at: "2026-10-15T14:45:00.000Z",
    all_day: false,
    location: "Zoom",
    url: "https://www.google.com/calendar/event?eid=abc",
    color: "#5B7CF5",
  });
  assertEquals(items[2].all_day, true);
  assertEquals([items[2].starts_at, items[2].ends_at], ["2026-10-20T00:00:00Z", "2026-10-20T23:59:59Z"], "one day: Google's end is the day after");
  assertEquals([items[3].starts_at, items[3].ends_at], ["2026-11-02T00:00:00Z", "2026-11-03T23:59:59Z"], "two days");
  assertEquals(items[3].description, "Agenda:\nDay one & two");
  assertEquals(items[0].title, "Busy", "no summary (a private event in a shared calendar)");
  assertEquals(items[0].ends_at, items[0].starts_at, "an end before the start is the start");
  assertEquals("color" in shapeEvents([{ id: "x", start: { date: "2026-01-01" } }])[0], false);
});

Deno.test("an occurrence without an id falls back to its iCal uid and start", () => {
  const [item] = shapeEvents([{ iCalUID: "abc@google.com", summary: "X", start: { dateTime: "2026-10-16T10:00:00Z" } }]);
  assertEquals(item.id, "abc@google.com@2026-10-16T10:00:00.000Z");
  assertEquals(item.ends_at, item.starts_at);
});

Deno.test("descriptions lose their HTML", () => {
  assertEquals(plainText("Hello<br/>there &lt;b&gt;"), "Hello\nthere <b>");
  assertEquals(plainText("<div>a</div><div>b</div>\n\n\n\nc"), "a\nb\n\nc");
});

Deno.test("what Google's refusals say, in under 300 characters", () => {
  assertEquals(apiMessage(401, {}), REVOKED_MESSAGE);
  assertStringIncludes(apiMessage(403, { error: { errors: [{ reason: "rateLimitExceeded" }] } }), "slow down");
  assertStringIncludes(apiMessage(429, {}), "slow down");
  assertStringIncludes(apiMessage(404, { error: { errors: [{ reason: "notFound" }] } }), "doesn't show this calendar");
  assertStringIncludes(apiMessage(403, { error: { errors: [{ reason: "forbidden" }] } }), "doesn't show this calendar");
  assertEquals(apiMessage(500, { error: { status: "INTERNAL" } }), "Google answered 500 (INTERNAL)");
  assertEquals(apiMessage(502, "nope"), "Google answered 502");
  for (const m of [apiMessage(401, {}), apiMessage(403, {}), apiMessage(429, {}), REVOKED_MESSAGE]) assert(m.length <= 300);
});

Deno.test("the web hook address is the function's, or GOOGLE_WEBHOOK_URL", () => {
  const env = (vars: Record<string, string>) => (n: string) => vars[n];
  assertEquals(webhookAddress(env({ SUPABASE_URL: "https://ref.supabase.co/" })), "https://ref.supabase.co/functions/v1/google-calendar/notify");
  assertEquals(webhookAddress(env({ SUPABASE_URL: "https://ref.supabase.co", GOOGLE_WEBHOOK_URL: " https://mcfly.bot/api/google/notify " })), "https://mcfly.bot/api/google/notify");
  assertEquals(webhookAddress(env({ SUPABASE_URL: "https://ref.supabase.co", GOOGLE_WEBHOOK_URL: "http://mcfly.bot/x" })), null, "Google wants https");
  assertEquals(webhookAddress(env({})), null);
});

Deno.test("the watch request names the channel, the token, the address and a week", () => {
  const { url, body } = watchRequest("c_work@group.calendar.google.com", { address: "https://mcfly.bot/api/google/notify", channelId: "chan-1", token: "tok", now: 1_000 });
  assertEquals(url, "https://www.googleapis.com/calendar/v3/calendars/c_work%40group.calendar.google.com/events/watch");
  assertEquals(body, { id: "chan-1", type: "web_hook", address: "https://mcfly.bot/api/google/notify", token: "tok", expiration: String(1_000 + WATCH_DAYS * 86_400_000) });
});

Deno.test("Google's channel answer becomes a channel with an ISO expiry", () => {
  assertEquals(shapeChannel({ kind: "api#channel", id: "chan-1", resourceId: "res-9", expiration: "1792170396956" }, { channelId: "chan-1" }), {
    channelId: "chan-1",
    resourceId: "res-9",
    expiresAt: new Date(1792170396956).toISOString(),
  });
  assertEquals(shapeChannel({ resourceId: "res-9" }, { channelId: "mine", now: 0 })?.expiresAt, new Date(86_400_000).toISOString(), "no expiry: a day, to be renewed");
  assertEquals(shapeChannel({ id: "chan-1" }, { channelId: "chan-1" }), null, "no resource, no channel");
});

Deno.test("a notification's headers", () => {
  const h = new Headers({ "X-Goog-Channel-ID": "chan-1", "X-Goog-Resource-ID": "res-9", "X-Goog-Resource-State": "Exists", "X-Goog-Channel-Token": "tok", "X-Goog-Message-Number": "3" });
  assertEquals(parseNotification(h), { channelId: "chan-1", resourceId: "res-9", state: "exists", token: "tok", messageNumber: 3 });
  assertEquals(parseNotification(new Headers({ "X-Goog-Channel-ID": "sync-1", "X-Goog-Resource-State": "sync" }))?.state, "sync");
  assertEquals(parseNotification(new Headers({})), null, "not from Google");
});

Deno.test("tokens compare in full", () => {
  assert(sameToken("abc", "abc"));
  assert(!sameToken("abc", "abd"));
  assert(!sameToken("abc", "ab"));
  assert(!sameToken("", ""));
});

Deno.test("a refused channel says why", () => {
  assertStringIncludes(apiMessage(401, { error: { errors: [{ reason: "push.webhookUrlUnauthorized" }] } }), REVOKED_MESSAGE.slice(0, 20));
  assertStringIncludes(apiMessage(400, { error: { errors: [{ reason: "push.webhookUrlUnauthorized" }] } }), "domain isn't verified");
  assertStringIncludes(apiMessage(400, { error: { errors: [{ reason: "push.channelIdNotUnique" }] } }), "push.channelIdNotUnique");
  assert(apiMessage(400, { error: { errors: [{ reason: "push.webhookUrlUnauthorized" }] } }).length <= 300);
});
