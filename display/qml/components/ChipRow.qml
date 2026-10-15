import QtQuick
import QtQuick.Controls
import McFly

// A row of pill chips, one chosen, that scrolls sideways when there are more
// than fit: news sources, the boards picker, Markets | Metrics.
//
//   ChipRow { model: [{ id, label, color? }]; current: "ops"; onPicked: id => ... }
Flickable {
    id: chips
    property var model: []
    property string current: ""
    property int chipHeight: 48
    signal picked(string id)

    implicitWidth: row.width
    implicitHeight: chipHeight
    contentWidth: row.width
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentWidth > width
    clip: true

    Row {
        id: row
        spacing: 6
        Repeater {
            model: chips.model
            delegate: Rectangle {
                required property var modelData
                readonly property bool chosen: chips.current === modelData.id
                readonly property bool dotted: !!modelData.color
                width: label.implicitWidth + (dotted ? 44 : 28)
                height: chips.chipHeight
                radius: height / 2
                color: chosen ? Theme.accent : Theme.surface
                Rectangle {
                    visible: parent.dotted
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; radius: 5
                    color: modelData.color || Theme.accent
                }
                Label {
                    id: label
                    x: parent.dotted ? 30 : 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: parent.chosen ? Theme.accentInk : Theme.text
                    font.pixelSize: Theme.fontXs + 1
                    font.weight: Font.DemiBold
                }
                // The chip is shorter than a touch target; the hit area is not.
                TapHandler { margin: (Theme.touchTarget - chips.chipHeight) / 2; onTapped: chips.picked(modelData.id) }
            }
        }
    }
}
