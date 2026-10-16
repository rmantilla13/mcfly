import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Home: today, in time order.
//
// The left column is the moment: the greeting and the clock, what's up next,
// anything blocked, and the way to ask McFly. The right column is the day:
// the markets in one strip, then one stream of what arrived and what is
// planned (Store.timeline), scrolled so "now" sits near the top. Past rows
// fade, the current event is outlined, the next one is marked. Under the
// last row, tomorrow's events (Store.tomorrow) preview what's coming.
//
// Mini keeps both columns but drops the ask bar (the nav's sparkle does its
// job); Tall stacks everything into a feed (docs/LAYOUTS.md). Both
// carry the markets as a ticker tape that scrolls every symbol.
//
// Under the date, what stands out (Store.highlights) turns over one at a
// time; a tap asks McFly about it. Up next is a gradient tile in the
// event's colour, counting down its last hour on a ring, or showing how far
// a meeting on now has run. A thread runs down the day list's gutter with
// now on it, gliding along as the minutes pass. Everything settles in,
// staggered, as Home shows (Reveal).
Item {
    id: home
    signal openScreen(int index)
    signal openAssistant(string question)
    signal pushToTalk()

    // On screen and not covered (set by Main.qml); the ask bar's glow only
    // animates while it is.
    property bool shown: true
    // The page picked, under the assistant panel too: it settles in as
    // this turns true, not again when the panel goes.
    property bool isCurrent: true
    // Loops and glides run only while someone can see them.
    readonly property bool moving: shown && !Device.idle && Device.animatedTiles

    Reveal { id: rv; shown: home.isCurrent }

    property date now: new Date()
    // Past / now / next move once a minute, not every second.
    readonly property real minuteMs: Math.floor(now.getTime() / 60000) * 60000

    // Every symbol: the strip is a ticker tape, so none has to be left out.
    readonly property var tickers: Store.quotes
    readonly property var blocked: Store.projects.filter(p => p.status === "blocked")
    // The event on now, else the next one today or later (not all-day).
    readonly property var nextEvent: {
        const t = minuteMs
        for (const e of Store.events)
            if (!e.all_day && e.endMs > t)
                return e
        return null
    }
    // Nothing up next and nothing blocked (a new account, or a free night):
    // the clock has the left column to itself.
    readonly property bool quiet: !nextEvent && blocked.length === 0
    readonly property var timeline: Store.timeline
    readonly property var tomorrow: Store.tomorrow
    // The row to keep in view: the first one not yet over.
    readonly property int focusIndex: {
        const t = minuteMs
        for (let i = 0; i < timeline.length; ++i)
            if (!timeline[i].allDay && timeline[i].endMs >= t && timeline[i].kind === "event")
                return i
        return timeline.length - 1
    }
    readonly property int nextIndex: {
        const t = minuteMs
        for (let i = 0; i < timeline.length; ++i)
            if (timeline[i].kind === "event" && !timeline[i].allDay && timeline[i].startMs > t)
                return i
        return -1
    }

    Timer { objectName: "clockTick"; interval: 1000; running: home.visible; repeat: true; triggeredOnStart: true; onTriggered: home.now = new Date() }

    function greeting() {
        const h = now.getHours()
        const part = h < 5 ? qsTr("Good night") : h < 12 ? qsTr("Good morning") : h < 18 ? qsTr("Good afternoon") : qsTr("Good evening")
        return Store.displayName && Store.displayName !== "McFly" ? part + ", " + Store.displayName : part
    }
    function minutesUntil(ms) { return Math.max(0, Math.round((ms - minuteMs) / 60000)) }
    function untilLabel(ms) {
        const m = minutesUntil(ms)
        if (m < 1) return qsTr("now")
        if (m < 60) return qsTr("in %1 min").arg(m)
        const h = Math.floor(m / 60), r = m % 60
        return r === 0 ? qsTr("in %1 h").arg(h) : qsTr("in %1 h %2 min").arg(h).arg(r)
    }
    function nextHeading() {
        const e = nextEvent
        if (!e) return ""
        if (e.startMs <= minuteMs) return qsTr("NOW · ENDS %1").arg(untilLabel(e.endMs).toUpperCase())
        if (e.day !== Store.today) return qsTr("UP NEXT · %1").arg(e.dayLabel.toUpperCase())
        return qsTr("UP NEXT · %1").arg(untilLabel(e.startMs).toUpperCase())
    }
    function kindIcon(item) {
        switch (item.kind) {
        case "news": return "news"
        case "brief": return "brief"
        case "alert": return "info"
        case "project": return item.icon || "check"
        case "todo": return "check"
        case "reminder": return "clock"
        default: return "calendar"
        }
    }
    // Where now falls among the day's rows (y in the rows' own space): inside
    // the event on now, as far in as it has run; else halfway across the gap
    // after the last thing that started, or before the first if nothing has.
    // NaN while that row isn't made. All-day rows and to-dos sit apart.
    function nowPlace(rowAt, gap) {
        const t = minuteMs
        let last = -1, first = -1
        for (let i = 0; i < timeline.length; ++i) {
            if (timeline[i].allDay)
                continue
            if (timeline[i].startMs <= t)
                last = i
            else {
                first = i
                break
            }
        }
        if (last < 0) {
            const next = first >= 0 ? rowAt(first) : null
            return next ? next.y - gap / 2 : NaN
        }
        const row = rowAt(last), item = timeline[last]
        if (!row)
            return NaN
        if (item.kind === "event" && item.endMs > t && item.endMs > item.startMs)
            return row.y + row.height * (t - item.startMs) / (item.endMs - item.startMs)
        return row.y + row.height + gap / 2
    }

    // ---- The regions.

    // Greeting, the big clock, the date. `big`: larger still, for a column
    // with nothing else in it (as the Ambient saver's clock is).
    component Clock: ColumnLayout {
        id: clock
        property bool big: false
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                visible: Theme.navMode === "bar"
                width: Theme.mini ? 30 : 36; height: width; radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.glowBlue }
                    GradientStop { position: 1; color: Theme.glowCoral }
                }
                Icon { anchors.centerIn: parent; name: "bolt"; size: parent.width * 0.52; color: "white"; strokeWidth: 2.2 }
            }
            Label {
                Layout.fillWidth: true
                text: home.greeting()
                color: Theme.textMuted
                font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd
                elide: Text.ElideRight
            }
            Label {
                visible: Store.mode === "demo"
                text: qsTr("DEMO")
                color: Theme.accent
                font.pixelSize: Theme.fontXs
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
        }
        RowLayout {
            spacing: 8
            Label {
                text: Qt.formatTime(home.now, "h:mm AP").split(" ")[0]
                color: Theme.text
                font.pixelSize: clock.big ? (Theme.mini ? 104 : Theme.compact ? 144 : 176)
                                    : (Theme.mini ? 64 : Theme.compact ? 88 : 112)
                font.weight: Font.Light
                font.letterSpacing: clock.big ? (Theme.mini ? -3 : -6) : (Theme.mini ? -2 : -4)
            }
            Label {
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: clock.big ? (Theme.mini ? 18 : 30) : (Theme.mini ? 12 : 20)
                text: Qt.formatTime(home.now, "AP")
                color: Theme.textMuted
                font.pixelSize: clock.big ? (Theme.mini ? Theme.fontMd : Theme.fontLg) : (Theme.mini ? Theme.fontSm : Theme.fontMd)
            }
        }
        Label {
            Layout.fillWidth: true
            text: Qt.formatDate(home.now, Theme.mini ? "ddd, MMM d" : "dddd, MMMM d") + " · " + Store.lastSyncLabel
            color: Theme.textMuted
            font.pixelSize: clock.big ? (Theme.mini ? Theme.fontSm : Theme.fontMd) : (Theme.mini ? Theme.fontXs : Theme.fontSm)
            elide: Text.ElideRight
        }
    }

    // Up next (or on now), on a gradient tile in the event's colour. In its
    // last hour a ring beside it empties as the start nears; on now, a bar
    // under it fills as the meeting runs. Both move once a minute.
    component NextCard: GradientTile {
        id: nextTile
        readonly property var event: home.nextEvent
        readonly property bool onNow: !!event && event.startMs <= home.minuteMs
        readonly property int minutesTo: event ? home.minutesUntil(event.startMs) : 0
        readonly property bool countdown: !!event && !onNow && event.day === Store.today && minutesTo <= 60
        readonly property real elapsed: onNow && event.endMs > event.startMs
                                        ? Math.min(1, (home.minuteMs - event.startMs) / (event.endMs - event.startMs)) : 0
        readonly property int ringSize: Theme.mini ? 52 : Theme.compact ? 68 : 76
        // Its place in Home's reveal.
        property int order: 2
        visible: !!event
        // On now, a little more room under the words for the bar (none on Mini, which has none to spare).
        implicitHeight: Math.max(nextCol.implicitHeight, countdown ? ringSize : 0) + (Theme.mini ? 24 : 36)
                        + (onNow && !Theme.mini ? 10 : 0)
        radius: Theme.radius
        baseColor: event && event.color ? event.color : Theme.accent
        active: home.shown
        seed: 2.4
        rings: 1
        ringBias: 0.9
        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: nextTile.onNow && !Theme.mini ? -5 : 0
            anchors.margins: Theme.mini ? 14 : 22
            spacing: Theme.mini ? 12 : 18
            ColumnLayout {
                id: nextCol
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: home.nextHeading()
                    color: nextTile.inkMuted
                    font.pixelSize: Theme.fontXs - (Theme.mini ? 1 : 0)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.3
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: nextTile.event ? nextTile.event.title : ""
                    color: nextTile.ink
                    font.pixelSize: Theme.mini ? Theme.fontMd : Theme.fontLg
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    visible: !Theme.mini || !!(nextTile.event && nextTile.event.location)
                    text: nextTile.event ? [nextTile.event.timeLabel, nextTile.event.location || nextTile.event.calendar].filter(s => !!s).join(" · ") : ""
                    color: nextTile.inkMuted
                    font.pixelSize: Theme.mini ? Theme.fontXs : Theme.fontSm
                    elide: Text.ElideRight
                }
            }
            // The last hour: what's left of it, and the minutes in the middle.
            Ring {
                objectName: "countdown"
                visible: nextTile.countdown
                Layout.preferredWidth: nextTile.ringSize
                Layout.preferredHeight: nextTile.ringSize
                Layout.alignment: Qt.AlignVCenter
                value: nextTile.minutesTo / 60
                shown: rv.at(nextTile.order)
                color: nextTile.ink
                track: Qt.rgba(nextTile.ink.r, nextTile.ink.g, nextTile.ink.b, 0.16)
                lineWidth: Theme.mini ? 4 : 5
                Column {
                    anchors.centerIn: parent
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: nextTile.minutesTo
                        color: nextTile.ink
                        font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("min")
                        color: nextTile.inkMuted
                        font.pixelSize: Theme.fontXs - 3
                    }
                }
            }
        }
        // On now: how far it has run, along the bottom edge inside the padding.
        Item {
            objectName: "elapsed"
            visible: nextTile.onNow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.mini ? 14 : 22
            anchors.rightMargin: Theme.mini ? 14 : 22
            anchors.bottomMargin: Theme.mini ? 6 : 14
            height: Theme.mini ? 4 : 6
            Rectangle { anchors.fill: parent; radius: height / 2; color: nextTile.ink; opacity: 0.16 }
            Rectangle {
                width: parent.width
                height: parent.height
                radius: height / 2
                color: nextTile.ink
                // Scaled, not resized: the reveal sweeps it in for free.
                transform: Scale { xScale: Math.max(0.02, nextTile.elapsed) * rv.at(nextTile.order) }
            }
        }
        TapHandler { onTapped: home.openScreen(6) }
    }

    // The first blocked project, on a warm tint.
    component BlockedCard: Rectangle {
        readonly property var project: home.blocked.length > 0 ? home.blocked[0] : null
        visible: !!project
        implicitHeight: blockedRow.implicitHeight + (Theme.mini ? 20 : 30)
        radius: Theme.radius
        color: Qt.tint(Theme.surface, Qt.rgba(0.94, 0.42, 0.33, Theme.dark ? 0.22 : 0.16))
        RowLayout {
            id: blockedRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.mini ? 14 : 20
            spacing: 14
            Rectangle {
                width: Theme.mini ? 32 : 40; height: width; radius: width / 2
                color: Qt.rgba(0.94, 0.42, 0.33, 0.22)
                Icon { anchors.centerIn: parent; name: "info"; size: Theme.mini ? 18 : 20; color: Theme.danger }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: project ? (home.blocked.length > 1 ? qsTr("%1 and %2 more are blocked").arg(project.name).arg(home.blocked.length - 1)
                                                            : qsTr("%1 is blocked").arg(project.name)) : ""
                    color: Theme.text
                    font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd - 2
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: project ? (project.next_step || project.summary || "") : ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.mini ? Theme.fontXs : Theme.fontSm
                    elide: Text.ElideRight
                }
            }
        }
        TapHandler { onTapped: home.openScreen(4) }
    }

    // "Ask McFly" on the voice glow.
    component AskBar: Rectangle {
        id: askBar
        property bool live: true
        implicitHeight: Theme.tall ? 84 : 88
        radius: height / 2
        color: "#1B1A1F"
        clip: true
        SpectrumGlow {
            anchors.fill: parent
            kind: "input"
            cornerRadius: askBar.radius
            ambient: true
            intensity: 0.8
            active: home.shown && askBar.live
            processing: AI.busy
            // Beside the up-next tile (30 fps), on the same frames as it.
            maxFps: home.nextEvent ? 30 : 20
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 28
            anchors.rightMargin: 14
            spacing: 14
            Icon { name: "sparkle"; size: 24; color: Qt.rgba(1, 1, 1, 0.85) }
            Label {
                Layout.fillWidth: true
                text: qsTr("Ask McFly")
                color: Qt.rgba(1, 1, 1, 0.86)
                font.pixelSize: Theme.fontMd - 2
                elide: Text.ElideRight
            }
            IconButton {
                width: 60; height: 60
                icon: Voice.available ? "mic" : "mic-off"
                fill: Qt.rgba(1, 1, 1, 0.14)
                ink: "white"
                onClicked: home.pushToTalk()
            }
        }
        TapHandler { onTapped: home.openAssistant("") }
    }

    // One copy of the ticker tape: the holdings summed (when an agent sends
    // them), then symbol, price, move, for every quote; on a wall, the
    // symbol's recent line too.
    component TickerTape: Row {
        property real gap: 40
        spacing: gap
        Row {
            visible: !!Store.portfolio.held
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            spacing: Theme.mini ? 8 : 10
            Label { text: qsTr("Holdings"); color: Theme.textMuted; font.pixelSize: Theme.fontSm }
            Label { text: Store.portfolio.valueLabel || ""; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.Bold; font.features: ({ "tnum": 1 }) }
            Label {
                visible: !!Store.portfolio.dayChangeLabel
                text: (Store.portfolio.dayUp ? "▲ " : "▼ ") + (Store.portfolio.dayChangeLabel || "")
                color: Store.portfolio.dayUp ? Theme.gain : Theme.loss
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }
        Repeater {
            model: home.tickers
            delegate: Row {
                id: tick
                required property var modelData
                readonly property color tone: modelData.flat ? Theme.textMuted : modelData.up ? Theme.gain : Theme.loss
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                spacing: Theme.mini ? 8 : 10
                Label { text: modelData.symbol; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.Bold }
                Label { text: modelData.priceLabel; color: Theme.textMuted; font.pixelSize: Theme.fontSm; font.features: ({ "tnum": 1 }) }
                // Wide only: elsewhere none is made (two tapes, one per symbol each).
                Loader {
                    active: Theme.wide && (tick.modelData.history || []).length > 1
                    visible: active
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: Sparkline {
                        width: 64
                        height: 26
                        points: tick.modelData.history || []
                        color: tick.tone
                        lineWidth: 2
                    }
                }
                Label {
                    text: (modelData.flat ? "" : modelData.up ? "\u25B2 " : "\u25BC ") + modelData.pctLabel
                    color: parent.tone
                    font.pixelSize: Theme.fontSm
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    // The markets on a ticker tape: every symbol, its price and its move,
    // gliding right to left while Home is on screen. Two copies of the tape
    // sit end to end, each at least as wide as the strip, so the loop never
    // shows a seam; the offset wraps at one copy, so a new price (a wider
    // tape) changes the lap without a jump. Edges fade into the card.
    component MarketsStrip: Rectangle {
        id: strip
        implicitHeight: Theme.mini ? 56 : 68
        radius: Theme.radiusSm + 6
        color: Theme.surface
        visible: home.tickers.length > 0

        readonly property real gap: Theme.mini ? 28 : 40
        // One copy of the tape and the gap after it, never narrower than the window.
        readonly property real lap: Math.max(tapeA.implicitWidth + gap, track.width)
        readonly property real speed: Theme.mini ? 42 : 56   // px a second: read in passing, not chased
        property real offset: 0

        // Not while idle: under the screen saver or the sleep cover it would
        // redraw the whole window every frame, the saver's full-screen
        // backdrop included. (With Animated tiles off it still runs: the tape
        // is how the symbols past the strip's width get shown at all.)
        FrameAnimation {
            running: home.shown && !Device.idle && strip.visible && strip.lap > 0
            onTriggered: strip.offset = (strip.offset + frameTime * strip.speed) % strip.lap
        }

        // Inset from the rounded ends, so the tape and its fades stay inside the card.
        Item {
            id: track
            anchors.fill: parent
            anchors.margins: 6
            anchors.leftMargin: Theme.mini ? 10 : 14
            anchors.rightMargin: Theme.mini ? 10 : 14
            clip: true
            Item {
                x: -strip.offset
                width: 2 * strip.lap
                height: parent.height
                TickerTape { id: tapeA; gap: strip.gap; anchors.verticalCenter: parent.verticalCenter }
                TickerTape { x: strip.lap; gap: strip.gap; anchors.verticalCenter: parent.verticalCenter }
            }
            Rectangle {
                width: Theme.mini ? 22 : 32
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.surface }
                    GradientStop { position: 1; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0) }
                }
            }
            Rectangle {
                anchors.right: parent.right
                width: Theme.mini ? 22 : 32
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0) }
                    GradientStop { position: 1; color: Theme.surface }
                }
            }
        }
        TapHandler { onTapped: home.openScreen(2) }
    }

    // One row of the day: the time, then the card.
    component TimelineRow: RowLayout {
        id: row
        required property var modelData
        required property int index
        // A row of tomorrow's preview: never past, on now or next, whatever its index.
        property bool preview: false
        // Its place in Home's reveal (rows on screen first, in order).
        property int order: 7
        readonly property bool isEvent: modelData.kind === "event"
        readonly property bool isNow: !preview && isEvent && !modelData.allDay && modelData.startMs <= home.minuteMs && modelData.endMs > home.minuteMs
        readonly property bool isNext: !preview && index === home.nextIndex
        readonly property bool isPast: !preview && !modelData.allDay && (isEvent ? modelData.endMs <= home.minuteMs : false)
        readonly property bool hasPicture: Theme.pictures && !Theme.mini && modelData.kind === "news" && !!modelData.imageUrl
        width: ListView.view ? ListView.view.width : implicitWidth
        spacing: Theme.mini ? 10 : 16
        opacity: (isPast ? 0.5 : 1) * rv.at(order)
        transform: Translate { y: rv.rise(row.order) }

        // The time, right-aligned against the card.
        ColumnLayout {
            Layout.preferredWidth: Theme.mini ? 50 : 64
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Theme.mini ? 12 : 18
            spacing: 0
            Label {
                Layout.alignment: Qt.AlignRight
                text: modelData.timeLabel
                color: row.isNow || row.isNext ? Theme.accent : Theme.text
                font.pixelSize: modelData.allDay ? Theme.fontXs : Theme.fontSm
                font.weight: Font.DemiBold
            }
            Label {
                Layout.alignment: Qt.AlignRight
                visible: !!modelData.ampm
                text: modelData.ampm
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs - 2
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: cardRow.implicitHeight + (Theme.mini ? 22 : 30)
            radius: Theme.radiusSm + 4
            color: row.isEvent && !row.isNow ? "transparent" : Theme.surface
            border.width: row.isNow ? 2 : row.isEvent ? 1 : 0
            border.color: row.isNow ? (modelData.color || Theme.accent) : Theme.divider
            clip: true

            RowLayout {
                id: cardRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.mini ? 12 : 18
                anchors.rightMargin: Theme.mini ? 12 : 18
                spacing: Theme.mini ? 10 : 14

                // A picture for the Pulse; else the kind, on its colour.
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: row.hasPicture ? 96 : (Theme.mini ? 30 : 36)
                    Layout.preferredHeight: row.hasPicture ? 72 : Layout.preferredWidth
                    radius: row.hasPicture ? 14 : width / 2
                    color: "transparent"
                    clip: true
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: modelData.color || Theme.accent
                        opacity: row.hasPicture ? 0.35 : 0.18
                    }
                    Image {
                        anchors.fill: parent
                        visible: row.hasPicture && status === Image.Ready
                        source: row.hasPicture ? modelData.imageUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 192
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: !row.hasPicture
                        name: home.kindIcon(modelData)
                        size: Theme.mini ? 16 : 18
                        color: modelData.color || Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        Layout.fillWidth: true
                        visible: !row.isEvent
                        text: (modelData.label || "").toUpperCase()
                        color: modelData.color || Theme.textMuted
                        font.pixelSize: Theme.fontXs - 2
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.title
                        color: Theme.text
                        font.pixelSize: Theme.mini ? Theme.fontSm : (modelData.kind === "news" ? Theme.fontMd - 2 : Theme.fontSm + 1)
                        font.weight: row.isEvent || modelData.kind === "news" ? Font.DemiBold : Font.Medium
                        wrapMode: Text.WordWrap
                        maximumLineCount: modelData.kind === "brief" || modelData.kind === "alert" ? 1 : 2
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0 && !(Theme.mini && row.isEvent)
                        text: modelData.detail || ""
                        color: Theme.textMuted
                        font.pixelSize: Theme.mini ? Theme.fontXs : Theme.fontSm - 2
                        wrapMode: Text.WordWrap
                        maximumLineCount: Theme.mini ? 1 : 2
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    visible: row.isNow || row.isNext
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: badge.implicitWidth + 20
                    implicitHeight: badge.implicitHeight + 10
                    radius: height / 2
                    color: row.isNow ? (modelData.color || Theme.accent) : Theme.accentSoft
                    Label {
                        id: badge
                        anchors.centerIn: parent
                        text: row.isNow ? qsTr("Now") : home.untilLabel(modelData.startMs)
                        color: row.isNow ? "white" : Theme.accent
                        font.pixelSize: Theme.fontXs - 1
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
        TapHandler {
            onTapped: {
                // A report row opens that report, whatever News showed last.
                if (modelData.kind === "news") {
                    Store.showSource(modelData.agentId || "")
                    Store.showReport(modelData.id)
                }
                home.openScreen(modelData.target)
            }
        }
    }

    // The day's thread, down the gutter between the times and the cards,
    // with now on it (home.nowPlace): the part already lived is tinted, and
    // the dot glides to its new place as the minutes pass. It lives among
    // the rows (`rowAt` finds them), so it scrolls with them.
    component NowRail: Item {
        id: nowRail
        // The row at an index, or null where it isn't made.
        property var rowAt: i => null
        property real gap: 10
        property real railTop: 0
        property real railBottom: 0
        // Read to ask again where now is when the rows may have moved.
        property var watch
        readonly property real nowY: {
            nowRail.watch
            nowRail._remade
            return home.nowPlace(nowRail.rowAt, nowRail.gap)
        }
        // A sync makes the rows again, a moment after the day changes: ask
        // again once they're there.
        property int _remade: 0
        Timer { id: remade; interval: 120; onTriggered: nowRail._remade++ }
        Connections {
            target: home
            function onTimelineChanged() { remade.restart() }
        }
        readonly property bool placed: !isNaN(nowY) && nowY >= railTop - 1 && nowY <= railBottom + gap
        x: (Theme.mini ? 50 : 64) + (Theme.mini ? 10 : 16) / 2 - width / 2
        y: railTop
        width: 14
        height: Math.max(0, railBottom - railTop)
        visible: height > 0 && home.timeline.some(r => !r.allDay)
        opacity: rv.at(3)
        Rectangle {
            x: (nowRail.width - width) / 2
            width: 2
            height: parent.height
            radius: 1
            color: Theme.divider
        }
        // Lived: from the top to the dot.
        Rectangle {
            visible: nowRail.placed
            x: (nowRail.width - width) / 2
            width: 2
            height: parent.height
            radius: 1
            color: Theme.accent
            opacity: 0.55
            transform: Scale { yScale: nowRail.height > 0 ? Math.max(0, Math.min(1, (dot.y + dot.height / 2) / nowRail.height)) : 0 }
        }
        Item {
            id: dot
            visible: nowRail.placed
            x: (nowRail.width - width) / 2
            y: (nowRail.placed ? nowRail.nowY - nowRail.railTop : 0) - height / 2
            width: Theme.mini ? 10 : 12
            height: width
            Behavior on y {
                enabled: home.moving
                NumberAnimation { duration: Theme.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
            }
            // A ring of the canvas around it, so it sits on the thread.
            Rectangle { anchors.centerIn: parent; width: parent.width + 6; height: width; radius: width / 2; color: Theme.background }
            StatusDot {
                anchors.centerIn: parent
                size: dot.width
                color: Theme.accent
                breathing: true
                running: home.moving
            }
        }
    }

    component TodayHeading: RowLayout {
        Label {
            text: qsTr("TODAY")
            color: Theme.textMuted
            font.pixelSize: Theme.fontXs
            font.weight: Font.Bold
            font.letterSpacing: 1.6
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }
        Label {
            text: home.timeline.length === 0 ? qsTr("Nothing yet")
                : home.timeline.length === 1 ? qsTr("1 thing") : qsTr("%1 things").arg(home.timeline.length)
            color: Theme.textMuted
            font.pixelSize: Theme.fontXs
        }
    }

    component TomorrowHeading: RowLayout {
        Label {
            text: qsTr("TOMORROW")
            color: Theme.textMuted
            font.pixelSize: Theme.fontXs
            font.weight: Font.Bold
            font.letterSpacing: 1.6
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }
        Label {
            text: Store.tomorrowLabel + " · " + (home.tomorrow.length === 1 ? qsTr("1 thing") : qsTr("%1 things").arg(home.tomorrow.length))
            color: Theme.textMuted
            font.pixelSize: Theme.fontXs
        }
    }

    // Tomorrow's events under today's last row: a preview of what's coming,
    // on the same rows, outlined like any event still ahead. The landscape
    // list carries it as its footer, so a day that is over rests on it; the
    // Tall feed carries it after the last row. Hidden on a free tomorrow.
    component TomorrowPreview: Column {
        visible: home.tomorrow.length > 0
        topPadding: Theme.mini ? 10 : 16
        spacing: Theme.mini ? 8 : 10
        TomorrowHeading { width: parent.width; height: implicitHeight }
        Repeater {
            model: home.tomorrow
            delegate: TimelineRow { width: parent.width; height: implicitHeight; preview: true }
        }
    }

    // What stands out, under the date: a tap asks about the one showing.
    // Not what the cards under it already say (the blocked project, the
    // event up next).
    component Insights: InsightLine {
        id: insights
        property int order: 1
        items: Store.highlights.filter(h => !(h.kind === "blocked" && home.blocked.length > 0)
                                            && !(h.kind === "event" && !!home.nextEvent && h.itemId === home.nextEvent.id))
        running: home.shown
        opacity: rv.at(insights.order)
        transform: Translate { y: rv.rise(insights.order) }
        onPicked: item => home.openAssistant(item.question)
    }

    // A day with nothing in it yet, as on a new account: what lands here,
    // and a code apiece to scan for the pages on mcfly.bot that set it up.
    component EmptyDay: ColumnLayout {
        spacing: Theme.mini ? 8 : 12
        Label {
            Layout.fillWidth: true
            text: qsTr("Your day shows up here")
            color: Theme.text
            font.pixelSize: Theme.mini ? Theme.fontSm + 1 : Theme.fontMd
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
        Label {
            Layout.fillWidth: true
            visible: !Theme.mini
            text: qsTr("Briefs, the Daily Pulse, projects and your calendar, in time order, as they come in. Set them up from your phone:")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSm
            wrapMode: Text.WordWrap
        }
        GridLayout {
            visible: Store.mode !== "pairing"
            Layout.fillWidth: true
            Layout.topMargin: Theme.mini ? 0 : 6
            columns: Theme.wide ? 3 : 1
            rowSpacing: Theme.mini ? 8 : 10
            columnSpacing: 10
            Repeater {
                model: [{ url: "https://mcfly.bot/bots", title: qsTr("Grok bots"), caption: qsTr("Briefs and a Daily Pulse, written on a schedule.") },
                        { url: "https://mcfly.bot/calendars", title: qsTr("Calendars"), caption: qsTr("Google, iCloud or Outlook, read every 15 minutes.") },
                        { url: "https://mcfly.bot/agents", title: qsTr("Agents"), caption: qsTr("Your own scripts and tools, each with its own key.") }]
                delegate: QrPanel {
                    required property var modelData
                    Layout.fillWidth: true
                    url: modelData.url
                    title: modelData.title
                    // The 7" panel has room for the name and the address only.
                    caption: Theme.mini ? "" : modelData.caption
                    domain: modelData.url.replace("https://", "")
                    codeSize: Theme.mini ? 64 : Theme.wide ? 112 : 96
                }
            }
        }
    }

    // ---- Landscape (Wide, Compact, Mini): the moment | the day.
    RowLayout {
        visible: !Theme.tall
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.spacing + (Theme.wide ? 8 : 0)

        ColumnLayout {
            objectName: "moment"
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.mini ? 5 : 4
            Layout.maximumWidth: Theme.wide ? 520 : 99999
            spacing: Theme.spacing
            // Quiet, the clock grows and sits in the middle of the room above
            // the questions, as the Ambient saver's does with no cards.
            Item { Layout.fillHeight: true; visible: home.quiet }
            Clock { Layout.fillWidth: true; big: home.quiet; opacity: rv.at(0); transform: Translate { y: rv.rise(0) } }
            Insights { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight }
            NextCard { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; opacity: rv.at(2); transform: Translate { y: rv.rise(2) } }
            BlockedCard { objectName: "blockedCard"; Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; opacity: rv.at(3); transform: Translate { y: rv.rise(3) } }
            Item { Layout.fillHeight: true }
            // Questions to ask in one tap, over the bar that asks anything:
            // Home's own ("Summarize my day") first, then what the feed raises.
            SuggestionChips {
                Layout.fillWidth: true
                visible: !Theme.mini
                // suggestionsFor doesn't notify; reading AI.suggestions does.
                items: {
                    const all = AI.suggestions
                    return all.length > 0 ? AI.suggestionsFor("home") : all
                }
                centred: false
                maxRows: 2
                opacity: rv.at(4)
                transform: Translate { y: rv.rise(4) }
                onPicked: text => home.openAssistant(text)
            }
            AskBar {
                Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; visible: !Theme.mini; live: !Theme.tall
                opacity: rv.at(5); transform: Translate { y: rv.rise(5) }
            }
        }

        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.mini ? 6 : 6
            spacing: Theme.mini ? 10 : 14
            MarketsStrip { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; opacity: rv.at(1); transform: Translate { y: rv.rise(1) } }
            TodayHeading { Layout.fillWidth: true; opacity: rv.at(2) }
            // Filling the column keeps TODAY at the top; scrolls where it's short.
            FocusFlickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: home.timeline.length === 0 && home.tomorrow.length === 0
                fadeColor: Theme.background
                contentHeight: emptyDay.implicitHeight
                EmptyDay { id: emptyDay; width: parent.width }
            }
            ListView {
                id: dayList
                objectName: "dayList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: home.timeline.length > 0 || home.tomorrow.length > 0
                clip: true
                spacing: Theme.mini ? 8 : 10
                model: home.timeline
                boundsBehavior: Flickable.StopAtBounds
                // The rows on screen settle in from the top, whatever row the list rests on.
                delegate: TimelineRow { order: 3 + Math.max(0, index - dayList.topIndex) }
                readonly property int topIndex: Math.max(0, indexAt(width / 2, contentY + spacing + 1))
                // Every row of a day is made, so the thread always finds now.
                cacheBuffer: 2400

                NowRail {
                    objectName: "nowRail"
                    // Among the rows, so it scrolls with them.
                    parent: dayList.contentItem
                    rowAt: i => dayList.itemAtIndex(i)
                    gap: dayList.spacing
                    railTop: dayList.originY
                    railBottom: dayList.footerItem ? dayList.footerItem.y : dayList.originY + dayList.contentHeight
                    watch: [dayList.contentHeight, dayList.count, dayList.contentY, home.minuteMs]
                }

                // Keep "now" in view: one row of what came before, then the rest.
                property bool touched: false
                // Room under the last row, so the list never rests with a row
                // half under TODAY (see trimTop).
                property real endRoom: 0
                footer: Column {
                    width: dayList.width
                    TomorrowPreview { width: parent.width }
                    Item { width: 1; height: dayList.endRoom }
                }
                // A flick comes to rest on a row too.
                snapMode: ListView.SnapToItem
                function settle() {
                    if (touched || count === 0)
                        return
                    endRoom = 0
                    positionViewAtIndex(Math.max(0, home.focusIndex - 1), ListView.Beginning)
                    trimTop()
                }
                // Late in the day the list rests on its end, where the row at
                // the top edge can be cut in half. Start at the next row then,
                // and leave that much room under the last one instead.
                function trimTop() {
                    if (!atYEnd)
                        return
                    const row = itemAtIndex(indexAt(width / 2, contentY + 1))
                    if (!row || row.y >= contentY - 1)
                        return
                    const next = row.y + row.height + spacing
                    endRoom = next - contentY
                    contentY = next
                }
                onMovementStarted: { touched = true; settleTimer.restart() }
                onCountChanged: Qt.callLater(settle)
                // Rows wrap to the width, so place them again once it (or the
                // room) is known.
                onWidthChanged: if (!touched) Qt.callLater(settle)
                onHeightChanged: if (!touched) Qt.callLater(settle)

                // Whichever edge cuts a row (while scrolling, or a row the
                // snap can't reach) fades it out rather than slicing it.
                // Over the list, not in it, so they stay at the edges.
                // (contentHeight: asked again once the rows are laid out.)
                readonly property bool cutAtTop: {
                    const row = contentHeight > 0 ? itemAtIndex(indexAt(width / 2, contentY + 1)) : null
                    return !!row && row.y < contentY - 1
                }
                readonly property bool cutAtBottom: {
                    const edge = contentY + height
                    const row = contentHeight > 0 ? itemAtIndex(indexAt(width / 2, edge - 1)) : null
                    if (row)
                        return row.y + row.height > edge + 1
                    // In the footer (tomorrow): a row is cut unless the list rests at its end.
                    return !!footerItem && footerItem.y < edge - 1 && !atYEnd
                }
                Rectangle {
                    parent: dayList
                    z: 1
                    width: dayList.width
                    height: Theme.mini ? 28 : 48
                    opacity: dayList.cutAtTop ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.background }
                        GradientStop { position: 1; color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0) }
                    }
                }
                Rectangle {
                    parent: dayList
                    z: 1
                    y: dayList.height - height
                    width: dayList.width
                    height: Theme.mini ? 20 : 32
                    opacity: dayList.cutAtBottom ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0) }
                        GradientStop { position: 1; color: Theme.background }
                    }
                }
                Timer { id: settleTimer; interval: 45000; onTriggered: { dayList.touched = false; dayList.settle() } }
                Connections {
                    target: home
                    function onFocusIndexChanged() { Qt.callLater(dayList.settle) }
                    function onShownChanged() { if (home.shown) { dayList.touched = false; Qt.callLater(dayList.settle) } }
                }
                Component.onCompleted: Qt.callLater(settle)
            }
        }
    }

    // ---- Portrait (Tall): the same, as a feed.
    FocusFlickable {
        visible: Theme.tall
        anchors.fill: parent
        fadeColor: Theme.background
        contentHeight: feed.implicitHeight + 2 * Theme.pageMargin
        ColumnLayout {
            id: feed
            x: Theme.pageMargin
            y: Theme.pageMargin
            width: parent.width - 2 * Theme.pageMargin
            spacing: Theme.spacing
            Clock { Layout.fillWidth: true; opacity: rv.at(0); transform: Translate { y: rv.rise(0) } }
            Insights { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight }
            NextCard { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; opacity: rv.at(2); transform: Translate { y: rv.rise(2) } }
            BlockedCard { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; opacity: rv.at(3); transform: Translate { y: rv.rise(3) } }
            AskBar { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; live: Theme.tall; opacity: rv.at(4); transform: Translate { y: rv.rise(4) } }
            MarketsStrip { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; opacity: rv.at(5); transform: Translate { y: rv.rise(5) } }
            TodayHeading { Layout.fillWidth: true; opacity: rv.at(6) }
            EmptyDay { Layout.fillWidth: true; visible: home.timeline.length === 0 && home.tomorrow.length === 0 }
            Repeater {
                id: feedRows
                model: home.timeline
                delegate: TimelineRow { Layout.fillWidth: true }
            }
            TomorrowPreview { Layout.fillWidth: true }
        }
        // The thread, over the feed's rows, in their own space.
        Item {
            x: feed.x
            y: feed.y
            width: feed.width
            height: feed.height
            NowRail {
                readonly property Item first: feedRows.count > 0 ? feedRows.itemAt(0) : null
                readonly property Item last: feedRows.count > 0 ? feedRows.itemAt(feedRows.count - 1) : null
                rowAt: i => feedRows.itemAt(i)
                gap: feed.spacing
                railTop: first ? first.y : 0
                railBottom: last ? last.y + last.height : 0
                watch: [feed.height, feedRows.count, home.minuteMs, first ? first.y : 0]
            }
        }
    }
}
