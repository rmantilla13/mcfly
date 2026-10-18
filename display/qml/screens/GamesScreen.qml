import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Games: a card per game; tapping one runs it full screen, over the nav
// too, with an X to close it and how to play and where it comes from behind
// the info button. 2048, Same Game and Maroon in
// Trouble are open-source games; Traffic Jam plays on open-source Rush Hour
// logic with levels made for McFly; tic-tac-toe and four in a row are our
// own. All of these but four in a row are the homeOS wall display's Games
// tab, brought over as they were.
//
// A game is loaded only while it's open, and closed when the tab is left,
// tapped again, or the screen saver comes up (it takes the display back to
// Home). Nothing keeps ticking, animating or making sounds behind the other
// pages. Third-party code and licences: display/games/README.md.
//
// Scoop Shop and Penguin March, ours too, run against the clock: a game
// with a pause() function is paused while how to play or the assistant
// panel covers it.
Item {
    id: games
    property bool shown: true
    // The page picked, under the assistant panel too. A game stays open
    // while the panel is over it, and closes when the page is left.
    property bool isCurrent: true
    property int openIndex: -1
    readonly property var openGame: openIndex >= 0 ? catalog[openIndex] : null
    // The running game's root item, or null.
    readonly property Item game: loader.item
    // How to play, over the open game.
    property bool howToOpen: false
    // A card's height: two rows and a part of the next on every panel.
    readonly property int cardHeight: Theme.wide ? 380 : Theme.tall ? 300 : Theme.mini ? 128 : 280

    // `source` is the game's QML; `size` is a fixed-size game's own size,
    // scaled up to fit the stage (the rest fill it); `art` is the card picture.
    readonly property var catalog: [
        {
            title: qsTr("Traffic Jam"),
            tagline: qsTr("Slide the cars to get the red one out."),
            howTo: qsTr("Drag the cars and trucks along their lanes. Cars only go forward and back. Clear a path so the red car can drive out of the exit on the right. 40 levels, from beginner to expert."),
            players: qsTr("1 player"),
            credit: qsTr("Rush Hour board logic by Michael Fogleman (MIT License). Levels made for McFly."),
            source: "../games/TrafficJam.qml",
            art: artTraffic
        },
        {
            title: qsTr("Tic-tac-toe"),
            tagline: qsTr("Three in a row wins."),
            howTo: qsTr("Take turns tapping a square. The first to get three in a row, across, down or corner to corner, wins. Play someone at the screen, or play McFly: Easy is beatable, Hard never loses."),
            players: qsTr("1–2 players"),
            credit: qsTr("Made for McFly."),
            source: "../games/TicTacToe.qml",
            art: artTicTacToe
        },
        {
            title: qsTr("Four in a Row"),
            tagline: qsTr("Drop the discs, line up four."),
            howTo: qsTr("Take turns tapping a column to drop a disc into it. The first to line up four, across, down or corner to corner, wins. Play someone at the screen, or play McFly: Easy is beatable, Hard looks several moves ahead."),
            players: qsTr("1–2 players"),
            credit: qsTr("Made for McFly."),
            source: "../games/FourInARow.qml",
            art: artFourInARow
        },
        {
            title: "2048",
            tagline: qsTr("Slide and join the tiles to reach 2048."),
            howTo: qsTr("Swipe up, down, left or right to slide every tile. Two tiles with the same number join into one. Make a 2048 tile to win, then keep going."),
            players: qsTr("1 player"),
            credit: qsTr("2048 by Gabriele Cirulli. MIT License."),
            source: "../games/Game2048.qml",
            art: art2048
        },
        {
            title: "Same Game",
            tagline: qsTr("Clear the board one color at a time."),
            howTo: qsTr("Tap a group of two or more matching blocks to clear it. Bigger groups score more. Play alone, take turns with someone across the board, relax in Zen or solve puzzles."),
            players: qsTr("1–2 players"),
            credit: qsTr("Same Game, a Qt demo by The Qt Company. BSD-3-Clause."),
            source: "../../games/samegame/samegame.qml",
            size: Qt.size(320, 480),
            art: artSameGame
        },
        {
            title: "Maroon in Trouble",
            tagline: qsTr("Pop the bubbles and save the fish."),
            howTo: qsTr("Clownfish in bubbles float up from the deep. Tap the sea to place helpers that pop the bubbles before they reach the surface: starfish make coins, crabs, octopuses and pufferfish pop bubbles."),
            players: qsTr("1 player"),
            credit: qsTr("Maroon in Trouble, a Qt demo by The Qt Company. BSD-3-Clause."),
            source: "../../games/maroon/maroon.qml",
            size: Qt.size(320, 480),
            art: artMaroon
        },
        {
            title: qsTr("Scoop Shop"),
            tagline: qsTr("Serve every order before they give up."),
            howTo: qsTr("Pick who works the counter: Pip the penguin or Lotl the axolotl. Each customer's ticket shows their order: a cone or a cup, the scoops from the bottom up, and any toppings. Tap the pieces to build it, then tap the customer to hand it over. Right and quick scores more. A wrong order, or a customer who runs out of patience, costs a heart; lose three and the shop closes. Every five served it gets busier."),
            players: qsTr("1 player"),
            credit: qsTr("Made for McFly, Pip and Lotl too."),
            source: "../games/ScoopShop.qml",
            art: artScoopShop
        },
        {
            title: qsTr("Penguin March"),
            tagline: qsTr("Get the penguins home to the igloo."),
            howTo: qsTr("Penguins drop in and keep walking, turning at walls, and a long fall is the end of one. Pick a skill, then tap a penguin: Block turns the others back, Dig goes down, Bash goes through a wall, Build lays steps and Float opens an umbrella. Get enough of them into the igloo to win."),
            players: qsTr("1 player"),
            credit: qsTr("Made for McFly."),
            source: "../games/PenguinMarch.qml",
            art: artPenguins
        }
    ]

    function open(index) { howToOpen = false; openIndex = index }
    function close() { howToOpen = false; openIndex = -1 }
    // Main's closeDetails(): the tab tapped again, or the screen saver coming up.
    function closeDetail() { close() }
    onIsCurrentChanged: if (!isCurrent) close()
    // How to play over the game, or the assistant panel: a game against the
    // clock stops it, and carries on when the person says so.
    readonly property bool covered: howToOpen || !shown
    function pauseGame() {
        if (covered && game && typeof game.pause === "function")
            game.pause()
    }
    onCoveredChanged: pauseGame()

    Reveal { id: rv; shown: games.isCurrent && games.openGame === null }

    // ---- The list of games
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.spacing
        visible: games.openGame === null

        ScreenHeader {
            Layout.fillWidth: true
            title: qsTr("Games")
            subtitle: qsTr("Puzzles and games for a break")
        }

        // Fixed-height cards, scrolling: two rows show, and the top of the
        // next one says there are more.
        FocusFlickable {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            fadeColor: Theme.background
            contentHeight: cards.height

            Grid {
                id: cards
                // From the list's width, not the grid's own.
                readonly property real cardWidth: (list.width - (columns - 1) * columnSpacing) / columns
                width: list.width
                columns: Theme.tall ? 2 : 3
                rowSpacing: Theme.spacing
                columnSpacing: Theme.spacing

                Repeater {
                    model: games.catalog
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        required property int index

                        objectName: "card:" + modelData.title
                        width: cards.cardWidth
                        height: games.cardHeight
                        radius: Theme.radius
                        color: Theme.surface
                        opacity: rv.at(index)
                        scale: cardTap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.quick } }
                        transform: Translate { y: rv.rise(card.index) }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 10 : Theme.compact ? 14 : 20
                            spacing: Theme.mini ? 4 : 6

                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.bottomMargin: Theme.mini ? 2 : 6
                                sourceComponent: card.modelData.art
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Label {
                                    Layout.fillWidth: true
                                    text: card.modelData.title
                                    color: Theme.text
                                    font.pixelSize: Theme.mini ? Theme.fontSm : Theme.compact ? Theme.fontMd : Theme.fontLg
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Tag { visible: !Theme.mini; text: card.modelData.players }
                            }
                            Label {
                                visible: !Theme.mini
                                Layout.fillWidth: true
                                text: card.modelData.tagline
                                color: Theme.textMuted
                                font.pixelSize: Theme.compact ? Theme.fontXs : Theme.fontSm
                                elide: Text.ElideRight
                            }
                        }
                        // A flick of the list cancels the tap.
                        TapHandler { id: cardTap; onTapped: games.open(card.index) }
                    }
                }
            }
        }
    }

    // ---- Card art, drawn from each game's own colors and graphics
    Component {
        id: artTraffic
        Rectangle {
            radius: Theme.radiusSm
            color: Theme.sunken
            Item {
                id: lot
                readonly property real cell: Math.min(parent.width, parent.height) * 0.8 / 6
                width: cell * 6
                height: cell * 6
                anchors.centerIn: parent
                Rectangle {
                    x: lot.width - 2
                    y: lot.cell * 2 + lot.cell * 0.1
                    width: lot.cell * 0.5
                    height: lot.cell * 0.8
                    radius: 4
                    color: Theme.surface
                }
                // [column, row, length, horizontal, color]: a level's opening position.
                Repeater {
                    model: [[0, 2, 2, true, "#E5484D"], [2, 1, 3, false, "#5B8DEF"], [3, 0, 3, true, "#F2B84B"],
                            [4, 2, 2, false, "#3DB37A"], [0, 4, 2, true, "#8E7CE6"], [5, 3, 3, false, "#EF8A6F"],
                            [1, 0, 2, false, "#5FB3B3"]]
                    delegate: Rectangle {
                        required property var modelData
                        x: modelData[0] * lot.cell + lot.cell * 0.06
                        y: modelData[1] * lot.cell + lot.cell * 0.06
                        width: (modelData[3] ? modelData[2] : 1) * lot.cell - lot.cell * 0.12
                        height: (modelData[3] ? 1 : modelData[2]) * lot.cell - lot.cell * 0.12
                        radius: lot.cell * 0.2
                        color: modelData[4]
                    }
                }
            }
        }
    }
    Component {
        id: artTicTacToe
        Rectangle {
            radius: Theme.radiusSm
            color: Theme.sunken
            Grid {
                id: ttt
                readonly property real cell: Math.min(parent.width, parent.height) * 0.26
                anchors.centerIn: parent
                columns: 3
                spacing: cell * 0.08
                Repeater {
                    model: ["X", "O", "", "", "X", "O", "", "", "X"]
                    delegate: Rectangle {
                        required property string modelData
                        width: ttt.cell
                        height: ttt.cell
                        radius: Theme.radiusSm
                        color: Theme.surface
                        Repeater {
                            model: modelData === "X" ? [45, -45] : []
                            delegate: Rectangle {
                                required property real modelData
                                anchors.centerIn: parent
                                width: ttt.cell * 0.62
                                height: ttt.cell * 0.12
                                radius: height / 2
                                rotation: modelData
                                color: "#F07F5A"
                            }
                        }
                        Rectangle {
                            visible: modelData === "O"
                            anchors.centerIn: parent
                            width: ttt.cell * 0.5
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: ttt.cell * 0.1
                            border.color: "#4F7CF7"
                        }
                    }
                }
            }
        }
    }
    Component {
        id: artFourInARow
        Rectangle {
            radius: Theme.radiusSm
            color: Theme.sunken
            Rectangle {
                id: rack
                readonly property real cell: Math.min(parent.width / 7.6, parent.height / 6.6)
                width: cell * 7
                height: cell * 6
                anchors.centerIn: parent
                radius: cell * 0.4
                color: Theme.surface
                // Bottom row first; a diagonal four for orange.
                readonly property var marks: ["X", "O", "O", "X", "O", "", "",
                                              "", "X", "X", "O", "", "", "",
                                              "", "O", "X", "X", "", "", "",
                                              "", "", "O", "X", "", "", "",
                                              "", "", "", "", "", "", "",
                                              "", "", "", "", "", "", ""]
                Repeater {
                    model: 42
                    delegate: Rectangle {
                        required property int index
                        readonly property string mark: rack.marks[index]
                        x: (index % 7) * rack.cell + rack.cell * 0.1
                        y: (5 - Math.floor(index / 7)) * rack.cell + rack.cell * 0.1
                        width: rack.cell * 0.8
                        height: width
                        radius: width / 2
                        color: mark === "X" ? "#F07F5A" : mark === "O" ? "#4F7CF7" : Theme.sunken
                    }
                }
            }
        }
    }
    Component {
        id: art2048
        Rectangle {
            radius: Theme.radiusSm
            color: "#faf8ef"
            Grid {
                id: mini
                readonly property real cell: Math.min(parent.width, parent.height) * 0.3
                anchors.centerIn: parent
                columns: 2
                spacing: cell * 0.12
                Repeater {
                    model: [{ v: 2, c: "#eee4da" }, { v: 8, c: "#f2b179" }, { v: 64, c: "#f65e3b" }, { v: 2048, c: "#edc22e" }]
                    delegate: Rectangle {
                        required property var modelData
                        width: mini.cell
                        height: mini.cell
                        radius: 6
                        color: modelData.c
                        Label {
                            anchors.centerIn: parent
                            text: modelData.v
                            color: modelData.v <= 4 ? "#776e65" : "#f9f6f2"
                            font.pixelSize: mini.cell * (modelData.v > 1000 ? 0.3 : 0.45)
                            font.bold: true
                        }
                    }
                }
            }
        }
    }
    Component {
        id: artSameGame
        Rectangle {
            radius: Theme.radiusSm
            color: "#ececec"
            Column {
                anchors.centerIn: parent
                // The pictures are drawn at their own size: shrink to the card.
                scale: Math.min(1, (parent.height - 8) / Math.max(1, implicitHeight), (parent.width - 8) / Math.max(1, implicitWidth))
                spacing: 18
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    Repeater {
                        model: ["s", "a", "m", "e"]
                        delegate: Image {
                            required property string modelData
                            source: Qt.resolvedUrl("../../games/samegame/content/gfx/logo-" + modelData + ".png")
                        }
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: ["red", "green", "blue", "yellow"]
                        delegate: Image {
                            required property string modelData
                            source: Qt.resolvedUrl("../../games/samegame/content/gfx/" + modelData + ".png")
                        }
                    }
                }
            }
        }
    }
    Component {
        id: artMaroon
        Rectangle {
            radius: Theme.radiusSm
            gradient: Gradient {
                GradientStop { position: 0; color: "#97cfe5" }
                GradientStop { position: 1; color: "#276280" }
            }
            Image {
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.9, sourceSize.width)
                height: width * sourceSize.height / Math.max(1, sourceSize.width)
                source: Qt.resolvedUrl("../../games/maroon/content/gfx/logo.png")
            }
        }
    }
    Component {
        id: artScoopShop
        Rectangle {
            id: shop
            radius: Theme.radiusSm
            color: Theme.sunken
            readonly property real size: Math.min(height * 0.72, width / 2.6)
            ScoopAwning {
                x: shop.radius
                width: parent.width - 2 * shop.radius
                height: Math.round(Math.max(10, shop.height * 0.18))
                stripeWidth: Math.max(14, height * 1.1)
                stripe: Theme.dark ? "#C9557F" : "#F28DB2"
                between: Theme.dark ? "#EADDE4" : "#FFFFFF"
                frame: Theme.dark ? "#83375A" : "#D65C8A"
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: shop.height * 0.06
                spacing: -shop.size * 0.08
                ScoopCrew { width: shop.size * 0.8; height: shop.size * 0.96; anchors.bottom: parent.bottom; who: "pip" }
                ScoopTreat {
                    width: shop.size * 0.6
                    height: shop.size
                    base: "cone"
                    scoops: ["mint", "strawberry"]
                    toppings: ["sprinkles", "cherry"]
                    units: 10.4
                }
                ScoopCrew { width: shop.size * 0.8; height: shop.size * 0.96; anchors.bottom: parent.bottom; who: "lotl" }
            }
        }
    }

    Component {
        id: artPenguins
        Rectangle {
            id: scene
            radius: Theme.radiusSm
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.dark ? "#0B1424" : "#B9DCF3" }
                GradientStop { position: 1; color: Theme.dark ? "#1D2C47" : "#EDF6FC" }
            }
            readonly property real unit: Math.min(width / 9, height / 4.2)
            // Ice under a cap of snow, as the levels have it; the rounded
            // corners at the foot in the ice's deepest colour.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2 * Theme.radiusSm
                radius: Theme.radiusSm
                color: Theme.dark ? "#3F6489" : "#86B3D9"
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                y: parent.height * 0.7
                height: parent.height * 0.3 - Theme.radiusSm
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.dark ? "#A9C6DE" : "#D6EAF8" }
                    GradientStop { position: 1; color: Theme.dark ? "#3F6489" : "#86B3D9" }
                }
                Rectangle {
                    width: parent.width
                    height: Math.max(4, scene.unit * 0.25)
                    color: Theme.dark ? "#E4EEF7" : "#FFFFFF"
                }
            }
            PenguinPicture {
                x: parent.width * 0.62
                width: scene.unit * 2.6
                height: width * 40 / 48
                y: parent.height * 0.7 - height
                kind: "igloo"
                dark: Theme.dark
            }
            Repeater {
                model: [{ x: 0.1, kind: "walk" }, { x: 0.27, kind: "walk" }, { x: 0.42, kind: "float", up: 1.3 }]
                delegate: PenguinPicture {
                    required property var modelData
                    x: scene.width * modelData.x
                    width: scene.unit * 1.5
                    height: width
                    y: scene.height * 0.7 - height * 26 / 28 - (modelData.up || 0) * scene.unit
                    kind: modelData.kind
                    dark: Theme.dark
                }
            }
        }
    }

    // ---- An open game, full screen: over the nav too, with an X to close it
    // and (i) for how to play. Main draws the pages over the nav, and the
    // assistant panel, the sheets, the wake-word card and the screen saver
    // over the pages, so those still come over a game. The page leaves
    // Theme.navWidth on the left and Theme.navHeight at the bottom for the
    // nav: the window is that much bigger than this screen.
    Item {
        id: full
        // The buttons down the right on a landscape panel, where height is
        // short; along the top on a portrait one, where width is, and on the
        // 7" panel, whose games are laid out for its full width.
        readonly property bool alongTop: height > width || Theme.mini
        readonly property real margin: Theme.pageMargin
        x: -Theme.navWidth
        y: 0
        width: games.width + Theme.navWidth
        height: games.height + Theme.navHeight
        // Under the assistant panel the nav shows beside it as on every other
        // page; the game waits underneath (paused, if it runs on a clock).
        visible: games.openGame !== null && games.shown

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            // Taps the game doesn't take stop here, not on the nav underneath.
            MouseArea { anchors.fill: parent }
        }

        Label {
            visible: full.alongTop
            x: full.margin
            y: full.margin
            width: info.x - x - Theme.spacing
            height: Theme.touchTarget
            verticalAlignment: Text.AlignVCenter
            text: games.openGame ? games.openGame.title : ""
            color: Theme.text
            font.pixelSize: Theme.fontLg
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        IconButton {
            id: quit
            objectName: "game:close"
            x: full.width - full.margin - width
            y: full.margin
            icon: "close"
            onClicked: games.close()
        }
        IconButton {
            id: info
            objectName: "game:info"
            x: full.alongTop ? quit.x - Theme.spacing - width : quit.x
            y: full.alongTop ? quit.y : quit.y + quit.height + Theme.spacing
            icon: "info"
            fill: games.howToOpen ? Theme.accentSoft : Theme.surface
            onClicked: games.howToOpen = !games.howToOpen
        }

        Item {
            id: stage
            x: full.margin
            y: full.alongTop ? quit.y + quit.height + Theme.spacing : full.margin
            width: (full.alongTop ? full.width : quit.x - Theme.spacing) - x - (full.alongTop ? full.margin : 0)
            height: full.height - y - full.margin

            Item {
                id: frame
                readonly property size size: games.openGame && games.openGame.size ? games.openGame.size : Qt.size(0, 0)
                readonly property bool fixed: size.width > 0
                readonly property real fit: fixed ? Math.min(stage.width / size.width, stage.height / size.height) : 1
                width: fixed ? size.width * fit : stage.width
                height: fixed ? size.height * fit : stage.height
                anchors.centerIn: parent
                // Fixed-size games draw past their edges (Maroon slides its
                // screens in from above and below).
                clip: true

                Loader {
                    id: loader
                    width: frame.fixed ? frame.size.width : frame.width
                    height: frame.fixed ? frame.size.height : frame.height
                    scale: frame.fit
                    transformOrigin: Item.TopLeft
                    focus: true
                    active: games.openGame !== null
                    source: active ? Qt.resolvedUrl(games.openGame.source) : ""
                    onLoaded: {
                        item.forceActiveFocus() // arrow keys on a desktop
                        games.pauseGame()
                    }
                    onStatusChanged: if (status === Loader.Error) console.warn("Games: could not load", source)
                }
                // Same Game's own Quit button.
                Connections {
                    target: loader.item
                    ignoreUnknownSignals: true
                    function onQuitRequested() { games.close() }
                }
            }
            // Round the frame's corners by painting the page colour over them.
            Rectangle {
                visible: frame.fixed
                anchors.fill: frame
                anchors.margins: -Theme.radiusSm
                radius: Theme.radiusSm * 2
                color: "transparent"
                border.width: Theme.radiusSm
                border.color: Theme.background
            }

            // How to play and where the game comes from, over the game.
            Rectangle {
                anchors.fill: parent
                visible: opacity > 0
                opacity: games.howToOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
                radius: Theme.radius
                color: Theme.surface
                // Keep taps from reaching the game underneath.
                MouseArea { anchors.fill: parent; onClicked: games.howToOpen = false }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacing + 8
                    spacing: 16
                    Label {
                        Layout.fillWidth: true
                        text: games.openGame ? games.openGame.title : ""
                        color: Theme.text
                        font.pixelSize: Theme.fontLg
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: games.openGame ? games.openGame.howTo : ""
                        color: Theme.text
                        font.pixelSize: Theme.fontSm
                        lineHeight: 1.2
                        wrapMode: Text.WordWrap
                    }
                    Label {
                        Layout.fillWidth: true
                        text: games.openGame ? games.openGame.credit : ""
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontXs
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
