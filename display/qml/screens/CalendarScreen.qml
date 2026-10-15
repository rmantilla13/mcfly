import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Calendar: the next days as an agenda, with the week along the top. Events
// come from the calendar agents, colored by calendar. The picked day sits
// large beside the agenda on the wide tiers, over it on Tall; the 7" panel
// has the strip and the agenda alone.
Item {
    id: calendar
    property bool shown: true
    property string pickedDay: Store.today
    readonly property var dayEvents: (Store.eventDays.find(d => d.day === pickedDay) || ({})).events || []
    function closeDetail() { md.closeDetail() }

    function addDays(iso, n) {
        const d = new Date(iso + "T12:00:00")
        d.setDate(d.getDate() + n)
        return Qt.formatDate(d, "yyyy-MM-dd")
    }
    function eventsOn(iso) { return (Store.eventDays.find(d => d.day === iso) || ({})).events || [] }

    // The picked day, large.
    component DayTile: GradientTile {
        id: dayTile
        property bool live: true
        property int shownEvents: 6
        radius: Theme.radius
        colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
        seed: 5.1
        rings: 1
        active: calendar.shown && live
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.tall ? 22 : Theme.compact ? 24 : 32
            spacing: Theme.tall ? 4 : 10
            Label { text: Qt.formatDate(new Date(calendar.pickedDay + "T12:00:00"), "dddd").toUpperCase(); color: dayTile.inkMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
            Label { text: Qt.formatDate(new Date(calendar.pickedDay + "T12:00:00"), "MMMM d"); color: dayTile.ink; font.pixelSize: Theme.tall ? Theme.fontLg + 4 : Theme.fontXl; font.weight: Font.Medium }
            Label {
                text: calendar.dayEvents.length === 0 ? qsTr("Nothing planned")
                    : calendar.dayEvents.length === 1 ? qsTr("1 event") : qsTr("%1 events").arg(calendar.dayEvents.length)
                color: dayTile.inkMuted
                font.pixelSize: Theme.fontSm
            }
            Item { height: Theme.tall ? 4 : 8 }
            Repeater {
                model: calendar.dayEvents.slice(0, dayTile.shownEvents)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle { width: 10; height: 10; radius: 5; color: modelData.color }
                    Label { text: modelData.startLabel; color: dayTile.inkMuted; font.pixelSize: Theme.fontSm; Layout.preferredWidth: 90 }
                    Label { Layout.fillWidth: true; text: modelData.title; color: dayTile.ink; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight }
                }
            }
            Item { Layout.fillHeight: true }
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
                shownEvents: 2
                Layout.fillWidth: true
                Layout.preferredHeight: 230
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
                    required property var modelData
                    width: ListView.view.width
                    height: Theme.mini ? 64 : 78
                    radius: Theme.radiusSm
                    color: modelData.now ? Theme.accentSoft : Theme.surface
                    opacity: modelData.past ? 0.6 : 1
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
                EmptyState {
                    anchors.fill: parent
                    visible: Store.events.length === 0
                    text: qsTr("Nothing on the calendar.")
                    hint: qsTr("A calendar agent pushes events to McFly; see docs/AGENTS.md.")
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
