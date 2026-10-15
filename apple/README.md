# McFly for iPhone and Mac

One SwiftUI app target, built for iOS 17+ (iPhone) and macOS 14+, that shows
the same feeds as the wall display (briefs, quotes, the Daily Pulse report,
projects, metrics, dashboards, calendar events), pairs a display to your
account, and talks to the assistant. The
contract is [docs/PLATFORM_SPEC.md](../docs/PLATFORM_SPEC.md) (§1 tables and
RLS, §1.6 admin RPCs, §2.2 pairing, §2.3 revoke, §2.4 assistant, §4 this app).

```
apple/
├── project.yml            xcodegen: the McFly target (iOS + macOS), supabase-swift, McFlyKit
├── Config/                xcconfig layering: Defaults → Signing → optional Local (secrets, team)
├── McFly/                 the app
│   ├── App/               McFlyApp (scenes, links), AppModel (session, phase, services), Config
│   ├── Theme/             mood palettes and Appearance, GradientTile (+ its Metal shader), glow, cards and pills
│   ├── Views/             one file per screen, Components.swift for shared pieces
│   ├── Voice/             VoiceGlow (from Homestead), listener, speaker, session, VoiceModeView
│   ├── Assets.xcassets    app icon (scripts/render_app_icon.py), launch color
│   └── McFly-*.entitlements   associated domain; the Mac one adds the sandbox
└── McFlyKit/              Swift package: models (Models.swift, Productivity.swift), FeedStore, Home's
                           Timeline and the Mood, assistant SSE client, pairing, admin, demo data,
                           unit tests (`swift test`)
```

## Configure

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set
   `SUPABASE_URL` (written `https:/$()/…`, because `//` starts an xcconfig
   comment) and `SUPABASE_ANON_KEY`. Only the anon/publishable key ever goes
   in: the app reads them from Info.plist at launch (`Config.swift`) and
   refuses placeholders. Add `MCFLY_TEAM_ID` to run on an iPhone or to sign
   the Mac app; `MCFLY_BUNDLE_ID` defaults to `bot.mcfly.app`.
2. In Supabase → Authentication → URL Configuration, add
   `mcfly://auth-callback` to **Redirect URLs**, so "Email me a link" opens
   the app.
3. Apply the migrations and deploy the `pair-device`, `admin` and `assistant`
   functions (the backend README). The first account to sign up is the
   platform admin; the app says so to anyone else.

## Build and run

```bash
cd apple
xcodegen generate                 # writes McFly.xcodeproj from project.yml (xcodegen 2.38+)
open McFly.xcodeproj              # pick "My Mac" or an iPhone simulator, then Run
```

From the command line:

```bash
xcodebuild -project McFly.xcodeproj -scheme McFly -destination 'platform=macOS' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project McFly.xcodeproj -scheme McFly -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build
swift test --package-path McFlyKit   # the kit's unit tests, no Xcode project needed
```

Xcode is the only requirement for the app (Xcode 16 or newer; the voice
screen's `SpeechAnalyzer` path needs the iOS 26 / macOS 26 SDK, so Xcode 26+
to compile that branch; on older SDKs change nothing, the fallback is the
whole story). The icon is rendered by `scripts/render_app_icon.py` (pure
Python) if it ever needs regenerating.

**Demo mode.** Without a Supabase project, run with the launch argument
`-McFlyDemo YES` (scheme → Run → Arguments, or `MCFLY_DEMO=1` in the
environment): the seed's data from `McFlyKit/Sources/McFlyKit/Resources/demo.json`,
an in-memory admin, and a canned assistant, so every screen works and the
voice loop can be tried. The demo's dates move so its newest push is 20
minutes old and its newest Pulse report is today's, so Home always has a day.
`-McFlyMood morning|day|evening|night|dark` (or `MCFLY_MOOD`, as on the
display) pins the palette for screenshots.

## TestFlight

```bash
scripts/release-ios.sh --upload
```

This builds the app for iPhone and iPad, signs it for the App Store and
uploads it; TestFlight has it once Apple has processed it, usually within
minutes. Without `--upload` it stops at `build/ios/McFly.xcarchive`, and
nothing leaves the Mac.

It builds a commit, `origin/main` unless `MCFLY_RELEASE_REF` names another
(a branch, a tag, `HEAD`), in a checkout of its own: never this checkout's
files, which other work in progress may share, so push what should ship
first. Each build says which commit it is. Only `Config/Local.xcconfig`
comes from here. It refuses to make a build without the Supabase project
there (a tester would only see "not connected"), and checks what App Store
Connect would otherwise turn away after the upload: the build number, the
privacy manifest, the associated domain, and a reason in the manifest for
each API Apple asks about that the linked binary uses, packages included.

Before the first upload:

1. `Config/Local.xcconfig` with `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
   `MCFLY_TEAM_ID`, and `mcfly://auth-callback` in Supabase's **Redirect
   URLs** (Configure, above): without it an emailed sign-in link opens the
   console, not the app.
2. At [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list),
   **Identifiers → + → App IDs → App**: bundle ID `bot.mcfly.app` (explicit),
   with **Associated Domains** ticked. (The upload would register it too, but
   App Store Connect lists only bundle IDs that already exist.)
3. In [App Store Connect](https://appstoreconnect.apple.com/apps), **+ → New
   App**: iOS, bundle ID `bot.mcfly.app`, any SKU. The name must be unique on
   the App Store; the home screen still says McFly (`CFBundleDisplayName`).
   Without it the upload ends in "No suitable application records were
   found".
4. Xcode signed in to the developer account (**Settings → Accounts**). The
   upload makes the Apple Distribution certificate and the App Store profile
   itself, and no iPhone need be registered to the team: the archive is
   signed for the App Store at export, never for development. An App Store
   Connect API key works instead; see the script's header.

Each build number is the time it was built, so every upload is newer than the
last. Bump `MARKETING_VERSION` in `project.yml` for a new version. Add yourself
to a group under **TestFlight → Internal Testing**, and builds reach you
through the TestFlight app. Testers outside the team need Beta App Review,
which needs an account for the reviewer to sign in with (a password one: an
emailed link can't be opened at Apple).

`McFly/PrivacyInfo.xcprivacy` gives the reasons for those APIs (file dates,
for supabase-swift's Storage; user defaults, for the Mac app's dark mode) and
what the app sends (the account's email, what is asked of the assistant). A
new use of one needs its reason there, or the upload is refused; the script
says which.

## Screens

| Where | What |
|---|---|
| **Sign in** | Email + password, or **Email me a link** (a magic link that comes back to `mcfly://auth-callback`). After signing in, `is_platform_admin` is checked; a non-admin sees "This account isn't a McFly admin. The first account to sign up becomes the admin." with Sign out. |
| **Home** | The display's Home in its portrait layout: the greeting and a big clock, **Up next** (the event on now, else the next one, on its colour), the first blocked project, **Ask McFly** on the voice glow (tap to type, the mic to talk), the markets in one strip, then **Today**: one stream in time order of today's Pulse reports, briefs, project updates and events (`Timeline` in the kit, the same rules as the display's FeedStore and the web's `lib/today.ts`). Past events fade, the one on now is outlined, the next is marked; each row opens its story, brief, project or event. Pull to refresh; coming back to the app after a minute refreshes too. |
| **Ambient** | The moon on Home: the display's ambient screen saver full screen, for a stand or a nightstand. The moving gradient, the clock, the date, what's next and what follows, and a rail of cards (the latest brief, the markets, a blocked project, today's top story, later events). It drifts a few points a minute, keeps the screen awake, and a tap goes back. |
| **Briefs** | Grouped by day; a reader lays out paragraphs and `- ` bullets. |
| **Markets** | A tile per visible symbol in the console's order, with a sparkline from the history; detail with the note and the history. Below the quotes, a **Metrics** section: a tile per visible metric (`metrics` history + `metric_settings` for label, group, order and hidden), grouped by the console's group, with the same sparklines and a detail with the note and history. |
| **News** | The newest report by section, story cards with thumbnail, headline and takeaway; story detail with the image, takeaway, source domain and Open Link; a calendar menu picks an older report. |
| **Voice** | **Talk to McFly** opens the full-screen voice mode (below); **Ask by typing** is a chat sheet in `chat` mode with streamed replies and a Claude / Grok switch that sends `provider` with the request (it starts from `platform_settings.assistant_provider`; the voice loop leaves the choice to the server). |
| **Projects** | A card per project: name, status pill (blocked, active, paused, done), progress, summary, next step, the last update. Detail: the timeline (the feed's newest five, then everything from `admin_project_updates`) and an Open link. |
| **Dashboards** | A segmented picker across the agents' dashboards; each is a grid of widget cards by type: metric, status, progress, list, text, and chart (a small Path). A type this version doesn't know shows as a placeholder rather than hiding the dashboard. |
| **Calendar** | A month grid with a dot per calendar color, then the agenda: events by day for the weeks ahead (`events` from yesterday to 60 days out). Tap a day to see just that day. Detail: time span, location, description, link. |
| **Displays** | `admin_list_devices`: name, last seen, online when seen within 15 minutes. Rename (`admin_rename_device`), revoke (the `admin` function's `revoke_device`), and **Pair a display**. |
| **Agents** | `admin_list_agents`: name, color, kind, last push, errors. **New agent** shows the key once with Copy and Share; rotate (`admin_rotate_agent_key`, also un-revokes), revoke, delete. |
| **Projects** | `projects` with their `project_updates` embedded: a card per project with status, progress, summary, next step and the last update; detail with the update timeline (`admin_project_updates` for more of it). |
| **Dashboards** | `dashboards`, one at a time with a chip row to switch: the `widgets` array rendered by type: metric, status, progress, list, text, chart. An unknown type shows as a placeholder rather than hiding the dashboard. |
| **Calendar** | `events` from yesterday to two months out: a day list (agenda), and a week view. All-day and multi-day events sit on every day they span. |
| **Settings** | Account email and Sign out, display name and timezone, **Answers from** (Claude or Grok, `assistant_provider`), all through `admin_get_settings` / `admin_update_settings`; app version, which speech engine this system uses. |

On the iPhone, Home, Briefs, Markets and News are tabs, the display's first
four, and the rest (Projects, Dashboards, Calendar, Voice, Displays, Agents,
Settings) sit behind **More**: five in all, as many as an iPhone's tab bar
shows. Voice is also Home's Ask bar. On the Mac they're a sidebar.

## Look

The display's design language (`display/qml/Theme.qml`), in `McFly/Theme`:

- **Time-of-day palettes.** Morning (warm peach, coral accent), day (clear,
  blue), evening (violet) and night (dim, dark) by the display's hours
  (`Mood` in the kit: night 9:30 pm to 6:30 am, then morning until 11, day
  until 5 pm). Every colour in the app comes from `Theme`, so all of it moves
  together, easing over when the mood changes. With the system in dark mode
  it's the display's warm near-black palette instead (its Settings → Dark
  mode). A night palette is dark even when the system is light, so the app
  sets its own colour scheme and reads the system's from the screen.
- **GradientTile** is the display's shader (`display/shaders/gradienttile.frag`)
  as a SwiftUI colour effect (`GradientTile.metal`): the pastel mesh
  gradient, the frosted-glass rings blurred into it and the static film
  grain, in one pass, with the palette worked out from a base colour or the
  glow colours as the QML does. It only moves while on screen, with the app
  in front and Reduce Motion off.

The assistant request carries `provider: "claude" | "grok"` when the person
has picked one (Settings → Answers from); the function otherwise uses
`platform_settings.assistant_provider`.

## Pairing: code, QR, universal link

A display shows a 6-digit code (and a QR code) until it's paired. The app
claims it with `pair-device` `{ action: "claim", code, name }` and the
admin's JWT; the display's `redeem` poll then gets its session.

Three ways in:

- **Type the code** on Displays → + → Pair a display.
- **Scan the QR code** (iPhone): VisionKit's `DataScannerViewController` when
  the device supports it, else an `AVCaptureSession` with a QR metadata
  output. The payload may be the bare digits or a pairing link.
- **Open a link**: `https://mcfly.bot/pair?code=123456` (a universal link) or
  `mcfly://pair?code=123456` opens the app on Displays with the sheet filled
  in. The universal link needs `mcfly.bot` to serve
  `/.well-known/apple-app-site-association` with the app's
  `<team id>.bot.mcfly.app` under `applinks` (that file lives with the
  console, in `admin/`); until then the `mcfly://` scheme works and the QR
  code's https link still opens Safari.

## Voice

Adapted from Homestead's voice mode. The glow is `VoiceGlow.swift` as is
(the colour-spectrum lobes and band), driven by the microphone while
listening and by the speaker's word pulses while talking; only its lock
changed, from `Synchronization.Mutex` (iOS 18+) to `OSAllocatedUnfairLock`,
because this app runs on iOS 17.

| Step | iOS 26 / macOS 26 | iOS 17–25 / macOS 14–25 |
|---|---|---|
| Speech → text | `SpeechAnalyzer` + `SpeechTranscriber`, on device; the model is downloaded once by the system if missing | `SFSpeechRecognizer`, `requiresOnDeviceRecognition` where the device supports it (the status chip's lock means on device) |
| Answer | `assistant`, `quick` mode, streamed over SSE with the last 10 turns as `history` | same |
| Text → speech | `AVSpeechSynthesizer` with the best installed voice for the language (premium → enhanced → default) | same |

The loop is hands-free by default: a 1.3 s pause ends the question, the
answer is spoken sentence by sentence as it streams (`SpokenText` cuts it),
and listening starts again when speech ends. "Tap to talk" turns the loop
off. The mic button ends a question early or interrupts an answer; Space
does the same on the Mac, Escape closes. The screen stays awake while the
mode is open.

## Kit tests

`swift test --package-path McFlyKit` covers the pure parts: the SSE parser
and the assistant's event decoding, model decoding from the demo file that
mirrors `seed.sql` (feeds, projects with their updates, metrics, dashboards
and the widget enum, events, settings with and without the newer columns),
quote and metric grouping and ordering, pairing-code validation and link
parsing, brief text blocks, sentence splitting for speech, formatting, the
feed store's refresh and derived values, the demo admin service, and Home's
timeline: the web's cases from `admin/tests/today.test.mjs` (today's rows
only, all-day first; an overnight report opening the day; past, now and
next; up next; the labels), the mood's hours, and the demo's report dates.
