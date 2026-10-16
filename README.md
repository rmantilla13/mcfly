# McFly

Ricky's agent display: one person's AI agents push what matters into a few
feeds, and the feeds show up on a wall screen at home, on the phone and on
the Mac. Grok writes hourly and daily briefs, a stocks agent pushes quotes, the
Daily Pulse pipeline pushes the day's sourced stories, a code agent reports
on projects, other agents push metrics, whole dashboards and the calendar.
A voice assistant (Claude or Grok) answers questions about all of it.

| Part | What it is |
|---|---|
| `backend/` | Supabase: Postgres with row-level security, the feed tables, agent keys, and four edge functions (`ingest`, `pair-device`, `admin`, `assistant`) |
| `display/` | The wall screen: a Qt 6 / QML / C++ kiosk for a Raspberry Pi 5 with a touchscreen. Home, Briefs, Markets (and Metrics), News, Projects, Boards, Calendar, screen savers, voice |
| `apple/` | The iPhone and Mac app (SwiftUI): the same feeds, pairing a display, voice with the color-spectrum glow |
| `admin/` | The console at mcfly.bot (Next.js + shadcn/ui): agents and their keys, the feeds, displays, settings, audit |
| `voice/` | The on-device voice service for the Pi: wake word, speech in and out |
| `scripts/` | `mcfly_push.py`, a one-file client any agent box can push with |
| `docs/` | [Architecture](docs/ARCHITECTURE.md) · [Agents: how to push](docs/AGENTS.md) · [Platform spec](docs/PLATFORM_SPEC.md) · [Admin console](docs/ADMIN.md) · [Pi setup](docs/PI_SETUP.md) · [Voice](docs/VOICE.md) · [Hardware](docs/HARDWARE.md) · [Daily Pulse handoff](docs/HANDOFF.md) |

McFly is built on the Ohana (homeOS) foundation: the same Supabase shape, the
same Pi kiosk (boot video, quiet boot, systemd units, Wi-Fi from the screen,
sleep), the same design language (time-of-day palette, gradient tiles, nav
rail, cards) and the same console and app structure, with the family modules
replaced by the agent feeds.

## How it fits together

```
 Grok ─┐                                  ┌──────────────────────┐        ┌─────────────────┐
 stocks agent ─┤   POST /ingest/<feed>     │ Supabase             │ ◀────▶ │ Pi display      │
 Daily Pulse ──┼──────────────────────────▶│ feeds · keys · auth  │        │ (Qt, kiosk)     │
 code agent ───┤   Authorization: mcf_…    │ ingest · assistant   │ ◀────▶ │ iPhone / Mac    │
 your own ─────┘                           │ pair-device · admin  │ ◀────▶ │ Console         │
                                           └──────────────────────┘        └─────────────────┘
```

1. In the console (or the phone app) you make an **agent** and get its key
   once (`mcf_…`).
2. The agent pushes to `https://<project>.supabase.co/functions/v1/ingest/<feed>`
   with that key: `briefs`, `quotes`, `news`, `projects`, `metrics`,
   `dashboards`, `events` or `todos`. [AGENTS.md](docs/AGENTS.md) has every payload;
   `scripts/mcfly_push.py` pushes from a shell.
3. A display pairs to **your account**: it shows a 6-digit code and a QR
   code; sign in on the phone, the Mac or mcfly.bot/pair and enter it. The
   screen reads the feeds as its own device user from then on.
4. The assistant answers questions about what is on the display, in text or
   by voice, with Claude or Grok (your choice, in Settings), and adds to
   your day when asked: an event, a todo or a reminder (which the display
   announces at its time).

## Quick start

### Backend

```bash
cd backend && supabase start           # local stack (Docker + Supabase CLI)
supabase db reset                      # migrations + seed: six agents and sample feeds
supabase functions deploy ingest pair-device admin assistant
supabase secrets set ANTHROPIC_API_KEY=...   # and/or XAI_API_KEY=... for Grok
tests/run.sh                           # SQL tests on a throwaway Postgres
cd supabase/functions && deno test && deno check */index.ts
```

The first account to sign up becomes the admin. Turn sign-ups off in the
Supabase dashboard after that ([ADMIN.md](docs/ADMIN.md)).

### Display (a Linux desktop, a Mac with Homebrew Qt, or the Pi)

```bash
cmake -S display -B build/display -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt   # Mac
cmake --build build/display -j
./build/display/mcfly-display --demo --windowed      # sample data, no backend
ctest --test-dir build/display
```

Useful: `--screen setup|home|briefs|markets|news|projects|boards|calendar|saver|ask`,
`--screenshot out.png` (saves a picture and quits), `--size 800x480`,
`MCFLY_IDLE_SECONDS=30`, `MCFLY_SCREENSAVER=ambient|clock|headlines`,
`QT_SCALE_FACTOR=1.5` (the 10.1" 1920×1200 panel). To connect it, set
`MCFLY_SUPABASE_URL` and `MCFLY_SUPABASE_ANON_KEY` (on the Pi: `/etc/mcfly/display.env`);
the setup screen then shows the pairing code. [PI_SETUP.md](docs/PI_SETUP.md)
installs everything on a Raspberry Pi 5 and starts it on boot.

### Console

```bash
cd admin && npm install
NEXT_PUBLIC_ADMIN_DEMO=1 npm run dev    # sample data, no sign-in
npm run lint && npm run typecheck && npm run build && npm test
```

### Apple app

```bash
cd apple && xcodegen generate && open McFly.xcodeproj
swift test --package-path apple/McFlyKit
```

Put the Supabase URL and anon key in `apple/Config/Local.xcconfig` (see
`apple/README.md`).

### Voice (optional, on the Pi)

`./display/deploy/install-pi.sh --with-voice`, then say the wake word; see
[VOICE.md](docs/VOICE.md).

## Checks, all in one place

```bash
backend/tests/run.sh                                   # SQL: RLS, ingest, admin, productivity, accounts
(cd backend/supabase/functions && deno test && deno check */index.ts)
ctest --test-dir build/display                         # C++/QML unit tests, shell tests for the kiosk
(cd admin && npm run lint && npm run typecheck && npm run build && npm test)
swift test --package-path apple/McFlyKit
pytest voice
```

CI runs the same (`.github/workflows/ci.yml`).
