import QtQuick
import QtQuick.Controls
import QtQuick.LocalStorage
import McFly
import McFly.Core

// Pairs: the cards lie face down, two of every picture. Turn two over; a
// pair stays up and the same player goes again, two that don't match turn
// back. Alone it counts the turns, and keeps the fewest for each size of
// board; two people at the screen, or one against McFly, take turns and
// count pairs. Easy McFly remembers some of what it has seen, Hard all of it.
//
// The pictures are Color by Number's, painted in, each from a different
// shelf so no two pairs look alike. Nothing runs between turns: a timer
// only while a missed pair waits to turn back, and while McFly plays.
Item {
    id: game

    // "solo", "two" (two people at the screen) or "mcfly".
    property string mode: "solo"
    property bool hard: false
    // How many cards: 12, 16 or 20.
    property int size: 16
    readonly property var sizes: [12, 16, 20]
    // Per card: the picture on it (a Color by Number index).
    property var faces: []
    // Per card: who found it ("X", "O", or "S" alone), "" while it's still down.
    property var found: []
    // The cards turned up this turn and not yet a pair: none, one or two.
    property var up: []
    property string turn: "X"
    property string starter: "X"
    property var score: ({ X: 0, O: 0 })
    // Turns taken alone (a turn is two cards).
    property int moves: 0
    // The fewest turns to clear each size alone, from LocalStorage.
    property var best: ({})
    // What McFly has seen: card index → picture.
    property var seen: ({})
    // A missed pair stays up this long; McFly takes this long a card.
    property int hideMs: 1100
    property int thinkMs: 700

    readonly property bool solo: mode === "solo"
    readonly property bool vsComputer: mode === "mcfly"
    readonly property int pairsLeft: faces.length / 2 - found.filter(f => f !== "").length / 2
    readonly property bool over: faces.length > 0 && pairsLeft === 0
    readonly property bool missed: up.length === 2
    readonly property bool computerTurn: vsComputer && turn === "O" && !over
    readonly property string winner: !over || solo ? "" : score.X > score.O ? "X" : score.O > score.X ? "O" : "draw"

    readonly property color xColor: "#F07F5A"
    readonly property color oColor: "#4F7CF7"
    readonly property string xName: qsTr("Orange")
    readonly property string oName: qsTr("Blue")

    // ---- Shape. Wide and short (the 7" panel, the 10.1", a TV): the cards
    // on the left, the controls stacked beside them. Upright: the controls
    // on top and the button under the cards. Plain geometry, not anchors, so
    // the shape can switch.
    readonly property bool side: width > height * 1.4
    readonly property real gap: Theme.spacing
    // As wide as the widest switch or the score needs, whatever the font.
    readonly property real controlsWidth: Math.max(modeBeside.implicitWidth, levelBeside.implicitWidth,
                                                   sizeBeside.implicitWidth, chipsBeside.implicitWidth)
    readonly property real sideWidth: side ? Math.min(460, Math.max(340, controlsWidth + 16, width * 0.34)) : width
    // Where the cards go, and the grid that gives the biggest cards in it.
    readonly property real areaWidth: side ? width - sideWidth - gap : width
    readonly property real areaHeight: side ? height : Math.max(0, newGameButton.y - gap - area.y)
    readonly property var grid: layoutFor(size, areaWidth, areaHeight)
    readonly property real cell: grid.cell
    readonly property real card: cell * 0.92

    // The columns and rows for `count` cards that make them biggest in w × h.
    function layoutFor(count, w, h) {
        let out = { columns: 4, rows: count / 4, cell: 0 }
        for (let columns = 2; columns <= count; ++columns) {
            if (count % columns)
                continue
            const rows = count / columns
            const cell = Math.min(w / columns, h / rows)
            if (cell > out.cell)
                out = { columns: columns, rows: rows, cell: cell }
        }
        return out
    }

    function shuffled(list) {
        const a = list.slice()
        for (let i = a.length - 1; i > 0; --i) {
            const j = Math.floor(Math.random() * (i + 1))
            const t = a[i]
            a[i] = a[j]
            a[j] = t
        }
        return a
    }

    // A new board: one picture from each of `size / 2` shelves, twice over.
    function deal() {
        hider.stop()
        const shelves = shuffled(library.categories.map(c => c.id)).slice(0, size / 2)
        const pictures = shelves.map(shelf => {
            const all = library.picturesIn(shelf)
            return all[Math.floor(Math.random() * all.length)]
        })
        faces = shuffled(pictures.concat(pictures))
        found = Array(faces.length).fill("")
        up = []
        seen = ({})
        moves = 0
        score = { X: 0, O: 0 }
        // Who goes first alternates every round.
        starter = starter === "X" ? "O" : "X"
        turn = solo ? "X" : starter
    }
    onModeChanged: { starter = "O"; deal() }
    onHardChanged: deal()
    onSizeChanged: deal()

    // McFly sees every card turned up; Easy keeps about a third of them.
    function remember(i) {
        if (!vsComputer || (!hard && Math.random() >= 0.35))
            return
        const s = Object.assign({}, seen)
        s[i] = faces[i]
        seen = s
    }

    // Turns card `i` up for whoever's turn it is.
    function flip(i) {
        if (over || i < 0 || i >= faces.length || found[i] !== "" || up.indexOf(i) >= 0)
            return false
        if (missed)
            hideNow()
        up = up.concat([i])
        remember(i)
        if (up.length === 2) {
            if (solo)
                ++moves
            const [a, b] = up
            if (faces[a] === faces[b]) {
                const f = found.slice()
                f[a] = f[b] = solo ? "S" : turn
                found = f
                up = []
                if (!solo) {
                    const s = Object.assign({}, score)
                    s[turn] += 1
                    score = s
                }
                if (over && solo)
                    recordBest()
            } else {
                hider.restart()
            }
        }
        return true
    }
    // A tap on a card: the person whose turn it is. A tap while a missed pair
    // is up turns it back at once.
    function play(i) {
        if (computerTurn && !missed)
            return false
        if (missed) {
            hideNow()
            if (computerTurn)
                return false
        }
        return flip(i)
    }
    // A missed pair turns back, and the turn passes.
    function hideNow() {
        hider.stop()
        if (!missed)
            return
        up = []
        if (!solo)
            turn = turn === "X" ? "O" : "X"
    }

    // The card McFly turns next: half of a pair it remembers, the other half
    // of the card it just turned if it has seen it, or one it hasn't seen.
    function computerPick() {
        const open = []
        for (let i = 0; i < faces.length; ++i) {
            if (found[i] === "" && up.indexOf(i) < 0)
                open.push(i)
        }
        const known = open.filter(i => seen[i] !== undefined)
        if (up.length === 1) {
            const partner = known.find(i => seen[i] === faces[up[0]])
            if (partner !== undefined)
                return partner
        } else {
            for (const i of known) {
                if (known.some(j => j !== i && seen[j] === seen[i]))
                    return i
            }
        }
        const fresh = open.filter(i => seen[i] === undefined)
        const from = fresh.length ? fresh : open
        return from[Math.floor(Math.random() * from.length)]
    }
    function computerMove() {
        if (computerTurn && !missed)
            flip(computerPick())
    }

    Timer {
        id: hider
        interval: game.hideMs
        onTriggered: game.hideNow()
    }
    Timer {
        interval: game.thinkMs
        repeat: true
        running: game.computerTurn && !game.missed
        onTriggered: game.computerMove()
    }

    // ---- The fewest turns, in LocalStorage
    function database() {
        try {
            const db = LocalStorage.openDatabaseSync("McFlyPairs", "1.0", "Pairs best scores", 10000)
            db.transaction(tx => tx.executeSql("CREATE TABLE IF NOT EXISTS best(size INTEGER PRIMARY KEY, moves INTEGER)"))
            return db
        } catch (e) {
            console.warn("Pairs: scores are not saved:", e)
            return null
        }
    }
    function restore() {
        const db = database()
        if (!db)
            return
        try {
            db.readTransaction(tx => {
                const rows = tx.executeSql("SELECT size, moves FROM best").rows
                const b = {}
                for (let i = 0; i < rows.length; ++i)
                    b[rows.item(i).size] = rows.item(i).moves
                best = b
            })
        } catch (e) {
            console.warn("Pairs: could not read scores:", e)
        }
    }
    function recordBest() {
        if (best[size] !== undefined && best[size] <= moves)
            return
        const b = Object.assign({}, best)
        b[size] = moves
        best = b
        const db = database()
        if (!db)
            return
        try {
            db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO best VALUES (?, ?)", [size, moves]))
        } catch (e) {
            console.warn("Pairs: could not save:", e)
        }
    }

    Component.onCompleted: {
        restore()
        deal()
    }

    // Where the pictures come from: Color by Number's shelves.
    ColorByNumberBoard {
        id: library
        visible: false
    }

    readonly property string statusText: solo
        ? (over ? qsTr("All found in %1 turns").arg(moves) : qsTr("%1 pairs to find").arg(pairsLeft))
        : over ? (winner === "draw" ? qsTr("It's a draw")
                  : vsComputer ? (winner === "X" ? qsTr("You win!") : qsTr("McFly wins!"))
                  : qsTr("%1 wins!").arg(winner === "X" ? xName : oName))
        : computerTurn ? qsTr("McFly's turn")
        : vsComputer ? qsTr("Your turn")
        : qsTr("%1's turn").arg(turn === "X" ? xName : oName)
    readonly property color statusColor: solo || over && winner === "draw" ? Theme.text
        : (over ? winner : turn) === "X" ? xColor : oColor

    // ---- Controls: who plays, how hard, how many cards, and the score
    Component {
        id: modeSwitch
        SegmentedControl {
            options: [qsTr("Solo"), qsTr("2 players"), qsTr("vs McFly")]
            currentIndex: ["solo", "two", "mcfly"].indexOf(game.mode)
            onSelected: index => game.mode = ["solo", "two", "mcfly"][index]
        }
    }
    Component {
        id: levelSwitch
        SegmentedControl {
            options: [qsTr("Easy"), qsTr("Hard")]
            currentIndex: game.hard ? 1 : 0
            onSelected: index => game.hard = index === 1
        }
    }
    Component {
        id: sizeSwitch
        SegmentedControl {
            options: game.sizes.map(n => String(n))
            currentIndex: game.sizes.indexOf(game.size)
            onSelected: index => game.size = game.sizes[index]
        }
    }
    Component {
        id: scoreChips
        Row {
            spacing: 12
            Repeater {
                model: game.solo
                    ? [{ label: qsTr("Turns"), value: game.moves, color: Theme.textMuted },
                       { label: qsTr("Best"), value: game.best[game.size] !== undefined ? game.best[game.size] : "–", color: Theme.textMuted }]
                    : [{ label: game.vsComputer ? qsTr("You") : game.xName, value: game.score.X, color: game.xColor },
                       { label: game.vsComputer ? qsTr("McFly") : game.oName, value: game.score.O, color: game.oColor }]
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: Math.max(88, chip.implicitWidth + 32)
                    implicitHeight: 64
                    radius: Theme.radiusSm
                    color: Theme.surface
                    Column {
                        id: chip
                        anchors.centerIn: parent
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            color: modelData.color
                            font.pixelSize: Theme.fontXs
                            font.weight: Font.DemiBold
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.value
                            color: Theme.text
                            font.pixelSize: Theme.fontMd
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }

    // Beside the cards: the status with a new-game button, then the
    // switches and the score, closer together when the stage is short.
    Column {
        id: stack
        visible: game.side
        x: game.width - game.sideWidth
        y: 0
        width: game.sideWidth
        spacing: Math.max(4, Math.min(game.gap, (game.height - 64 * 2 - 60 * 3) / 4))

        Item {
            width: parent.width
            height: 64
            Label {
                anchors.left: parent.left
                anchors.right: restart.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: game.statusText
                color: game.statusColor
                font.pixelSize: Theme.fontMd
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            IconButton {
                id: restart
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon: "refresh"
                fill: game.over ? Glass.primary : Theme.surface
                ink: game.over ? "white" : Theme.text
                onClicked: game.deal()
            }
        }
        Loader { id: modeBeside; sourceComponent: modeSwitch }
        Loader { id: levelBeside; sourceComponent: levelSwitch; active: game.vsComputer; visible: active }
        Loader { id: sizeBeside; sourceComponent: sizeSwitch }
        Loader { id: chipsBeside; sourceComponent: scoreChips }
    }

    // Above the cards: the switches, wrapping when they don't fit, then the
    // score and the status.
    Flow {
        id: header
        visible: !game.side
        x: 0
        y: 0
        width: game.width
        spacing: 12
        Loader { sourceComponent: modeSwitch }
        Loader { sourceComponent: levelSwitch; active: game.vsComputer; visible: active }
        Loader { sourceComponent: sizeSwitch }
        Loader { sourceComponent: scoreChips }
    }
    Label {
        id: status
        visible: !game.side
        x: (game.width - width) / 2
        y: header.y + header.height + game.gap
        text: game.statusText
        color: game.statusColor
        font.pixelSize: Theme.fontLg
        font.weight: Font.DemiBold
    }
    Item {
        id: area
        visible: false
        y: status.y + status.height + game.gap
    }

    // ---- The cards
    Item {
        id: board
        x: game.side ? (game.areaWidth - width) / 2 : (game.width - width) / 2
        y: game.side ? (game.height - height) / 2 : area.y + (game.areaHeight - height) / 2
        width: game.grid.columns * game.cell
        height: game.grid.rows * game.cell

        Repeater {
            model: game.faces.length
            delegate: Item {
                id: card
                required property int index
                readonly property string by: game.found[index] || ""
                readonly property bool faceUp: by !== "" || game.up.indexOf(index) >= 0
                // What's drawn, and its picture: they change halfway through
                // the turn, so a new deal never shows its pictures.
                property bool showing: false
                property int shownFace: 0
                objectName: "tap:card"
                x: (index % game.grid.columns) * game.cell + (game.cell - width) / 2
                y: Math.floor(index / game.grid.columns) * game.cell + (game.cell - height) / 2
                width: game.card
                height: game.card
                scale: tap.pressed && !faceUp ? 0.95 : 1
                Behavior on scale { NumberAnimation { duration: Theme.quick } }
                transform: Scale { id: turnOver; origin.x: card.width / 2 }

                onFaceUpChanged: turning.restart()
                SequentialAnimation {
                    id: turning
                    NumberAnimation { target: turnOver; property: "xScale"; to: 0; duration: 90; easing.type: Easing.InQuad }
                    ScriptAction {
                        script: {
                            card.showing = card.faceUp
                            if (card.faceUp)
                                card.shownFace = game.faces[card.index] || 0
                        }
                    }
                    NumberAnimation { target: turnOver; property: "xScale"; to: 1; duration: 110; easing.type: Easing.OutQuad }
                }

                // The back: the accent, with a ring inside.
                Rectangle {
                    anchors.fill: parent
                    visible: !card.showing
                    radius: Math.min(Theme.radiusSm, width * 0.18)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.15) }
                        GradientStop { position: 1; color: Theme.accent }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.42
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: Math.max(2, parent.width * 0.05)
                        border.color: Qt.rgba(1, 1, 1, 0.55)
                    }
                }
                // The face: the picture, on white (a dark grey at night), and
                // a ring in the colour of whoever found the pair.
                Rectangle {
                    anchors.fill: parent
                    visible: card.showing
                    radius: Math.min(Theme.radiusSm, width * 0.18)
                    color: Theme.dark ? "#2C2C31" : "#FFFFFF"
                    border.width: card.by !== "" ? Math.max(3, width * 0.05) : 0
                    border.color: card.by === "X" ? game.xColor : card.by === "O" ? game.oColor : Theme.success
                    opacity: game.over || card.by === "" ? 1 : 0.8
                    ColorByNumberBoard {
                        anchors.fill: parent
                        anchors.margins: parent.width * 0.12
                        preview: true
                        dark: Theme.dark
                        picture: card.shownFace
                        saved: "1".repeat(total)
                    }
                }
                TapHandler {
                    id: tap
                    onTapped: game.over ? game.deal() : game.play(card.index)
                }
            }
        }
    }

    PillButton {
        id: newGameButton
        visible: !game.side
        x: (game.width - width) / 2
        y: game.height - height
        text: game.over ? qsTr("Play again") : qsTr("New game")
        fill: game.over ? Glass.primary : Theme.surface
        ink: game.over ? Theme.accentInk : Theme.text
        onClicked: game.deal()
    }
}
