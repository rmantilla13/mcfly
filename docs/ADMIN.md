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
| Overview | Agents, pushes in the last 24 hours (and errors), briefs, symbols, reports, projects (blocked ones), metrics, dashboards, upcoming events, displays online; the recent pushes with any refusal sentence; the displays and when they were last seen |
| Agents | Make an agent (name, kind, colour): the key shows **once**, with a curl example for its kind. Rotate a key (the old one stops at once), revoke (stops pushes, keeps what it pushed), delete (removes its feed rows), edit |
| Feed | Briefs, Markets (order and hide symbols), News (reports and their stories), Projects (and each one's updates), Metrics (group, order, relabel, hide), Dashboards (preview the widgets, order, hide), Calendar (events by day; remove an event or a whole calendar) |
| Displays | Pair a display (enter the 6-digit code from its setup screen), rename, revoke. `/pair?code=…` is the page the display's QR code opens |
| Settings | Display name, time zone, the assistant's provider (Claude or Grok), retention (briefs, quotes, metrics, events in days; reports kept) |
| Audit | Every admin change, with who did it |

## Keys and secrets

- Agent keys: `mcf_` and 40 hex characters, hashed in the database; see
  [AGENTS.md](AGENTS.md).
- The functions' secrets live in Supabase (`supabase secrets set`):
  `ANTHROPIC_API_KEY` for Claude, `XAI_API_KEY` for Grok, optional
  `ASSISTANT_MODEL` / `GROK_MODEL`.
- The console's environment has only the project URL and the anon key.
