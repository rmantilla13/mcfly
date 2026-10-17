import QtQuick
import QtQuick.Controls
import QtQuick.LocalStorage
import QtQuick.Shapes
import McFly
import "scoops.js" as Scoops

// Scoop Shop: an ice cream counter against the clock, for one player, who
// picks who works the shift: Pip the penguin or Lotl the axolotl. Customers
// come to the counter with a ticket: a cone or a cup, the scoops from the
// bottom up, and toppings. Tap the pieces to build it, then tap the
// customer to hand it over before their patience runs out. A right order
// scores, more the quicker it is; a wrong one, or a customer who gives up,
// costs one of three hearts. Every five served it gets busier: more seats,
// bigger orders, less time (scoops.js has the rules).
//
// One clock, a Timer stepping advance() while a shift is on and not paused;
// GamesScreen pauses it while how to play or the assistant panel covers it.
// The best score and who worked last are kept in LocalStorage, written when
// a shift ends (and when the game closes), never on a tap.
Item {
    id: game

    // ---- The shift
    // "ready" (choosing who works), "playing" or "over".
    property string phase: "ready"
    property bool paused: false
    property string worker: "pip"
    property int score: 0
    property int best: 0
    property bool newBest: false
    property int hearts: Scoops.HEARTS
    property int served: 0
    readonly property int level: Scoops.level(served)
    readonly property var rules: Scoops.rules(level)
    readonly property bool playing: phase === "playing" && !paused
    // The shop shows while it's open and not paused (no peeking at tickets).
    readonly property bool showing: playing
    // Shift time in ms; it runs only while playing.
    property real now: 0
    property real nextArrival: 0
    // The seats at the counter: a customer or null. A customer is { id,
    // order, kind, arrived, patience, gone, goneAt, points }: `gone` is ""
    // while they wait, then "right", "wrong" or "late" as they leave.
    property var seats: [null, null, null, null]
    property int nextId: 1
    // The treat being made: { base, scoops (bottom up), toppings }.
    property var build: emptyBuild()
    // A word over the treat when a tap can't do anything ("Cone or cup first").
    property string hint: ""
    // How the shopkeeper takes the last delivery: "", "happy" or "oops".
    property string mood: ""
    // A repeatable shift for tests: the generator starts here (0: anywhere).
    property double seed: 0
    property double dice: 1
    // Tests turn the clock off and call advance() themselves.
    property bool autoClock: true
    readonly property int leaveMs: 700

    readonly property var kinds: ["bear", "bunny", "cat", "frog", "chick"]
    readonly property var tints: ({ bear: "#C49A6C", bunny: "#EEE6F4", cat: "#F3B36B", frog: "#86CF7E", chick: "#F7D65A" })
    readonly property var names: ({
        cone: qsTr("Cone"), cup: qsTr("Cup"), vanilla: qsTr("Vanilla"), chocolate: qsTr("Chocolate"),
        strawberry: qsTr("Strawberry"), mint: qsTr("Mint"), sprinkles: qsTr("Sprinkles"),
        cherry: qsTr("Cherry"), wafer: qsTr("Wafer"), undo: qsTr("Undo")
    })

    function emptyBuild() { return { base: "", scoops: [], toppings: [] } }

    // mulberry32 (scoops.js), its state kept here.
    function random() {
        dice = Scoops.next(dice)
        return Scoops.unit(dice)
    }
    // For tests: an order for `lv`, from a generator started at `s`.
    function orderFor(lv, s) { return Scoops.makeOrder(lv, Scoops.random(s)) }
    function rulesFor(lv) { return Scoops.rules(lv) }
    function patienceFor(order, lv) { return Scoops.patience(order, lv) }
    function pointsFor(order, left) { return Scoops.points(order, left) }

    function start(who) {
        if (who === "pip" || who === "lotl")
            worker = who
        remember("worker", worker)
        score = 0
        served = 0
        hearts = Scoops.HEARTS
        newBest = false
        now = 0
        nextArrival = 1000
        nextId = 1
        seats = [null, null, null, null]
        build = emptyBuild()
        hint = ""
        mood = ""
        dice = seed > 0 ? seed : Math.floor(Math.random() * 4294967296)
        paused = false
        phase = "playing"
    }
    function pause() {
        if (phase === "playing")
            paused = true
    }
    function resume() { paused = false }

    // Moves the shift on by `ms`, a tenth of a second at a time.
    function advance(ms) {
        while (ms > 0 && playing) {
            const step = Math.min(100, ms)
            ms -= step
            now += step
            tick()
        }
    }
    function customer(order) {
        return { id: nextId++, order: order, kind: kinds[Math.floor(random() * kinds.length)], arrived: now,
                 patience: Scoops.patience(order, level), gone: "", goneAt: 0, points: 0 }
    }
    function leaving(c, how, points) {
        return Object.assign({}, c, { gone: how, goneAt: now, points: points })
    }
    function tick() {
        const next = seats.slice()
        let changed = false, late = 0
        for (let i = 0; i < next.length; ++i) {
            const c = next[i]
            if (!c)
                continue
            if (c.gone && now - c.goneAt >= leaveMs) {
                next[i] = null
                changed = true
            } else if (!c.gone && now - c.arrived >= c.patience) {
                next[i] = leaving(c, "late", 0)
                changed = true
                ++late
            }
        }
        // Nobody waiting: the next one comes in soon.
        if (!next.some(c => c && !c.gone))
            nextArrival = Math.min(nextArrival, now + 1200)
        if (now >= nextArrival) {
            const free = []
            for (let i = 0; i < rules.seats; ++i) {
                if (!next[i])
                    free.push(i)
            }
            if (free.length) {
                next[free[Math.floor(random() * free.length)]] = customer(Scoops.makeOrder(level, random))
                changed = true
                nextArrival = now + rules.arrival
            } else {
                nextArrival = now + 400 // someone's at the door
            }
        }
        if (changed)
            seats = next
        if (late)
            loseHearts(late)
    }
    // For tests: a customer with this order in seat `index`. Returns how
    // long they will wait.
    function seat(index, order) {
        if (phase !== "playing")
            return 0
        const next = seats.slice()
        next[index] = customer(order)
        seats = next
        return next[index].patience
    }

    // ---- Making the treat
    function pickBase(base) {
        if (!playing || Scoops.BASES.indexOf(base) < 0)
            return false
        build = { base: base, scoops: build.scoops, toppings: build.toppings }
        hint = ""
        return true
    }
    function addScoop(flavour) {
        if (!playing || Scoops.FLAVOURS.indexOf(flavour) < 0)
            return false
        if (!build.base)
            return nudge(qsTr("Cone or cup first"))
        if (build.scoops.length >= Scoops.MAX_SCOOPS)
            return nudge(qsTr("Three scoops at most"))
        build = { base: build.base, scoops: build.scoops.concat([flavour]), toppings: build.toppings }
        hint = ""
        return true
    }
    function addTopping(topping) {
        if (!playing || Scoops.TOPPINGS.indexOf(topping) < 0)
            return false
        if (!build.scoops.length)
            return nudge(qsTr("A scoop first"))
        if (build.toppings.indexOf(topping) >= 0)
            return false
        build = { base: build.base, scoops: build.scoops, toppings: build.toppings.concat([topping]) }
        hint = ""
        return true
    }
    // Takes off what's on top: a topping, else a scoop, else the cone or cup.
    function undo() {
        if (!playing)
            return false
        const b = build
        if (b.toppings.length)
            build = { base: b.base, scoops: b.scoops, toppings: b.toppings.slice(0, -1) }
        else if (b.scoops.length)
            build = { base: b.base, scoops: b.scoops.slice(0, -1), toppings: [] }
        else if (b.base)
            build = emptyBuild()
        else
            return false
        hint = ""
        return true
    }
    function nudge(text) {
        hint = text
        hintTimer.restart()
        return false
    }
    function tapped(key) {
        if (key === "undo")
            return undo()
        if (Scoops.BASES.indexOf(key) >= 0)
            return pickBase(key)
        if (Scoops.FLAVOURS.indexOf(key) >= 0)
            return addScoop(key)
        return addTopping(key)
    }

    // Hands the treat to the customer in seat `index`. Returns "right",
    // "wrong", or "" when nothing changed hands.
    function deliver(index) {
        if (!playing)
            return ""
        const c = seats[index]
        if (!c || c.gone)
            return ""
        if (!build.base) {
            nudge(qsTr("Make their order first"))
            return ""
        }
        const right = Scoops.matches(c.order, build)
        const next = seats.slice()
        if (right) {
            const points = Scoops.points(c.order, 1 - (now - c.arrived) / c.patience)
            score += points
            served += 1
            next[index] = leaving(c, "right", points)
        } else {
            next[index] = leaving(c, "wrong", 0)
        }
        seats = next
        build = emptyBuild()
        hint = ""
        if (right)
            react("happy")
        else
            loseHearts(1)
        return right ? "right" : "wrong"
    }
    function loseHearts(n) {
        hearts = Math.max(0, hearts - n)
        react("oops")
        if (hearts === 0)
            endShift()
    }
    function react(how) {
        mood = ""
        mood = how
        moodTimer.restart()
    }
    function endShift() {
        if (phase !== "playing")
            return
        phase = "over"
        paused = false
        if (score > best) {
            best = score
            newBest = true
        }
        remember("best", best)
    }

    // "Level 3: busier!" over the treat for a moment, clear of the tickets.
    property string news: ""
    onLevelChanged: {
        if (phase === "playing" && level > 1) {
            news = qsTr("Level %1: busier!").arg(level)
            newsTimer.restart()
        }
    }

    // ---- The best score and who worked last, in LocalStorage
    function database() {
        try {
            const db = LocalStorage.openDatabaseSync("McFlyScoopShop", "1.0", "Scoop Shop best score", 10000)
            db.transaction(tx => tx.executeSql("CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT)"))
            return db
        } catch (e) {
            console.warn("Scoop Shop: the best score is not saved:", e)
            return null
        }
    }
    function restore() {
        const db = database()
        if (!db)
            return
        try {
            db.readTransaction(tx => {
                const rows = tx.executeSql("SELECT key, value FROM kv").rows
                for (let i = 0; i < rows.length; ++i) {
                    const row = rows.item(i)
                    if (row.key === "best")
                        best = Number(row.value) || 0
                    else if (row.key === "worker" && (row.value === "pip" || row.value === "lotl"))
                        worker = row.value
                }
            })
        } catch (e) {
            console.warn("Scoop Shop: could not read the best score:", e)
        }
    }
    function remember(key, value) {
        const db = database()
        if (!db)
            return
        try {
            db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO kv VALUES (?, ?)", [key, String(value)]))
        } catch (e) {
            console.warn("Scoop Shop: could not save:", e)
        }
    }
    Component.onCompleted: restore()
    // Closed mid-shift (the tab left, the screen saver): a higher score still counts.
    Component.onDestruction: if (score > best) remember("best", score)

    Timer {
        id: clock
        interval: 100
        repeat: true
        running: game.autoClock && game.playing
        property double last: 0
        onRunningChanged: last = Date.now()
        onTriggered: {
            const t = Date.now()
            game.advance(Math.min(250, t - last))
            last = t
        }
    }
    Timer { id: hintTimer; interval: 1600; onTriggered: game.hint = "" }
    Timer { id: newsTimer; interval: 2000; onTriggered: game.news = "" }
    Timer { id: moodTimer; interval: 900; onTriggered: game.mood = "" }

    // ---- Layout
    //
    // Three shapes, from the stage alone (plain geometry, so they can switch):
    //   side    much wider than tall (the 7" panel): the counter over the
    //           buttons, the score and the treat in a column beside them;
    //   tall    portrait: the score, the counter, the treat, the buttons;
    //   square  the rest: the counter over the treat and the buttons, side by side.
    readonly property real gap: Theme.spacing
    readonly property real padGap: Theme.mini ? 8 : 12
    readonly property var geo: layout(width, height)
    readonly property string shape: geo.shape

    function layout(w, h) {
        const g = gap, pg = padGap, t = Theme.touchTarget
        if (w > h * 1.4) {
            const sw = Math.round(Math.min(300, Math.max(200, w * 0.28)))
            const lw = w - sw - g
            const bh = Math.max(t, Math.min(96, Math.floor((h - g) * 0.22)))
            const ph = 2 * bh + pg
            return {
                shape: "side",
                hud: { x: lw + g, y: 0, w: sw, h: t },
                counter: { x: 0, y: 0, w: lw, h: h - ph - g },
                station: { x: lw + g, y: t + g, w: sw, h: h - t - g },
                pad: { x: 0, y: h - ph, w: lw, h: ph, bw: (lw - 5 * pg) / 6, bh: bh }
            }
        }
        const top = t + g
        if (h > w * 1.25) {
            const bw = (w - 3 * pg) / 4
            const bh = Math.max(t, Math.min(104, Math.floor(bw * 0.75)))
            const ph = 3 * bh + 2 * pg
            const ch = Math.max(150, Math.min(w / 4 * 1.75, h - top - g - ph - g - 200))
            return {
                shape: "tall",
                hud: { x: 0, y: 0, w: w, h: t },
                counter: { x: 0, y: top, w: w, h: ch },
                station: { x: 0, y: top + ch + g, w: w, h: Math.max(0, h - top - ch - g - ph - g) },
                pad: { x: 0, y: h - ph, w: w, h: ph, bw: bw, bh: bh }
            }
        }
        const slot = Math.min(w / 4, 320)
        const pw = Math.min(w * 0.6, 4 * 180 + 3 * pg)
        const ch = Math.max(150, Math.min(slot * 1.6, h - top - g - (3 * t + 2 * pg)))
        const sh = Math.max(0, h - top - ch - g)
        const bh = Math.max(t, Math.min(110, Math.floor((sh - 2 * pg) / 3)))
        const ph = 3 * bh + 2 * pg
        return {
            shape: "square",
            hud: { x: 0, y: 0, w: w, h: t },
            counter: { x: 0, y: top, w: w, h: ch },
            station: { x: 0, y: top + ch + g, w: Math.max(0, w - pw - g), h: sh },
            pad: { x: w - pw, y: h - ph, w: pw, h: ph, bw: (pw - 3 * pg) / 4, bh: bh }
        }
    }

    // The buttons: [key, column, row, columns spanned] in the side shape's
    // 6 × 2 grid and the others' 4 × 3.
    readonly property var keys: shape === "side"
        ? [["cone", 0, 0, 1], ["cup", 1, 0, 1], ["vanilla", 2, 0, 1], ["chocolate", 3, 0, 1], ["strawberry", 4, 0, 1],
           ["mint", 5, 0, 1], ["sprinkles", 0, 1, 1], ["cherry", 1, 1, 1], ["wafer", 2, 1, 1], ["undo", 5, 1, 1]]
        : [["cone", 0, 0, 2], ["cup", 2, 0, 2], ["vanilla", 0, 1, 1], ["chocolate", 1, 1, 1], ["strawberry", 2, 1, 1],
           ["mint", 3, 1, 1], ["sprinkles", 0, 2, 1], ["cherry", 1, 2, 1], ["wafer", 2, 2, 1], ["undo", 3, 2, 1]]

    // ---- The score, the best, the level, hearts and pause
    Item {
        id: hud
        visible: game.showing
        x: game.geo.hud.x
        y: game.geo.hud.y
        width: game.geo.hud.w
        height: game.geo.hud.h
        readonly property bool narrow: game.shape === "side"

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacing + 8
            visible: !hud.narrow
            Repeater {
                model: [{ label: qsTr("Score"), value: game.score }, { label: qsTr("Best"), value: Math.max(game.best, game.score) },
                        { label: qsTr("Level"), value: game.level }]
                delegate: Column {
                    required property var modelData
                    Label {
                        text: modelData.label
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontXs
                    }
                    Label {
                        text: modelData.value
                        color: Theme.text
                        font.pixelSize: Theme.fontLg
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
        // Beside the counter: the score over the hearts.
        Column {
            anchors.verticalCenter: parent.verticalCenter
            visible: hud.narrow
            spacing: 4
            Row {
                spacing: 8
                Label {
                    anchors.baseline: scoreValue.baseline
                    text: qsTr("Score")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                }
                Label {
                    id: scoreValue
                    text: game.score
                    color: Theme.text
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.DemiBold
                }
            }
            Row {
                spacing: 8
                Hearts { size: 20 }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Level %1").arg(game.level)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                }
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacing
            Hearts {
                anchors.verticalCenter: parent.verticalCenter
                visible: !hud.narrow
                size: 30
            }
            IconButton {
                objectName: "tap:pause"
                icon: "pause"
                fill: Theme.surface
                enabled: game.playing
                onClicked: game.pause()
            }
        }
    }

    // ---- The counter: a seat for each customer, a ticket over their head.
    Item {
        id: counter
        visible: game.showing
        x: game.geo.counter.x
        y: game.geo.counter.y
        width: game.geo.counter.w
        height: game.geo.counter.h
        readonly property real slotWidth: game.shape === "side" ? width / Scoops.MAX_SEATS : Math.min(width / Scoops.MAX_SEATS, 320)
        readonly property real slotsX: (width - slotWidth * Scoops.MAX_SEATS) / 2
        readonly property real critterHeight: Math.min(slotWidth * 0.62, height * (game.shape === "side" ? 0.3 : 0.36))
        readonly property real band: Math.round(critterHeight * 0.3)

        Repeater {
            model: Scoops.MAX_SEATS
            delegate: Item {
                id: seat
                required property int index
                readonly property var customer: game.seats[index]
                readonly property int customerId: customer ? customer.id : 0
                readonly property string gone: customer ? customer.gone : ""
                readonly property bool open: index < game.rules.seats
                // Patience left, 1 down to 0.
                readonly property real patienceLeft: customer && !gone
                                             ? Math.max(0, 1 - (game.now - customer.arrived) / customer.patience) : 0
                readonly property real pad: Theme.mini ? 6 : 10
                property real arrive: 1
                property real leave: 0
                objectName: open ? "tap:seat" + index : ""
                x: counter.slotsX + index * counter.slotWidth
                width: counter.slotWidth
                height: counter.height

                onCustomerIdChanged: if (customerId > 0 && !gone) arriveAnim.restart()
                onGoneChanged: {
                    if (gone) {
                        leaveAnim.restart()
                    } else {
                        leaveAnim.stop()
                        leave = 0
                    }
                }
                NumberAnimation { id: arriveAnim; target: seat; property: "arrive"; from: 0; to: 1; duration: Theme.enter; easing.type: Easing.OutCubic }
                NumberAnimation { id: leaveAnim; target: seat; property: "leave"; from: 0; to: 1; duration: game.leaveMs - 100; easing.type: Easing.InQuad }

                // The ticket: what they'd like, and how long they'll wait.
                Rectangle {
                    id: ticket
                    x: Theme.mini ? 4 : 8
                    width: parent.width - 2 * x
                    height: parent.height - counter.critterHeight - 4
                    radius: Theme.radiusSm
                    color: Theme.surface
                    visible: seat.customer !== null
                    opacity: seat.arrive * (1 - seat.leave)
                    border.width: seat.gone === "wrong" || seat.gone === "late" ? 3 : 0
                    border.color: Theme.danger

                    ScoopTreat {
                        // Handed over (or not): the ticket says how it went instead.
                        visible: seat.gone === ""
                        x: seat.pad
                        y: seat.pad
                        width: parent.width - 2 * seat.pad
                        height: patience.y - seat.pad - y
                        base: seat.customer ? seat.customer.order.base : ""
                        scoops: seat.customer ? seat.customer.order.scoops : []
                        toppings: seat.customer ? seat.customer.order.toppings : []
                    }
                    Rectangle {
                        id: patience
                        x: seat.pad + 2
                        y: parent.height - height - seat.pad
                        width: parent.width - 2 * x
                        height: Theme.mini ? 8 : 10
                        radius: height / 2
                        color: Theme.sunken
                        Rectangle {
                            width: parent.width * seat.patienceLeft
                            height: parent.height
                            radius: height / 2
                            color: seat.patienceLeft > 0.5 ? Theme.success : seat.patienceLeft > 0.25 ? Theme.warning : Theme.danger
                        }
                    }
                }
                // The ticket's tail, down to the customer.
                Rectangle {
                    visible: ticket.visible
                    opacity: ticket.opacity
                    x: (parent.width - width) / 2
                    y: ticket.height - height / 2 - 1
                    width: Theme.mini ? 10 : 16
                    height: width
                    rotation: 45
                    color: Theme.surface
                }

                Critter {
                    visible: seat.customer !== null
                    width: counter.critterHeight * 10 / 9
                    height: counter.critterHeight
                    x: (parent.width - width) / 2
                    // Coming up to the counter and going: a little rise and fall behind it.
                    y: parent.height - height + (1 - seat.arrive + seat.leave) * counter.band * 0.6 - counter.band * 0.4
                    opacity: seat.arrive * (1 - seat.leave)
                    kind: seat.customer ? seat.customer.kind : "bear"
                    tint: game.tints[kind] || "#C49A6C"
                    face: seat.gone === "right" ? "happy" : seat.gone ? "cross"
                        : seat.patienceLeft > 0.5 ? "smile" : seat.patienceLeft > 0.25 ? "flat" : "frown"
                }

                // How it went, on the ticket: the points, or what went wrong, rising.
                Label {
                    visible: seat.gone !== ""
                    x: ticket.x + seat.pad
                    width: ticket.width - 2 * seat.pad
                    y: (ticket.height - height) / 2 - seat.leave * ticket.height * 0.2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: seat.gone === "right" ? "+" + (seat.customer ? seat.customer.points : 0)
                        : seat.gone === "wrong" ? qsTr("Wrong order") : qsTr("Too slow")
                    color: seat.gone === "right" ? Theme.success : Theme.danger
                    font.pixelSize: seat.gone === "right" ? Theme.fontXl : Theme.fontMd
                    font.weight: Font.Bold
                    opacity: 1 - seat.leave * seat.leave
                }

                // A seat that opens later.
                Label {
                    visible: !seat.open && game.phase === "playing"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: ticket.height * 0.5
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: qsTr("Opens at level %1").arg(seat.index < 3 ? 3 : 5)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                }

                TapHandler {
                    enabled: seat.customer !== null
                    gesturePolicy: TapHandler.WithinBounds
                    onTapped: game.deliver(seat.index)
                }
            }
        }

        // The counter top, in front of the customers.
        Rectangle {
            y: parent.height - counter.band
            width: parent.width
            height: counter.band
            radius: Math.min(Theme.radiusSm, height / 2)
            color: Theme.surface
            Rectangle {
                x: parent.radius
                width: parent.width - 2 * parent.radius
                height: 4
                color: "#56C3A0"
            }
        }
    }

    // ---- The treat being made, and who's making it
    Rectangle {
        id: station
        visible: game.showing
        x: game.geo.station.x
        y: game.geo.station.y
        width: game.geo.station.w
        height: game.geo.station.h
        radius: Theme.radius
        color: Theme.surface
        readonly property real pad: Theme.mini ? 10 : 16

        Label {
            id: hintLabel
            x: station.pad
            y: station.pad - 2
            width: parent.width - 2 * station.pad
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: game.hint ? game.hint
                : game.news ? game.news
                : !game.build.base ? qsTr("Cone or cup?")
                : !game.build.scoops.length ? qsTr("Now the scoops")
                : qsTr("Tap a customer to serve")
            color: game.hint ? Theme.warningInk : game.news ? Theme.accent : Theme.textMuted
            font.pixelSize: Theme.mini ? Theme.fontXs : Theme.fontSm
            font.weight: game.hint || game.news ? Font.DemiBold : Font.Normal
        }
        ScoopCrew {
            id: crew
            readonly property real room: parent.height - hintLabel.y - hintLabel.height - station.pad
            x: station.pad
            width: Math.min(parent.width * 0.42, room * 0.8)
            height: width * 1.2
            y: parent.height - height - station.pad
            who: game.worker
            mood: game.mood
        }
        ScoopTreat {
            id: treat
            x: crew.x + crew.width
            y: hintLabel.y + hintLabel.height + 4
            width: parent.width - x - station.pad
            height: parent.height - y - station.pad
            base: game.build.base
            scoops: game.build.scoops
            toppings: game.build.toppings
            // A tap that can't do anything shakes it.
            property real shake: 0
            transform: Translate { x: treat.shake * 6 }
            Connections {
                target: game
                function onHintChanged() { if (game.hint) shakeAnim.restart() }
            }
            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: treat; property: "shake"; to: -1; duration: 50 }
                NumberAnimation { target: treat; property: "shake"; to: 1; duration: 100 }
                NumberAnimation { target: treat; property: "shake"; to: 0; duration: 50 }
            }
        }
    }

    // ---- The buttons: cone, cup, the flavours, the toppings, undo
    Item {
        id: pad
        visible: game.showing
        x: game.geo.pad.x
        y: game.geo.pad.y
        width: game.geo.pad.w
        height: game.geo.pad.h

        Repeater {
            model: game.keys
            delegate: PadButton {
                required property var modelData
                key: modelData[0]
                x: modelData[1] * (game.geo.pad.bw + game.padGap)
                y: modelData[2] * (game.geo.pad.bh + game.padGap)
                width: modelData[3] * game.geo.pad.bw + (modelData[3] - 1) * game.padGap
                height: game.geo.pad.bh
            }
        }
    }

    component PadButton: Item {
        id: button
        property string key
        readonly property bool isBase: Scoops.BASES.indexOf(key) >= 0
        readonly property bool isFlavour: Scoops.FLAVOURS.indexOf(key) >= 0
        readonly property bool isTopping: Scoops.TOPPINGS.indexOf(key) >= 0
        readonly property bool chosen: isBase ? game.build.base === key : isTopping && game.build.toppings.indexOf(key) >= 0
        // Not yet: still tappable, to say why.
        readonly property bool ready: isFlavour ? !!game.build.base : isTopping ? game.build.scoops.length > 0 : true
        readonly property bool labelled: height >= 84
        objectName: "tap:" + key
        scale: tap.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Theme.quick } }

        Lens {
            anchors.fill: parent
            kind: button.chosen ? "active" : "rest"
            fill: Theme.surface
            radius: Theme.radiusSm
        }
        Item {
            id: picture
            opacity: button.ready ? 1 : 0.4
            x: 6
            y: 6
            width: parent.width - 12
            height: parent.height - 12 - (button.labelled ? label.height : 0)
            ScoopTreat {
                visible: button.key !== "undo"
                anchors.fill: parent
                base: button.isBase ? button.key : ""
                scoops: button.isFlavour ? [button.key] : []
                toppings: button.isTopping ? [button.key] : []
                units: button.isBase ? (button.key === "cone" ? 5.0 : 4.0) : button.isFlavour ? 3.0 : 3.2
                lift: button.isBase ? 0.25 : button.isFlavour ? 0.3 : 0
            }
            Icon {
                visible: button.key === "undo"
                anchors.centerIn: parent
                name: "undo"
                size: Math.min(32, parent.height * 0.7)
                color: Theme.text
            }
        }
        Label {
            id: label
            visible: button.labelled
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - 8
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: game.names[button.key] || ""
            color: button.chosen ? Glass.ink : Theme.text
            font.pixelSize: Theme.fontXs
            font.weight: Font.Medium
        }
        TapHandler {
            id: tap
            gesturePolicy: TapHandler.WithinBounds
            onTapped: game.tapped(button.key)
        }
    }

    // ---- Hearts: three, and the ones lost dimmed.
    component Hearts: Row {
        id: hearts
        property real size: 24
        spacing: size * 0.2
        Repeater {
            model: Scoops.HEARTS
            delegate: Item {
                required property int index
                width: hearts.size
                height: hearts.size
                Item {
                    width: 24
                    height: 24
                    scale: hearts.size / 24
                    transformOrigin: Item.TopLeft
                    Shape {
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: index < game.hearts ? "#F0566E" : Theme.sunken
                            strokeColor: "transparent"
                            PathSvg { path: "M12 20.5C5.6 16.2 3 13 3 9.6 3 7 5 5 7.5 5c1.8 0 3.4 1 4.5 2.6C13.1 6 14.7 5 16.5 5 19 5 21 7 21 9.6c0 3.4-2.6 6.6-9 10.9z" }
                        }
                    }
                }
            }
        }
    }

    // A part of a customer, on its grid: the unit `c` comes from the critter
    // (or the part) it sits on.
    component Bit: Rectangle {
        property real c: parent ? parent.c || 0 : 0
        property real px
        property real py
        property real pw
        property real ph
        x: px * c
        y: py * c
        width: pw * c
        height: ph * c
        radius: Math.min(width, height) / 2
    }

    // ---- A customer: a round animal face over the counter.
    // A 10 × 9 grid; `face` is smile, flat, frown, happy or cross.
    component Critter: Item {
        id: critter
        property string kind: "bear"
        property color tint: "#C49A6C"
        property string face: "smile"
        readonly property real c: Math.min(width / 10, height / 9)
        readonly property color edge: Qt.darker(tint, 1.3)
        readonly property color ink: "#2B2230"

        Bit { px: 1.6; py: 7.0; pw: 6.8; ph: 3.0; color: Qt.darker(critter.tint, 1.08); border.width: critter.c * 0.12; border.color: critter.edge }
        // Ears, or a frog's eye bumps, or a chick's tuft.
        Repeater {
            model: critter.kind === "bear" ? [2.0, 5.6] : []
            delegate: Bit {
                required property real modelData
                px: modelData; py: 2.0; pw: 2.4; ph: 2.4
                color: critter.tint; border.width: critter.c * 0.12; border.color: critter.edge
                Bit { px: 0.6; py: 0.6; pw: 1.2; ph: 1.2; color: "#F2B8C6" }
            }
        }
        Repeater {
            model: critter.kind === "bunny" ? [[3.0, -12], [5.5, 12]] : []
            delegate: Bit {
                required property var modelData
                px: modelData[0]; py: -0.2; pw: 1.5; ph: 4.2; rotation: modelData[1]
                color: critter.tint; border.width: critter.c * 0.12; border.color: critter.edge
                Bit { px: 0.4; py: 0.5; pw: 0.7; ph: 2.9; color: "#F2B8C6" }
            }
        }
        Shape {
            visible: critter.kind === "cat"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: critter.tint
                strokeColor: critter.edge
                strokeWidth: critter.c * 0.12
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    readonly property real c: critter.c
                    path: "M %1 %2 L %3 %4 L %5 %6 Z M %7 %2 L %8 %4 L %9 %6 Z"
                        .arg(2.3 * c).arg(4.6 * c).arg(2.7 * c).arg(1.2 * c).arg(4.9 * c).arg(3.0 * c)
                        .arg(7.7 * c).arg(7.3 * c).arg(5.1 * c)
                }
            }
        }
        Repeater {
            model: critter.kind === "frog" ? [3.4, 6.6] : []
            delegate: Bit {
                required property real modelData
                px: modelData - 1.3; py: 1.9; pw: 2.6; ph: 2.6
                color: critter.tint; border.width: critter.c * 0.12; border.color: critter.edge
                Bit { px: 0.5; py: 0.5; pw: 1.6; ph: 1.6; color: "white" }
                Bit {
                    px: 0.9; py: critter.face === "happy" ? 1.2 : 0.9; pw: 0.8; ph: critter.face === "happy" ? 0.3 : 0.8
                    color: critter.ink
                }
            }
        }
        Repeater {
            model: critter.kind === "chick" ? [[4.3, -25], [4.85, 0], [5.4, 25]] : []
            delegate: Bit {
                required property var modelData
                px: modelData[0]; py: 1.4; pw: 0.5; ph: 1.6; rotation: modelData[1]
                color: Qt.darker(critter.tint, 1.15)
            }
        }
        // The head.
        Bit { px: 2.0; py: 2.6; pw: 6.0; ph: 6.0; color: critter.tint; border.width: critter.c * 0.12; border.color: critter.edge }
        // Eyes (a frog's are on top), and brows when cross.
        Repeater {
            model: critter.kind === "frog" ? [] : [3.8, 6.2]
            delegate: Bit {
                required property real modelData
                px: modelData - 0.4
                py: critter.face === "happy" ? 5.3 : 5.0
                pw: 0.8
                ph: critter.face === "happy" ? 0.3 : 0.8
                color: critter.ink
            }
        }
        Repeater {
            model: critter.face === "cross" ? [[3.3, 18], [5.7, -18]] : []
            delegate: Bit {
                required property var modelData
                px: modelData[0]; py: critter.kind === "frog" ? 1.5 : 4.3; pw: 1.0; ph: 0.28; rotation: modelData[1]
                color: critter.ink
            }
        }
        Bit { px: 2.9; py: 6.1; pw: 0.9; ph: 0.5; color: "#FF8FA8"; opacity: 0.55 }
        Bit { px: 6.2; py: 6.1; pw: 0.9; ph: 0.5; color: "#FF8FA8"; opacity: 0.55 }
        // A beak for the chick, a mouth for the rest.
        Bit {
            visible: critter.kind === "chick"
            px: 4.55; py: 5.85; pw: 0.9; ph: 0.9; radius: critter.c * 0.15; rotation: 45
            color: "#F39A3B"
        }
        Shape {
            visible: critter.kind !== "chick"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: critter.ink
                strokeWidth: Math.max(1.5, critter.c * 0.22)
                capStyle: ShapePath.RoundCap
                PathSvg {
                    readonly property real c: critter.c
                    readonly property var line: ({
                        smile: [4.3, 6.4, 7.0, 5.7],
                        happy: [4.1, 6.3, 7.5, 5.9],
                        flat: [4.4, 6.7, 6.7, 5.6],
                        frown: [4.3, 7.0, 6.4, 5.7],
                        cross: [4.3, 7.1, 6.3, 5.7]
                    })[critter.face] || [4.3, 6.4, 7.0, 5.7]
                    path: "M %1 %2 Q %3 %4 %5 %2".arg(line[0] * c).arg(line[1] * c).arg(5 * c).arg(line[2] * c).arg(line[3] * c)
                }
            }
        }
    }

    // ---- Who works the shift: at the start, and once the shop closes
    Rectangle {
        id: chooser
        anchors.fill: parent
        visible: game.phase !== "playing"
        radius: Theme.radius
        color: Theme.background
        readonly property bool side: game.shape === "side"
        // Keep taps off the shop underneath.
        MouseArea { anchors.fill: parent }

        Column {
            id: words
            x: chooser.side ? 0 : (parent.width - width) / 2
            y: chooser.side ? (parent.height - height) / 2 : Math.max(0, (parent.height - height - cards.height - Theme.spacing * 2) / 2)
            width: chooser.side ? parent.width - cards.width - Theme.spacing * 2 : Math.min(parent.width, 640)
            spacing: 6
            Label {
                width: parent.width
                horizontalAlignment: chooser.side ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: game.phase === "over" ? qsTr("Closing time!") : qsTr("Who's on shift?")
                color: Theme.text
                font.pixelSize: chooser.side ? Theme.fontLg : Theme.fontXl
                font.weight: Font.DemiBold
            }
            Label {
                width: parent.width
                horizontalAlignment: chooser.side ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: game.phase === "over"
                      ? qsTr("%1 points, %2 served.").arg(game.score).arg(game.served) + " "
                        + (game.newBest ? qsTr("A new best!") : qsTr("Best %1.").arg(game.best))
                      : game.best > 0 ? qsTr("Best %1. Build each order before the customer gives up.").arg(game.best)
                                      : qsTr("Build each order before the customer gives up.")
                color: game.phase === "over" && game.newBest ? Theme.success : Theme.textMuted
                font.pixelSize: Theme.fontSm
                font.weight: game.phase === "over" && game.newBest ? Font.DemiBold : Font.Normal
            }
            Label {
                visible: game.phase === "over"
                width: parent.width
                horizontalAlignment: chooser.side ? Text.AlignLeft : Text.AlignHCenter
                text: qsTr("Who's on next?")
                color: Theme.text
                font.pixelSize: Theme.fontSm
                topPadding: 6
            }
        }
        Row {
            id: cards
            readonly property real cardHeight: chooser.side ? parent.height
                : Math.min(320, parent.height - words.height - Theme.spacing * 2)
            readonly property real cardWidth: Math.min(260, cardHeight * 0.85,
                                                       ((chooser.side ? parent.width * 0.62 : parent.width) - spacing) / 2)
            x: chooser.side ? parent.width - width : (parent.width - width) / 2
            y: chooser.side ? 0 : words.y + words.height + Theme.spacing * 2
            spacing: Theme.spacing
            Repeater {
                model: [{ who: "pip", name: qsTr("Pip"), what: qsTr("the penguin") },
                        { who: "lotl", name: qsTr("Lotl"), what: qsTr("the axolotl") }]
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    objectName: "tap:" + modelData.who
                    width: cards.cardWidth
                    height: cards.cardHeight
                    radius: Theme.radius
                    color: Theme.surface
                    scale: cardTap.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.quick } }
                    ScoopCrew {
                        x: 12
                        y: 12
                        width: parent.width - 24
                        height: nameLabel.y - 18
                        who: card.modelData.who
                    }
                    Label {
                        id: nameLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height - height - whatLabel.height - 12
                        text: card.modelData.name
                        color: Theme.text
                        font.pixelSize: Theme.fontMd
                        font.weight: Font.DemiBold
                    }
                    Label {
                        id: whatLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height - height - 10
                        text: card.modelData.what
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontXs
                    }
                    TapHandler { id: cardTap; onTapped: game.start(card.modelData.who) }
                }
            }
        }
    }

    // ---- Paused: the shop hidden; a tap carries on, or ends the shift.
    Rectangle {
        anchors.fill: parent
        visible: game.phase === "playing" && game.paused
        radius: Theme.radius
        color: Theme.background
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent
            spacing: Theme.spacing
            ScoopCrew {
                anchors.horizontalCenter: parent.horizontalCenter
                width: height * 10 / 12
                height: Math.min(180, game.height - 64 - 3 * Theme.spacing - 70)
                who: game.worker
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Paused")
                color: Theme.text
                font.pixelSize: Theme.fontXl
                font.weight: Font.DemiBold
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacing
                PillButton {
                    objectName: "tap:carryOn"
                    text: qsTr("Carry on")
                    onClicked: game.resume()
                }
                PillButton {
                    objectName: "tap:endShift"
                    text: qsTr("End shift")
                    fill: Theme.surface
                    ink: Theme.text
                    onClicked: game.endShift()
                }
            }
        }
    }
}
