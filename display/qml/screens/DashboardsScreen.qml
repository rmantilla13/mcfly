import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Dashboards: the boards agents lay out themselves, one at a time, as a
// grid of widgets: metrics, statuses, progress, charts, lists and notes.
// Six columns on a wall, four on the panel, two on the small ones (a wide
// widget then takes the row).
Item {
    id: boards
    property int index: 0
    readonly property var board: Store.dashboards[Math.min(index, Math.max(0, Store.dashboards.length - 1))] || ({})
    readonly property var widgets: board.widgets || []

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: 14

        ScreenHeader {
            Layout.fillWidth: true
            title: boards.board.title || qsTr("Dashboards")
            subtitle: boards.board.subtitle ? boards.board.subtitle + (boards.board.updatedLabel ? " · " + boards.board.updatedLabel : "")
                    : boards.board.updatedLabel ? qsTr("Updated %1 by %2").arg(boards.board.updatedLabel).arg(boards.board.agentName) : ""
            // One chip per board.
            ChipRow {
                Layout.fillWidth: true
                visible: Store.dashboards.length > 1
                model: Store.dashboards.map((d, i) => ({ id: String(i), label: d.title }))
                current: String(boards.index)
                onPicked: id => boards.index = parseInt(id)
            }
        }

        FocusFlickable {
            id: boardsView
            Layout.fillWidth: true
            Layout.fillHeight: true
            fadeColor: Theme.background
            contentHeight: gridCol.implicitHeight
            clip: true
            GridLayout {
                id: gridCol
                width: parent.width
                columns: Theme.widgetColumns
                columnSpacing: Theme.spacing
                rowSpacing: Theme.spacing
                Repeater {
                    model: boards.widgets
                    delegate: Rectangle {
                        required property var modelData
                        readonly property string type: modelData.type || ""
                        Layout.fillWidth: true
                        Layout.columnSpan: modelData.wide ? 2 : 1
                        Layout.preferredWidth: modelData.wide ? 2 : 1
                        Layout.preferredHeight: Theme.widgetRowHeight + (type === "text" || type === "list" ? 40 : 0)
                        radius: Theme.radiusSm
                        color: Theme.surface

                        // metric
                        ColumnLayout {
                            visible: type === "metric"
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: 4
                            Label { Layout.fillWidth: true; text: modelData.label || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight }
                            Item { Layout.fillHeight: true }
                            Label { Layout.fillWidth: true; text: modelData.valueLabel || ""; color: Theme.text; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Label {
                                visible: !!modelData.hasDelta
                                text: modelData.deltaLabel || ""
                                color: modelData.up ? Theme.gain : Theme.loss
                                font.pixelSize: Theme.fontXs
                                font.weight: Font.DemiBold
                            }
                        }
                        // status
                        ColumnLayout {
                            visible: type === "status"
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: 6
                            RowLayout {
                                spacing: 10
                                Rectangle {
                                    width: 16; height: 16; radius: 8
                                    color: modelData.stateColor || Theme.textMuted
                                    SequentialAnimation on opacity {
                                        running: modelData.state === "warn" || modelData.state === "down"
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 900 }
                                        NumberAnimation { to: 1; duration: 900 }
                                    }
                                }
                                Label { text: modelData.label || ""; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            Label { text: modelData.stateLabel || ""; color: modelData.stateColor || Theme.text; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold }
                            Label { Layout.fillWidth: true; visible: !!modelData.detail; text: modelData.detail || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                            Item { Layout.fillHeight: true }
                        }
                        // progress
                        ColumnLayout {
                            visible: type === "progress"
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: 6
                            Label { Layout.fillWidth: true; text: modelData.label || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight }
                            Item { Layout.fillHeight: true }
                            Label { text: modelData.valueLabel || ""; color: Theme.text; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 10; radius: 5
                                color: Theme.sunken
                                Rectangle { height: parent.height; radius: 5; width: parent.width * (modelData.fraction || 0); color: Theme.accent }
                            }
                        }
                        // chart
                        ColumnLayout {
                            visible: type === "chart"
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: modelData.label || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { text: modelData.valueLabel || ""; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                            }
                            Sparkline { Layout.fillWidth: true; Layout.fillHeight: true; points: modelData.points || []; color: Theme.accent }
                        }
                        // list
                        ColumnLayout {
                            visible: type === "list"
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: 6
                            Label { visible: !!modelData.title; text: modelData.title || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                            Repeater {
                                model: (modelData.items || []).slice(0, Theme.mini ? 4 : 5)
                                delegate: RowLayout {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { width: 6; height: 6; radius: 3; color: Theme.accent }
                                    Label { Layout.fillWidth: true; text: modelData; color: Theme.text; font.pixelSize: Theme.fontSm; elide: Text.ElideRight }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                        // text
                        ColumnLayout {
                            visible: type === "text"
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: 6
                            Label { visible: !!modelData.title; text: modelData.title || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                            Label { Layout.fillWidth: true; Layout.fillHeight: true; text: modelData.body || ""; color: Theme.text; font.pixelSize: Theme.fontSm; wrapMode: Text.WordWrap; elide: Text.ElideRight; verticalAlignment: Text.AlignTop }
                        }
                    }
                }
            }
            // Over the view, not in its (empty, zero-height) content.
            EmptyState {
                parent: boardsView
                anchors.fill: parent
                visible: Store.dashboards.length === 0
                icon: "grid"
                text: qsTr("No dashboards yet")
                hint: qsTr("An agent sends one with a title and its widgets.")
                url: "https://mcfly.bot/agents"
                action: qsTr("Add an agent")
                caption: qsTr("Scan to open Agents on your phone: pick what it's for and it gives you the prompt to paste.")
            }
        }
    }
}
