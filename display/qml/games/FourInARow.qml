import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Four in a row for two people at the screen, or one against McFly. Tap a
// column and the disc drops to the lowest free hole; four of a color in a
// line, across, down or corner to corner, wins. Easy McFly often plays at
// random and otherwise looks two discs ahead; Hard up to ten. Who
// goes first alternates every round, and the score is kept until the game
// is closed.
//
// Every column is a tap target at least Theme.touchTarget wide, even when
// the discs in it are smaller (the 7" panel's short stage).
Item {
    id: game

    readonly property int columns: 7
    readonly property int rows: 6
    property bool vsComputer: false
    property bool hard: false
    // The holes, bottom row first: index = row * columns + column.
    property var cells: emptyBoard()
    property string turn: "X"
    property string starter: "X"
    property var winLine: null
    // The hole the last disc dropped into, or -1.
    property int lastMove: -1
    readonly property bool draw: !winLine && cells.every(c => c !== "")
    readonly property bool over: winLine !== null || draw
    readonly property string winner: winLine ? cells[winLine[0]] : ""
    readonly property bool computerTurn: vsComputer && turn === "O" && !over
    property var score: ({ X: 0, O: 0, draw: 0 })
    // McFly moves once the last disc has landed (the longest drop is 450 ms).
    property int thinkMs: 600
    // How many discs ahead Hard McFly looks, at most.
    property int hardDepth: 10

    readonly property color xColor: "#F07F5A"
    readonly property color oColor: "#4F7CF7"
    readonly property string xName: qsTr("Orange")
    readonly property string oName: qsTr("Blue")

    // ---- Shape. Wide and short (the 7" panel, a TV): the board on the left,
    // everything else stacked beside it. Otherwise the controls on top and
    // the button under the board, as tic-tac-toe has them. Plain geometry,
    // not anchors, so the shape can switch.
    readonly property bool side: width > height * 1.4
    readonly property real gap: Theme.spacing
    readonly property real sideWidth: side ? Math.max(0, width - boardWidth - gap) : width
    readonly property real boardWidth: side
        ? Math.max(columns * Theme.touchTarget, Math.min(height * columns / rows, width - 300 - gap))
        : Math.max(columns * Theme.touchTarget, Math.min(width, area.height * columns / rows))
    // A column's width (its tap target) and a row's height. Rows may be
    // shorter than columns are wide on a short stage; the discs follow the
    // smaller of the two.
    readonly property real colWidth: boardWidth / columns
    readonly property real rowHeight: Math.min(colWidth, (side ? height : area.height) / rows)
    readonly property real disc: Math.min(colWidth, rowHeight) * 0.8

    function emptyBoard() {
        return Array(42).fill("")
    }

    // The hole a disc dropped in `column` lands in, or -1 when it is full.
    function landing(board, column) {
        for (let r = 0; r < rows; ++r) {
            if (board[r * columns + column] === "")
                return r * columns + column
        }
        return -1
    }

    // The run of four or more through hole `i`, in order, or null.
    function lineThrough(board, i) {
        const p = board[i]
        if (!p)
            return null
        const c0 = i % columns, r0 = Math.floor(i / columns)
        for (const [dc, dr] of [[1, 0], [0, 1], [1, 1], [1, -1]]) {
            const line = [i]
            for (const s of [1, -1]) {
                let c = c0 + dc * s, r = r0 + dr * s
                while (c >= 0 && c < columns && r >= 0 && r < rows && board[r * columns + c] === p) {
                    if (s > 0)
                        line.push(r * columns + c)
                    else
                        line.unshift(r * columns + c)
                    c += dc * s
                    r += dr * s
                }
            }
            if (line.length >= 4)
                return line
        }
        return null
    }

    // The column `player` should play, looking `depth` discs ahead: wins
    // soonest, loses latest, random between equally good columns. The search
    // is C++ (src/games/FourInARowEngine.cpp): in JavaScript it froze the
    // screen for seconds a move.
    function bestMove(board, player, depth) {
        return FourInARowEngine.bestMove(board, player, depth)
    }

    function place(column) {
        const at = landing(cells, column)
        if (over || at < 0)
            return false
        const next = cells.slice()
        next[at] = turn
        cells = next
        lastMove = at
        winLine = lineThrough(next, at)
        if (over) {
            const s = Object.assign({}, score)
            s[winner || "draw"] += 1
            score = s
        } else {
            turn = turn === "X" ? "O" : "X"
        }
        return true
    }
    // A tap on a column: the person whose turn it is.
    function play(column) {
        if (computerTurn)
            return false
        return place(column)
    }
    function computerMove() {
        if (!computerTurn)
            return
        const open = []
        for (let c = 0; c < columns; ++c) {
            if (landing(cells, c) >= 0)
                open.push(c)
        }
        const random = !hard && Math.random() < 0.4
        place(random ? open[Math.floor(Math.random() * open.length)]
                     : bestMove(cells, "O", hard ? hardDepth : 2))
    }
    function newRound() {
        starter = starter === "X" ? "O" : "X"
        cells = emptyBoard()
        winLine = null
        lastMove = -1
        turn = starter
    }
    function reset() {
        score = { X: 0, O: 0, draw: 0 }
        starter = "O"
        newRound()
    }
    onVsComputerChanged: reset()
    onHardChanged: reset()

    Timer {
        interval: game.thinkMs
        running: game.computerTurn
        onTriggered: game.computerMove()
    }

    readonly property string statusText: winner
        ? (vsComputer ? (winner === "X" ? qsTr("You win!") : qsTr("McFly wins!"))
                      : qsTr("%1 wins!").arg(winner === "X" ? xName : oName))
        : draw ? qsTr("It's a draw")
        : computerTurn ? qsTr("McFly is thinking…")
        : vsComputer ? qsTr("Your turn")
        : qsTr("%1's turn").arg(turn === "X" ? xName : oName)
    readonly property color statusColor: winner === "X" ? xColor : winner === "O" ? oColor : Theme.text

    // ---- Controls: who plays, how hard, and the score
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
        id: scoreChips
        Row {
            spacing: 12
            Repeater {
                model: [{ key: "X", label: game.vsComputer ? qsTr("You") : game.xName, color: game.xColor },
                        { key: "draw", label: qsTr("Draws"), color: Theme.textMuted },
                        { key: "O", label: game.vsComputer ? qsTr("McFly") : game.oName, color: game.oColor }]
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
                            text: game.score[modelData.key]
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
        spacing: Math.max(4, Math.min(game.gap, (game.height - 64 * 2 - 60 * 2) / 3))

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
        Loader { sourceComponent: modeSwitch }
        Loader { sourceComponent: levelSwitch; active: game.vsComputer; visible: active }
        Loader { sourceComponent: scoreChips }
    }

    // Above the board: the switches on the left and the score on the right,
    // as tic-tac-toe has them; the score goes under them when they don't fit.
    Item {
        id: header
        readonly property bool oneRow: switches.width + 12 + chips.width <= width
        visible: !game.side
        x: 0
        y: 0
        width: game.width
        height: oneRow ? Math.max(switches.height, chips.height) : switches.height + 12 + chips.height

        Row {
            id: switches
            spacing: 12
            Loader { sourceComponent: modeSwitch }
            Loader { sourceComponent: levelSwitch; active: game.vsComputer; visible: active }
        }
        Loader {
            id: chips
            x: header.oneRow ? header.width - width : 0
            y: header.oneRow ? (header.height - height) / 2 : switches.height + 12
            sourceComponent: scoreChips
        }
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

    // Where the board goes under the controls (the upright shapes).
    Item {
        id: area
        visible: false
        y: status.y + status.height + game.gap
        width: game.width
        height: Math.max(0, newRoundButton.y - game.gap - y)
    }

    // ---- Board
    Rectangle {
        id: board
        x: game.side ? 0 : (game.width - width) / 2
        y: game.side ? (game.height - height) / 2 : area.y + (area.height - height) / 2
        width: game.boardWidth
        height: game.rowHeight * game.rows
        radius: Math.min(Theme.radius, game.disc * 0.5)
        color: Theme.surface
        // A disc drops in from above the board's top edge.
        clip: true

        // The holes, and the discs in them.
        Repeater {
            model: game.rows * game.columns
            delegate: Item {
                id: hole
                required property int index
                readonly property int column: index % game.columns
                readonly property int row: Math.floor(index / game.columns)
                readonly property string mark: game.cells[index]
                readonly property bool lit: game.winLine !== null && game.winLine.indexOf(index) >= 0
                x: column * game.colWidth
                y: (game.rows - 1 - row) * game.rowHeight
                width: game.colWidth
                height: game.rowHeight

                Rectangle {
                    anchors.centerIn: parent
                    width: game.disc
                    height: width
                    radius: width / 2
                    color: Theme.sunken
                }
                Rectangle {
                    id: piece
                    anchors.centerIn: parent
                    width: game.disc
                    height: width
                    radius: width / 2
                    visible: hole.mark !== ""
                    color: hole.mark === "X" ? game.xColor : game.oColor
                    opacity: game.over && !hole.lit ? 0.45 : 1
                    Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
                    transform: Translate { id: fall }

                    // The winning four: a white ring inside each disc.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.62
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: Math.max(2, game.disc * 0.08)
                        border.color: "white"
                        visible: hole.lit
                    }
                    // The disc that just landed, so a move made across the
                    // room is easy to find.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.22
                        height: width
                        radius: width / 2
                        color: "white"
                        opacity: 0.85
                        visible: !game.over && game.lastMove === hole.index
                    }
                }
                NumberAnimation {
                    id: drop
                    target: fall
                    property: "y"
                    from: -(game.rows - hole.row) * game.rowHeight
                    to: 0
                    duration: 120 + (game.rows - hole.row) * 55
                    easing.type: Easing.OutBounce
                }
                onMarkChanged: {
                    if (mark !== "")
                        drop.restart()
                    else
                        fall.y = 0
                }
            }
        }

        // The columns: each one a tap target the full height of the board.
        Repeater {
            model: game.columns
            delegate: Item {
                id: lane
                required property int index
                readonly property int target: game.landing(game.cells, index)
                readonly property bool open: target >= 0 && !game.over && !game.computerTurn
                x: index * game.colWidth
                width: game.colWidth
                height: board.height

                Rectangle {
                    anchors.fill: parent
                    color: game.turn === "X" ? game.xColor : game.oColor
                    opacity: laneTap.pressed && lane.open ? 0.12 : 0
                }
                // Where the disc will land, while the column is pressed.
                Rectangle {
                    visible: laneTap.pressed && lane.open
                    x: (game.colWidth - width) / 2
                    y: lane.target < 0 ? 0 : (game.rows - 1 - Math.floor(lane.target / game.columns)) * game.rowHeight
                       + (game.rowHeight - height) / 2
                    width: game.disc
                    height: width
                    radius: width / 2
                    color: game.turn === "X" ? game.xColor : game.oColor
                    opacity: 0.4
                }
                TapHandler {
                    id: laneTap
                    onTapped: game.over ? game.newRound() : game.play(lane.index)
                }
            }
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
