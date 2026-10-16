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
| Ambient (`/ambient`) | The display's ambient screen saver full screen, for a spare monitor or a tablet: the moving gradient, the clock, what's next, and a rail of cards. Any click or key goes back to Today |
| Overview | Agents, pushes in the last 24 hours (and errors), briefs, symbols, reports, projects (blocked ones), metrics, dashboards, upcoming events, displays online; the recent pushes with any refusal sentence; the displays and when they were last seen |
| Voice (`/voice`) | Talk to McFly full screen, with Homestead's voice glow and voice: Kokoro-82M ("Heart" by default; Bella, Michael, Fenrir) runs in the browser (a one-time ~90 MB download, then cached; the browser's own voice speaks until it's ready). Tap the mic, or type; "Keep talking" listens again after each answer. Also from Today's Ask McFly bar |
| Agents | Pick what it's for (briefings, markets, Daily Pulse, calendar mirror, projects, custom): the key shows **once**, inside a ready-to-paste task prompt, with a test push and a live "waiting for the first push". Permissions per agent: read the calendar, read memory, keep notes (off by default; enforced by ingest from the key). Rotate, revoke, delete, edit |
| Grok bots | Bots McFly runs itself: a prompt, a schedule (from every 15 minutes to daily, optionally from a time of day) and web/X search. On schedule the `bots` function asks Grok through xAI's Responses API and stores the answer as a brief or a Daily Pulse report under the bot's own agent. Run now, pause, edit; the last runs with their sources. Needs `XAI_API_KEY` |
| Memory | Notes McFly keeps: about you (shared: the assistant reads them, as do agents with "read memory") and each agent's own working notes. Add, edit, pin, delete. The display shows the shared ones |
| Calendars | Subscribe to a Google ("secret address in iCal format"), iCloud (public) or Outlook (published ICS) calendar. Read every 15 minutes by `calendar-sync`, recurring events expanded; the link stays on the server (only its host shows). Sync now, pause, remove |
| Feed | Briefs, Markets (order and hide symbols), News (reports and their stories), Projects (and each one's updates), Metrics (group, order, relabel, hide), Dashboards (preview the widgets, order, hide), Calendar (events by day; remove an event or a whole calendar) |
| Displays | Pair a display (enter the 6-digit code from its setup screen), rename, revoke, and **Customize**: screen saver, backdrop, dark mode, sleep, who answers, wake word, voice and speed. The display applies changes within a minute, and changes made on its own Settings come back here (`devices.settings`). `/pair?code=…` is the page the display's QR code opens |
| Settings | Display name, time zone, the assistant's provider (Claude or Grok), retention (briefs, quotes, metrics, events in days; reports kept). **Backend**: whether the migrations, functions, API keys and schedules are in place (secrets show as set or missing, never their values), with links to fix each |
| Audit | Every admin change, with who did it |

## Schedules (calendars and Grok bots)

pg_cron calls `calendar-sync` every 15 minutes and `bots` every 5, carrying a
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
  `ASSISTANT_MODEL` / `GROK_MODEL`.
- The console's environment has only the project URL and the anon key.
