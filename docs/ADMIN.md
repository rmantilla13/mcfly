# The console: mcfly.bot

A Next.js app (`admin/`, shadcn/ui on Tailwind) for the person who runs
McFly: agents and their keys, every feed, displays and pairing, settings,
the audit log. It signs in as you and lets the database check that you are
an admin; it never holds the service role key.

## Running it

```bash
cd admin && npm install
NEXT_PUBLIC_ADMIN_DEMO=1 npm run dev     # sample data, no sign-in: http://localhost:3000
```

For real use, `admin/.env.local`:

```
NEXT_PUBLIC_SUPABASE_URL=https://<project>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon or publishable key>
```

Deploy to Vercel (`vercel.json` is there) with the same two variables and
point `mcfly.bot` at it. The display's QR codes open
`https://mcfly.bot/pair?code=…`, so that domain has to be the console.

## Your account

Sign up once with email and password (Supabase Auth, email provider on).
**The first account becomes the admin**; then turn sign-ups off
(Supabase → Authentication → Sign In / Up → Allow new users to sign up: off)
so nobody else can. Another admin is added by an admin with the
`admin_set_admin` RPC (SQL editor) by user id.

The same account signs in on the iPhone and the Mac app.

## Pages

| Page | What you do |
|---|---|
| Today | The display's Home on the web: the greeting and clock, what's up next, anything blocked, the markets, and today in time order (the Pulse, briefs, project updates and events), scrolled to now. Same rules as the display (`lib/today.ts`, tested in `tests/today.test.mjs`); refreshes every minute |
| Ambient (`/ambient`) | The display's ambient screen saver full screen, for a spare monitor or a tablet: the display's backdrop (the moving gradient with an aurora at night, or the sky chosen under Displays → Customize), the clock, what's next, and a rail of cards. Any click or key goes back to Today |
| Overview | Agents, pushes in the last 24 hours (and errors), briefs, symbols, reports, projects (blocked ones), metrics, dashboards, upcoming events, displays online; the recent pushes with any refusal sentence; the displays and when they were last seen |
| Voice (`/voice`) | Talk to McFly full screen, with Homestead's voice glow and voice: Kokoro-82M ("Heart" by default; Bella, Michael, Fenrir) runs in the browser (a one-time ~90 MB download, then cached; the browser's own voice speaks until it's ready). Tap the mic, or type; "Keep talking" listens again after each answer. Also from Ask's Talk button |
| Ask (`/ask`) | Ask McFly full screen, for reading: the assistant answers in `read` mode (longer, with headings, lists, bold figures and tables) and each answer is laid out in a wide reading column under its question, which opens at the top of the page while the answer arrives. Type or tap the mic; stop an answer, copy it, have it read aloud, start a new chat. The thread stays for the browser tab; Today's Ask bar expands to here with its conversation, and `/ask?q=…` asks a question on arrival. Escape stops an answer, then leaves |
| Agents | Pick what it's for (briefings, markets, Daily Pulse, calendar mirror, projects, custom): the key shows **once**, inside a ready-to-paste task prompt, with a test push and a live "waiting for the first push". Permissions per agent: read the calendar, read memory, keep notes (off by default; enforced by ingest from the key). Rotate, revoke, delete, edit |
| Grok bots | Bots McFly runs itself: a prompt, a schedule (from every 15 minutes to daily, optionally from a time of day) and web/X search. On schedule the `bots` function asks Grok through xAI's Responses API and stores the answer as a brief or a Daily Pulse report under the bot's own agent. Run now, pause, edit; the last runs with their sources. Needs `XAI_API_KEY` |
| Memory | Notes McFly keeps: about you (shared: the assistant reads them, as do agents with "read memory") and each agent's own working notes. Add, edit, pin, delete. The display shows the shared ones |
| Calendars | **Google**: Connect a Google account (sign in once, read-only) and each of its calendars is a switch: your own, the ones shared with you, a work account's. Read through the Calendar API by `calendar-sync`, so no secret address, and the calendar as it is now rather than Google's hours-stale iCal feed. Connect again when Google drops the sign-in; Disconnect revokes it and removes the account's calendars. Setup: [Google Calendar sign-in](#google-calendar-sign-in). **Links**: iCloud (public), Outlook (published ICS) or any iCal link, Google's secret address included. Both kinds are read every 15 minutes, recurring events expanded; links and sign-ins stay on the server. Sync now, pause, remove |
| Feed | Briefs, Markets (order and hide symbols), News (reports and their stories), Projects (and each one's updates), Metrics (group, order, relabel, hide), Dashboards (preview the widgets, order, hide), Calendar (events by day; remove an event or a whole calendar) |
| Displays | Pair a display (enter the 6-digit code from its setup screen), rename, revoke, and **Customize**: home layout (Today, Bento or Assistant first), screen saver, backdrop, dark mode, sleep, who answers, wake word, voice and speed. The display applies changes within a minute, and changes made on its own Settings come back here (`devices.settings`). `/pair?code=…` is the page the display's QR code opens |
| Settings | Display name, time zone (**Use my location**: the browser's position, rounded to about a kilometre, looked up on Open-Meteo; once allowed, each visit checks the field against where you are and offers the zone if it differs; or type an IANA name), the assistant's provider (Claude or Grok), retention (briefs, quotes, metrics, events in days; reports kept). **Backend**: whether the migrations, functions, API keys and schedules are in place (secrets show as set or missing, never their values), with links to fix each |
| Audit | Every admin change, with who did it |

## Google Calendar sign-in

Calendars → Connect a Google account sends the admin to Google, which sends
them back to the `google-calendar` function with a code; the function trades
it for a refresh token, keeps that in `google_accounts` (a table only the
functions read) and sends the browser back to the Calendars page. From then
on `calendar-sync` reads the chosen calendars with that token. It needs an
OAuth client of your own in Google Cloud, once:

1. [console.cloud.google.com](https://console.cloud.google.com) → a project
   (any name) → **APIs & Services → Library** → enable **Google Calendar API**.
2. **Google Auth Platform** (the OAuth consent screen): External, app name
   McFly, your email as the contact. Under **Data access** add the scopes
   `.../auth/calendar.readonly`, `openid` and `.../auth/userinfo.email`.
   Under **Audience**, click **Publish app** and confirm (no verification is
   needed to use your own app; the consent screen then shows an "unverified
   app" notice you click through once per account). Left in **Testing**,
   Google expires every sign-in after seven days and the console asks you to
   connect again weekly.
3. **Clients → Create client**: Web application; Authorized redirect URI
   `https://<ref>.supabase.co/functions/v1/google-calendar/callback` (your
   project ref; `GOOGLE_REDIRECT_URI` overrides it for a custom domain).
   Copy the client ID and secret.
4. `supabase secrets set GOOGLE_CLIENT_ID=… GOOGLE_CLIENT_SECRET=…`, then
   `supabase functions deploy google-calendar calendar-sync admin` and
   `supabase db push` (migration `20261016000011`). Settings → Backend
   shows whether the two secrets are set.
5. Console → Calendars → **Connect a Google account**. Pick the account,
   allow access, and switch on the calendars to show.

What McFly asks for and keeps: read-only calendar access and the account's
email (`openid email`). Events arrive as titles, times, locations,
descriptions (as text) and a link to the event, never the guest list;
occurrences the account declined and working-location markers are left out.
Disconnect revokes the sign-in at Google before removing it here. A
calendar that Google stops showing to the account ("Not in Google's list
anymore") can still be switched off.

### Instant updates

With a calendar switched on, `calendar-sync` also asks Google to notify
McFly when it changes (a notification channel, `events.watch`, renewed
weekly), and the `google-calendar` function's `/notify` route reads that one
calendar at once: a change shows on the display within a minute instead of
at the next 15-minute run. The console says "live" beside a watched calendar.

Google only sends notifications to a domain verified for the Cloud project,
and a `supabase.co` subdomain can't be verified, so point Google at the
console instead, which forwards them (`app/api/google/notify`):

1. [Search Console](https://search.google.com/search-console) → add
   `mcfly.bot` as a Domain property and verify it with the DNS record it
   gives you (where the domain's DNS is managed).
2. Google Cloud → **APIs & Services → Domain verification** → Add domain
   → `mcfly.bot`.
3. `supabase secrets set GOOGLE_WEBHOOK_URL=https://www.mcfly.bot/api/google/notify`
   and redeploy `calendar-sync` and `google-calendar`. Use the host that
   answers directly: the apex `mcfly.bot` redirects to `www`, and Google
   doesn't follow a redirect for a notification.

Until then every Google calendar says "Every 15 minutes, not live: Google
refused the notification channel (push.webhookUrlUnauthorized)" and is read
on the schedule as before; nothing else changes. A calendar switched off
keeps receiving notifications for up to a week, which the route ignores.

A Workspace admin may block sign-ins to apps outside the organization; for
those calendars, Apps Script from inside Google still works
([AGENTS.md](AGENTS.md), "A Google calendar without a secret address").

## Schedules (calendars and Grok bots)

pg_cron calls `calendar-sync` every 15 minutes (links and Google calendars
alike) and `bots` every 5, carrying a
secret from Vault that the functions check with the database
(`cron_secret_matches`), so no copy of it exists anywhere else. Set it up once
in the SQL editor; the secret is made inside the database and never shown:

```sql
select vault.create_secret('https://<ref>.supabase.co', 'mcfly_project_url');
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'mcfly_cron_secret');
```

Until both are there the jobs do nothing; Settings → Backend says which is missing.

## Keys and secrets

- Agent keys: `mcf_` and 40 hex characters, hashed in the database; see
  [AGENTS.md](AGENTS.md).
- The functions' secrets live in Supabase (`supabase secrets set`):
  `ANTHROPIC_API_KEY` for Claude, `XAI_API_KEY` for Grok, optional
  `ASSISTANT_MODEL` / `GROK_MODEL`; `GOOGLE_CLIENT_ID` and
  `GOOGLE_CLIENT_SECRET` for the Google Calendar sign-in (optional
  `GOOGLE_REDIRECT_URI`, and `GOOGLE_WEBHOOK_URL` for instant updates).
  Google refresh tokens live in `google_accounts` and notification channels'
  tokens in `google_watch_channels` (RLS on, no policies: the functions alone
  read them).
- The console's environment has only the project URL and the anon key.
