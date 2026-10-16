import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Home as a bento (Settings → Home → Bento): the time and the health of
// everything in one line, then tiles, each a door into its screen. The newest
// brief is the big tile, on the drifting gradient; beside it what's next and
// the numbers; on the right the markets and the lead story. A tile with
// nothing to show steps aside and the others in its column take the room; a
// column with nothing in it goes and the rest widen. Only the brief's tile
// always stays, so a new account sees where its briefs will land.
//
// Wide and Compact: three columns (the brief and projects | what's next, a
// number, what's coming | the markets and the news). Mini: two (the brief |
// what's next and the markets). Tall: one column that scrolls.
Item {
    id: bento

    // On screen and not covered (Main.qml via HomeLayouts): the gradient only
    // drifts while it is.
    property bool shown: true
    // Picked (Main.qml, as every screen gets it); this layout doesn't animate in yet.
    property bool isCurrent: true
    signal openScreen(int index)
    signal openAssistant(string question)
    signal pushToTalk()

    property date now: new Date()
    Timer { interval: 1000; running: bento.visible; repeat: true; triggeredOnStart: true; onTriggered: bento.now = new Date() }
    readonly property real minuteMs: Math.floor(now.getTime() / 60000) * 60000

    // ---- What the tiles show (Store's rows, shaped in FeedStore.cpp).
    readonly property var brief: Store.latestBrief
    readonly property bool hasBrief: !!(brief && brief.title)
    readonly property var upcoming: Store.upcoming.filter(e => !(e.all_day || e.allDay) && e.endMs >= minuteMs)
    readonly property var nextEvent: upcoming.length > 0 ? upcoming[0] : null
    readonly property var later: upcoming.slice(1, 4)
    readonly property var quotes: Store.quotes.slice(0, Theme.wide ? 5 : 4)
    readonly property var metric: Store.metrics.length > 0 ? Store.metrics[0] : null
    readonly property var moreMetrics: Store.metrics.slice(1, 3)
    readonly property var story: Store.news && Store.news.hero && Store.news.hero.headline ? Store.news.hero : null
    readonly property var projects: Store.projects.filter(p => p.status !== "done").slice(0, 3)
    readonly property var blocked: Store.projects.filter(p => p.status === "blocked")
    // The health line: every status on the boards (API, workers…), then what's blocked.
    readonly property var pills: {
        const out = []
        for (const board of Store.dashboards)
            for (const w of (board.widgets || []))
                if (w.type === "status" && out.length < 3)
                    out.push({ text: (w.label || "") + " " + (w.stateLabel || ""), color: w.stateColor || Theme.textMuted })
        if (blocked.length === 1)
            out.push({ text: qsTr("%1 blocked").arg(blocked[0].name), color: Theme.danger })
        else if (blocked.length > 1)
            out.push({ text: qsTr("%1 blocked").arg(blocked.length), color: Theme.danger })
        return out
    }

    // Nothing at all yet (a new account): the brief's tile and two that say
    // what to connect, each with a code to scan.
    readonly property bool emptyFeed: !hasBrief && !nextEvent && later.length === 0 && quotes.length === 0
                                      && !metric && !story && projects.length === 0

    function untilLabel(ms) {
        const m = Math.max(0, Math.round((ms - minuteMs) / 60000))
        if (m < 1) return qsTr("now")
        if (m < 60) return qsTr("in %1 min").arg(m)
        const h = Math.floor(m / 60), r = m % 60
        return r === 0 ? qsTr("in %1 h").arg(h) : qsTr("in %1 h %2 min").arg(h).arg(r)
    }
    function nextHeading(e) {
        if (!e) return ""
        if (e.startMs <= minuteMs) return qsTr("ON NOW · ENDS %1").arg(untilLabel(e.endMs).toUpperCase())
        if (e.day !== Store.today) return qsTr("NEXT · %1").arg((e.dayLabel || "").toUpperCase())
        return qsTr("NEXT · %1").arg(untilLabel(e.startMs).toUpperCase())
    }
    function countLabel(n, one, many) { return n === 1 ? one : many.arg(n) }

    // ---- The pieces.

    component Caps: Label {
        font.pixelSize: Theme.fontXs - (Theme.mini ? 1 : 0)
        font.weight: Font.Bold
        font.letterSpacing: 1.3
        elide: Text.ElideRight
    }

    // A plain tile: the surface, a door into `target`'s screen.
    component Tile: Rectangle {
        property int target: -1
        radius: Theme.radius
        color: Theme.surface
        clip: true
        TapHandler { enabled: parent.target >= 0; onTapped: bento.openScreen(parent.target) }
    }

    // The time, the date, the sync, and the health pills.
    component StatusLine: RowLayout {
        spacing: Theme.mini ? 12 : 18
        Label {
            text: Qt.formatTime(bento.now, "h:mm AP").split(" ")[0]
            color: Theme.text
            font.pixelSize: Theme.mini ? 34 : 44
            font.weight: Font.Light
            font.letterSpacing: -1.5
        }
        ColumnLayout {
            Layout.fillWidth: !Theme.tall
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: Qt.formatDate(bento.now, Theme.mini ? "ddd, MMM d" : "dddd, MMMM d")
                color: Theme.text
                font.pixelSize: Theme.fontSm + (Theme.mini ? 0 : 1)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: [Store.lastSyncLabel, Store.agents.length > 0 ? bento.countLabel(Store.agents.length, qsTr("1 agent"), qsTr("%1 agents")) : ""]
                      .filter(s => !!s).join(" · ")
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
                elide: Text.ElideRight
            }
        }
        Item { Layout.fillWidth: Theme.tall }
        Repeater {
            model: Theme.mini || Theme.tall ? bento.pills.slice(0, 2) : bento.pills
            delegate: Rectangle {
                required property var modelData
                implicitHeight: Theme.mini ? 36 : 44
                implicitWidth: pillRow.implicitWidth + (Theme.mini ? 24 : 32)
                radius: height / 2
                color: Theme.surface
                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle { width: 9; height: 9; radius: 4.5; color: modelData.color }
                    Label { text: modelData.text; color: Theme.text; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold }
                }
            }
        }
    }

    // The newest brief on the gradient; with none yet, where they'll land.
    component BriefTile: GradientTile {
        id: briefTile
        baseColor: bento.hasBrief && bento.brief.agentColor ? bento.brief.agentColor : Theme.accent
        active: bento.shown
        rings: 1
        seed: 2
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.mini ? 18 : 26
            spacing: Theme.mini ? 6 : 10
            Caps {
                Layout.fillWidth: true
                color: briefTile.inkMuted
                text: bento.hasBrief ? [bento.brief.agentName, bento.brief.whenLabel].filter(s => !!s).join(" · ").toUpperCase()
                                     : qsTr("BRIEFS")
            }
            Label {
                Layout.fillWidth: true
                text: bento.hasBrief ? bento.brief.title : qsTr("Your briefs land here")
                color: briefTile.ink
                font.pixelSize: Theme.mini ? Theme.fontLg : Theme.fontXl - 8
                font.weight: Font.DemiBold
                lineHeight: 1.08
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: Text.AlignTop
                text: bento.hasBrief ? (bento.brief.summary || "")
                                     : qsTr("A Grok bot's report, an agent's check-in: the newest one fills this tile. Make a bot at mcfly.bot/bots.")
                color: briefTile.inkMuted
                font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd - 4
                lineHeight: 1.3
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }
            Label {
                visible: Store.briefs.length > 0
                text: bento.countLabel(Store.briefs.length, qsTr("1 brief ›"), qsTr("%1 briefs ›"))
                color: briefTile.ink
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
            }
        }
        TapHandler { onTapped: bento.openScreen(1) }
    }

    // What's next, on its calendar's colour.
    component NextTile: Tile {
        target: 6
        visible: !!bento.nextEvent
        color: bento.nextEvent && bento.nextEvent.color ? bento.nextEvent.color : Theme.accent
        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.mini ? 16 : 22
            spacing: 4
            Caps { Layout.fillWidth: true; color: Qt.rgba(1, 1, 1, 0.88); text: bento.nextHeading(bento.nextEvent) }
            Label {
                Layout.fillWidth: true
                text: bento.nextEvent ? bento.nextEvent.title : ""
                color: "white"
                font.pixelSize: Theme.mini ? Theme.fontMd : Theme.fontLg
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: {
                    const e = bento.nextEvent
                    if (!e) return ""
                    const then = bento.later.length > 0 ? qsTr("then %1 %2").arg(bento.later[0].title).arg(bento.later[0].startLabel || "") : ""
                    return [e.startLabel || e.timeLabel, then].filter(s => !!s).join(" · ")
                }
                color: Qt.rgba(1, 1, 1, 0.9)
                font.pixelSize: Theme.mini ? Theme.fontXs : Theme.fontSm
                elide: Text.ElideRight
            }
        }
    }

    // The first number on the boards, big, and the next two under it.
    component MetricTile: Tile {
        target: 5
        visible: !!bento.metric
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.mini ? 16 : 20
            spacing: 4
            Label {
                Layout.fillWidth: true
                text: bento.metric ? bento.metric.label : ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontSm
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: bento.metric ? bento.metric.valueLabel : ""
                color: Theme.text
                font.pixelSize: Theme.fontXl - 8
                font.weight: Font.DemiBold
                font.letterSpacing: -1
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.fontLg
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: !!(bento.metric && bento.metric.hasDelta && bento.metric.deltaLabel)
                text: bento.metric ? bento.metric.deltaLabel : ""
                color: bento.metric && bento.metric.up === false ? Theme.loss : Theme.gain
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Item { Layout.fillHeight: true }
            Repeater {
                model: bento.moreMetrics
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Label { Layout.fillWidth: true; text: modelData.label; color: Theme.textMuted; font.pixelSize: Theme.fontXs + 1; elide: Text.ElideRight }
                    Label { text: modelData.valueLabel; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                }
            }
        }
    }

    // What's coming after the next one.
    component LaterTile: Tile {
        target: 6
        visible: bento.later.length > 0
        implicitHeight: laterCol.implicitHeight + 2 * (Theme.mini ? 16 : 20)
        ColumnLayout {
            id: laterCol
            anchors.fill: parent
            anchors.margins: Theme.mini ? 16 : 20
            spacing: 10
            Caps { Layout.fillWidth: true; color: Theme.textMuted; text: qsTr("COMING UP") }
            Repeater {
                model: bento.later
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle { width: 4; Layout.preferredHeight: 22; radius: 2; color: modelData.color || Theme.accent }
                    Label { text: modelData.day === Store.today ? (modelData.startLabel || "") : (modelData.dayLabel || ""); color: Theme.textMuted; font.pixelSize: Theme.fontXs + 1 }
                    Label { Layout.fillWidth: true; text: modelData.title; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // The markets: symbol, its day as a line, the price, the move.
    component MarketsTile: Tile {
        target: 2
        visible: bento.quotes.length > 0
        implicitHeight: marketsCol.implicitHeight + 2 * (Theme.mini ? 16 : 20)
        ColumnLayout {
            id: marketsCol
            anchors.fill: parent
            anchors.margins: Theme.mini ? 16 : 20
            spacing: Theme.mini ? 6 : 10
            RowLayout {
                Layout.fillWidth: true
                Label { Layout.fillWidth: true; text: qsTr("Markets"); color: Theme.text; font.pixelSize: Theme.fontMd - 4; font.weight: Font.DemiBold }
                Label { text: bento.quotes.length > 0 ? (bento.quotes[0].asOfLabel || "") : ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs }
            }
            Repeater {
                model: bento.quotes
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Label { Layout.preferredWidth: Theme.mini ? 52 : 60; text: modelData.symbol; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.Bold; elide: Text.ElideRight }
                    Sparkline {
                        visible: !Theme.mini && (modelData.history || []).length > 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        points: modelData.history || []
                        color: modelData.up ? Theme.gain : Theme.loss
                        lineWidth: 2
                    }
                    Item { visible: Theme.mini || (modelData.history || []).length <= 1; Layout.fillWidth: true }
                    Label { text: modelData.priceLabel || ""; color: Theme.text; font.pixelSize: Theme.fontSm }
                    Label {
                        Layout.preferredWidth: Theme.mini ? 64 : 72
                        horizontalAlignment: Text.AlignRight
                        text: modelData.pctLabel || ""
                        color: modelData.flat ? Theme.textMuted : modelData.up ? Theme.gain : Theme.loss
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // The lead story: its picture (or its section's colour), the headline.
    component NewsTile: Tile {
        id: newsTile
        target: 3
        visible: !!bento.story
        readonly property color section: bento.story && bento.story.sectionColor ? bento.story.sectionColor : Theme.glowBlue
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(72, newsTile.height * 0.46)
                clip: true
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.lighter(newsTile.section, 1.35) }
                        GradientStop { position: 1; color: newsTile.section }
                    }
                }
                Image {
                    anchors.fill: parent
                    visible: Theme.pictures && status === Image.Ready
                    source: Theme.pictures && bento.story && bento.story.imageUrl ? bento.story.imageUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {
                    visible: !!(bento.story && bento.story.sectionName)
                    x: 14; y: 12
                    implicitHeight: 28
                    implicitWidth: sectionLabel.implicitWidth + 22
                    radius: 12
                    color: Qt.rgba(0, 0, 0, 0.38)
                    Label {
                        id: sectionLabel
                        anchors.centerIn: parent
                        text: bento.story ? (bento.story.sectionName || "").toUpperCase() : ""
                        color: "white"
                        font.pixelSize: Theme.fontXs - 2
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: Theme.mini ? 14 : 18
                spacing: 4
                Label {
                    Layout.fillWidth: true
                    text: bento.story ? bento.story.headline : ""
                    color: Theme.text
                    font.pixelSize: Theme.fontMd - 3
                    font.weight: Font.DemiBold
                    lineHeight: 1.15
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    verticalAlignment: Text.AlignTop
                    visible: !Theme.mini && !!(bento.story && bento.story.takeaway)
                    text: bento.story ? (bento.story.takeaway || "") : ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSm
                    lineHeight: 1.3
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }
                Item { visible: Theme.mini || !(bento.story && bento.story.takeaway); Layout.fillHeight: true }
                Label {
                    Layout.fillWidth: true
                    text: {
                        const n = Store.news ? (Store.news.itemCount || 0) - 1 : 0
                        const who = Store.news ? (Store.news.agentName || "") : ""
                        return [who, n > 0 ? bento.countLabel(n, qsTr("1 more story"), qsTr("%1 more stories")) : ""].filter(s => !!s).join(" · ")
                    }
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs + 1
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Projects: the blocked ones first, each with how far along it is.
    component ProjectsTile: Tile {
        target: 4
        visible: bento.projects.length > 0
        implicitHeight: projectsCol.implicitHeight + 2 * (Theme.mini ? 16 : 20)
        ColumnLayout {
            id: projectsCol
            anchors.fill: parent
            anchors.margins: Theme.mini ? 16 : 20
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Label { Layout.fillWidth: true; text: qsTr("Projects"); color: Theme.text; font.pixelSize: Theme.fontMd - 4; font.weight: Font.DemiBold }
                Label {
                    visible: bento.blocked.length > 0
                    text: qsTr("%1 blocked").arg(bento.blocked.length)
                    color: Theme.danger
                    font.pixelSize: Theme.fontXs + 1
                    font.weight: Font.DemiBold
                }
            }
            Repeater {
                model: bento.projects
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Label { Layout.preferredWidth: 110; text: modelData.name; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Rectangle {
                        visible: !!modelData.hasProgress
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 4
                        color: Theme.sunken
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, (modelData.progress || 0) / 100))
                            height: parent.height
                            radius: 4
                            color: modelData.statusColor || Theme.accent
                        }
                    }
                    Label {
                        Layout.fillWidth: !modelData.hasProgress
                        horizontalAlignment: Text.AlignRight
                        text: modelData.hasProgress ? Math.round(modelData.progress || 0) + "%" : (modelData.statusLabel || "")
                        color: modelData.status === "blocked" ? Theme.danger : Theme.textMuted
                        font.pixelSize: Theme.fontXs + 1
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // What to connect, while there's nothing to show (EmptyState: a line, a
    // hint, a code that opens the page on mcfly.bot).
    component StartTile: Tile {
        id: startTile
        property string what: ""
        property string hint: ""
        property string url: ""
        property string action: ""
        implicitHeight: startState.implicitHeight
        EmptyState {
            id: startState
            anchors.fill: parent
            text: startTile.what
            hint: startTile.hint
            url: startTile.url
            action: startTile.action
        }
    }
    component CalendarStart: StartTile {
        target: 6
        what: qsTr("Nothing on the calendar")
        hint: qsTr("Add a calendar's iCal link and what's next shows here.")
        url: "https://mcfly.bot/calendars"
        action: qsTr("Add a calendar")
    }
    component AgentsStart: StartTile {
        target: 1
        what: qsTr("Nothing from your agents yet")
        hint: qsTr("Briefs, markets and news from agents and Grok bots fill these tiles.")
        url: "https://mcfly.bot/bots"
        action: qsTr("Make a Grok bot")
    }

    // ---- Wide and Compact: three columns. Mini: two.
    ColumnLayout {
        visible: !Theme.tall
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.spacing

        StatusLine { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacing

            // The brief, and the projects under it.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: Theme.mini ? 3 : 5
                spacing: Theme.spacing
                BriefTile { Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 2 }
                ProjectsTile { visible: !Theme.mini && bento.projects.length > 0; Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 1 }
            }

            // What's next, a number, what's coming (Mini: next and the markets).
            ColumnLayout {
                visible: !!bento.nextEvent || (!Theme.mini && (!!bento.metric || bento.later.length > 0)) || (Theme.mini && bento.quotes.length > 0)
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: Theme.mini ? 2 : 3
                spacing: Theme.spacing
                NextTile { Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 1 }
                MetricTile { visible: !Theme.mini && !!bento.metric; Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 1 }
                LaterTile { visible: !Theme.mini && bento.later.length > 0; Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 1 }
                MarketsTile { visible: Theme.mini && bento.quotes.length > 0; Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 1 }
            }

            // Nothing yet: what to connect (Mini: the calendar only).
            ColumnLayout {
                visible: bento.emptyFeed
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: Theme.mini ? 2 : 7
                spacing: Theme.spacing
                CalendarStart { Layout.fillWidth: true; Layout.fillHeight: true }
                AgentsStart { visible: !Theme.mini; Layout.fillWidth: true; Layout.fillHeight: true }
            }

            // The markets and the lead story.
            ColumnLayout {
                visible: !Theme.mini && (bento.quotes.length > 0 || !!bento.story)
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 4
                spacing: Theme.spacing
                MarketsTile { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight; Layout.fillHeight: !bento.story }
                NewsTile { Layout.fillWidth: true; Layout.fillHeight: true }
            }
        }
    }

    // ---- Tall: one column, top to bottom, that scrolls.
    Flickable {
        id: tallFlick
        visible: Theme.tall
        anchors.fill: parent
        contentWidth: width
        contentHeight: tallColumn.implicitHeight + 2 * Theme.pageMargin
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ColumnLayout {
            id: tallColumn
            x: Theme.pageMargin
            y: Theme.pageMargin
            width: tallFlick.width - 2 * Theme.pageMargin
            spacing: Theme.spacing
            StatusLine { Layout.fillWidth: true }
            BriefTile { Layout.fillWidth: true; Layout.preferredHeight: 380 }
            NextTile { Layout.fillWidth: true; Layout.preferredHeight: 160 }
            MarketsTile { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight }
            NewsTile { Layout.fillWidth: true; Layout.preferredHeight: 360 }
            ProjectsTile { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight }
            MetricTile { Layout.fillWidth: true; Layout.preferredHeight: 200 }
            LaterTile { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight }
            CalendarStart { visible: bento.emptyFeed; Layout.fillWidth: true; Layout.preferredHeight: implicitHeight + 40 }
            AgentsStart { visible: bento.emptyFeed; Layout.fillWidth: true; Layout.preferredHeight: implicitHeight + 40 }
        }
    }
}
