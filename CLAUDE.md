# Working in this repo

McFly is one person's agent display: `backend/` (Supabase), `display/` (the
Pi kiosk, Qt 6), `apple/` (iPhone and Mac, SwiftUI), `admin/` (the console,
Next.js + shadcn/ui), `voice/` (the Pi's voice service, Python). Read
`README.md` first, then `docs/PLATFORM_SPEC.md`: it is the contract between
the parts, and when code and the spec disagree one of them is wrong.

## Conventions that are load-bearing

**Migrations are added, never edited in place.** `backend/supabase/migrations`
is applied in order by the CLI and by `backend/tests/run.sh`; a shipped
migration is history. New columns go in a new file, backward-compatible.
Supabase-only migrations (realtime publication) are listed in `run.sh`'s
`supabase_only` and get a stub on plain Postgres.

**Every write to a feed goes through an `ingest_*` SQL function**, called by
the `ingest` edge function with the service role after it matched the
agent's key. The SQL functions check the payload again (the last line); the
TypeScript parser (`ingest/parse.ts`) says what was wrong in a sentence. Add
a feed by adding a table + policy, an `ingest_<feed>` function, its parser
and tests on both sides, the display's `FeedStore`, the console tab and the
app's model, and a section in `docs/AGENTS.md`.

**Secrets never reach a client.** Agent keys live only as SHA-256 hashes in
`agent_keys` (RLS on, no policies); the key itself is returned once by
`admin_create_agent` / `admin_rotate_agent_key` and never logged. The service
role key exists only inside edge functions. The console and the apps sign
in as the person and let the database check `is_platform_admin()`.

**Displays read, never write** (except their own `last_seen_at`). RLS lets
`can_read()` callers (a paired device or an admin) select every feed table;
nothing else sees a row. A new table needs `enable row level security` and a
`for select using (public.can_read())` policy or it is invisible.

**The first account to sign up is the admin** (`handle_new_user`). Tests
insert the admin user first for that reason.

**Keep the display's data shaping in C++.** `FeedStore::rebuild()` turns rows
into display-ready maps (labels, colors, sparkline points); QML binds to
them and does no formatting. A QML `TypeError … of undefined` means a
property is missing from the store, not a QML bug.

**Design language is the Ohana one.** `Theme.qml` tokens, `GradientTile` for
highlight tiles, `SpectrumGlow` for voice, cards on `Theme.surface`, the nav
rail, and glass controls: `Lens` (with `Glass.qml`) under buttons, chips and
the chosen state, `Glass.ink` on an active one. Hit targets 64 px, type
readable from across the room. Dark mode and the time-of-day palette come
from the same tokens.

**The kiosk's boot and tty rules are tested** (`display/tests/kiosk_boot_test.sh`,
`bootscreen_test.sh`): the unit files, `install-pi.sh` and the boot video
helper are checked line by line. Change them together with the tests.

## Checks

```bash
PG_BIN=/opt/homebrew/opt/postgresql@17/bin backend/tests/run.sh   # SQL (any Postgres ≥ 16)
(cd backend/supabase/functions && deno test && deno check */index.ts)
cmake -S display -B build/display -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt && cmake --build build/display -j && ctest --test-dir build/display
(cd admin && npm run lint && npm run typecheck && npm run build && npm test)
swift test --package-path apple/McFlyKit
pytest voice
```

On a Mac: Postgres 17 needs `LC_ALL` set (run.sh does), Qt comes from
Homebrew (`brew install qt cmake`), one dialog test wants the Inter font
(`brew install --cask font-inter`), and the boot-screen shell test only runs on
Linux (GNU ps). `--screen <name> --screenshot out.png` on the display binary
with `QT_QPA_PLATFORM=offscreen` gives a picture of any screen without a
display.

## Things to leave alone unless asked

- The `mcfly://` scheme and the `applinks:mcfly.bot` association in `apple/`
  and the `/pair` route in `admin/`: the display's QR code points at
  `https://mcfly.bot/pair?code=…`, and all three must agree.
- `display/third_party/qrcodegen` is Project Nayuki's library (MIT), vendored
  as is.
- `admin/components/reactbits/` and `display/shaders/aurora.frag` are ported
  from React Bits (MIT + Commons Clause), not McFly's own BSD code. Using them
  in McFly is allowed; selling or redistributing the components themselves,
  ported or not, is not. Keep the licence header at the top of each file, and
  give anything else taken from React Bits the same header.
- The voice service's WebSocket protocol (`voice/mcfly_voice/protocol.py`
  and `display/src/voice/VoiceClient.cpp`) changes on both sides at once.
