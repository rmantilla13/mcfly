# McFly console

The admin console at [mcfly.bot](https://mcfly.bot): agents and their keys,
the three feeds (briefs, markets, news), paired displays, settings and the
audit log. Next.js (App Router) + Supabase, built on shadcn/ui.

```bash
npm install
cp .env.example .env.local   # Supabase URL and anon key
npm run dev                  # http://localhost:3000

NEXT_PUBLIC_ADMIN_DEMO=1 npm run dev   # fixture data, no backend, no sign-in
```

## How it talks to the backend

The console never holds the service role key. Every page and action goes
through `lib/data.ts`, which calls the `admin_*` RPCs and the two edge
functions with the signed-in admin's own JWT (`@supabase/ssr` keeps the
session in httpOnly cookies and `proxy.ts` refreshes it on every request):

| Page | Calls |
|---|---|
| `/` | `admin_overview`, `admin_list_ingest`, `admin_list_devices` |
| `/agents` | `admin_list_agents`, `admin_create_agent`, `admin_rotate_agent_key`, `admin_update_agent`, `admin_revoke_agent`, `admin_delete_agent` |
| `/feed` | Briefs, Markets, News: `admin_list_briefs`, `admin_delete_brief`, `admin_list_quotes`, `admin_set_symbol`, `admin_delete_symbol`, `admin_list_news_reports`, `admin_delete_news_report`. Projects, Metrics, Dashboards, Calendar: `admin_list_projects`, `admin_delete_project`, `admin_list_metrics`, `admin_set_metric`, `admin_delete_metric`, `admin_list_dashboards`, `admin_set_dashboard`, `admin_delete_dashboard`, `admin_list_events(7, 60)`, `admin_delete_event`, `admin_delete_calendar`; `admin_get_settings` for the calendar's time zone |
| `/feed/news/[id]` | `admin_news_report`, `admin_delete_news_report` |
| `/feed/projects/[id]` | `admin_list_projects` (the row), `admin_project_updates`, `admin_delete_project` |
| `/feed/dashboards/[id]` | `admin_list_dashboards` (the row; its widgets drawn read-only), `admin_delete_dashboard` |
| `/displays`, `/pair` | `admin_list_devices`, `admin_rename_device`, the `admin` function (`revoke_device`), the `pair-device` function (`claim`) |
| `/settings` | `admin_get_settings`, `admin_update_settings` (only the changed fields; includes the assistant provider and the metrics/events retention) |
| `/audit` | `admin_list_audit` |

The RPCs and functions check `is_platform_admin()` themselves and write
`admin_audit_log`; the console's own gate (`proxy.ts`, `requireAdmin`) is the
fast path. Shapes and names are in [docs/PLATFORM_SPEC.md](../docs/PLATFORM_SPEC.md).

Sign-in is email + password with Supabase Auth. The first account to sign
up becomes the admin (`handle_new_user`); anyone else sees "That account
isn't a McFly admin" until an admin adds them with `admin_set_admin`.

## Pairing a display

An unpaired display shows a QR code for `https://mcfly.bot/pair?code=123456`
and the six digits. `/pair` goes through the sign-in gate with a `?next=`
round trip, then submits the code to the `pair-device` function's `claim`
action as the admin; the display picks up its session within a few seconds.
`/displays` has the same form.

## Demo mode

`NEXT_PUBLIC_ADMIN_DEMO=1` serves fixtures shaped like `backend/supabase/
seed.sql` (Grok, Market desk, Daily Pulse, GitHub watcher, Ops metrics,
Calendar sync; a few briefs, four symbols with history, two Pulse reports,
three projects with updates, five metrics with history, two dashboards, six
events around today, two displays, a day of ingest log) from an in-memory
store in `lib/demo/`. Every action works against it: a new agent
gets a fake `mcf_` key, any six digits pair a display. Changes reset when
the server restarts. Demo mode never creates a Supabase client.

## Checks

```bash
npm run lint
npm run typecheck
npm run build
npm test          # node --test; no database needed
```

## Deploying to mcfly.bot

The console deploys to Vercel as a Next.js project with `admin/` as the root
directory. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`
in the project's environment (Production and Preview), leave
`NEXT_PUBLIC_ADMIN_DEMO` unset, and point the `mcfly.bot` domain at the
project. In Supabase, add `https://mcfly.bot` to Auth → URL Configuration
(site URL and redirect URLs) so password sign-in and recovery emails land
on the console. `vercel.json` only names the framework; the security
headers (`X-Frame-Options`, `noindex`, …) come from `next.config.ts`.
