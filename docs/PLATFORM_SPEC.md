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
| `profiles` | One per person with an account: `id` (= auth user), `display_name`, `message_name` (what the household calls them on Messages, 1–24 characters, one line; null until set with `set_message_name`). A person reads and updates their own; admins read all. Not created for device accounts (`raw_app_meta_data.kind = 'device'`) |
| `platform_admins` | Who runs McFly. **The first person to sign up becomes an admin** (`handle_new_user` trigger); later people are added with `admin_set_admin`. Read-only to admins |
| `platform_settings` | One row: `display_name` ('McFly'), `timezone` ('America/Chicago'), `briefs_keep_days` (30), `quotes_keep_days` (90), `news_keep_reports` (14), `message_names` (who writes from the displays, at most 8, no two alike; `admin_set_message_names`), away mode: `away_since`, `away_until` (null: until it's turned off), `away_note` (≤80, one line), `away_name` (the person's `message_name` when they set it, or the first admin's when a display does; displays can't read profiles), all written by `set_away` and, from a display, `device_set_away` (§1.8). Readable by displays and admins; written by `admin_update_settings` |

Helpers: `is_service_role()`, `is_platform_admin()` (true for the service
role too), `is_device()`, `can_read()` (= device or admin).

### 1.2 Displays

| Table | Notes |
|---|---|
| `devices` | Paired displays: `id`, `user_id` (its auth user, unique), `name`, `last_seen_at`, `created_at`, `settings` (jsonb, the keys `clean_device_settings` allows). A display reads its own row and may update only `last_seen_at` directly (`devices_guard`), its settings through `device_update_settings`; admins read all. `settings.voice` is also **the account's voice**: the first display's (by `created_at`) that has one is what the console and the Apple app speak with, and a voice they pick is written to every display ([VOICE.md](VOICE.md), One voice everywhere) |
| `dismissals` | Callouts someone dismissed (migration 20261021000070): `key` (an insight's id, lower-cased: `blocked:<project id>`, `metric:<key>`, `mover:<symbol>`, …), `hide_until` (null: until the project's status or next step changes, which a trigger on `projects` sees to; anything else: the end of today in `platform_settings.timezone`), `dismissed_at`, `device_id`. Displays and admins read; written only by `dismiss(item)` (a paired display or an admin), which also prunes the run-out rows. The display, the console's Today and the app hide a Needs-you project or an insight while its id has a row that hasn't run out |
| `asks` | Questions agents wait on (migration 20261029000010; §1.4) are answered by a display, as by the person, through `answer_ask(ask, choice, via, question)` (`authenticated`): a paired display's answer is `answered_via` display with its `device_id` (set null when the display is revoked), an admin's app or console (`via` 'console', else app), the service role's assistant. The caller's `via` counts only for an admin. The row is locked while it's checked; `question`, the text the caller showed, refuses the answer with "the agent changed this question; look again" when the agent has changed it since (whitespace aside), and every client sends it |
| `messages` | The household thread (migration 20261103000010; §1.8): a display writes to it through `send_message(body, sender_name)` and marks the person's replies read through `read_messages(up_to)` (`authenticated`), the fifth and sixth things a display may write |
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
| `quotes_latest` | View: the newest row per symbol. Its `data` (the holding, signals and stats of docs/AGENTS.md) is read from here by the display, the app and the console's Markets (a direct select, `can_read()`), so the history is read without it |
| `symbols` | Every symbol seen: `symbol`, `name`, `sort_order` (1000 for new ones), `hidden`, `updated_at`. The console orders and hides; the display shows `not hidden` in `sort_order, symbol` order |
| `news_reports` | A Daily Pulse report: `agent_id`, `slug` (unique, normally the date), `report_date`, `display_date` (as the agent wrote it), `hero_item` (an item key), `published_at` |
| `news_items` | `report_id`, `section_key`, `section_name`, `section_order`, `item_key` (unique per report and section), `position`, `headline` (≤300), `takeaway` (≤2000), `url` (http/https), `image_url`, `source_domain` (host without www) |
| `news_articles` | The article behind a story, read the first time someone opens it (§2.6) and kept with its item (`item_id`, primary key, cascades): `status` ∈ ready (the page's text) · partial (a preview: a paywall, a video) · unavailable, `title`, `byline`, `site_name`, `published_at`, `lead_image`, `blocks` (below), `word_count`, `summary` (≤2000), `points` (≤8), `summary_model`, `summary_tried_at`, `illustration` (Grok's picture of the story: its path in the private `news-illustrations` bucket), `illustration_model`, `illustration_tried_at`, `fetched_at`. Written only by `store_news_article(item, article jsonb)` (service role), which checks it again |
| `admin_audit_log` | Every admin change, written by the RPCs and the functions |
| `calendar_sources` | Calendar subscriptions, read every 15 minutes by `calendar-sync` into `events` under the built-in agent `calendar-subscriptions`: `kind` ∈ ical · google, `name` (unique; the events' calendar), `url` (an iCal link, kind ical; service role only, the console sees its host), `google_account_id` + `google_calendar_id` (kind google), `color`, `enabled`, `last_synced_at`, `last_error`, `event_count` |
| `google_accounts` | Service role only (RLS on, no policies): a Google account the admin signed in with: `email` (unique), `refresh_token`, `scope`, `connected_by`, `connected_at`, `last_error`. `google_oauth_states` (same) holds a sign-in under way: `state`, `user_id`, `return_to`, ten minutes |
| `asks` | A question an agent is waiting on (migration 20261029000010): `agent_id`, `external_id` (the agent's id, no commas; unique per agent), `question` (≤300), `detail` (≤2000), `choices` (2 to 4 distinct one-line labels of 1 to 32 characters; Yes and No when none are sent), `url`, `expires_at`, `withdrawn_at`, `answer` (one of `choices`), `answered_at`, `answered_by` (the auth user, no reference), `device_id`, `answered_via` ∈ display · app · console · assistant, `created_at`, `updated_at`. Status (`ask_status`): answered, withdrawn, expired (`expires_at` passed) or open. Written by `ingest_asks` and `answer_ask` only. Closed ones go 30 days after they closed (`prune_asks()`, run by `ingest_asks` and after every push). Clients read the open ones with run-out ones filtered on the server, so old ones never crowd out new ones. In the realtime publication (20261029000011) |
| `google_watch_channels` | Service role only: one notification channel per watched Google calendar: `source_id`, `channel_id` (unique), `resource_id`, `token` (Google echoes it), `expires_at`. `calendar_sources.watch_error` says why Google refused one |

An article's `blocks`, in page order: `{ type: "p" | "h", text }`,
`{ type: "quote", text, cite? }`, `{ type: "list", items: [text], ordered? }`,
`{ type: "image", url, caption? }`, `{ type: "video", url, provider: "youtube" |
"vimeo" | "file", poster?, caption? }` (a YouTube or Vimeo video's `url` is its
watch page). Clients leave out a type they don't know.

Retention: `prune_feed()` applies the settings (old briefs, old quote
history keeping the newest row per symbol, old reports, 90 days of log).
The ingest function calls it after each push.

### 1.5 Ingest functions (service role)

`ingest_briefs(agent, items jsonb) → int`, `ingest_quotes(agent, items jsonb,
as_of_default) → int`, `ingest_news(agent, report jsonb) → uuid` (replaces a
report with the same slug), `record_ingest(agent, feed, count, status,
message)`, `agent_for_key(hash) → (id, name, slug, kind)` (null when
unknown or revoked). `ingest_asks(agent, items jsonb) → jsonb` (each ask as
`ask_reply()`: id, status, question, choices, answer, answered_at,
answered_via, asked_at, expires_at; an answered ask is never changed by a
re-push), `agent_read_asks(agent, ids text[], open_only) → setof jsonb`
(the agent's own, newest first, at most 100) and `prune_asks() → int`.
Payload shapes:
[AGENTS.md](AGENTS.md).

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
| `admin_list_devices()` | rows: id, user_id, name, last_seen_at, created_at, settings (oldest first) |
| `admin_update_device_settings(device, patch)` | jsonb settings; merges the cleaned patch into the display's |
| `admin_rename_device(device, name)` | void |
| `admin_revoke_device(device)` | jsonb { user_id, auth_user_removed }; the `admin` function finishes the auth user |
| `admin_get_settings()` / `admin_update_settings(display_name, timezone, briefs_keep_days, quotes_keep_days, news_keep_reports)` | jsonb settings; nulls keep; an unknown timezone is refused |
| `admin_set_admin(target, make_admin)` | void; the last admin can't be removed; displays can't be admins |
| `admin_list_calendar_sources()` | rows: id, name, host, color, enabled, last_synced_at, last_error, event_count, created_at, kind, account_id, account_email, google_calendar_id, watch_expires_at, watch_error |
| `admin_add_calendar_source(name, url, color)` / `admin_update_calendar_source(source, name, color, enabled)` / `admin_delete_calendar_source(source)` | uuid / void / void (with the events) |
| `admin_list_google_accounts()` | rows: id, email, connected_at, last_error, calendars |
| `admin_add_google_calendar(account, calendar_id, name, color)` | uuid: a `calendar_sources` row of kind google (a taken name gets the account's email appended) |
| `admin_delete_google_account(account)` | the email; its calendars and their events go too (the `google-calendar` function revokes at Google first) |
| `admin_list_audit(lim, off)` | rows: id, created_at, admin_email, action, target_type, target_id, details |

Audit actions: create_agent, rotate_agent_key, update_agent, revoke_agent,
delete_agent, delete_brief, set_symbol, delete_symbol, delete_news_report,
rename_device, revoke_device, pair_device (written by pair-device),
update_settings, set_admin, add_calendar_source, update_calendar_source,
delete_calendar_source, connect_google_account (written by google-calendar,
as the admin who began the sign-in), disconnect_google_account,
set_message_names, set_message_name, set_away (§1.8).

Service role only, for the functions: `calendar_sources_due(source)` (the
enabled subscriptions with each Google calendar's account and token),
`calendar_source_synced(source, count, error)`, `google_oauth_begin(state,
who, return_to)` / `google_oauth_finish(state)` (one use, ten minutes),
`google_account_save(email, refresh_token, scope, who)` (upsert by email),
`google_account_credentials(account)`, `google_account_failed(account, error)`;
for the notification channels `google_watch_list()`, `google_watch_save(source,
channel_id, resource_id, token, expires_at)` (upsert by source; clears
`watch_error`), `google_watch_failed(source, error)`,
`google_watch_for_channel(channel)` → (source_id, token, enabled, last_synced_at).

### 1.7 Made dashboards

`dashboards.sources` (jsonb, null for an agent's board) is a board made in
the console: a list of 1 to 20 parts, each `{ from, … }`
([AGENTS.md](AGENTS.md), Dashboards you make in the console);
`dashboards.template` names the console template it started from. The
database draws the parts into `widgets` (`dashboard_widgets(sources)`, the
same six widget types an agent pushes), so displays and apps read a made
board like any other and need nothing new. It redraws them once at the end
of any transaction that writes a table they pull from (a deferred
constraint trigger on quotes, symbols, metrics, metric_settings, projects,
events, todos, news_reports, news_items, briefs, agents and ingest_log;
a failed redraw is a warning, never the writer's error), and pg_cron
redraws every minute (`mcfly-dashboards`) for time-relative parts. Rows are
written only when their widgets change. A made board belongs to
`mcfly_agent()`; `ingest_dashboards` can't take one over.

| Function | Returns |
|---|---|
| `admin_dashboard_sources()` | jsonb: symbols, metrics, projects, calendars, news_sections, agents (what parts can pull from), timezone |
| `admin_preview_dashboard(sources)` | jsonb widgets, drawn now, nothing saved |
| `admin_save_dashboard(dashboard, title, sources, subtitle, template)` | uuid; no `dashboard` makes one (its key from the title, made unique), else edits a made one |
| `admin_list_dashboards()` | rows: id, key, title, subtitle, widgets, sort_order, hidden, updated_at, agent_name, agent_color, template, sources |

Audit actions: create_dashboard, edit_dashboard (with set_dashboard and
delete_dashboard, which treat a made board like any other).

### 1.8 Messages

The people at home write to the person from a display, and the person
replies from the app or the console (migration 20261103000010). One thread
for the household. Not an agent feed: there is no `ingest_messages` and
nothing in AGENTS.md.

| Table | Notes |
|---|---|
| `messages` | `id`, `sender_kind` ∈ display (written on a display) · person (the person's reply), `sender_name` (≤40: one of `platform_settings.message_names` in the list's spelling, else the display's own name; for the person their `message_name`, else "Parent"), `body` (1–500 characters, lines but no other control characters), `device_id` (the display; set null when it's revoked), `author` (the auth user, no reference), `via` ∈ display · app · console, `created_at`, `updated_at` (moved by a read and a notification too: screens poll by it), `read_at` (the other side read it), `notified_at` / `notify_error` (a display's message: Apple took its notification for a phone, or why none went), `audio_path` / `audio_ms` (a voice note, migration 20261104000020: its WAV in the `voice-notes` bucket and its length, 0.3–31 s; with no caption the body is the server's own "🎤 Voice note · 0:12"). Displays and admins read (`can_read()`). Messages over a year old go (pruned by `send_message`); their audio stays in the bucket |
| `voice-notes` (Storage bucket) | Private, WAVs (`audio/wav`) up to 1.5 MB: 30 s of 16 kHz mono 16-bit is about 960 KB. A paired display or an admin uploads into `<their auth user>/<uuid>.wav` and reads every note (policies `voice_notes_upload`, `voice_notes_read`) |
| `push_tokens` | Service role only (RLS on, no policies): `token` (hex, Apple's), `user_id`, `environment` ∈ sandbox · production (which of Apple's hosts: a debug build's token is a sandbox one), `bundle_id`, `platform` ∈ ios · macos, `created_at`, `updated_at` |

| Function | Who | Does |
|---|---|---|
| `send_message(body, sender_name, via, audio_path, audio_ms)` | a paired display, or an admin's own sign-in | (The three-argument one of 20261103000010 is gone; a call naming only those still resolves.) A voice note: `audio_path` in the caller's own folder of `voice-notes`, already uploaded, and `audio_ms`; the body is then an optional caption. Sends to the thread; the server says who (`sender_kind`, `device_id`, `via`: an admin's `via` is console or app). A display's `sender_name` must be one of the names when names are listed ("pick who is writing: Mia, Leo"); none given, it's the display's name. At most 10 a minute and 60 an hour from one display. The body is trimmed, `\r\n` made `\n`, tabs spaces, runs of blank lines one. Returns the row |
| `read_messages(up_to)` | the same | Marks the other side's messages read up to and including that one (null: all): a display the person's, the person the displays'. Returns how many |
| `register_push_token(token, environment, bundle_id, platform)` / `unregister_push_token(token)` | an admin's own sign-in, never a display | The phone that gets notifications; a kept token moves to whoever registers it |
| `set_message_name(name)` | an admin's own sign-in | Their `profiles.message_name`; blank clears it |
| `set_away(away, until, note)` | an admin's own sign-in, never a display | Away mode (migration 20261104000010) on, until `until` (at most two weeks out; null: until it's turned off), or off. On again while away keeps when it began. Returns { away, since, until, note, name }. Audit `set_away`. Each screen decides "still away" against `away_until` itself |
| `device_set_away(away, until)` | a paired display | Away mode from the screen at home (migration 20261104000030): the same limits as `set_away`, no note. The name is the household's for the person (the first admin's `message_name`, else "Parent"); on again while away keeps when it began, the name and the note; off ends it whoever set it. Audit `set_away` with the display's name. Anyone at the screen may: all it does is put Messages first |
| `admin_set_message_names(names)` | admins | `platform_settings.message_names`, trimmed, blanks out, at most 8, no two alike (audit `set_message_names`) |
| `message_push(message)`, `message_notified(message, error)`, `push_token_gone(token)` | service role | For `notify` (§2.7): a display's message as its notification says it with the unread count and every admin's tokens; its outcome; a dead token forgotten |

A display's message is posted to `notify` by the `messages_notify` trigger
through pg_net, with the project URL and the cron secret from Vault, once
the insert commits. Without Vault or pg_net (the local test run) nothing is
sent, and a failure there is only a warning: it never blocks the message.

## 2. Edge functions

All answer JSON with the CORS headers; errors are `{ error }`. The gateway's
JWT check is off for all of them (`config.toml`); each checks its caller.

### 2.1 `ingest` (agents)

`Authorization: Bearer mcf_…` (or `X-Agent-Key`). `POST /ingest/briefs`,
`/ingest/quotes`, `/ingest/news`, … `/ingest/asks`, or `POST /ingest` with `"type"`.
`GET /ingest` → `{ ok, agent: { id, name, slug, kind }, recent: [...], feeds }`.
`GET /ingest/asks` (`?id=a,b`, `?open=1`) → `{ ok, asks: [...] }`, the
agent's own asks and their answers, with no scope needed.
Success: `{ ok: true, feed, count, agent (slug), …extras }` (`symbols` for
quotes; `report_id`, `slug`, `images`, `items` for news; `asks` for asks, each
as it now stands). Errors: 400 bad
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
POST { message: string (≤4000), mode?: "chat" | "quick" | "read", stream?: boolean, suggested?: boolean,
       history?: [{ role: "user" | "assistant", text, interrupted?: boolean }] (the last turns, at most 10, client-held) }
stream false → { reply, model, changed? }
stream true  → text/event-stream:  event: delta  data: { text }
                                   event: done   data: { reply, model, changed? }
                                   event: error  data: { message }
```

Grounded in a snapshot read with the caller's own JWT: the display name and
local time (`platform_settings`), the newest briefs (10, clipped), every
visible symbol's latest quote and note, and the newest report's stories
(headline, takeaway, source), the open `todos`, and the open `asks` (with
their agent's name and choices). Tools: when the person
asks, it adds an event (calendar "McFly"), a todo or a reminder, checks a
todo off, or answers an agent's question (`add_event`, `add_todo`,
`add_reminder`, `complete_todo`, `answer_ask`). Times
come from the model as local wall-clock times and are turned into instants
in `platform_settings.timezone` on the server. The writes go through
`ingest_events` / `ingest_todos` / `set_todo_done` with the service role, as
the built-in key-less agent "McFly" (`mcfly_agent()`), after `can_read()`
passed; at most 5 per question, and never because the snapshot says to.
`answer_ask` answers one of the snapshot's open asks with one of its
choices, through `answer_ask` with the service role (`answered_via`
assistant, with the question it showed), and only when the person's
latest message says that choice (`saidChoice`): the label's words, or for
Yes and No a word that says it, not after "not" or "don't", in a message
that isn't a question and names no other of its choices; a second question
in the same message must name its agent. `suggested: true` says the message
wasn't typed or spoken by the person (a chip, an insight, a question carried
in a link such as `/ask?q=`): every client sends it, and such a message
never answers an ask. So text an agent pushed can't pick an answer. `changed` (`["asks", "events", "todos"]`) says what was written, so
a client can refresh at once.
`interrupted: true` on an assistant turn says the person cut that answer
short (stopped it, or talked over it while it was read out) to say what
comes next; the turn after it reaches the model with a note to take it as a
change to the question unless it's a new one. Every client sends it: the
display (stop, or a tap on the voice card or push-to-talk while a reply is
read out), the app (a tap in voice mode, Stop in the chat) and the console
(Stop, or the mic or a new question while an answer is read out). An answer stopped before any of it came isn't sent: its question
joins the next message.
`quick` answers in one or two spoken sentences, no markdown; `chat` may use
short lists; `read` (the console's full-screen Ask, `/ask`) answers at length
in Markdown (headings, lists, bold, tables), with a larger token budget and
medium effort instead of low. The prompt is composed from three skills
(`assistant/skills.ts`, [ASSISTANT.md](ASSISTANT.md)): `brief` in every
mode, `layout` in `read`, `spoken` in `quick`. `read` adds two shapes to
Markdown, which the app and the console both draw: a list item opening with
`[word or two]` (1–24 characters, then a space) carries it as a chip, and a
fence marked `stats` holds `label | value | tone` lines (tone `up`, `down`,
`watch` or none) drawn as tiles. A table that doesn't fit the page is drawn
as a card per row. Model: `ASSISTANT_MODEL` secret, default `claude-sonnet-5-5`.
Login: `ANTHROPIC_API_KEY` secret. Errors: 400 bad body, 401 no session,
403 not a reader, 503 model unavailable (`{ error }`, or an `error` event
once the stream has begun).

### 2.5 `google-calendar`

The Google sign-in behind the console's Calendars page. Secrets:
`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, optional `GOOGLE_REDIRECT_URI`
(default `<project>/functions/v1/google-calendar/callback`). Scopes asked
for: `openid email https://www.googleapis.com/auth/calendar.readonly`, with
`access_type=offline` and `prompt=consent` so a refresh token comes back.

```
POST { action: "connect", return_to, email? }   admin JWT → { ok, url }  (Google's authorization page; a random
                                                 state is kept with google_oauth_begin, ten minutes, one use)
GET  /callback?code&state                        Google's redirect of the admin's browser → 302 to return_to
                                                 ?google=connected, or ?google_error=<sentence>. The state is
                                                 spent (google_oauth_finish), the code traded for tokens, the
                                                 account's email read from the id token, the refresh token kept
                                                 with google_account_save; a sign-in without the calendar scope
                                                 or a refresh token is revoked at Google and refused
POST { action: "calendars", account }            admin JWT → { ok, email, calendars: [{ id, name, color, primary,
                                                 access_role, selected }] }  (Google's calendarList, now)
POST { action: "disconnect", account }           admin JWT → { ok, email }  (revoked at Google, then
                                                 admin_delete_google_account as the admin)
POST /notify   X-Goog-Channel-ID, -Channel-Token, Google's notification that a watched calendar changed → 200 at once;
               -Resource-ID, -Resource-State     a "sync" state (a new channel) does nothing; otherwise the channel is
                                                 looked up (google_watch_for_channel), its token compared in constant
                                                 time, and the one calendar read through calendar-sync after the answer
                                                 (EdgeRuntime.waitUntil). Unknown channel or token: 200, nothing done.
                                                 A calendar read in the last 15 s is not read again (one change, a burst)
```

Errors: 400 bad body, 401 no session, 403 not an admin, 404 unknown account,
409 Google no longer accepts the sign-in (the account's `last_error` is set;
connect again), 503 secrets missing or Google unreachable.

`calendar-sync` (every 15 minutes, or one source from "Sync now") reads each
enabled subscription: a link's iCal, or for a Google calendar
`events.list(singleEvents, −1 day … +60 days)` with a token refreshed once
per account per run, then `ingest_events` with `replace` under the built-in
agent. An `invalid_grant` from Google marks the account (`google_account_failed`).
After a Google calendar is read it keeps the calendar's notification channel
(`events.watch` to `GOOGLE_WEBHOOK_URL`, default the function's own `/notify`,
which Google refuses until the address's domain is verified: `watch_error`):
opened when there is none, renewed with under two days left, the old one
stopped (`channels.stop`). The console's `/api/google/notify` forwards
Google's headers to the function for a domain of the console's own.

### 2.6 `article`

A news story read in full, for the story view on the display and in the
app. `Authorization: Bearer <JWT>` of anyone `can_read()`.

```
POST { item_id }  → { article: { item_id, status, title, byline, site_name, published_at, lead_image,
                                 blocks[], word_count, summary, points[], summary_model, illustration_url,
                                 illustration_model, fetched_at, pending } }
```

The story is read as the caller (RLS); its own `url` is fetched, never one
the caller sends, and only a public http(s) address on every redirect hop
(no local, private or link-local hosts), at most 3 MB of HTML in 8 s. The
article comes from the page's JSON-LD `articleBody` when that has more of the
story, else from Readability over the page, keeping its pictures and
YouTube/Vimeo/video-file embeds as blocks; under 120 words it is `partial`
with the page's description. A YouTube or Vimeo story is its video. A
`ready` article of 150 words or more is summarized by the assistant's model
(`platform_settings.assistant_provider`: Claude with `ASSISTANT_MODEL`, or
Grok with `GROK_MODEL`), as JSON `{ summary, points }`; a `partial` or
`unavailable` one (many sites turn servers away) by Grok reading the story
with its web search (Responses API, `GROK_READ_MODEL`, default
`grok-4.20-0309-non-reasoning`). A failure leaves `summary` null and is tried
again after 10 minutes. The answer comes within 11 s with what is ready and
`pending: true` while a summary or picture is still being made; that work is
stored when it lands, and clients ask again every 6 s (about two minutes at most). Everything is kept in
`news_articles`: later opens, from any client, get that copy; an
`unavailable` page is read again after an hour. While the page is read,
Grok draws a picture of the story (xAI's `GROK_IMAGE_MODEL`, default
`grok-imagine-image-2.0`, 4:3 at 1k, from the headline, takeaway and section;
no words, logos or real people), kept in the `news-illustrations` bucket as
`<item_id>.jpg` and answered as `illustration_url`, a link signed for 30 days.
Clients lead the summary with it ("Drawn by Grok"); a failure is tried again
after 10 minutes. After a new picture, ones whose story is gone are removed
(`orphaned_illustrations()`, service role). Errors: 400 bad body, 401 no
session, 403 not a reader, 404 no such story.

### 2.7 `notify`

A message from home on the person's phones, through Apple's push service
(HTTP/2, a provider token signed ES256 with the team's key and kept 50
minutes). Secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (the .p8
file's text; `\n` for its line breaks, or the whole file in base64, also do).

```
POST { message }          x-mcfly-cron (the messages_notify trigger) → { ok, sent, failed, gone }
POST { action: "test" }   an admin's JWT → { ok, results: [{ token (its end), environment, status, reason, outcome, message }] }
```

The notification: the writer as the title, the display under it when
there's more than one, the message, the unread count from home as the
badge, `thread-id` mcfly-messages, category `MCFLY_MESSAGE` (the app's Reply
action), and `message_id`. Each token goes to its own environment's host
with its own bundle id as the topic. A token Apple calls no good (410,
BadDeviceToken, DeviceTokenNotForTopic) is forgotten; an expired provider
token is made anew once. The outcome is kept on the message
(`message_notified`): "notifications aren't set up on the server yet"
without the secrets, "no phone has turned on notifications yet" without a
token. Errors: 400 bad body, 401 not the scheduler (or no session for
`test`), 403 not an admin, 404 no phone of yours (`test`), 503 not set up.

## 3. Pi display

Qt 6 app (`display/`). Settings: `MCFLY_SUPABASE_URL`, `MCFLY_SUPABASE_ANON_KEY`
(display.env), `MCFLY_IDLE_SECONDS`, `MCFLY_SCREENSAVER` (ambient | clock | headlines; ambient by default),
`MCFLY_VOICE_URL` (default `ws://127.0.0.1:8765`), `QT_SCALE_FACTOR`.
Syncs every 60 s (REST, device JWT): `platform_settings`, `agents`, `briefs`
(newest 100, unexpired), `symbols` + `quotes` (newest 2000 rows for
sparklines) + `quotes_latest` (`data` only: the holding, signals and stats
of docs/AGENTS.md, shown while part of their agent's newest push), `news_reports` with embedded `news_items` (newest 14),
and its own `devices.settings`, both ways (`SettingsBridge`: the server's copy is applied, a change made on the screen is
sent with `device_update_settings`; the voice included, which the console and the app follow). Checks
in (`devices.last_seen_at`) every 5 min. Screens: Home, Briefs, Markets,
News (a story opens to its summary and key points or the full article,
from `article` (§2.6), with Grok's picture leading the summary, the page's
pictures and videos, and a QR code
for the link, or for a video once one is tapped), Settings; screen savers
Ambient (the default), Clock and Headlines; the quick-answer card (voice) and the Ask panel.
Also read (optional, so an older backend doesn't fail the sync): the open
`asks`, shown as a card at the top of the screen (under the screen saver;
never waking the screen or speaking) with a button per choice, put off for
half an hour with ×; a tap hides it at once and calls `answer_ask` after a
six-second undo, and an answer that lost to another screen's says so; open `todos`,
shown on Home's timeline; when a reminder's time comes (or came in the last
5 minutes), a card at the top of the screen and the voice service read it out
once (`FeedStore.reminderDue`). After an answer whose `done` has `changed`, it
syncs at once.

Messages (the ninth screen, `--screen messages`; optional, so an older
backend shows "Messages aren't set up yet"): `MessageStore` reads the
thread once, then only what changed (`updated_at` after the newest seen
less 30 s, rows de-duplicated by id), every 5 s while Messages is open or
for five minutes after a send, else every 30 s; `message_names` with the
first read and every tenth. Who's writing is a button a name (a name stays
picked until the screen goes idle); a message is typed or tapped from the
quick row. It shows at once ("Sending…") and stays with why it didn't go,
a tap to try again. Under home's newest: Sent, "On Dad's phone"
(`notified_at`), "Seen by Dad" (`read_at`). On screen and uncovered, the
person's replies are marked read (`read_messages`). **Voice notes**:
the Voice note button (beside Send, shown while the voice service has a
microphone) records one through the voice service (`record`, at most 30 s;
Send ends and sends it, × drops it; it asks who's talking first when names
are listed), uploaded to `voice-notes` in the display's folder, then
`send_message` with it; ▶ plays one, its WAV read from Storage with the
device's session and handed to the voice service (`play`), which never
reaches the network. A voice note from the person plays when it arrives,
under the same guards as the read-aloud. A reply seen for the
first time elsewhere is a card at the top of the screen with Reply, read out
once; it wakes the screen unless the screen is asleep, where it waits under
the sleep cover. The rail's Messages carries the unread count. Asks never
show on Messages. `platform_settings` is read with every poll (`select=*`,
so an older backend still answers) for the names and away mode: while
away, Messages is the whole window, the rail (or bar), the assistant, the
wake-word card and Settings out of reach, so the chat is all there is;
whoever wakes the screen finds it, and a pill over the screen saver says to
tap to send a message. Its header says who's out, counts down to
`away_until` each second ("2:04:59 till Dad's back", "Back around 6:00
pm", the note; with no time, "Messages go to Dad's phone"), and has "I'm
home". "Still away" is checked each minute against `away_until`, and at
the end of the countdown. On the landscape tiers who's writing and the
quick messages are a column of their own beside the thread, never over it.
**Away mode from the screen**: "I'm heading out" beside the title asks how
long (till they're back, 1, 2, 4 or 8 hours) and turns it on through
`device_set_away`; "I'm home" on the banner turns it off. The banner
follows once the server has it; a refusal is a toast saying why.

## 4. Apple app

SwiftUI, iPhone and Mac from one target set (`apple/`). Signs in with the
person's account (email + password or magic link, supabase-swift) and then:

- reads the same feeds through PostgREST with the person's JWT (RLS lets an
  admin read; a person who isn't an admin sees an explanation); `quotes`
  without `data`, which comes from `quotes_latest`, so Markets shows the
  holding, signals and numbers as the display does;
- **pairs a display**: enter (or scan) the 6-digit code → `pair-device`
  `claim`; lists displays (`admin_list_devices`) and can rename/revoke;
- voice: talks to `assistant` (`quick` for spoken turns, `chat` typed), with
  speech recognition and synthesis on the device, in the account's Kokoro
  voice (`devices.settings.voice`, §1.2; a pick in Settings goes to every
  display through `admin_update_device_settings`) or, chosen here, the
  system's own, which stays on the device; the glow is the Homestead
  `VoiceGlow` (color spectrum) driven by the microphone and the speaker;
- shows agents and their last push (`admin_list_agents`), and can make a
  key (`admin_create_agent`, shown once) so an agent can be set up from the
  phone;
- opens a news story to its summary and key points or the full article
  (`article`, §2.6), Grok's picture leading the summary and the page's
  pictures and videos in place; the choice
  is remembered, and the takeaway and the link stand in when a page can't
  be read;
- makes dashboards (Dashboards → +) and edits made ones, as the console
  does (§1.7): the same templates (McFlyKit `DashboardTemplate`), the parts'
  pickers from `admin_dashboard_sources`, a preview from
  `admin_preview_dashboard`, saved with `admin_save_dashboard`. The demo
  draws made boards itself (`DashboardDrawing`).
- shows the open `asks` at the top of Home, a button per choice, and answers
  one with `answer_ask` (`via` app) after a five-second undo, as the
  display does;
- Messages (Home's card when home wrote, More on the iPhone, the sidebar on
  the Mac): the thread read once, then polled every 5 s while open; a reply
  goes through `send_message` (`via` app) and shows at once, with Retry if
  it didn't go; home's messages are marked read as the thread shows (the
  badge follows). Who writes: what the household calls you
  (`set_message_name`) and the displays' names (`admin_set_message_names`),
  and a test notification. **Away mode** (the house button): on until a
  time or until it's turned off, with a note, through `set_away`; a banner
  on Messages while it's on. The App Intents "I'm Away" and "I'm Home" do
  the same from Shortcuts, so an automation on leaving and arriving home
  switches it. **Voice notes**: with the box empty the mic records one
  (AVAudioRecorder, 16 kHz mono 16-bit WAV, at most 30 s; ↑ sends, ✕ drops),
  uploaded to `voice-notes` in the person's folder, then sent; ▶ plays one,
  downloaded once and kept. On the iPhone, after sign-in, McFly asks to
  notify, registers its token (`register_push_token`, sandbox for a debug
  build, else production; again each launch, dropped on sign-out); a
  notification's tap opens Messages, its Reply sends from the lock screen.
  The Mac has no pushes: while open it polls every 30 s and notifies for
  itself;
- plays the display's games (Games), but for Same Game and Maroon in
  Trouble: on the device only, scores and progress in `UserDefaults`, nothing
  sent to the server.

## 5. Voice service (Pi)

`voice/`: wake word → the display shows the quick-answer card, streams the
answer from `assistant` (`quick`) and speaks it. Protocol as in
[VOICE.md](VOICE.md) over `ws://127.0.0.1:8765`.
