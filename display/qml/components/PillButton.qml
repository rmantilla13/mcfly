import QtQuick
import QtQuick.Controls
import McFly

// Large touch-friendly button, in glass (Lens). Left as it is, it is the
// primary action: the deep accent (Glass.primary) under white ink, with a
// caustic and a shadow in its own colour. Given a `fill` of its own it is a
// resting button in that colour. `icon.name` puts one of Icon's glyphs
// before the text (the Voice note button's mic).
AbstractButton {
    id: control
    property color fill: Glass.primary
    property color ink: "white"

    implicitHeight: Theme.touchTarget
    implicitWidth: Math.max(Theme.touchTarget * 2, content.implicitWidth + 56)
    opacity: enabled ? 1 : 0.4
    scale: pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Theme.quick } }

    background: Lens {
        kind: Qt.colorEqual(control.fill, Glass.primary) ? "primary" : "rest"
        fill: control.fill
        radius: height / 2
    }
    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight
        Row {
            id: content
            anchors.centerIn: parent
            spacing: 10
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.icon.name !== ""
                name: control.icon.name
                size: 22
                color: control.ink
            }
            Label {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: control.text
                color: control.ink
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
