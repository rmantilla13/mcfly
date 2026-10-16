import QtQuick
import McFly

// Round icon button (prev/next, close, mic, send), in glass (Lens): `fill`
// under a lit rim and a sheen. `kind: "active"` makes it clear glass that
// gathers the aura, as the rail's Ask button is; give it `ink: Glass.ink`.
Item {
    id: btn
    property string icon: ""
    property color fill: Theme.surface
    property color ink: Theme.text
    property real iconSize: 24
    // How far the tap reaches past the disc on each side: a small disc can
    // still take a touch-target-sized tap (the rail's buttons). Keep it
    // within half the gap to the next button, or one tap presses both.
    property real hitMargin: 0
    property alias kind: body.kind
    signal clicked()

    implicitWidth: Theme.touchTarget
    implicitHeight: Theme.touchTarget
    opacity: enabled ? 1 : 0.4
    scale: tap.pressed ? 0.94 : 1
    Behavior on scale { NumberAnimation { duration: Theme.quick } }

    Lens {
        id: body
        anchors.fill: parent
        fill: btn.fill
    }
    Icon {
        anchors.centerIn: parent
        name: btn.icon
        size: btn.iconSize
        color: btn.ink
    }
    // Claim the tap so handlers on items underneath (e.g. a photo that toggles
    // the viewer controls) don't also react.
    TapHandler { id: tap; margin: btn.hitMargin; gesturePolicy: TapHandler.WithinBounds; onTapped: btn.clicked() }
}
