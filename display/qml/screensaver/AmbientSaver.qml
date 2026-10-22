import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// The default screen saver: readable from across the room.
//
// The backdrop fills the screen: Settings → Backdrop picks the moving
// gradient with an aurora hanging over it at night (GradientTile, AuroraGlow)
// or one of Backdrop's skies; it keeps animating while idle, at a low frame
// rate, and stops when the panel goes off. On it: a big clock, the date, what's next
// and what follows, and along the bottom a rail of cards from the feeds: the
// latest brief, the markets, a blocked project, today's top story and the
// rest of the day. With no feeds yet it is just the clock.
//
// Nothing here is tappable: the touch that wakes the screen is swallowed
// (DisplayController), so there are no hints to tap or swipe. The whole
// composition drifts a few pixels every minute against burn-in. Night comes
// in as one slow dusk: over a minute the backdrop deepens, the cards dim and
// the aurora rises, together.
Item {
    id: ambient
    // Updates a second for what moves (ScreenSaver's: it eases off after a while).
    property int fps: Theme.saverFps
    property date now: new Date()
    readonly property real minuteMs: Math.floor(now.getTime() / 60000) * 60000
    readonly property bool night: Device.nightMode || Theme.dark

    // The dusk: 0 by day, 1 at night, eased over a minute. Everything that
    // changes at night follows `dusk`, which is the same in steps of 1/400, so
    // the saver changes a few times a second while it falls, not every frame.
    property real nightness: night ? 1 : 0
    Behavior on nightness { NumberAnimation { duration: 60000; easing.type: Easing.InOutSine } }
    readonly property real dusk: Math.round(nightness * 400) / 400
    // Text turns from dark to light quickly in the middle of it, where the
    // cards (and the backdrop under the clock) pass mid-grey, so it never sits
    // grey on grey for long.
    readonly property real inkNight: {
        const x = Math.max(0, Math.min(1, (dusk - 0.44) / 0.12))
        return x * x * (3 - 2 * x)
    }
    function tone(day, nightColor, k) {
        const a = Qt.lighter(day, 1.0), b = Qt.lighter(nightColor, 1.0)   // accepts colours and strings
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k,
                       a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
    }

    // Against burn-in the composition slides to a new spot every minute,
    // over 4 s, eased in and out, on the saver's clock: an animation would
    // draw every one of the panel's frames while it slides.
    property real _fromX: 0
    property real _fromY: 0
    property real _toX: 0
    property real _toY: 0
    MotionClock {
        id: slide
        objectName: "slide"
        time: 4
        playing: time < 4
        fps: ambient.fps
    }
    readonly property real _slid: 0.5 - 0.5 * Math.cos(Math.PI * Math.min(1, slide.time / 4))
    readonly property real shiftX: _fromX + (_toX - _fromX) * _slid
    readonly property real shiftY: _fromY + (_toY - _fromY) * _slid
    // From where it is now: the start first, then the clock, then the end.
    function _slideTo(x, y) {
        _fromX = shiftX
        _fromY = shiftY
        slide.time = 0
        _toX = x
        _toY = y
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: ambient.now = new Date() }
    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        onTriggered: ambient._slideTo((Math.random() - 0.5) * (Theme.mini ? 16 : 32),
                                      (Math.random() - 0.5) * (Theme.mini ? 10 : 20))
    }

    // ---- What to say.

    readonly property var todaysEvents: Store.events.filter(e => !e.all_day && e.endMs > minuteMs && e.day === Store.today)
    readonly property var nextEvent: todaysEvents.length > 0 ? todaysEvents[0] : null
    readonly property var laterEvents: todaysEvents.slice(1, 3)
    readonly property var brief: Store.latestBrief
    readonly property var hero: Store.news.isToday ? (Store.news.hero || ({})) : ({})
    // Needs you: the blocked projects not dismissed.
    readonly property var blocked: Store.needsYou
    readonly property var tickers: Store.quotes.slice(0, 4)

    function untilLabel(ms) {
        const m = Math.max(0, Math.round((ms - minuteMs) / 60000))
        if (m < 1) return qsTr("now")
        if (m < 60) return qsTr("in %1 minutes").arg(m)
        return qsTr("at %1").arg(Qt.formatTime(new Date(ms), "h:mm AP").toLowerCase())
    }
    readonly property string nextLine: {
        const e = nextEvent
        if (!e) return ""
        if (e.startMs <= minuteMs) return qsTr("%1, until %2").arg(e.title).arg(Qt.formatTime(new Date(e.endMs), "h:mm AP").toLowerCase())
        return qsTr("%1 %2").arg(e.title).arg(untilLabel(e.startMs))
    }
    readonly property string thenLine: laterEvents.length === 0 ? ""
        : qsTr("Then %1").arg(laterEvents.map(e => e.title + " at " + Qt.formatTime(new Date(e.startMs), "h:mm AP").toLowerCase()).join(" · "))

    // The rail, in order; each kind only when it has something to show.
    readonly property var cards: {
        const list = []
        if (brief.title) list.push("brief")
        if (tickers.length > 0) list.push("markets")
        if (blocked.length > 0) list.push("blocked")
        if (hero.headline) list.push("pulse")
        if (todaysEvents.length > 3) list.push("later")
        return list
    }
    readonly property int railColumns: Theme.tall ? 2 : Theme.wide ? 4 : Theme.mini ? 2 : 3
    readonly property int railRows: Theme.tall ? 2 : 1
    readonly property var shownCards: cards.slice(0, railColumns * railRows)

    // ---- The look.

    // The backdrop (Settings → Backdrop, Device.backdrop): the mesh is the
    // moving gradient with an aurora hanging over it at night, as on the
    // console's ambient view; the rest are skies of their own (Backdrop),
    // light or dark with the dusk. Only the chosen one is built.
    readonly property bool mesh: Device.backdrop === "mesh"
    Loader {
        id: backdrop
        anchors.fill: parent
        sourceComponent: ambient.mesh ? meshBackdrop : skyBackdrop
        // What reads on it: the loaded backdrop's own pick.
        readonly property color ink: item ? item.ink : "#1D1B24"
        readonly property color inkMuted: item ? item.inkMuted : "#4A4555"
    }
    Component {
        id: meshBackdrop
        Item {
            readonly property color ink: tile.ink
            readonly property color inkMuted: tile.inkMuted
            GradientTile {
                // Full screen: shaded at the skies' size (Theme.backdropResolution).
                resolution: Theme.backdropResolution / Math.max(1, Screen.devicePixelRatio)
                id: tile
                anchors.fill: parent
                radius: 0
                colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
                darkness: ambient.dusk
                whileIdle: true
                maxFps: ambient.fps
                period: Theme.saverDrift
                rings: 2
                ringScale: 1.3
            }
            // At night an aurora in the night glow hangs over the clock. It
            // rises with the dusk; at night the screen saver is up for hours,
            // so it runs small and slow.
            AuroraGlow {
                anchors.fill: parent
                visible: opacity > 0
                opacity: 0.5 * ambient.dusk
                lightMode: false
                whileIdle: true
                maxFps: ambient.fps
                speed: 0.35
                layers: 2
                hem: 0.36
                blend: 0.7
                amplitude: 1.1
            }
        }
    }
    Component {
        id: skyBackdrop
        Backdrop {
            style: Device.backdrop
            darkness: ambient.dusk
            whileIdle: true
            maxFps: ambient.fps
        }
    }
    // Weather over the backdrop and under the words (Settings → Backdrop →
    // Weather), on the backdrop's frames; nothing is built while it is off.
    Weather {
        anchors.fill: parent
        darkness: ambient.dusk
        maxFps: ambient.fps
    }

    readonly property color nightFill: Qt.rgba(0.08, 0.08, 0.12, 0.55)
    readonly property color cardFill: tone(Qt.rgba(1, 1, 1, 0.86), nightFill, dusk)
    readonly property color cardInk: tone("#1D1B24", Qt.rgba(1, 1, 1, 0.78), inkNight)
    readonly property color cardMuted: tone("#4A4555", Qt.rgba(1, 1, 1, 0.55), inkNight)
    readonly property int edge: Theme.mini ? 28 : Theme.tall ? 40 : Theme.wide ? 72 : 56

    Item {
        id: composition
        anchors.fill: parent
        anchors.leftMargin: ambient.edge
        anchors.rightMargin: ambient.edge
        anchors.topMargin: ambient.edge * 0.8
        anchors.bottomMargin: ambient.edge * 0.8
        transform: Translate { x: ambient.shiftX; y: ambient.shiftY }

        // The calm part.
        ColumnLayout {
            id: calm
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            // With nothing in the rail, the clock sits in the middle.
            anchors.topMargin: ambient.shownCards.length === 0 ? Math.max(0, (composition.height - implicitHeight) / 2) : 0
            spacing: 0

            RowLayout {
                spacing: Theme.mini ? 8 : 14
                Label {
                    text: Qt.formatTime(ambient.now, "h:mm AP").split(" ")[0]
                    color: backdrop.ink
                    font.pixelSize: Theme.mini ? 104 : Theme.tall ? 150 : Theme.wide ? 200 : 168
                    font.weight: Font.Light
                    font.letterSpacing: Theme.mini ? -3 : -7
                    lineHeight: 0.92
                }
                Label {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Theme.mini ? 18 : 34
                    text: Qt.formatTime(ambient.now, "AP")
                    color: backdrop.inkMuted
                    font.pixelSize: Theme.mini ? Theme.fontMd : Theme.fontLg
                }
            }
            Label {
                text: Qt.formatDate(ambient.now, "dddd, MMMM d")
                color: backdrop.ink
                font.pixelSize: Theme.mini ? Theme.fontMd : Theme.fontLg
            }
            Label {
                Layout.fillWidth: true
                Layout.topMargin: Theme.mini ? 10 : 22
                visible: text.length > 0
                text: ambient.nextLine
                color: backdrop.ink
                font.pixelSize: Theme.mini ? Theme.fontMd : Theme.fontLg
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0 && !Theme.mini
                text: ambient.thenLine
                color: backdrop.inkMuted
                font.pixelSize: Theme.fontMd - 2
                elide: Text.ElideRight
            }
        }

        // The rail.
        GridLayout {
            id: rail
            visible: ambient.shownCards.length > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: ambient.railRows * cardHeight + (ambient.railRows - 1) * rowSpacing
            columns: ambient.railColumns
            rowSpacing: Theme.mini ? 12 : 18
            columnSpacing: Theme.mini ? 12 : 18
            readonly property int cardHeight: Theme.mini ? 150 : Theme.tall ? 220 : Theme.wide ? 260 : 220

            Repeater {
                model: ambient.shownCards
                delegate: Rectangle {
                    id: card
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: rail.cardHeight
                    radius: Theme.mini ? 22 : 28
                    color: modelData === "blocked" ? ambient.tone("#FFE7DF", ambient.nightFill, ambient.dusk) : ambient.cardFill
                    clip: true
                    Loader {
                        anchors.fill: parent
                        sourceComponent: card.modelData === "brief" ? briefCard
                                       : card.modelData === "markets" ? marketsCard
                                       : card.modelData === "blocked" ? blockedCard
                                       : card.modelData === "pulse" ? pulseCard
                                       : laterCard
                    }
                }
            }
        }
    }

    // ---- The cards.

    component Kicker: Label {
        Layout.fillWidth: true
        font.pixelSize: Theme.fontXs - (Theme.mini ? 2 : 1)
        font.weight: Font.Bold
        font.letterSpacing: 1.3
        elide: Text.ElideRight
    }
    component Title: Label {
        Layout.fillWidth: true
        color: ambient.cardInk
        font.pixelSize: Theme.mini ? Theme.fontSm + 1 : Theme.fontMd
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }
    component Body: Label {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: ambient.cardMuted
        font.pixelSize: Theme.mini ? Theme.fontXs : Theme.fontSm - 1
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        verticalAlignment: Text.AlignTop
        clip: true
        lineHeight: 1.1
    }

    Component {
        id: briefCard
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.mini ? 16 : 22
            spacing: Theme.mini ? 4 : 8
            Kicker {
                text: (ambient.brief.agentName + " · " + ambient.brief.whenLabel).toUpperCase()
                color: ambient.tone(ambient.brief.agentColor || Theme.accent, ambient.cardMuted, ambient.inkNight)
            }
            Title { text: ambient.brief.title || "" }
            Body { text: ambient.brief.summary || "" }
        }
    }

    Component {
        id: marketsCard
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.mini ? 16 : 22
            spacing: Theme.mini ? 6 : 10
            Kicker { text: qsTr("MARKETS"); color: ambient.tone(Theme.success, ambient.cardMuted, ambient.inkNight) }
            Repeater {
                model: ambient.tickers.slice(0, Theme.mini ? 3 : 4)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Label { text: modelData.symbol; color: ambient.cardInk; font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd - 3; font.weight: Font.DemiBold; Layout.preferredWidth: Theme.mini ? 56 : 70 }
                    Label {
                        Layout.fillWidth: true
                        visible: !Theme.mini
                        text: modelData.priceLabel
                        color: ambient.cardMuted
                        font.pixelSize: Theme.fontMd - 3
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }
                    Label {
                        Layout.fillWidth: Theme.mini
                        Layout.preferredWidth: Theme.mini ? -1 : 84
                        horizontalAlignment: Text.AlignRight
                        text: modelData.pctLabel
                        color: ambient.tone(modelData.up ? "#1C7A4E" : "#B5432A", ambient.cardInk, ambient.inkNight)
                        font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd - 3
                        font.weight: Font.DemiBold
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: blockedCard
        ColumnLayout {
            readonly property var project: ambient.blocked[0] || ({})
            anchors.fill: parent
            anchors.margins: Theme.mini ? 16 : 22
            spacing: Theme.mini ? 4 : 8
            Kicker { text: qsTr("NEEDS YOU"); color: ambient.tone("#B23224", "#FF9B8A", ambient.inkNight) }
            Title {
                text: ambient.blocked.length > 1 ? qsTr("%1 and %2 more are blocked").arg(project.name).arg(ambient.blocked.length - 1)
                                                 : qsTr("%1 is blocked").arg(project.name)
                color: ambient.tone("#3B1D12", ambient.cardInk, ambient.inkNight)
            }
            Body {
                text: [project.next_step || project.summary || "", project.hasProgress ? qsTr("%1% done").arg(project.progress) : ""].filter(s => !!s).join(" · ")
                color: ambient.tone("#5A3426", ambient.cardMuted, ambient.inkNight)
            }
        }
    }

    Component {
        id: pulseCard
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            readonly property bool picture: Theme.pictures && !!ambient.hero.imageUrl && !Theme.mini
            Rectangle {
                visible: parent.picture
                Layout.fillWidth: true
                Layout.preferredHeight: parent.height * 0.46
                color: ambient.hero.sectionColor || Theme.accent
                Image {
                    anchors.fill: parent
                    source: parent.parent.picture ? ambient.hero.imageUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 640
                    opacity: 1 - 0.3 * ambient.dusk
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: Theme.mini ? 16 : 20
                spacing: 4
                Kicker {
                    text: (Store.news.agentName || qsTr("Daily Pulse")).toUpperCase() + " · " + qsTr("%1 STORIES").arg(Store.news.itemCount || 0)
                    color: ambient.tone(ambient.hero.sectionColor || Theme.accent, ambient.cardMuted, ambient.inkNight)
                }
                Title { text: ambient.hero.headline || ""; maximumLineCount: parent.parent.picture ? 2 : 3 }
                Body { visible: !parent.parent.picture; text: ambient.hero.takeaway || "" }
                Item { Layout.fillHeight: true; visible: parent.parent.picture }
            }
        }
    }

    Component {
        id: laterCard
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.mini ? 16 : 22
            spacing: Theme.mini ? 6 : 10
            Kicker { text: qsTr("LATER TODAY"); color: ambient.tone(Theme.accent, ambient.cardMuted, ambient.inkNight) }
            Repeater {
                model: ambient.todaysEvents.slice(3, Theme.mini ? 5 : 7)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle { width: 4; Layout.preferredHeight: 22; radius: 2; color: modelData.color }
                    Label { text: Qt.formatTime(new Date(modelData.startMs), "h:mm"); color: ambient.cardMuted; font.pixelSize: Theme.fontSm - 1; Layout.preferredWidth: 46 }
                    Label { Layout.fillWidth: true; text: modelData.title; color: ambient.cardInk; font.pixelSize: Theme.fontSm - 1; font.weight: Font.Medium; elide: Text.ElideRight }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
