import QtQuick
import QtQuick.Controls
import McFly

// Large touch-friendly button, in glass (Lens). Left as it is, it is the
// primary action: the deep accent (Glass.primary) under white ink, with a
// caustic and a shadow in its own colour. Given a `fill` of its own it is a
// resting button in that colour.
AbstractButton {
    id: control
    property color fill: Glass.primary
    property color ink: "white"

    implicitHeight: Theme.touchTarget
    implicitWidth: Math.max(Theme.touchTarget * 2, label.implicitWidth + 56)
    opacity: enabled ? 1 : 0.4
    scale: pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Theme.quick } }

    background: Lens {
        kind: Qt.colorEqual(control.fill, Glass.primary) ? "primary" : "rest"
        fill: control.fill
        radius: height / 2
    }
    contentItem: Label {
        id: label
        text: control.text
        color: control.ink
        font.pixelSize: Theme.fontSm
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
