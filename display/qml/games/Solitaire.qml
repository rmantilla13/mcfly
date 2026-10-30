import QtQuick
import QtQuick.Controls
import QtQuick.LocalStorage
import McFly

// Solitaire (Klondike, the traditional patience): build each suit up from
// the ace on the four piles at the top right, moving cards between the
// seven columns in descending runs of alternating colour, a king (or a run
// under one) to an empty column. Tap the deck to turn one card over, or
// three; when it's empty a tap turns the pile back over.
//
// No dragging: a tap moves a card, and every card on it, to the best place
// it can go (home first for one card, then a column with cards in it, then
// an empty one). Each column is one tap target the width of a card and the
// height of the column, so a tap on a run that can't move tries the column's
// other cards. Undo takes back a move at a time. Once every card is face up,
// the rest go home on their own.
//
// The game in progress is kept in LocalStorage, so the screen saver closing
// the Games tab doesn't lose it, and so are the wins and the fewest moves.
Item {
    id: game

    property bool drawThree: false
    // Each pile's cards, bottom first: 0–51 as SolitaireCard counts them.
    property var stock: []
    property var waste: []
    property var foundations: [[], [], [], []]   // one per suit
    property var tableau: [[], [], [], [], [], [], []]
    // How many cards at the bottom of each column are face down.
    property var hidden: [0, 0, 0, 0, 0, 0, 0]
    property int moves: 0
    // Earlier positions, for Undo.
    property var history: []
    property int wins: 0
    property int fewest: 0   // the fewest moves in a win; 0 before the first
    // The cards that moved last, drawn over the rest while they glide.
    property var lastMoved: []
    // Once every card is face up, one goes home this often.
    property int finishMs: 110
    // Cards glide between piles (not while the game is being set out).
    property bool glide: false
    property bool restoring: false

    readonly property int home: foundations.reduce((n, f) => n + f.length, 0)
    readonly property bool won: home === 52
    readonly property bool finishing: !won && stock.length === 0 && waste.length === 0
                                      && hidden.every(h => h === 0)

    function suitOf(card) { return Math.floor(card / 13) }
    function rankOf(card) { return card % 13 + 1 }
    function isRed(card) { const s = suitOf(card); return s === 1 || s === 2 }

    // ---- Dealing
    // A shuffled deck; the same one for the same seed (the tests' deals).
    function shuffledDeck(seed) {
        const deck = []
        for (let i = 0; i < 52; ++i)
            deck.push(i)
        let s = (seed || 0) >>> 0
        const random = seed === undefined ? Math.random
                                          : () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296
        for (let i = 51; i > 0; --i) {
            const j = Math.floor(random() * (i + 1))
            const t = deck[i]
            deck[i] = deck[j]
            deck[j] = t
        }
        return deck
    }
    function deal(seed) {
        const deck = shuffledDeck(seed)
        const columns = []
        for (let c = 0; c < 7; ++c)
            columns.push(deck.splice(0, c + 1))
        tableau = columns
        hidden = [0, 1, 2, 3, 4, 5, 6]
        stock = deck
        waste = []
        foundations = [[], [], [], []]
        moves = 0
        history = []
        lastMoved = []
        saveGame()
    }
    onDrawThreeChanged: {
        if (restoring)
            return
        remember("drawThree", drawThree ? 1 : 0)
        deal()
    }

    // ---- Rules
    function fitsHome(card) {
        return foundations[suitOf(card)].length === rankOf(card) - 1
    }
    function fitsColumn(card, column) {
        const t = tableau[column]
        if (!t.length)
            return rankOf(card) === 13
        const top = t[t.length - 1]
        return rankOf(top) === rankOf(card) + 1 && isRed(top) !== isRed(card)
    }
    // A pile: { kind: "w" } the waste, { kind: "f", i } a home pile,
    // { kind: "t", i } a column.
    function cardsOf(pile) {
        return pile.kind === "w" ? waste : pile.kind === "f" ? foundations[pile.i] : tableau[pile.i]
    }
    // Where the top `count` cards of `from` go best, or null.
    function destinationFor(from, count) {
        const src = cardsOf(from)
        if (count < 1 || count > src.length)
            return null
        const card = src[src.length - count]
        if (count === 1 && from.kind !== "f" && fitsHome(card))
            return { kind: "f", i: suitOf(card) }
        let empty = null
        for (let c = 0; c < 7; ++c) {
            if ((from.kind === "t" && from.i === c) || !fitsColumn(card, c))
                continue
            if (tableau[c].length)
                return { kind: "t", i: c }
            if (empty === null)
                empty = { kind: "t", i: c }
        }
        // A king to an empty column, unless it's the whole of one already.
        if (empty && !(from.kind === "t" && src.length === count))
            return empty
        return null
    }

    // ---- Moves. Every pile is a new array after a move, so the earlier
    // positions in `history` stay as they were.
    function snapshot() {
        return { stock: stock, waste: waste, foundations: foundations, tableau: tableau, hidden: hidden, moves: moves }
    }
    function copyState() {
        return { stock: stock.slice(), waste: waste.slice(), foundations: foundations.map(f => f.slice()),
                 tableau: tableau.map(t => t.slice()), hidden: hidden.slice(), moves: moves + 1 }
    }
    function setState(s) {
        stock = s.stock
        waste = s.waste
        foundations = s.foundations
        tableau = s.tableau
        hidden = s.hidden
        moves = s.moves
    }
    function commit(s, moved) {
        history = history.concat([snapshot()]).slice(-300)
        setState(s)
        lastMoved = moved
        saveGame()
    }
    function moveRun(from, count, to) {
        const s = copyState()
        const pileIn = p => p.kind === "w" ? s.waste : p.kind === "f" ? s.foundations[p.i] : s.tableau[p.i]
        const src = pileIn(from)
        const cards = src.splice(src.length - count, count)
        pileIn(to).push(...cards)
        // Turn the column's new top card face up.
        if (from.kind === "t" && s.hidden[from.i] >= src.length)
            s.hidden[from.i] = Math.max(0, src.length - 1)
        commit(s, cards)
        return true
    }
    // The deck: turn one card (or three) onto the waste, or, when it's
    // empty, turn the waste back over.
    function draw() {
        if (won || finishing)
            return false
        const s = copyState()
        const turned = []
        if (s.stock.length) {
            for (let k = Math.min(drawThree ? 3 : 1, s.stock.length); k > 0; --k) {
                turned.push(s.stock.pop())
                s.waste.push(turned[turned.length - 1])
            }
        } else if (s.waste.length) {
            s.stock = s.waste.reverse()
            s.waste = []
        } else {
            return false
        }
        commit(s, turned)
        return true
    }
    function tapWaste() {
        if (!waste.length || won)
            return false
        const to = destinationFor({ kind: "w" }, 1)
        return to ? moveRun({ kind: "w" }, 1, to) : false
    }
    function tapHome(suit) {
        if (!foundations[suit].length || won)
            return false
        const to = destinationFor({ kind: "f", i: suit }, 1)
        return to ? moveRun({ kind: "f", i: suit }, 1, to) : false
    }
    // A tap on column `column` at its card `index`: that card and the ones
    // on it if they can go somewhere, else the top card, else any other run
    // in the column, the longest first.
    function tapColumn(column, index) {
        const t = tableau[column]
        if (won || !t.length)
            return false
        const top = t.length - 1, first = hidden[column]
        const order = [Math.max(first, Math.min(top, index)), top]
        for (let i = first; i <= top; ++i)
            order.push(i)
        const from = { kind: "t", i: column }
        const tried = {}
        for (const i of order) {
            if (tried[i])
                continue
            tried[i] = true
            const to = destinationFor(from, t.length - i)
            if (to)
                return moveRun(from, t.length - i, to)
        }
        return false
    }
    function undo() {
        if (!history.length || won)
            return false
        setState(history[history.length - 1])
        history = history.slice(0, -1)
        lastMoved = []
        saveGame()
        return true
    }
    // With every card face up, the lowest card that fits goes home.
    function finishStep() {
        if (!finishing)
            return
        let pick = -1
        for (let c = 0; c < 7; ++c) {
            const t = tableau[c]
            if (t.length && fitsHome(t[t.length - 1])
                    && (pick < 0 || rankOf(t[t.length - 1]) < rankOf(tableau[pick][tableau[pick].length - 1])))
                pick = c
        }
        if (pick < 0)
            return
        const s = copyState()
        s.moves = moves // going home on its own isn't a move
        const card = s.tableau[pick].pop()
        s.foundations[suitOf(card)].push(card)
        setState(s)
        lastMoved = [card]
        saveGame()
    }
    Timer {
        interval: game.finishMs
        repeat: true
        running: game.finishing
        onTriggered: game.finishStep()
    }
    onWonChanged: {
        if (!won || restoring)
            return
        wins += 1
        remember("wins", wins)
        if (!fewest || moves < fewest) {
            fewest = moves
            remember("fewest", fewest)
        }
    }

    // ---- LocalStorage: the game in progress, the wins, the fewest moves
    function database() {
        try {
            const db = LocalStorage.openDatabaseSync("McFlySolitaire", "1.0", "Solitaire progress", 100000)
            db.transaction(tx => tx.executeSql("CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT)"))
            return db
        } catch (e) {
            console.warn("Solitaire: progress is not saved:", e)
            return null
        }
    }
    function remember(key, value) {
        const db = database()
        if (!db)
            return
        try {
            db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO kv VALUES (?, ?)", [key, String(value)]))
        } catch (e) {
            console.warn("Solitaire: could not save:", e)
        }
    }
    function saveGame() {
        if (!restoring)
            remember("game", won ? "" : JSON.stringify({ stock: stock, waste: waste, foundations: foundations,
                                                          tableau: tableau, hidden: hidden, moves: moves }))
    }
    // A saved game, if it holds every card once and nothing else.
    function validGame(g) {
        if (!g || !Array.isArray(g.stock) || !Array.isArray(g.waste) || !Array.isArray(g.foundations)
                || g.foundations.length !== 4 || !Array.isArray(g.tableau) || g.tableau.length !== 7
                || !Array.isArray(g.hidden) || g.hidden.length !== 7)
            return false
        const all = g.stock.concat(g.waste, ...g.foundations, ...g.tableau)
        if (all.length !== 52 || new Set(all).size !== 52 || all.some(c => !(c >= 0 && c < 52 && c % 1 === 0)))
            return false
        return g.tableau.every((t, c) => g.hidden[c] >= 0 && (t.length ? g.hidden[c] < t.length : g.hidden[c] === 0))
    }
    function restore() {
        const db = database()
        const saved = {}
        if (db) {
            try {
                db.readTransaction(tx => {
                    const rows = tx.executeSql("SELECT key, value FROM kv").rows
                    for (let i = 0; i < rows.length; ++i)
                        saved[rows.item(i).key] = rows.item(i).value
                })
            } catch (e) {
                console.warn("Solitaire: could not read progress:", e)
            }
        }
        restoring = true
        wins = Number(saved.wins) || 0
        fewest = Number(saved.fewest) || 0
        drawThree = saved.drawThree === "1"
        let g = null
        try {
            g = saved.game ? JSON.parse(saved.game) : null
        } catch (e) {
            g = null
        }
        if (validGame(g)) {
            setState({ stock: g.stock, waste: g.waste, foundations: g.foundations, tableau: g.tableau,
                       hidden: g.hidden, moves: Number(g.moves) || 0 })
            restoring = false
        } else {
            restoring = false
            deal()
        }
    }
    Component.onCompleted: {
        restore()
        settled.start()
    }
    // Cards glide once the table is set out (a timer, not Qt.callLater, so a
    // game closed straight away takes it with it).
    Timer {
        id: settled
        interval: 0
        onTriggered: game.glide = true
    }

    // ---- Shape. Wide and short (the 7" panel, the 10.1", a TV): the
    // table on the left and the controls in a column beside it. Upright:
    // the controls on top. The table is the deck, the waste, a space and the
    // four home piles in a row, and the seven columns under them.
    readonly property bool side: width > height * 1.25
    readonly property real gap: Theme.spacing
    readonly property real sideWidth: side ? Math.min(360, Math.max(250, width * 0.22)) : width
    readonly property real tableX: 0
    readonly property real tableY: side ? 0 : header.y + header.height + gap
    readonly property real tableWidth: side ? width - sideWidth - gap : width
    readonly property real tableHeight: Math.max(0, height - tableY)
    readonly property real slot: Math.min(tableWidth / 7, tableHeight / 2.7 / 1.4 / 0.9)
    readonly property real cardWidth: slot * 0.9
    readonly property real cardHeight: cardWidth * 1.4
    readonly property real tableLeft: tableX + (tableWidth - 7 * slot) / 2
    readonly property real rowGap: Math.max(8, cardHeight * 0.12)
    readonly property real columnsTop: tableY + cardHeight + rowGap
    readonly property real columnsHeight: Math.max(cardHeight, tableY + tableHeight - columnsTop)
    // Draw three fans the top three cards of the waste, the rank and suit of
    // each showing.
    readonly property real wasteStep: slot * 0.4

    function slotX(i) { return tableLeft + i * slot + (slot - cardWidth) / 2 }
    // How far apart a column's face-down and face-up cards sit, squeezed so
    // the column fits.
    function spacing(column) {
        const n = tableau[column].length, down = hidden[column], open = n - down
        const room = columnsHeight - cardHeight
        let d = cardHeight * 0.1, o = cardHeight * 0.27
        if (down * d + Math.max(0, open - 1) * o > room && open > 1)
            o = Math.max(cardHeight * 0.17, (room - down * d) / (open - 1))
        if (down * d + Math.max(0, open - 1) * o > room && down > 0)
            d = Math.max(cardHeight * 0.04, (room - Math.max(0, open - 1) * o) / down)
        if (down * d + Math.max(0, open - 1) * o > room && open > 1)
            o = Math.max(0, (room - down * d) / (open - 1))
        return { down: d, open: o }
    }
    // Where every card is drawn, by card: x, y, stacking order and face up.
    readonly property var places: placeCards()
    function placeCards() {
        const out = []
        const top = tableY
        stock.forEach((c, i) => out[c] = { x: slotX(0), y: top, z: i, up: false })
        const fanFrom = drawThree ? Math.max(0, waste.length - 3) : waste.length
        waste.forEach((c, i) => out[c] = { x: slotX(1) + Math.max(0, i - fanFrom) * wasteStep, y: top, z: i, up: true })
        foundations.forEach((f, s) => f.forEach((c, i) => out[c] = { x: slotX(3 + s), y: top, z: i, up: true }))
        tableau.forEach((t, column) => {
            const gaps = spacing(column), down = hidden[column]
            t.forEach((c, i) => out[c] = {
                x: slotX(column),
                y: columnsTop + Math.min(i, down) * gaps.down + Math.max(0, i - down) * gaps.open,
                z: i,
                up: i >= down
            })
        })
        return out
    }
    // The card in column `column` under a point `y` down the table.
    function indexAt(column, y) {
        const t = tableau[column]
        let found = 0
        for (let i = 0; i < t.length; ++i) {
            if (places[t[i]] && places[t[i]].y <= y)
                found = i
        }
        return found
    }

    readonly property string statusText: won ? qsTr("You win!")
        : finishing ? qsTr("Going home…")
        : moves === 0 ? qsTr("Tap a card to move it")
        : qsTr("%1 of 52 home").arg(home)

    // ---- Controls: undo, a new game, how many to draw, and the score
    Component {
        id: buttons
        Row {
            spacing: 12
            IconButton {
                objectName: "solitaire:undo"
                icon: "undo"
                enabled: game.history.length > 0 && !game.won && !game.finishing
                onClicked: game.undo()
            }
            IconButton {
                objectName: "solitaire:new"
                icon: "refresh"
                fill: game.won ? Glass.primary : Theme.surface
                ink: game.won ? "white" : Theme.text
                onClicked: game.deal()
            }
        }
    }
    Component {
        id: drawSwitch
        SegmentedControl {
            options: [qsTr("Draw 1"), qsTr("Draw 3")]
            currentIndex: game.drawThree ? 1 : 0
            onSelected: index => game.drawThree = index === 1
        }
    }
    Component {
        id: scoreChips
        Row {
            spacing: 12
            Repeater {
                model: [{ label: qsTr("Moves"), value: game.moves },
                        { label: qsTr("Wins"), value: game.wins }]
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
                            color: Theme.textMuted
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

    Column {
        id: stack
        visible: game.side
        x: game.width - game.sideWidth
        y: 0
        width: game.sideWidth
        spacing: Math.max(4, Math.min(game.gap, (game.height - 56 - 64 * 3 - 60) / 3))
        Label {
            width: parent.width
            height: 56
            verticalAlignment: Text.AlignVCenter
            text: game.statusText
            color: game.won ? Theme.success : Theme.text
            font.pixelSize: Theme.fontMd
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Loader { sourceComponent: buttons }
        Loader { sourceComponent: drawSwitch }
        Loader { sourceComponent: scoreChips }
    }
    Flow {
        id: header
        visible: !game.side
        x: 0
        y: 0
        width: game.width
        spacing: 12
        Label {
            height: 64
            verticalAlignment: Text.AlignVCenter
            text: game.statusText
            color: game.won ? Theme.success : Theme.text
            font.pixelSize: Theme.fontLg
            font.weight: Font.DemiBold
        }
        Loader { sourceComponent: buttons }
        Loader { sourceComponent: drawSwitch }
        Loader { sourceComponent: scoreChips }
    }

    // ---- The table
    // Where piles go when they're empty.
    Repeater {
        model: 7
        delegate: Rectangle {
            required property int index
            readonly property bool isHome: index >= 3
            visible: index !== 2
            x: game.slotX(index)
            y: game.tableY
            width: game.cardWidth
            height: game.cardHeight
            radius: Math.min(Theme.radiusSm, width * 0.1)
            color: Theme.sunken
            CardSuit {
                visible: parent.isHome
                anchors.centerIn: parent
                width: parent.width * 0.42
                height: width
                suit: parent.index - 3
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
            }
            // The deck, turned back over on a tap.
            Icon {
                visible: parent.index === 0 && game.stock.length === 0 && game.waste.length > 0
                anchors.centerIn: parent
                name: "refresh"
                size: Math.min(36, parent.width * 0.45)
                color: Theme.textMuted
            }
        }
    }
    Repeater {
        model: 7
        delegate: Rectangle {
            required property int index
            x: game.slotX(index)
            y: game.columnsTop
            width: game.cardWidth
            height: game.cardHeight
            radius: Math.min(Theme.radiusSm, width * 0.1)
            color: "transparent"
            border.width: 2
            border.color: Theme.sunken
        }
    }

    // The cards.
    Repeater {
        model: 52
        delegate: SolitaireCard {
            required property int index
            readonly property var at: game.places[index] || ({ x: 0, y: 0, z: 0, up: false })
            card: index
            up: at.up
            x: at.x
            y: at.y
            z: at.z + (game.lastMoved.indexOf(index) >= 0 ? 100 : 0)
            width: game.cardWidth
            height: game.cardHeight
            Behavior on x { enabled: game.glide; NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: game.glide; NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
        }
    }

    // The tap targets, over the cards: the deck, the waste, the home piles
    // and the columns.
    Item {
        objectName: "tap:stock"
        x: game.tableLeft
        y: game.tableY
        width: game.slot
        height: game.cardHeight
        z: 200
        TapHandler { onTapped: game.draw() }
    }
    Item {
        objectName: "tap:waste"
        x: game.tableLeft + game.slot
        y: game.tableY
        width: game.slot * 2
        height: game.cardHeight
        z: 200
        TapHandler { onTapped: game.tapWaste() }
    }
    Repeater {
        model: 4
        delegate: Item {
            required property int index
            objectName: "tap:home"
            x: game.tableLeft + (3 + index) * game.slot
            y: game.tableY
            width: game.slot
            height: game.cardHeight
            z: 200
            TapHandler { onTapped: game.tapHome(parent.index) }
        }
    }
    Repeater {
        model: 7
        delegate: Item {
            id: lane
            required property int index
            objectName: "tap:column"
            x: game.tableLeft + index * game.slot
            y: game.columnsTop
            width: game.slot
            height: game.columnsHeight
            z: 200
            TapHandler {
                onTapped: eventPoint => game.tapColumn(lane.index, game.indexAt(lane.index, lane.y + eventPoint.position.y))
            }
        }
    }
}
