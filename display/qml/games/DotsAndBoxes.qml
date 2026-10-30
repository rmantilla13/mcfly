import QtQuick
import QtQuick.Controls
import McFly

// Dots and boxes for two people at the screen, or one against McFly. Take
// turns drawing a line between two dots; the line that closes a box claims
// it, and the same player goes again. Most boxes wins.
//
// Easy McFly often draws at random. Hard takes every box it can, never
// gives a box its third side while it has a choice, then hands over the
// smallest chain it can and, with longer chains still to come, leaves the
// last two boxes of a chain to keep the next one for itself. Who goes first
// alternates every round, and the score is kept until the game is closed.
//
// The whole board is one tap target: a tap draws the line nearest to it,
// and every box is at least Theme.touchTarget across.
Item {
    id: game

    property bool vsComputer: false
    property bool hard: false
    // Boxes across and down: 3, 4 or 5 each way.
    property int size: 4
    readonly property var sizes: [3, 4, 5]
    readonly property int rows: size
    readonly property int columns: size
    // The lines: the across ones row by row ((rows + 1) × columns), then the
    // down ones (rows × (columns + 1)). Who drew each, "" while undrawn.
    property var lines: emptyLines()
    // Who closed each box, row by row.
    property var boxes: emptyBoxes()
    property string turn: "X"
    property string starter: "X"
    property var score: ({ X: 0, O: 0, draw: 0 })
    // The line drawn last, or -1, so a move made across the room is easy to find.
    property int lastLine: -1
    // McFly draws a line this long after the last one.
    property int thinkMs: 550

    readonly property int across: (rows + 1) * columns
    readonly property int lineCount: across + rows * (columns + 1)
    readonly property int xBoxes: boxes.filter(b => b === "X").length
    readonly property int oBoxes: boxes.filter(b => b === "O").length
    readonly property bool over: boxes.every(b => b !== "")
    readonly property string winner: !over ? "" : xBoxes > oBoxes ? "X" : oBoxes > xBoxes ? "O" : "draw"
    readonly property bool computerTurn: vsComputer && turn === "O" && !over

    readonly property color xColor: "#F07F5A"
    readonly property color oColor: "#4F7CF7"
    readonly property string xName: qsTr("Orange")
    readonly property string oName: qsTr("Blue")

    // ---- Shape. Wide and short (the 7" panel, the 10.1", a TV): the board
    // on the left, the controls stacked beside it. Upright: the controls on
    // top and the button under the board. Plain geometry, not anchors, so the
    // shape can switch.
    readonly property bool side: width > height * 1.4
    readonly property real gap: Theme.spacing
    // As wide as the widest switch or the score needs, whatever the font.
    readonly property real controlsWidth: Math.max(modeBeside.implicitWidth, levelBeside.implicitWidth,
                                                   sizeBeside.implicitWidth, chipsBeside.implicitWidth)
    readonly property real sideWidth: side ? Math.min(460, Math.max(320, controlsWidth + 16, width * 0.34)) : width
    readonly property real areaWidth: side ? width - sideWidth - gap : width
    readonly property real areaHeight: side ? height : Math.max(0, newRoundButton.y - gap - area.y)
    // A box's side; the board keeps 0.4 of one around the dots so the outer
    // lines take a tap from outside them too.
    readonly property real box: Math.min(areaWidth / (columns + 0.8), areaHeight / (rows + 0.8))
    readonly property real pad: box * 0.4

    function emptyLines() { return Array((size + 1) * size * 2).fill("") }
    function emptyBoxes() { return Array(size * size).fill("") }

    // ---- The board as numbers: lines and boxes by index.
    function acrossLine(r, c) { return r * columns + c }
    function downLine(r, c) { return across + r * (columns + 1) + c }
    // The four lines around box `b`: top, bottom, left, right.
    function sidesOf(b) {
        const r = Math.floor(b / columns), c = b % columns
        return [acrossLine(r, c), acrossLine(r + 1, c), downLine(r, c), downLine(r, c + 1)]
    }
    // The one or two boxes beside line `l`.
    function boxesBeside(l) {
        const out = []
        if (l < across) {
            const r = Math.floor(l / columns), c = l % columns
            if (r > 0)
                out.push((r - 1) * columns + c)
            if (r < rows)
                out.push(r * columns + c)
        } else {
            const i = l - across, r = Math.floor(i / (columns + 1)), c = i % (columns + 1)
            if (c > 0)
                out.push(r * columns + c - 1)
            if (c < columns)
                out.push(r * columns + c)
        }
        return out
    }
    function drawnAround(drawn, b) {
        return sidesOf(b).filter(l => drawn[l] !== "").length
    }
    // Draws line `l` for `player` on plain arrays; returns how many boxes it closed.
    function drawOn(drawn, owners, l, player) {
        drawn[l] = player
        let closed = 0
        for (const b of boxesBeside(l)) {
            if (drawnAround(drawn, b) === 4) {
                owners[b] = player
                ++closed
            }
        }
        return closed
    }

    function place(l) {
        if (over || l < 0 || l >= lineCount || lines[l] !== "")
            return false
        const drawn = lines.slice(), owners = boxes.slice()
        const closed = drawOn(drawn, owners, l, turn)
        lines = drawn
        boxes = owners
        lastLine = l
        if (over) {
            const s = Object.assign({}, score)
            s[winner] += 1
            score = s
        } else if (closed === 0) {
            turn = turn === "X" ? "O" : "X"
        }
        return true
    }
    // A tap on the board: the person whose turn it is.
    function play(l) {
        if (computerTurn)
            return false
        return place(l)
    }
    function newRound() {
        starter = starter === "X" ? "O" : "X"
        lines = emptyLines()
        boxes = emptyBoxes()
        lastLine = -1
        turn = starter
    }
    function reset() {
        score = { X: 0, O: 0, draw: 0 }
        starter = "O"
        newRound()
    }
    onVsComputerChanged: reset()
    onHardChanged: reset()
    onSizeChanged: reset()

    // ---- McFly
    // The undrawn lines that close a box, that give no box its third side,
    // and the rest.
    function sortLines(drawn) {
        const out = { closing: [], safe: [], giving: [] }
        for (let l = 0; l < lineCount; ++l) {
            if (drawn[l] !== "")
                continue
            const counts = boxesBeside(l).map(b => drawnAround(drawn, b))
            if (counts.some(n => n === 3))
                out.closing.push(l)
            else if (counts.every(n => n < 2))
                out.safe.push(l)
            else
                out.giving.push(l)
        }
        return out
    }
    function pick(list) { return list[Math.floor(Math.random() * list.length)] }
    // How many boxes the other player takes, greedily, after line `l`.
    function handedOver(drawn, l) {
        const d = drawn.slice(), o = boxes.slice()
        d[l] = "O"
        let taken = 0
        for (;;) {
            const closing = sortLines(d).closing
            if (!closing.length)
                return taken
            taken += drawOn(d, o, closing[0], "X")
        }
    }
    // The open boxes reachable from `b` through undrawn lines between boxes.
    function chainOf(drawn, b) {
        const seenBoxes = {}
        const todo = [b]
        seenBoxes[b] = true
        while (todo.length) {
            const at = todo.pop()
            for (const l of sidesOf(at)) {
                if (drawn[l] !== "")
                    continue
                for (const next of boxesBeside(l)) {
                    if (!seenBoxes[next] && boxes[next] === "") {
                        seenBoxes[next] = true
                        todo.push(next)
                    }
                }
            }
        }
        return Object.keys(seenBoxes).map(Number)
    }
    function bestLine() {
        const drawn = lines
        const sorted = sortLines(drawn)
        if (!hard) {
            if (sorted.closing.length && Math.random() < 0.75)
                return pick(sorted.closing)
            if (sorted.safe.length && Math.random() < 0.6)
                return pick(sorted.safe)
            return pick(sorted.closing.concat(sorted.safe, sorted.giving))
        }
        if (sorted.closing.length) {
            // Keep control: with no safe line left after this chain, and a
            // chain of two closing, give those two away when a longer chain
            // waits (the other player has to open it after).
            if (!sorted.safe.length) {
                const l = sorted.closing[0]
                const b = boxesBeside(l).find(x => drawnAround(drawn, x) === 3)
                const chain = chainOf(drawn, b)
                if (chain.length === 2 && sorted.closing.length === 1) {
                    const rest = boxes.map((o, i) => i).filter(i => boxes[i] === "" && chain.indexOf(i) < 0)
                    let longest = 0
                    const counted = {}
                    for (const i of rest) {
                        if (counted[i])
                            continue
                        const c = chainOf(drawn, i)
                        c.forEach(x => counted[x] = true)
                        longest = Math.max(longest, c.length)
                    }
                    if (longest >= 3) {
                        // The far side of the second box, not the line between them.
                        const other = chain.find(x => x !== b)
                        const far = sidesOf(other).find(s => drawn[s] === "" && boxesBeside(s).indexOf(b) < 0)
                        if (far !== undefined)
                            return far
                    }
                }
            }
            return pick(sorted.closing)
        }
        if (sorted.safe.length)
            return pick(sorted.safe)
        // Only lines that give boxes away: the fewest, and between equals one
        // between two boxes, so a chain of two can't be split to keep control.
        let fewest = Infinity, choices = []
        for (const l of sorted.giving) {
            const n = handedOver(drawn, l) * 2 + (boxesBeside(l).length === 2 ? 0 : 1)
            if (n < fewest) {
                fewest = n
                choices = [l]
            } else if (n === fewest) {
                choices.push(l)
            }
        }
        return pick(choices)
    }
    function computerMove() {
        if (computerTurn)
            place(bestLine())
    }

    Timer {
        interval: game.thinkMs
        repeat: true
        running: game.computerTurn
        onTriggered: game.computerMove()
    }

    readonly property string statusText: over
        ? (winner === "draw" ? qsTr("It's a draw")
           : vsComputer ? (winner === "X" ? qsTr("You win!") : qsTr("McFly wins!"))
           : qsTr("%1 wins!").arg(winner === "X" ? xName : oName))
        : computerTurn ? qsTr("McFly is thinking…")
        : vsComputer ? qsTr("Your turn")
        : qsTr("%1's turn").arg(turn === "X" ? xName : oName)
    readonly property color statusColor: over ? (winner === "X" ? xColor : winner === "O" ? oColor : Theme.text)
                                              : turn === "X" ? xColor : oColor

    // ---- Controls: who plays, how hard, how big, and the boxes so far
    Component {
        id: modeSwitch
        SegmentedControl {
            options: [qsTr("2 players"), qsTr("vs McFly")]
            currentIndex: game.vsComputer ? 1 : 0
            onSelected: index => game.vsComputer = index === 1
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
            options: game.sizes.map(n => n + "×" + n)
            currentIndex: game.sizes.indexOf(game.size)
            onSelected: index => game.size = game.sizes[index]
        }
    }
    Component {
        id: scoreChips
        Row {
            spacing: 12
            Repeater {
                model: [{ key: "X", label: game.vsComputer ? qsTr("You") : game.xName, color: game.xColor, boxes: game.xBoxes },
                        { key: "O", label: game.vsComputer ? qsTr("McFly") : game.oName, color: game.oColor, boxes: game.oBoxes }]
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: Math.max(88, chip.implicitWidth + 32)
                    implicitHeight: 64
                    radius: Theme.radiusSm
                    color: Theme.surface
                    Column {
                        id: chip
                        anchors.centerIn: parent
                        // The name, with the games won once there are any.
                        Label {
                            readonly property int won: game.score[modelData.key]
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: won === 0 ? modelData.label
                                : won === 1 ? qsTr("%1 · 1 win").arg(modelData.label)
                                : qsTr("%1 · %2 wins").arg(modelData.label).arg(won)
                            color: modelData.color
                            font.pixelSize: Theme.fontXs
                            font.weight: Font.DemiBold
                        }
                        // The boxes in this game.
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.boxes
                            color: Theme.text
                            font.pixelSize: Theme.fontMd
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }

    // Beside the board: the status with a restart button, then the switches
    // and the score, closer together when the stage is short.
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
                onClicked: game.newRound()
            }
        }
        Loader { id: modeBeside; sourceComponent: modeSwitch }
        Loader { id: levelBeside; sourceComponent: levelSwitch; active: game.vsComputer; visible: active }
        Loader { id: sizeBeside; sourceComponent: sizeSwitch }
        Loader { id: chipsBeside; sourceComponent: scoreChips }
    }

    // Above the board: the switches, wrapping when they don't fit, then the
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

    // ---- Board
    Rectangle {
        id: board
        objectName: "tap:board"
        x: game.side ? (game.areaWidth - width) / 2 : (game.width - width) / 2
        y: game.side ? (game.height - height) / 2 : area.y + (game.areaHeight - height) / 2
        width: game.columns * game.box + 2 * game.pad
        height: game.rows * game.box + 2 * game.pad
        radius: Theme.radius
        color: Theme.surface

        readonly property real thick: Math.max(6, game.box * 0.09)
        // The line a finger is on, drawn in the player's colour until it lifts.
        readonly property int pressedLine: lineTap.pressed && !game.over && !game.computerTurn
                                           ? lineAt(lineTap.point.position) : -1
        readonly property real dot: Math.max(12, game.box * 0.16)

        // The line nearest a point on the board, or -1 when both lines
        // near it are drawn.
        function lineAt(p) {
            const x = (p.x - game.pad) / game.box, y = (p.y - game.pad) / game.box
            const r = Math.max(0, Math.min(game.rows, Math.round(y)))
            const c = Math.max(0, Math.min(game.columns - 1, Math.floor(x)))
            const dc = Math.max(0, Math.min(game.columns, Math.round(x)))
            const dr = Math.max(0, Math.min(game.rows - 1, Math.floor(y)))
            const a = game.acrossLine(r, c), d = game.downLine(dr, dc)
            const near = [[Math.abs(y - r), a], [Math.abs(x - dc), d]].sort((u, v) => u[0] - v[0])
            const free = near.find(n => game.lines[n[1]] === "")
            return free ? free[1] : -1
        }
        // Where a line is drawn.
        function lineRect(l) {
            const t = thick
            if (l < game.across) {
                const r = Math.floor(l / game.columns), c = l % game.columns
                return Qt.rect(game.pad + c * game.box, game.pad + r * game.box - t / 2, game.box, t)
            }
            const i = l - game.across, r = Math.floor(i / (game.columns + 1)), c = i % (game.columns + 1)
            return Qt.rect(game.pad + c * game.box - t / 2, game.pad + r * game.box, t, game.box)
        }

        // The boxes, in the colour of who closed them.
        Repeater {
            model: game.boxes.length
            delegate: Rectangle {
                required property int index
                readonly property string owner: game.boxes[index] || ""
                x: game.pad + (index % game.columns) * game.box + board.thick / 2
                y: game.pad + Math.floor(index / game.columns) * game.box + board.thick / 2
                width: game.box - board.thick
                height: width
                radius: Math.min(Theme.radiusSm, width * 0.15)
                color: owner === "X" ? game.xColor : game.oColor
                opacity: owner === "" ? 0 : 0.28
                Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
            }
        }
        // The lines: faint where undrawn, in the drawer's colour once drawn.
        Repeater {
            model: game.lineCount
            delegate: Rectangle {
                id: line
                required property int index
                readonly property string by: game.lines[index] || ""
                readonly property rect at: board.lineRect(index)
                x: at.x
                y: at.y
                width: at.width
                height: at.height
                radius: board.thick / 2
                color: by === "X" ? game.xColor : by === "O" ? game.oColor
                     : board.pressedLine === index ? (game.turn === "X" ? game.xColor : game.oColor) : Theme.sunken
                opacity: by === "" && board.pressedLine !== index ? 0.7 : 1
                // The last line drawn, with a white stripe through it.
                Rectangle {
                    visible: line.index === game.lastLine && !game.over
                    anchors.centerIn: parent
                    width: line.width > line.height ? line.width * 0.4 : line.width * 0.34
                    height: line.width > line.height ? line.height * 0.34 : line.height * 0.4
                    radius: Math.min(width, height) / 2
                    color: "white"
                    opacity: 0.85
                }
            }
        }
        // The dots, over the line ends.
        Repeater {
            model: (game.rows + 1) * (game.columns + 1)
            delegate: Rectangle {
                required property int index
                x: game.pad + (index % (game.columns + 1)) * game.box - width / 2
                y: game.pad + Math.floor(index / (game.columns + 1)) * game.box - height / 2
                width: board.dot
                height: width
                radius: width / 2
                color: Theme.text
            }
        }

        TapHandler {
            id: lineTap
            onTapped: (point) => game.over ? game.newRound() : game.play(board.lineAt(point.position))
        }
    }

    PillButton {
        id: newRoundButton
        visible: !game.side
        x: (game.width - width) / 2
        y: game.height - height
        text: game.over ? qsTr("Play again") : qsTr("Start over")
        fill: game.over ? Glass.primary : Theme.surface
        ink: game.over ? Theme.accentInk : Theme.text
        onClicked: game.newRound()
    }
}
