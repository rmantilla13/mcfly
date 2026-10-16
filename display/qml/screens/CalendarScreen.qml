import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Calendar: the next days as an agenda, with the week along the top. Events
// come from the calendar agents, colored by calendar. The picked day sits
// large beside the agenda on the wide tiers, over it on Tall; the 7" panel
// has the strip and the agenda alone. The day view's now line glides down
// on each minute; the agenda settles in as the page shows.
Item {
    id: calendar
    property bool shown: true
    // The page picked, under the assistant panel too: it settles in as
    // this turns true, not again when the panel goes.
    property bool isCurrent: true
    // Loops and glides run only while someone can see them.
    readonly property bool moving: shown && !Device.idle && Device.animatedTiles
    Reveal { id: rv; shown: calendar.isCurrent }
    property string pickedDay: Store.today
    readonly property var dayEvents: (Store.eventDays.find(d => d.day === pickedDay) || ({})).events || []
    function closeDetail() { md.closeDetail() }

    function addDays(iso, n) {
        const d = new Date(iso + "T12:00:00")
        d.setDate(d.getDate() + n)
        return Qt.formatDate(d, "yyyy-MM-dd")
    }
    function eventsOn(iso) { return (Store.eventDays.find(d => d.day === iso) || ({})).events || [] }
    // Anything to show at all: a subscription, or events an agent pushed.
    readonly property bool hasCalendar: Store.calendarSources.length > 0 || Store.events.length > 0

    // Small caps over a part of the day tile.
    component Kicker: Label {
        font.pixelSize: Theme.fontXs
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }

    // One day as hours down the side and its events as blocks where they
    // fall, so what's when and what's free reads at a glance. Blocks that
    // would overlap share the width. No block is shorter than a line of its
    // title, so a short event takes a little more room than its time.
    component DayGrid: Item {
        id: grid
        property var events: []   // the day's timed events, by start
        property string day: ""   // yyyy-MM-dd
        property color ink: Theme.text
        property color inkMuted: Theme.textMuted
        property color fill: Theme.surface
        property color stroke: Theme.divider

        readonly property int gutter: 58
        readonly property int minBlock: 40   // a line of title
        readonly property int roomy: 86      // two lines of title and the time
        readonly property int pad: 10   // half an hour label, above and below
        readonly property real dayStart: new Date(day + "T00:00:00").getTime()
        function hourOf(ms) { return Math.max(0, Math.min(24, (ms - dayStart) / 3600000)) }
        // 8 am to 8 pm, or wider to take in the first and last events.
        readonly property int firstHour: Math.min(8, ...events.map(e => Math.floor(hourOf(e.startMs))))
        readonly property int lastHour: Math.max(20, ...events.map(e => Math.ceil(hourOf(e.endMs))))
        readonly property real perHour: (height - 2 * pad) / Math.max(1, lastHour - firstHour)
        function yOf(hour) { return pad + (hour - firstHour) * perHour }
        readonly property int step: perHour >= 40 ? 1 : perHour >= 20 ? 2 : 3
        readonly property var marks: {
            const out = []
            for (let h = Math.ceil(firstHour / step) * step; h <= lastHour; h += step)
                out.push(h)
            return out
        }
        function hourLabel(h) { return Qt.formatTime(new Date(2000, 0, 1, h), "h AP").toLowerCase() }

        // Each block's place: lanes side by side within a run of blocks that
        // overlap, as many lanes as the run needs.
        readonly property var blocks: {
            const out = []
            const laneEnds = []
            let run = []
            let runEnd = -1
            const close = () => {
                const lanes = Math.max(...run.map(b => b.lane)) + 1
                for (const b of run)
                    b.lanes = lanes
            }
            for (const e of events) {
                const top = Math.min(yOf(hourOf(e.startMs)), height - pad - minBlock)
                const bottom = Math.max(top + minBlock, yOf(hourOf(e.endMs)))
                if (run.length > 0 && top >= runEnd) {
                    close()
                    run = []
                    laneEnds.length = 0
                    runEnd = -1
                }
                let lane = laneEnds.findIndex(end => end <= top + 0.5)
                if (lane < 0) {
                    lane = laneEnds.length
                    laneEnds.push(bottom)
                } else {
                    laneEnds[lane] = bottom
                }
                const block = { event: e, top: top, height: bottom - top, lane: lane, lanes: 1 }
                out.push(block)
                run.push(block)
                runEnd = Math.max(runEnd, bottom)
            }
            if (run.length > 0)
                close()
            // A short block grows to two lines of title and its time where
            // nothing sits right under it; its top stays at its start. One
            // that is over stops short of now, so it never reads as on now.
            const now = isToday ? yOf(hourOf(nowMs)) : height
            for (const b of out) {
                let limit = b.event.past ? Math.min(height - pad, now - 3) : height - pad
                for (const o of out) {
                    const beside = o.lane / o.lanes >= (b.lane + 1) / b.lanes || b.lane / b.lanes >= (o.lane + 1) / o.lanes
                    if (o.top > b.top && !beside)
                        limit = Math.min(limit, o.top)
                }
                b.height = Math.max(b.height, Math.min(roomy, limit - b.top))
            }
            return out
        }

        // On the minute: Store.nowAngle moves then.
        readonly property real nowMs: Store.nowAngle >= 0 ? Date.now() : 0
        readonly property bool isToday: day === Store.today

        // The hours.
        Repeater {
            model: grid.marks
            delegate: Item {
                required property int modelData
                y: grid.yOf(modelData)
                width: grid.width
                Label {
                    y: -Math.round(height / 2)
                    width: grid.gutter - 12
                    horizontalAlignment: Text.AlignRight
                    text: grid.hourLabel(modelData)
                    color: grid.inkMuted
                    font.pixelSize: Theme.fontXs - 1
                }
                Rectangle { x: grid.gutter; width: grid.width - grid.gutter; height: 1; color: Qt.rgba(grid.ink.r, grid.ink.g, grid.ink.b, 0.12) }
            }
        }

        // The events.
        Repeater {
            model: grid.blocks
            delegate: Rectangle {
                id: block
                required property var modelData
                readonly property var event: modelData.event
                readonly property real laneWidth: (grid.width - grid.gutter) / modelData.lanes
                x: grid.gutter + modelData.lane * laneWidth
                y: modelData.top + 1
                width: laneWidth - 4
                height: modelData.height - 3
                radius: 12
                color: grid.fill
                border.width: event.now ? 2 : 1
                border.color: event.now ? event.color : grid.stroke
                opacity: event.past ? 0.6 : 1
                clip: true
                Rectangle { x: 8; y: 8; width: 4; height: block.height - 16; radius: 2; color: block.event.color }
                Column {
                    x: 20
                    y: 8
                    width: block.width - 28
                    spacing: 1
                    Label {
                        id: blockTitle
                        width: parent.width
                        text: block.event.title
                        color: grid.ink
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: block.height >= 62 ? 2 : 1
                        elide: Text.ElideRight
                    }
                    Label {
                        visible: block.height >= blockTitle.height + 30
                        width: parent.width
                        text: [block.event.timeLabel, block.event.location].filter(s => !!s).join(" · ")
                        color: grid.inkMuted
                        font.pixelSize: Theme.fontXs
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Now, on today: it glides down to each new minute.
        Rectangle {
            readonly property real hour: grid.hourOf(grid.nowMs)
            visible: grid.isToday && hour >= grid.firstHour && hour <= grid.lastHour
            x: grid.gutter - 5
            y: grid.yOf(hour) - 1
            Behavior on y {
                enabled: calendar.moving
                NumberAnimation { duration: Theme.glide * 2; easing.type: Easing.InOutSine }
            }
            width: grid.width - grid.gutter + 5
            height: 2
            color: Theme.danger
            Rectangle { x: -1; y: -4; width: 10; height: 10; radius: 5; color: Theme.danger }
        }
    }

    // The picked day, large. Beside the agenda (`roomy`) it is a day view:
    // the hours with the events where they fall, then the calendars they come
    // from and how fresh each is (or, with none yet, the code to add one).
    // Over the agenda on Tall it's a short summary: two rows of time and title.
    component DayTile: GradientTile {
        id: dayTile
        property bool live: true
        property bool roomy: true
        radius: Theme.radius
        colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
        seed: 5.1
        rings: 1
        active: calendar.shown && live

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.tall ? 22 : Theme.compact ? 24 : 32
            spacing: Theme.tall ? 4 : 10
            Kicker { color: dayTile.inkMuted; text: Qt.formatDate(new Date(calendar.pickedDay + "T12:00:00"), "dddd").toUpperCase() }
            Label { text: Qt.formatDate(new Date(calendar.pickedDay + "T12:00:00"), "MMMM d"); color: dayTile.ink; font.pixelSize: Theme.tall ? Theme.fontLg + 4 : Theme.fontXl; font.weight: Font.Medium }
            Label {
                text: calendar.dayEvents.length === 0 ? qsTr("Nothing planned")
                    : calendar.dayEvents.length === 1 ? qsTr("1 event") : qsTr("%1 events").arg(calendar.dayEvents.length)
                color: dayTile.inkMuted
                font.pixelSize: Theme.fontSm
            }
            Item { implicitHeight: Theme.tall ? 4 : 8 }

            // Tall: time and title on one line.
            Repeater {
                model: dayTile.roomy ? [] : calendar.dayEvents.slice(0, 2)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle { width: 10; height: 10; radius: 5; color: modelData.color }
                    Label { text: modelData.startLabel; color: dayTile.inkMuted; font.pixelSize: Theme.fontSm; Layout.preferredWidth: 90 }
                    Label { Layout.fillWidth: true; text: modelData.title; color: dayTile.ink; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight }
                }
            }
            Item { visible: !dayTile.roomy; Layout.fillHeight: true }

            // Beside the agenda: all-day events, then the hours with the rest.
            Repeater {
                model: dayTile.roomy ? calendar.dayEvents.filter(e => e.all_day) : []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle { Layout.preferredWidth: 10; Layout.preferredHeight: 10; radius: 5; color: modelData.color }
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("All day · %1").arg(modelData.title)
                        color: dayTile.ink
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }
            DayGrid {
                visible: dayTile.roomy && calendar.hasCalendar
                Layout.fillWidth: true
                Layout.fillHeight: true
                events: calendar.dayEvents.filter(e => !e.all_day)
                day: calendar.pickedDay
                ink: dayTile.ink
                inkMuted: dayTile.inkMuted
                fill: dayTile.glassFill
                stroke: dayTile.glassStroke
            }

            // No calendar at all yet: the code that adds one, on the tile.
            Item { visible: dayTile.roomy && !calendar.hasCalendar; Layout.fillHeight: true }
            ColumnLayout {
                visible: dayTile.roomy && !calendar.hasCalendar && Store.mode !== "pairing"
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    Layout.preferredWidth: Theme.wide ? 168 : 144
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.bottomMargin: 10
                    radius: 16
                    color: "white"
                    Image {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        height: width
                        source: "image://qr/" + encodeURIComponent("https://mcfly.bot/calendars")
                        sourceSize: Qt.size(width, width)
                        smooth: false
                    }
                }
                Label { text: qsTr("Add a calendar"); color: dayTile.ink; font.pixelSize: Theme.fontMd - 2; font.weight: Font.DemiBold }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Scan to paste a Google, iCloud or Outlook link on your phone. McFly reads it every 15 minutes.")
                    color: dayTile.inkMuted
                    font.pixelSize: Theme.fontSm - 1
                    wrapMode: Text.WordWrap
                }
                Label { text: "mcfly.bot/calendars"; color: dayTile.ink; font.pixelSize: Theme.fontSm; font.weight: Font.Medium }
            }

            // Where they come from: each calendar and how fresh it is.
            Kicker { visible: dayTile.roomy && Store.calendarSources.length > 0; Layout.topMargin: 6; color: dayTile.inkMuted; text: qsTr("CALENDARS") }
            Repeater {
                model: dayTile.roomy ? Store.calendarSources : []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 5
                        Layout.preferredWidth: 10
                        Layout.preferredHeight: 10
                        radius: 5
                        color: modelData.color
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label { Layout.fillWidth: true; text: modelData.name; color: dayTile.ink; font.pixelSize: Theme.fontXs + 1; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Label {
                            Layout.fillWidth: true
                            text: !modelData.enabled ? qsTr("Paused")
                                : modelData.error ? modelData.error
                                : qsTr("%1 events · synced %2").arg(modelData.eventCount).arg(modelData.syncedLabel)
                            color: modelData.enabled && modelData.error ? Theme.danger : dayTile.inkMuted
                            font.pixelSize: Theme.fontXs
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    MasterDetail {
        id: md
        anchors.fill: parent
        paneWidth: Theme.wide ? 420 : 360
        hasDetail: Theme.paned

        // The next weeks, day by day.
        master: ColumnLayout {
            anchors.fill: parent
            spacing: 14
            ScreenHeader {
                Layout.fillWidth: true
                title: qsTr("Calendar")
                subtitle: Qt.formatDate(new Date(Store.today + "T12:00:00"), "MMMM yyyy")
            }
            // The days ahead.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.mini ? 6 : 8
                opacity: rv.at(0)
                transform: Translate { y: rv.rise(0) }
                Repeater {
                    model: Theme.dayColumns
                    delegate: Rectangle {
                        id: dayCell
                        required property int index
                        readonly property string iso: calendar.addDays(Store.today, index)
                        readonly property date date: new Date(iso + "T12:00:00")
                        readonly property bool chosen: iso === calendar.pickedDay
                        // Not `count`: inside the dots' Repeater that name is the Repeater's own.
                        readonly property int dotCount: calendar.eventsOn(iso).length
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: Theme.mini ? 66 : 82
                        radius: 18
                        color: chosen ? Theme.accent : (iso === Store.today ? Theme.accentSoft : Theme.surface)
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Label { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(date, "ddd").toUpperCase(); color: chosen ? Theme.accentInk : Theme.textMuted; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                            Label { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(date, "d"); color: chosen ? Theme.accentInk : Theme.text; font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd; font.weight: Font.DemiBold }
                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 3
                                Repeater {
                                    model: Math.min(dayCell.dotCount, 4)
                                    delegate: Rectangle {
                                        required property int index
                                        width: 5; height: 5; radius: 2.5
                                        color: dayCell.chosen ? Theme.accentInk : (calendar.eventsOn(dayCell.iso)[index] || {}).color || Theme.accent
                                    }
                                }
                            }
                        }
                        TapHandler { onTapped: calendar.pickedDay = iso }
                    }
                }
            }
            // Tall: the picked day over the agenda.
            DayTile {
                visible: Theme.tall
                live: Theme.tall
                roomy: false
                Layout.fillWidth: true
                Layout.preferredHeight: 230
                opacity: rv.at(1)
                transform: Translate { y: rv.rise(1) }
            }
            // The agenda from the picked day on.
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.mini ? 6 : 10
                boundsBehavior: Flickable.StopAtBounds
                model: Store.events.filter(e => e.day >= calendar.pickedDay)
                section.property: "dayLabel"
                section.criteria: ViewSection.FullString
                section.delegate: Label {
                    width: ListView.view.width
                    topPadding: Theme.mini ? 8 : 12
                    bottomPadding: 6
                    text: section.toUpperCase()
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }
                delegate: Rectangle {
                    id: agendaRow
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: Theme.mini ? 64 : 78
                    radius: Theme.radiusSm
                    color: modelData.now ? Theme.accentSoft : Theme.surface
                    opacity: (modelData.past ? 0.6 : 1) * rv.at(index + 2)
                    transform: Translate { y: rv.rise(agendaRow.index + 2) }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.mini ? 14 : 18
                        anchors.rightMargin: Theme.mini ? 14 : 18
                        spacing: 14
                        Rectangle { width: 6; height: Theme.mini ? 36 : 44; radius: 3; color: modelData.color }
                        ColumnLayout {
                            Layout.preferredWidth: Theme.mini ? 92 : 120
                            spacing: 0
                            Label { text: modelData.startLabel; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                            Label { visible: !modelData.all_day; text: modelData.timeLabel.split(" – ")[1] || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { Layout.fillWidth: true; text: modelData.title; color: Theme.text; font.pixelSize: Theme.fontMd - 2; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Label {
                                Layout.fillWidth: true
                                text: modelData.calendar + (modelData.location ? " · " + modelData.location : "")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontXs
                                elide: Text.ElideRight
                            }
                        }
                        Label { visible: modelData.now; text: qsTr("NOW"); color: Theme.accent; font.pixelSize: Theme.fontXs; font.weight: Font.Bold; font.letterSpacing: 1 }
                    }
                }
                // Beside the day tile (Wide, Compact) the code to scan is on the tile.
                EmptyState {
                    anchors.fill: parent
                    visible: Store.events.length === 0
                    readonly property bool none: Store.calendarSources.length === 0
                    icon: "calendar"
                    text: none ? qsTr("No calendars yet") : qsTr("Nothing coming up")
                    hint: !none ? qsTr("Your calendars have nothing planned for the next weeks.")
                        : Theme.paned ? qsTr("Scan the code beside this to subscribe to a Google, iCloud or Outlook calendar.")
                        : qsTr("Subscribe to Google, iCloud or Outlook calendars from your phone. McFly reads them every 15 minutes.")
                    url: none && !Theme.paned ? "https://mcfly.bot/calendars" : ""
                    action: qsTr("Add a calendar")
                    caption: qsTr("Scan to paste its iCal link on your phone. The link stays on the server.")
                }
            }
        }

        // Wide and Compact: the picked day beside the agenda.
        detail: DayTile {
            anchors.fill: parent
            live: Theme.paned
        }
    }
}
