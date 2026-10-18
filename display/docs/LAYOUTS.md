# Display layouts: one grammar, every panel

The McFly display runs on four kinds of panel. They are four settings of one
design, not four designs: the same homeOS language (left nav rail with the
gliding glass pill, white cards on the warm time-of-day canvas, GradientTile
highlights, glass controls, cross-fading pages, 64 px targets, no hover) bent,
never broken, to the room it has. `layout-manifest.json` is the same spec as data.

Two axes come out of one measurement of the window, in `Main.qml`:

- **Tier** (the frame): where the nav goes, how many columns the page has,
  whether a detail is a pane beside its list or a page pushed over it.
  Decided by orientation and width.
- **Scale** (the size): type, radius, padding. Decided by the shorter side of
  the window, because that is what limits how big type can be.

```
tier  = portrait ? tall : width < 1000 ? mini : width < 1600 ? compact : wide
scale = shortSide < 600 ? s : m     (l is reserved; today m is used above 600)
```

`Theme.compact` stays (`tier !== "wide"`), so every existing
`Theme.compact ? a : b` binding keeps its meaning at Compact, Mini and Tall.

## Tiers

| | Wide | Compact | Mini | Tall |
|---|---|---|---|---|
| Rule | landscape, width ≥ 1600 | landscape, 1000 ≤ width < 1600 | landscape, width < 1000 | portrait (height > width) |
| Panels | 1920×1080 TV or monitor; 4K at scale 2; the 10.1" at scale 1 | the 10.1" 1920×1200 at `QT_SCALE_FACTOR=1.5` → 1280×800 (primary) | the 7" Touch Display, 800×480 | the Touch Display 2, 720×1280 |
| Scale | m | m | s | m (s below 600 wide) |
| Nav | rail 124 wide, icon + label | rail 100 wide, icon + label | bottom bar 76 tall, icon only, the active slot shows its label | bottom bar 84 tall, same |
| Page margin / gutter | 40 / 24 | 24 / 16 | 16 / 12 | 20 / 16 |
| Page area | 1716×1000 | 1132×752 | 768×388 | 680×1156 |
| Detail (`Theme.paned`) | pane beside the list | pane beside the list | pushed page with a back arrow | pushed page |
| List / pane width | 520 / 440 | 440 / 380 | — | — |
| Pictures on pages | yes | yes | no (tinted initials) | yes |
| Home | fills the screen; only the day list scrolls | same | same, by dropping the ask bar | a feed that scrolls |

A rail needs about 770 px of height for eight items and three buttons at
64 px targets; that, not taste, is why Mini (480 tall) gets the bar. Tall
gets it because a rail would eat a fifth of a 720 px width.

## Scale

| token | s | m |
|---|---|---|
| fontXs / Sm / Md / Lg / Xl | 14 / 16 / 20 / 26 / 36 | 15 / 18 / 23 / 30 / 44 |
| fontHuge (saver clocks) | 64 | 88 (Compact) / 112 (Wide) |
| radius / radiusSm | 24 / 16 | 28 / 18 |
| touchTarget | 64 | 64 |

The touch target never drops. That one constant is why Mini shows fewer
things rather than smaller things: its regions *drop* and *push* instead of
shrinking below the target.

## Collapse rules, in the order every region follows

1. **Shrink**: fewer rows (tickers 6 → 4 → 3), shorter fixed heights
   (story cards 280 → 250 → 230), fewer `maximumLineCount`.
2. **Stack**: at Tall a band's regions go top-to-bottom in their
   left-to-right order inside one `FocusFlickable`.
3. **Push**: at Mini and Tall a side pane (reader, symbol detail, project
   detail, the day) becomes a page pushed over its list with `‹` in the
   header. `MasterDetail.qml` does this for every screen.
4. **Drop**: at Mini only, a region leaves, and the rule says where its
   content still is (the bar's sparkle instead of Home's ask bar; headlines
   instead of a hero picture).

## Navigation

Order everywhere: Home · Briefs · Markets · News · Projects · Boards ·
Calendar, then Ask (sparkle), Settings (gear) and Sleep (moon).

`NavRail.qml` has one model and two shapes. `horizontal: Theme.navMode ===
"bar"` lays the same items out along the bottom: icon-only slots (`barSlot`,
64 px where eight fit), the active slot widening to fit its label (the pill
animates `x` and `width`), a divider, then the three round buttons in 64 px
slots. The slots abut; the pill is inset 4 px. At 720 wide the item slots
narrow to 50 px and the bar is about 700 px, centred; at 800 they are 60.
In the rail the three buttons are discs smaller than a target (44 at
Compact, 52 at Wide), each centred in a 64 px slot it takes taps across
(`IconButton.hitMargin`), so they sit apart and the rail fits 800 px.

The controls are glass (`Lens.qml`, drawn by `shaders/lens.frag`; what they
share is `Glass.qml`). The rail shows the aura (the glow's colour fields,
fixed to the window) faintly and still, cached as a quarter-size layer; the
pill is clear glass that gathers more of it, so it bends a different part as
it glides. Everything chosen is the same "active" glass under `Glass.ink`:
the segment thumb, the chosen chip, Ask, the day picked on Calendar, the
project or holding open beside its detail, the screen saver picked in
Settings; the picked brief gets a clear slab of it laid over its row. A
PillButton left as it is is the primary action in `Glass.primary`;
everything else is its own fill, lit like glass. Without shaders each is a
plain rounded rect, the active ones in `Theme.accentSoft`.

`ScreenHeader.qml` is every screen's first row: title, subtitle, an optional
back arrow while a detail is pushed, and a control slot. At Mini and Tall the
controls wrap to a second row so titles never truncate.

## Layers

Unchanged from `Main.qml`, bottom to top: the nav and the pages (rail: side
by side; bar: pages above the bar), `AssistantPanel` over the pages (right
of the rail, or above the bar), Controls popups in the overlay, then the
Layers: keyboard (2), toast (3), screen saver (4), QuickAnswer (5), sleep
cover (6). At bar tiers the toast and QuickAnswer sit above the bar and the
offline pill moves to the top centre so it never covers a header's controls.

## Screens

| screen | Wide | Compact | Mini | Tall |
|---|---|---|---|---|
| Home | [greeting, clock 112, date; what stands out (one line, turning); up next on a gradient tile, a ring counting down its last hour, a bar while it's on; blocked; quick questions, 2 rows; ask 88] ≤ 520 · [the ticker tape, every symbol, each with its line; TODAY; the day list, kept at now, resting on a whole row, a thread down its gutter with now on it; under its last row, TOMORROW and its events as a preview]. Nothing up next or blocked: the clock grows to 176 and sits mid-column | same, clock 88 (144), tape without lines | same, clock 64 (104), what stands out 58, no questions or ask bar | feed: clock, what stands out, up next, blocked, ask, tape, every row of the day on the thread, then TOMORROW |
| Briefs | list 520 \| reader: the body in order, its points on dots (`blocks`) | list 440 \| reader, same | one-line rows → push reader | rows → push reader |
| Markets | breadth bar; grid 3 (line, price, low–high bar) \| pane 440 | breadth bar; grid 2, same \| pane 380 | breadth in the subtitle; grid 3 × 112, no low–high bar → push | breadth bar; grid 2 × 150, then the biggest mover large in the room under it (from 300 px) → push |
| Metrics | grid 4, coloured by good, "usually …" | grid 3, same | grid 2, no "usually" | grid 2 |
| News | hero 360, its picture drifting (Ken Burns); cards 4 × 280 | hero 300, same; cards 3 × 250 | lead row (no picture); rows 2 × 88 → story without a picture | hero 240, same; cards 2 × 290 → picture on top |
| Projects | board 3, a progress ring per card \| pane 460: tile with a ring 132, then next and the updates as a thread | board 2 \| pane 400, ring 108 | board 2 × 124, ring 50 → push, ring 84 | board 2 × 170, one line of summary → push |
| Boards | bento of 6: first metric a 2×2 hero tile, statuses in a row one health strip (up to 6 a row, then it wraps a row taller), charts 4×2, progress a ring | bento of 4, same (4 a row) | bento of 2: no hero, charts 2×2, 3 statuses a row; chips scroll | bento of 2, same |
| Calendar | 14 days \| agenda \| day tile 420: the day's hours with its events, now gliding down them, then its calendars | 10 days \| agenda \| tile 360, same | 7 days; agenda | 7 days; tile 230 (two rows); agenda |
| Games | cards 3 a row × 380, scrolling \| open: full screen, over the rail: the game as large as fits (Same Game and Maroon scaled from 320 × 480), X and (i) down the right, how to play over the game | cards 3 × 280, same | cards 3 × 128, no taglines \| open: full screen, over the bar; the name, (i) and X along the top (the games keep the full width); the board left, its controls beside it | cards 2 × 300 \| open: full screen, over the bar; the name, (i) and X along the top, the game under them |
| Assistant | as today | as today | subtitle dropped; bubbles 85 % | bubbles 85 % |
| QuickAnswer | 880 wide | 760 | page − 32, orb 120×88, 4 lines | 680, 6 lines |
| Setup | card ≤ 1240, 2 columns | ≤ 1120, 2 columns | page − 32, 2 columns, digits 56×76, QR 120 | page − 40, 1 column, scrolls |
| Settings | 1100, 2 columns: this screen \| about and your account | 1100, 2 columns, same | page − 16, 1 column | page − 32, 1 column |
| Ambient saver | clock 200, rail of 4 cards 260 | clock 168, 3 cards 220 | clock 104, 2 cards 150, no "then" line | clock 150, cards 2 × 2 at 220 |
| Clock saver | clock 0.2 w, 5 symbols | same | 3 symbols | symbols wrap |
| Headlines saver | headline 64 | 54 | 36, clock 56 | 44 |

### Home at Mini (768 × 388, the day list scrolls)

```
+--------------------------------------------------+
| (M) Good morning   DEMO | SPY +0.3  AAPL +1.1 …   |
| 9:41 AM                 | TODAY ───────── 11 things|
| Thu, Oct 15 · 2 min     |  9:30 │[Standup     ] dim|
| [⚡ Search is down     ⋮]|  9:31 │[GROK · Hourly… ]|
| [UP NEXT · IN 18 MIN (18)]|       ● now          |
| [Pulse review 3:30    ] |  3:30 │[Pulse review in]|
| [! Onyx is blocked    ] |  7:00 │[Dinner with Lina]|
+--------------------------------------------------+
|[Home ⌂][≡][↗][▤][◫][▦][▣]  ·  [*][⚙][☾]        |
+--------------------------------------------------+
```

### Home at Tall (680 × 1156, a feed)

```
+------------------------------------+
| (M) Good morning             DEMO  |
| 9:41 AM                            |
| Thursday, October 15 · 2 min ago   |
| -- What stands out (turns) ---- ⋮ + |
| -- Up next (gradient tile, ring) + |
| -- Onyx is blocked --------------+ |
| -- Ask 84 -----------------------+ |
| -- Ticker tape ------------------+ |
| TODAY ──────────────── 11 things   |
|  7:55 │[Daily Pulse · hero …    ]  |
|       ● now                        |
|  9:30 │[Standup                 ]  |
|  …                                 |
| TOMORROW ───── Friday · 2 things   |
| 11:00 [Investor call           ]   |
+------------------------------------+
|[Home ⌂][≡][↗][▤][◫][▦][▣] · [*][⚙][☾]|
+------------------------------------+
```

### Ambient saver (any size)

```
+--------------------------------------------------+
|  9:41 AM          (moving gradient, 30 fps)      |
|  Thursday, October 15                            |
|  Pulse review with the team at 3:30 pm           |
|  Then Dinner with Lina at 7:00 pm                |
|                                                  |
| [Brief   ] [Markets ] [Needs you] [Daily Pulse]  |
+--------------------------------------------------+
```

## Motion

One grammar for movement, the same on every panel (`Theme.qml` tokens):

- **Arriving.** A screen's contents settle in each time it is picked
  (`Reveal.qml`, `Theme.revealDuration`, 600 ms; the screen's `isCurrent`,
  so closing the assistant panel over it plays nothing): each region or row fades
  up 14 px over `Theme.enter`, a beat after the one before, the seventh and
  later together, so everything is in place well inside a second. Rows a
  sync makes again (every minute) bind to the same value and are simply
  there: nothing arrives from a delegate's `onCompleted`. Rings sweep in and
  lines draw on (a clip) with it.
- **Moving.** Things that change place glide (`Theme.glide`, 480 ms,
  `Theme.standard`): a board's tiles when the board or the tier changes, the
  "now" dot on Home's thread, the Briefs outline on a tap, the calendar's now
  line on each minute (twice as long). A value this display saw change in
  the last 3 s (`changedMs`) slides in from the way it moved.
- **Breathing.** The only loops: a status that needs a look, a blocked
  project's edge and the now dot breathe (`Theme.breath`, 2.2 s each way); a
  price pushed in the last 15 min sends a ring out from its newest point; the
  News hero's picture drifts over most of a minute; the Ask button turns a
  ring while an answer is on its way and the panel is shut. Nothing blinks.
- **Gating.** Loops run only while their screen is shown and the screen is
  not idle (and News' hero and a blocked card's edge only while on screen),
  and everything (arrivals included) is off with Settings → Animated tiles.
  Every slow loop (a status's breath, the now dot, a blocked project's edge,
  News' hero, Setup's drift and its dots waiting for a code) keeps the
  ambient clock (`MotionClock`, `Theme.motionFps`): an Animator steps on
  every frame the panel draws, 60 a second for a drift of a pixel a second,
  so a screen nobody is touching would never let the render loop sleep.
  Animators (opacity, scale, rotation) are for motion that ends (arrivals,
  glides, a fresh price's three rings) and for what moves only while an
  answer is on its way (the Ask ring, the typing dots); never `Layout.*` or
  a font size. Home's ticker tape is not ambient: it
  glides every frame the panel draws, as a swipe does, and with Animated
  tiles off too, since it is how the symbols past the strip get shown at
  all. A stopped loop leaves nothing half-way: its halo is hidden, not
  frozen.
- **Software.** Without a GPU (the fallback, and the offscreen pictures in
  `screenshots.sh`) there are no arrivals or sweeps: the pages are simply
  there. Qt's software renderer also draws a Shape (a ring, a line) past a
  scrolling view's clip, so a tile cut by the bottom edge can show its ring
  over the nav bar in those pictures; the GPU clips it.

## Common behaviour

- **Empty**: `EmptyState`, centred in the region: an icon, a line, where the
  feed comes from and a code to scan for the mcfly.bot page that sets it up
  (`/bots`, `/agents`, `/calendars`, `/memory`). A new account sees these
  everywhere, so they say what to do; Home's empty day has all three codes.
- **Offline**: nothing blanks; the last rows stay and the pill shows.
- **Overflow**: lists scroll; grids sit in a `FocusFlickable`; text elides
  with `maximumLineCount`; only a `ChipRow` scrolls sideways.
- **Idle**: `Device.idle` closes every pushed detail, the sheet, the keyboard
  and the assistant, then goes Home, so a device never wakes into a stale
  page.

## Checking it

```bash
display/scripts/screenshots.sh build/shots --no-build
```

shoots every screen at 1280×800, 1920×1080, 800×480 and 720×1280 from the
demo data. The review criteria are the collapse rules above: nothing cut
off, no target under 64 px, no sideways scrolling but chips.
