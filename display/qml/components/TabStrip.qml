import QtQuick
import QtQuick.Controls
import McFly

// Tabs across a sheet: equal columns on a sunken track, the chosen one under
// an active lens that glides to the next (as SegmentedControl's thumb does).
// The strip is a touch target tall and each column takes every tap across
// its own width, edge to edge, so a tap is never between two tabs and never
// picks both. Icons show beside the names where every column has room.
//
//   TabStrip { model: [{ id, label, icon }]; current: "screen"; onPicked: id => ... }
Rectangle {
    id: strip
    property var model: []
    property string current: ""
    signal picked(string id)

    readonly property int inset: 5
    readonly property real cell: model.length > 0 ? (width - 2 * inset) / model.length : 0
    readonly property int chosenIndex: Math.max(0, model.findIndex(t => t.id === current))
    // An icon, its gap and the longest name fit a column with room to spare.
    readonly property bool showIcons: cell >= longest.advanceWidth + 26 + 32

    implicitWidth: 6 * 120
    implicitHeight: Theme.touchTarget
    radius: height / 2
    color: Theme.sunken

    TextMetrics {
        id: longest
        font.pixelSize: Theme.fontSm
        font.weight: Font.DemiBold
        text: strip.model.reduce((a, t) => (t.label.length > a.length ? t.label : a), "")
    }

    Lens {
        kind: "active"
        x: strip.inset + strip.chosenIndex * strip.cell
        y: strip.inset
        width: strip.cell
        height: strip.height - 2 * strip.inset
        Behavior on x { NumberAnimation { duration: Theme.quick; easing.type: Easing.OutCubic } }
    }

    Row {
        x: strip.inset
        Repeater {
            model: strip.model
            delegate: Item {
                id: tab
                required property var modelData
                readonly property bool chosen: strip.current === modelData.id
                objectName: "tab-" + modelData.id
                width: strip.cell
                height: strip.height
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Icon {
                        visible: strip.showIcons
                        anchors.verticalCenter: parent.verticalCenter
                        name: tab.modelData.icon || ""
                        size: 20
                        color: tab.chosen ? Glass.ink : Theme.textMuted
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tab.modelData.label
                        color: tab.chosen ? Glass.ink : Theme.text
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                    }
                }
                TapHandler { onTapped: strip.picked(tab.modelData.id) }
            }
        }
    }
}
