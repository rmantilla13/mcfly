import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly

// A board's statuses side by side, under one line that sums them up ("1 down
// · 1 warning · 1 OK"): Store.boardLayout merges two or more status widgets
// in a row into one of these. Each status is its dot, its name, its state in
// its colour and a line of detail; one that needs a look breathes
// (StatusDot) instead of blinking. A long run wraps: `perRow` statuses to a
// row (boardLayout's, which made the strip a row taller for each).
//
//   HealthStrip { statuses: indexes.map(i => widgets[i]); summary: cell.summary
//                 stateColor: cell.stateColor; perRow: cell.perRow; running: boards.shown }
Rectangle {
    id: strip
    property var statuses: []
    property string summary: ""
    property color stateColor: Theme.textMuted
    property int perRow: statuses.length
    property bool running: true

    readonly property int _columns: Math.max(1, Math.min(perRow, statuses.length))
    readonly property int _rows: Math.max(1, Math.ceil(statuses.length / _columns))
    // The detail line goes where a row is short (the 7" panel).
    readonly property bool roomy: height / _rows >= 132

    radius: Theme.radiusSm
    color: Theme.surface

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.mini ? 14 : 18
        spacing: Theme.mini ? 6 : 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle { width: 10; height: 10; radius: 5; color: strip.stateColor }
            Label {
                text: qsTr("HEALTH")
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
            }
            Label {
                Layout.fillWidth: true
                text: strip.summary
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
                elide: Text.ElideRight
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: strip._columns
            columnSpacing: 0
            rowSpacing: Theme.mini ? 8 : 12
            Repeater {
                model: strip.statuses
                delegate: RowLayout {
                    id: status
                    objectName: "healthStatus"
                    required property var modelData
                    required property int index
                    readonly property bool needsLook: modelData.state === "warn" || modelData.state === "down"
                    readonly property bool first: index % strip._columns === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    // At the top, all of them: the first in a row has no
                    // hairline to stretch it and would sit in the middle.
                    Layout.alignment: Qt.AlignTop
                    spacing: 0
                    // A hairline between two statuses in a row.
                    Rectangle {
                        visible: !status.first
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.rightMargin: Theme.mini ? 12 : 18
                        color: Theme.divider
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            StatusDot {
                                size: 12
                                color: status.modelData.stateColor || Theme.textMuted
                                breathing: status.needsLook
                                running: strip.running
                            }
                            Label {
                                Layout.fillWidth: true
                                text: status.modelData.label || ""
                                color: Theme.text
                                font.pixelSize: Theme.fontSm
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: status.modelData.stateLabel || ""
                            color: status.modelData.stateColor || Theme.text
                            font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: strip.roomy && text.length > 0
                            text: status.modelData.detail || ""
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontXs
                            elide: Text.ElideRight
                        }
                    }
                    Item { Layout.preferredWidth: Theme.mini ? 12 : 18 }
                }
            }
        }
    }
}
