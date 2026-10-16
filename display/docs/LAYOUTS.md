# Display layouts: one grammar, every panel

The McFly display runs on four kinds of panel. They are four settings of one
design, not four designs: the same homeOS language (left nav rail with the
gliding pill, white cards on the warm time-of-day canvas, GradientTile
highlights, cross-fading pages, 64 px targets, no hover) bent, never broken,
to the room it has. `layout-manifest.json` is the same spec as data.

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

A rail needs about 720 px of height for seven items and three buttons at
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
"bar"` lays the same items out along the bottom: icon-only 64 px slots, the
active slot widening to fit its label (the pill animates `x` and `width`),
a divider, then the three round buttons in 64 px slots. The slots abut; the
pill is inset 4 px. At 720 wide the bar is about 704 px of slots, centred.

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
| Home | [greeting, clock 112, date; up next; blocked; quick questions, 2 rows; ask 88] ≤ 520 · [markets strip 5; TODAY; the day list, kept at now, resting on a whole row; under its last row, TOMORROW and its events as a preview]. Nothing up next or blocked: the clock grows to 176 and sits mid-column | same, clock 88 (144), 4 tickers | same, clock 64 (104), 3 tickers, no questions or ask bar | feed: clock, up next, blocked, ask, markets 4, every row of the day, then TOMORROW |
| Briefs | list 520 \| reader | list 440 \| reader | one-line rows → push reader | rows → push reader |
| Markets | grid 3 \| pane 440 | grid 2 \| pane 380 | grid 3 × 112 → push | grid 2 × 150 → push |
| Metrics | grid 4 | grid 3 | grid 2 | grid 2 |
| News | hero 360; cards 4 × 280 | hero 300; cards 3 × 250 | lead row (no picture); rows 2 × 88 → story without a picture | hero 240; cards 2 × 290 → picture on top |
| Projects | board 3 \| pane 460 | board 2 \| pane 400 | board 2 × 124 → push | board 2 × 170 → push |
| Boards | grid 6 | grid 4 | grid 2, chips scroll | grid 2 |
| Calendar | 14 days \| agenda \| day tile 420: the day's hours with its events, then its calendars | 10 days \| agenda \| tile 360, same | 7 days; agenda | 7 days; tile 230 (two rows); agenda |
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
| Thu, Oct 15 · 2 min     |  9:30 [Standup      ] dim|
| [UP NEXT · IN 18 MIN  ] |  9:31 [GROK · Hourly…  ]|
| [Pulse review 3:30    ] |  3:30 [Pulse review  in]|
| [! Onyx is blocked    ] |  7:00 [Dinner with Lina]|
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
| -- Up next (accent) -------------+ |
| -- Onyx is blocked --------------+ |
| -- Ask 84 -----------------------+ |
| -- Markets strip (4) ------------+ |
| TODAY ──────────────── 11 things   |
|  7:55 [Daily Pulse · hero …    ]   |
|  9:30 [Standup                 ]   |
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
|  9:41 AM          (moving gradient, 10 fps)      |
|  Thursday, October 15                            |
|  Pulse review with the team at 3:30 pm           |
|  Then Dinner with Lina at 7:00 pm                |
|                                                  |
| [Brief   ] [Markets ] [Needs you] [Daily Pulse]  |
+--------------------------------------------------+
```

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
