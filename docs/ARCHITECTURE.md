# Architecture

```
 ┌──────────────────┐        ┌──────────────────────────────┐        ┌──────────────────┐
 │  Agents          │──────▶ │  Supabase (cloud backend)    │◀──────▶│ Pi display       │
 │  Grok, stocks,   │ HTTPS  │  Postgres + RLS              │ HTTPS  │ Qt 6 / QML / C++ │
 │  Daily Pulse,    │ + key  │  Auth · Realtime             │ + SSE  │ Raspberry Pi 5   │
 │  code, metrics,  │        │  Edge Functions: ingest,     │        └────────┬─────────┘
 │  calendar, …     │        │  pair-device, admin,         │                 │ ws://127.0.0.1
 └──────────────────┘        │  assistant                   │        ┌────────┴─────────┐
 ┌──────────────────┐        │                              │        │ Voice service    │
 │ Console          │◀──────▶│                              │        │ wake word, STT,  │
 │ mcfly.bot        │  HTTPS └──────────────┬───────────────┘        │ TTS (on the Pi)  │
 └──────────────────┘                       │ HTTPS + SSE            └──────────────────┘
                             ┌──────────────┴───────────────┐
                             │ Apple app (iPhone, Mac)      │
                             │ feeds · voice · pairing      │
                             └──────────────────────────────┘
```

[PLATFORM_SPEC.md](PLATFORM_SPEC.md) is the contract between these parts.
Change it first when a shape changes.

## Backend: Supabase

- **Postgres** holds the feeds; row-level security lets a paired display or
  an admin read every row and nobody else (`backend/supabase/migrations`).
- **Auth** has two kinds of users: the person (the console and the apps sign
  in as them; the first to sign up is the admin) and devices (one auth user
  per display, created at pairing).
- **Agent keys** are SHA-256 hashes in a table with no policies. The key is
  shown once when made and never stored.
- **Edge functions**: `ingest` (agents push), `pair-device` (binds a display
  to the account), `admin` (the one console action that needs Auth's admin
  API), `assistant` (Claude or Grok, grounded in the feeds, streamed as SSE),
  `calendar-sync` (reads the calendar subscriptions every 15 minutes: iCal
  links, and Google calendars through the Calendar API), `google-calendar`
  (the Google sign-in behind the console's Calendars page; the refresh token
  stays in a service-role-only table), `bots` (Grok bots on a schedule).

### Data model

| Table | Notes |
|---|---|
| `profiles`, `platform_admins`, `platform_settings` | Accounts, who runs McFly, the display name, time zone, retention and the assistant's provider |
| `devices`, `pairing_codes` | Paired displays and the short-lived codes they show |
| `agents`, `agent_keys`, `ingest_log` | Who pushes, their hashed keys, every push |
| `briefs` | Text updates (Grok's hourly and daily notes, alerts) |
| `quotes`, `symbols`, `quotes_latest` | Stock quotes: one row per push, the newest per symbol shows, the history draws sparklines; order and hiding per symbol |
| `news_reports`, `news_items` | Daily Pulse reports: sections of sourced stories with takeaways and pictures. Several agents can push (several sources) |
| `projects`, `project_updates` | What's in flight: status, progress, stages and the one it is in, next step, and a timeline of commits, PRs, CI runs, deploys, notes |
| `metrics`, `metric_settings`, `metrics_latest` | Any number over time, grouped |
| `dashboards` | Boards agents lay out: a title and a widgets array (metric, status, progress, chart, list, text). A board made in the console has `sources` too, the parts it pulls from, and the database draws its widgets from them and keeps them drawn |
| `events` | Calendar events, per calendar; a push can replace a calendar whole |
| `todos` | Todos (maybe due by a day or time) and reminders (announced at a time), from agents or added by asking McFly |
| `admin_audit_log` | Every admin change |

Writes to the feeds happen only in the `ingest_*` SQL functions (called with
the service role after the key matched), which validate again; `prune_feed()`
applies the retention settings after each push.

## Display app: `display/`

Qt 6 with QML for the UI and C++ for data, networking and hardware.

```
QML screens  ─ Setup · Home · Briefs · Markets (+ Metrics) · News · Projects · Boards · Calendar
             ─ AssistantPanel · QuickAnswer · SettingsSheet · screen savers (Ambient, Headlines, Clock)
     │
FeedStore    ─ demo / pairing / live modes; shapes every feed for QML (labels, colors, sparklines)
Assistant    ─ streaming answers (ChatModel), Claude or Grok, demo answers from the feed
VoiceClient  ─ WebSocket to the voice service: wake, transcripts, speech
QrImageProvider ─ image://qr/… for the pairing code and story links (Nayuki's generator)
     │
SupabaseClient ─ REST (PostgREST) and streamed function calls (SSE)
     │
DisplayController ─ idle → screen saver → sleep, night palette, presence wake
PanelPower   ─ HDMI panel standby (DPMS) while the screen sleeps
SystemController ─ Wi-Fi, speakers, restart, reboot (through a root helper)
```

- **Setup screen**: the first-run screen is a full-screen drifting colour
  field (the `GradientTile` mesh gradient with its soft glass rings) and the
  `SpectrumGlow` along the bottom, both shaded at half their pixels
  (`resolution: 0.5`), with two steps on a glass card: Wi-Fi
  (networks and password, with the on-screen keyboard) and the 6-digit code
  plus a QR code (`https://mcfly.bot/pair?code=…`) to connect the screen to
  your account from the phone, the Mac or the console.
- **Voice glow**: `SpectrumGlow` is the Homestead app's voice visual (colour
  lobes, the band of light bending with the voice, the spectrum edge line)
  in one pass (`shaders/spectrumglow.vert` works out what depends only on x
  once a column, `.frag` the rest, and the dark rows above the light aren't
  drawn), driven by the microphone level, a spoken rhythm while the answer
  is read, and the beam while the model thinks.
- **Kiosk mode**: full screen on `eglfs`, one app per device, restarted by
  systemd; the boot video plays until the app takes the screen
  ([PI_SETUP.md](PI_SETUP.md)).
- **Sync**: every 60 s over REST with the device's JWT; a failed sync retries
  in 2 s, then 4, up to the interval; the device checks in every 5 minutes.
- **Touch first**: hit targets of at least 64 px, type readable from across
  the room, dialogs that close when the screen goes idle.

## Design system

- **Time-of-day moods.** `DisplayController` publishes a mood (morning, day,
  evening, night); `Theme.qml` maps it to a palette and animates every
  token. Settings → Dark mode swaps in a black palette with neutral greys.
- **Gradient tiles.** The highlight tiles (Home's brief, Markets' detail,
  the Calendar's day, the setup screen's field) are one shader pass: a
  pastel mesh gradient with drifting frosted-glass rings blurred into it
  (`GradientTile.blur`), under a fine static film grain.
- **Motion.** Pages cross-fade and settle, the nav pill springs, cards
  press, the code's digits light up in turn.

## Screen savers

After two minutes without a touch (`MCFLY_IDLE_SECONDS`) or a tap on the
moon: **Ambient**, the default (the clock, what's next and what follows
over the moving gradient, which keeps animating at 30 fps while idle and
stops when the panel is off, with a rail of cards along the bottom: the
latest brief, the markets, a blocked project, today's top story, later
events; the composition drifts every minute against burn-in), **Headlines**
(today's stories one at a time, over their pictures, with the clock) or
**Clock** (the time, the date, the latest brief and a
line of the markets on the time-of-day gradient). Settings → Backdrop (or the
console's Customize) picks what Ambient and Clock draw behind the words, and
what the assistant panel and the console's Ask open over (the mesh there
without the aurora, the console's skies at half strength):
**Mesh**, the moving gradient with an aurora hanging over it at night, or one
of five skies of their own, **Arc**, **Ribbons**, **Dawn**, **Silk** and
**Pillars** (`Backdrop.qml`: one shader each in the glow colours, laid on the
canvas in OKLab so they are a wash by day and a glow at night, each run at the
fraction of the screen its cost allows). Weather, beside it, falls over that
backdrop on Ambient and Clock, under the words: snow, petals, fireflies or
leaves, by the season where the display is (the date and its time zone's
hemisphere: `DisplayController::weatherFor`) or one all year (`Weather.qml`: a
few dozen small Shapes moved on the backdrop's own ten updates a second; the
console's Ambient view and the app's draw the same, with the same rules and
counts in each one's tests). Sleep turns the panel off
on a schedule (Settings → System → Sleep).

## Assistant

`assistant` grounds the model in a snapshot read with the caller's own JWT:
the display name and local time, the newest briefs, every visible quote and
metric, the open projects with their last update, the dashboards' widgets,
the next week's events, the open todos and reminders and today's stories.
Asked to, it adds an event, a todo or a reminder to the day, or checks a todo
off: four tools whose writes go through the ingest functions as McFly's own
key-less agent, never because something in the snapshot asked.
`quick` mode (voice) answers in one or two spoken sentences; `chat` may use
short lists. The provider is `platform_settings.assistant_provider` (Claude
or Grok, set in the console or the app) unless a display pins its own in
Settings → Voice → Assistant.

## Apple app: `apple/`

SwiftUI, one target for iPhone and Mac, `McFlyKit` for the models and
clients. Signs in with the person's account, reads the feeds with their JWT,
pairs displays (enter or scan the code; `mcfly://` and `https://mcfly.bot/pair`
links open the pairing sheet), and talks to the assistant with on-device
speech and the `VoiceGlow` colour-spectrum visual.

## Device pairing flow

1. An unpaired display asks `pair-device` for a code (sending only the
   SHA-256 of a secret it keeps) and shows it with a QR code.
2. The person, signed in on the phone, the Mac or mcfly.bot/pair, enters the
   code; `pair-device` checks they are an admin, creates the device auth user
   and the `devices` row, and marks the code claimed.
3. The display polls the code with its secret and receives its session. It
   stores the refresh token on disk and reads the feeds from then on.
