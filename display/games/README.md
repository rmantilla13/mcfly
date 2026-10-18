# Games

Open-source code behind the display's Games tab
(`qml/screens/GamesScreen.qml`). Each directory keeps its license next to the
code. Everything runs inside the display app; nothing is downloaded at run
time. The games, the board QML and `tests/tst_games.cpp` came over from the
homeOS wall display's Games tab, as they were but for the changes below.

| Game | Directory | Source | License |
|------|-----------|--------|---------|
| Same Game | `samegame/` | Qt demo [`examples/demos/samegame`](https://github.com/qt/qtdoc/tree/6.4/examples/demos/samegame), qtdoc 6.4 branch at `eb33fc97` | BSD-3-Clause |
| Maroon in Trouble | `maroon/` | Qt demo [`examples/demos/maroon`](https://github.com/qt/qtdoc/tree/6.4/examples/demos/maroon), qtdoc 6.4 branch at `eb33fc97` | BSD-3-Clause |
| 2048 | `2048/` | Gabriele Cirulli's [2048](https://github.com/gabrielecirulli/2048) at `478b6ec3` | MIT |
| Traffic Jam | `traffic/` | Michael Fogleman's [rush](https://github.com/fogleman/rush) (Rush Hour) at `3e3b8396` | MIT |

## What we changed

- **Same Game, Maroon in Trouble**: the 6.4 versions, because they load from
  resources with relative imports (homeOS ran them on Qt 6.4 and 6.8; here
  they are tested on 6.12).
  Same Game's Quit button now goes back to the list of games
  (`quitRequested()`) instead of quitting the app. Three fixes come from the
  6.8 versions: Maroon uses QtMultimedia's `SoundEffect` directly (the 6.4
  wrapper, `content/SoundEffect.qml`, looked for the sounds in the wrong
  directory under Qt 6, so they never played), and two signal handlers name
  their `mouse` and `event` parameters. Images and sounds are unchanged.
- **2048**: `game.js` is `tile.js`, `grid.js` and `game_manager.js` joined
  into one file, otherwise unchanged. The board, swipes and storage that
  replace the web page are ours, in `qml/games/Game2048.qml`, with the
  original colors and animations.
- **Traffic Jam**: `rush.js` is the `Piece`, `Move` and `Board` code from
  `web/app.js`, unchanged. The levels in `puzzles.js` are our own, made by
  `make-puzzles.py` (seeded, so it prints the same levels each run) and
  checked against `rush.js` by `tests/tst_games.cpp`. The board is
  `qml/games/TrafficJam.qml`.

Tic-tac-toe (`qml/games/TicTacToe.qml`) and Four in a Row
(`qml/games/FourInARow.qml`) are written for this app.

For McFly: the names (vs McFly, the LocalStorage databases), the primary
button in glass, and a second shape for Traffic Jam, tic-tac-toe and 2048:
on a stage much wider than tall (the 7" panel) the board sits on the left
with its controls beside it. Same Game and Maroon are unchanged.

Scoop Shop (`qml/games/ScoopShop.qml`, drawn by `ScoopTreat.qml`,
`ScoopCrew.qml`, `ScoopStock.qml` and `ScoopAwning.qml`, its rules in
`scoops.js`) is written for this app too, and so is everything in it: Pip the
penguin, Lotl the axolotl, the customers, the parlour and the ice cream are
QML shapes, not artwork from anywhere else.

Penguin March (`qml/games/PenguinMarch.qml`, with its rules, levels and
drawing in `src/games/`) is written for this app too: an original game in
the genre of Lemmings and Pingus, sharing no code, pictures, sounds, levels
or names with either. `tests/tst_penguins.cpp` replays a recorded solution
for every level to prove it can be won.

Color by Number (`qml/games/ColorByNumber.qml`, with its pictures, progress
and board in `src/games/ColorByNumber.cpp`) is written for this app too,
after Araib Karim's [Color by Number for iOS](https://github.com/AraibKarim/ColorByNumber-iOS).
That project has no licence, so none of its code, pictures or fonts is used:
the twelve pixel pictures are our own. `tests/tst_colors.cpp` checks every
picture.

The iPhone and Mac app has all of these but Same Game and Maroon, written
again in Swift (`apple/McFlyKit/Sources/McFlyKit/Games` for the rules,
`apple/McFly/Games` for the screens), with the same rules, levels and
credits. 2048's and Rush Hour's Swift carry their MIT notices at the top of
the file, and the app shows them under how to play. `apple/McFlyKit/Tests`
hold the Swift to the display: Four in a Row's search against
`FourInARowEngine`'s node counts, Scoop Shop's orders against `scoops.js`,
Penguin March's terrain and solution replays, cell for cell and tick for
tick, against `PenguinSim`, and Color by Number's pictures, zoom, pan and
sweeps against `ColorByNumber.cpp`. Scoop Shop's parlour (the awning, the
ticket rail, the freezer case and shelves, the prep bench) is drawn again in
SwiftUI from the same shapes and colours.

## Saved scores

Same Game, 2048, Traffic Jam, Scoop Shop and Penguin March keep high scores,
the 2048 game in progress, Traffic Jam and Penguin March progress, Scoop
Shop's last shopkeeper and every Color by Number picture as far as it's
painted in Qt's LocalStorage (SQLite), under
`~/.local/share/McFly/display/QML/OfflineStorage` on the Pi
(`~/Library/Application Support/McFly/display/...` on a Mac). This needs the
`qml6-module-qtquick-localstorage` and `libqt6sql6-sqlite` packages;
Same Game and Maroon also need `qml6-module-qtquick-particles`, and Maroon's
sounds `qml6-module-qtmultimedia`. `install-pi.sh` and CI install all four.

## Adding a game

Add an entry to `catalog` in `GamesScreen.qml`, with a card picture. Our own
QML goes in `qml/games/` and the module's `QML_FILES`; a third-party game kept
as-is goes in a directory here and into the resources glob in
`display/CMakeLists.txt`. Add it to `tests/tst_games.cpp` too. A game is
loaded only while it is open, so it doesn't need to pause or clean up when
it is hidden.

Work too heavy for QML's JavaScript, which runs on the thread that draws
the screen, goes in a C++ helper under `src/games/`, registered in
`McFly.Core` by `main.cpp` and by `tst_games` (Four in a Row's
`FourInARowEngine`: its search took seconds a move in JavaScript, and takes
milliseconds in C++, capped so even a tangled board stays quick on the Pi).
