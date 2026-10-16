import QtQuick
import QtQuick.Controls
import McFly

// A row of pill chips, one chosen, that scrolls sideways when there are more
// than fit: news sources, the boards picker, Markets | Metrics. In glass
// (Lens): the chosen chip gathers the aura under Glass.ink, the rest are
// resting glass; no shadows, which the row's clip would cut.
//
//   ChipRow { model: [{ id, label, color? }]; current: "ops"; onPicked: id => ... }
//
// The row is a touch target tall with the chips drawn across its middle, and
// a chip is never narrower than one: each takes the taps in its own column.
// Not a TapHandler margin: a Flickable takes no touch outside its edges, and
// margins reaching across the gap would pick both neighbours with one tap.
Flickable {
    id: chips
    property var model: []
    property string current: ""
    property int chipHeight: 48
    signal picked(string id)

    implicitWidth: row.width
    implicitHeight: Math.max(chipHeight, Theme.touchTarget)
    contentWidth: row.width
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentWidth > width
    clip: true

    Row {
        id: row
        height: chips.height
        spacing: 6
        Repeater {
            model: chips.model
            delegate: Item {
                id: chip
                required property var modelData
                readonly property bool chosen: chips.current === modelData.id
                readonly property bool dotted: !!modelData.color
                width: Math.max(Theme.touchTarget, label.implicitWidth + (dotted ? 44 : 28))
                height: row.height
                Lens {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: chips.chipHeight
                    kind: chip.chosen ? "active" : "rest"
                    shadow: 0
                    Rectangle {
                        visible: chip.dotted
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10; radius: 5
                        color: chip.modelData.color || Theme.accent
                    }
                    Label {
                        id: label
                        // Centred when the chip is wider than its words.
                        x: chip.dotted ? 30 : (parent.width - implicitWidth) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.label
                        color: chip.chosen ? Glass.ink : Theme.text
                        font.pixelSize: Theme.fontXs + 1
                        font.weight: Font.DemiBold
                    }
                }
                TapHandler { onTapped: chips.picked(chip.modelData.id) }
            }
        }
    }
}
