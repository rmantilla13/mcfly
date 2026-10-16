# McFly platform spec

The contract between the database, the edge functions, the admin console,
the Pi display, the Apple app (iPhone and Mac) and the agents that push.
Names here are exact. When code and this document disagree, fix one of them
so they match.

```
 ┌──────────────────┐        ┌──────────────────────────────┐        ┌──────────────────┐
 │  Agents          │──────▶ │  Supabase (cloud backend)    │◀──────▶│ Pi display       │
 │  Grok, a stocks  │ HTTPS  │  Postgres + RLS              │ HTTPS  │ Qt 6 / QML / C++ │
 │  agent, Daily    │ + key  │  Auth · Realtime             │ + SSE  │ Raspberry Pi 5   │
 │  Pulse, …        │        │  Edge Functions: ingest,     │        └────────┬─────────┘
 └──────────────────┘        │  pair-device, admin,         │                 │ ws://127.0.0.1
 ┌──────────────────┐        │  assistant                   │        ┌────────┴─────────┐
 │ Admin console    │◀──────▶│                              │        │ Voice service    │
 │ Next.js, mcfly.bot│ HTTPS └──────────────┬───────────────┘        │ wake word, STT,  │
 └──────────────────┘                       │ HTTPS + SSE            │ TTS (on the Pi)  │
                             ┌──────────────┴───────────────┐        └──────────────────┘
                             │ Apple app (iPhone, Mac)      │
                             │ SwiftUI: feeds, voice, pair  │
                             └──────────────────────────────┘
```

McFly is one person's. Their account (Supabase Auth) is the platform admin;
displays are paired to that account and read the feeds as their own device
user; agents push with an API key.

## 1. Database

Migration `backend/supabase/migrations/20261014000001_core.sql` (plain
Postgres) and `20261014000002_realtime.sql` (Supabase only). The SQL tests
in `backend/tests/*_test.sql` are the executable version of this section.

### 1.1 Accounts and admins

| Table | Notes |
|---|---|
| `profiles` | One per person with an account: `id` (= auth user), `display_name`. A person reads and updates their own; admins read all. Not created for device accounts (`raw_app_meta_data.kind = 'device'`) |
| `platform_admins` | Who runs McFly. **The first person to sign up becomes an admin** (`handle_new_user` trigger); later people are added with `admin_set_admin`. Read-only to admins |
| `platform_settings` | One row: `display_name` ('McFly'), `timezone` ('America/Chicago'), `briefs_keep_days` (30), `quotes_keep_days` (90), `news_keep_reports` (14). Readable by displays and admins; written by `admin_update_settings` |

Helpers: `is_service_role()`, `is_platform_admin()` (true for the service
role too), `is_device()`, `can_read()` (= device or admin).

### 1.2 Displays

| Table | Notes |
|---|---|
| `devices` | Paired displays: `id`, `user_id` (its auth user, unique), `name`, `last_seen_at`, `created_at`. A display reads its own row and may update only `last_seen_at` (`devices_guard`); admins read all |
| `pairing_codes` | Service role only (RLS on, no policies): `code` (6 digits), `secret_hash`, `device_id`, `claimed_by`, `expires_at` (10 min) |

### 1.3 Agents

| Table | Notes |
|---|---|
| `agents` | `id`, `name`, `slug` (unique, from the name), `kind` ∈ grok · stocks · news · other (a label for icons and colors; any agent may push to any feed), `color` (#rrggbb), `created_at`, `last_seen_at` (last successful push), `revoked_at` |
| `agent_keys` | Service role only: `agent_id`, `key_hash` (SHA-256 hex of the key), `key_prefix` (first 12 chars, for the console), `created_at`. The key is `mcf_` + 40 hex characters and is shown once, when it is made |
| `ingest_log` | Every push: `agent_id`, `feed`, `count`, `status` ok · error, `message`, `created_at`. Admins only |

### 1.4 Feeds

Displays and admins read; nothing writes but the ingest functions and the
admin RPCs.

| Table | Notes |
|---|---|
| `briefs` | Text updates: `agent_id`, `external_id` (the agent's own id; unique per agent, a re-push replaces), `title` (≤200), `body` (≤20,000, plain text with blank lines and `- ` bullets), `kind` ∈ hourly · daily · alert · update, `published_at`, `expires_at`, `created_at`, `updated_at` |
| `quotes` | One row per push and symbol: `agent_id`, `symbol` (upper, `^[A-Z0-9.^=:-]{1,16}$`), `name`, `price`, `change`, `change_pct`, `currency` (3 letters), `note` (≤2000), `data` (jsonb), `as_of`, `created_at` |
| `quotes_latest` | View: the newest row per symbol |
| `symbols` | Every symbol seen: `symbol`, `name`, `sort_order` (1000 for new ones), `hidden`, `updated_at`. The console orders and hides; the display shows `not hidden` in `sort_order, symbol` order |
| `news_reports` | A Daily Pulse report: `agent_id`, `slug` (unique, normally the date), `report_date`, `display_date` (as the agent wrote it), `hero_item` (an item key), `published_at` |
| `news_items` | `report_id`, `section_key`, `section_name`, `section_order`, `item_key` (unique per report and section), `position`, `headline` (≤300), `takeaway` (≤2000), `url` (http/https), `image_url`, `source_domain` (host without www) |
| `admin_audit_log` | Every admin change, written by the RPCs and the functions |

Retention: `prune_feed()` applies the settings (old briefs, old quote
history keeping the newest row per symbol, old reports, 90 days of log).
The ingest function calls it after each push.

### 1.5 Ingest functions (service role)

`ingest_briefs(agent, items jsonb) → int`, `ingest_quotes(agent, items jsonb,
as_of_default) → int`, `ingest_news(agent, report jsonb) → uuid` (replaces a
report with the same slug), `record_ingest(agent, feed, count, status,
message)`, `agent_for_key(hash) → (id, name, slug, kind)` (null when
unknown or revoked). Payload shapes: [AGENTS.md](AGENTS.md).

### 1.6 Admin RPCs

All check `is_platform_admin()` and raise `admin only` otherwise; each
mutation writes `admin_audit_log`.

| Function | Returns |
|---|---|
| `admin_overview()` | jsonb: agents, agents_revoked, pushes_24h, errors_24h, briefs, briefs_24h, symbols, quotes, news_reports, latest_report (slug), devices, devices_online (seen in 15 min), last_push_at |
| `admin_list_agents()` | rows: id, name, slug, kind, color, created_at, last_seen_at, revoked_at, key_prefix, key_created_at, pushes_7d, last_error |
| `admin_create_agent(name, kind, color)` | one row: id, slug, **key** (shown once) |
| `admin_rotate_agent_key(agent)` | the new key (text); un-revokes |
| `admin_update_agent(agent, name, kind, color)` | void; nulls keep |
| `admin_revoke_agent(agent)` / `admin_delete_agent(agent)` | void |
| `admin_list_briefs(lim, off)` | rows with agent_name, agent_color |
| `admin_delete_brief(brief)` | void |
| `admin_list_quotes()` | rows per symbol: symbol, name, sort_order, hidden, price, change, change_pct, currency, note, as_of, agent_name, agent_color, history_count |
| `admin_set_symbol(symbol, hidden, sort_order, name)` / `admin_delete_symbol(symbol)` | void |
| `admin_list_news_reports(lim)` | rows: id, slug, report_date, display_date, hero_item, published_at, agent_name, agent_color, item_count, sections (names) |
| `admin_news_report(report)` | jsonb { report, items[] } |
| `admin_delete_news_report(report)` | void |
| `admin_list_ingest(lim, off)` | rows: id, created_at, agent_id, agent_name, agent_color, feed, count, status, message |
| `admin_list_devices()` | rows: id, user_id, name, last_seen_at, created_at |
| `admin_rename_device(device, name)` | void |
| `admin_revoke_device(device)` | jsonb { user_id, auth_user_removed }; the `admin` function finishes the auth user |
| `admin_get_settings()` / `admin_update_settings(display_name, timezone, briefs_keep_days, quotes_keep_days, news_keep_reports)` | jsonb settings; nulls keep; an unknown timezone is refused |
| `admin_set_admin(target, make_admin)` | void; the last admin can't be removed; displays can't be admins |
| `admin_list_audit(lim, off)` | rows: id, created_at, admin_email, action, target_type, target_id, details |

Audit actions: create_agent, rotate_agent_key, update_agent, revoke_agent,
delete_agent, delete_brief, set_symbol, delete_symbol, delete_news_report,
rename_device, revoke_device, pair_device (written by pair-device),
update_settings, set_admin.

## 2. Edge functions

All answer JSON with the CORS headers; errors are `{ error }`. The gateway's
JWT check is off for all four (`config.toml`); each checks its caller.

### 2.1 `ingest` (agents)

`Authorization: Bearer mcf_…` (or `X-Agent-Key`). `POST /ingest/briefs`,
`/ingest/quotes`, `/ingest/news`, or `POST /ingest` with `"type"`.
`GET /ingest` → `{ ok, agent: { id, name, slug, kind }, recent: [...], feeds }`.
Success: `{ ok: true, feed, count, agent (slug), …extras }` (`symbols` for
quotes; `report_id`, `slug`, `images`, `items` for news). Errors: 400 bad
payload (the sentence names the first problem), 401 no or unknown key, 404
unknown feed, 413 body over 1 MB, 503 database unreachable. Every attempt is
written to `ingest_log`. Full payloads: [AGENTS.md](AGENTS.md).

### 2.2 `pair-device`

| Action | Caller | Body | Answer |
|---|---|---|---|
| `start` | display, no auth | `{ secretHash }` (hex SHA-256 of a secret the display keeps) | `{ code, expiresAt }` |
| `claim` | **an admin's JWT** (the Apple app or the console) | `{ code, name? }` | `{ deviceId }`; 403 for non-admins, 404 unknown/expired, 409 used |
| `redeem` | display, no auth | `{ code, secret }` | `{ status: "pending" }` or `{ status: "paired", deviceId, session: { accessToken, refreshToken, expiresAt } }`; 404 invalid, 410 expired |

The display polls `redeem` every 3 s and asks for a new code when one
expires. Once paired it stores the refresh token (`~/.config/McFly/display.conf`)
and reads the feeds as its device user.

### 2.3 `admin`

`Authorization: Bearer <admin JWT>`. `{ action: "revoke_device", device_id }`
→ `{ ok: true, auth_user_removed }`.

### 2.4 `assistant`

`Authorization: Bearer <JWT>` of a person with admin rights or of a paired
display (anyone `can_read()`).

```
POST { message: string (≤4000), mode?: "chat" | "quick", stream?: boolean,
       history?: [{ role: "user" | "assistant", text }] (the last turns, at most 10, client-held) }
stream false → { reply, model, changed? }
stream true  → text/event-stream:  event: delta  data: { text }
                                   event: done   data: { reply, model, changed? }
                                   event: error  data: { message }
```

Grounded in a snapshot read with the caller's own JWT: the display name and
local time (`platform_settings`), the newest briefs (10, clipped), every
visible symbol's latest quote and note, and the newest report's stories
(headline, takeaway, source), and the open `todos`. Tools: when the person
asks, it adds an event (calendar "McFly"), a todo or a reminder, or checks a
todo off (`add_event`, `add_todo`, `add_reminder`, `complete_todo`). Times
come from the model as local wall-clock times and are turned into instants
in `platform_settings.timezone` on the server. The writes go through
`ingest_events` / `ingest_todos` / `set_todo_done` with the service role, as
the built-in key-less agent "McFly" (`mcfly_agent()`), after `can_read()`
passed; at most 5 per question, and never because the snapshot says to.
`changed` (`["events", "todos"]`) says what was written, so a client can
refresh at once.
`quick` answers in one or two spoken sentences, no markdown; `chat` may use
short lists. Model: `ASSISTANT_MODEL` secret, default `claude-sonnet-5-5`.
Login: `ANTHROPIC_API_KEY` secret. Errors: 400 bad body, 401 no session,
403 not a reader, 503 model unavailable (`{ error }`, or an `error` event
once the stream has begun).

## 3. Pi display

Qt 6 app (`display/`). Settings: `MCFLY_SUPABASE_URL`, `MCFLY_SUPABASE_ANON_KEY`
(display.env), `MCFLY_IDLE_SECONDS`, `MCFLY_SCREENSAVER` (ambient | clock | headlines; ambient by default),
`MCFLY_VOICE_URL` (default `ws://127.0.0.1:8765`), `QT_SCALE_FACTOR`.
Syncs every 60 s (REST, device JWT): `platform_settings`, `agents`, `briefs`
(newest 100, unexpired), `symbols` + `quotes` (newest 2000 rows for
sparklines) + `quotes_latest` (`data` only: the holding, signals and stats
of docs/AGENTS.md, shown while part of their agent's newest push), `news_reports` with embedded `news_items` (newest 14). Checks
in (`devices.last_seen_at`) every 5 min. Screens: Home, Briefs, Markets,
News (story detail with a QR code for the link), Settings; screen savers
Ambient (the default), Clock and Headlines; the quick-answer card (voice) and the Ask panel.
Also read (optional, so an older backend doesn't fail the sync): open `todos`,
shown on Home's timeline; when a reminder's time comes (or came in the last
5 minutes), a card at the top of the screen and the voice service read it out
once (`FeedStore.reminderDue`). After an answer whose `done` has `changed`, it
syncs at once.

## 4. Apple app

SwiftUI, iPhone and Mac from one target set (`apple/`). Signs in with the
person's account (email + password or magic link, supabase-swift) and then:

- reads the same feeds through PostgREST with the person's JWT (RLS lets an
  admin read; a person who isn't an admin sees an explanation);
- **pairs a display**: enter (or scan) the 6-digit code → `pair-device`
  `claim`; lists displays (`admin_list_devices`) and can rename/revoke;
- voice: talks to `assistant` (`quick` for spoken turns, `chat` typed), with
  speech recognition and synthesis on the device; the glow is the Homestead
  `VoiceGlow` (color spectrum) driven by the microphone and the speaker;
- shows agents and their last push (`admin_list_agents`), and can make a
  key (`admin_create_agent`, shown once) so an agent can be set up from the
  phone.

## 5. Voice service (Pi)

`voice/`: wake word → the display shows the quick-answer card, streams the
answer from `assistant` (`quick`) and speaks it. Protocol as in
[VOICE.md](VOICE.md) over `ws://127.0.0.1:8765`.
