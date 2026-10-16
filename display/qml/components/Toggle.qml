import QtQuick
import McFly

// On/off switch. It doesn't flip itself: it asks with toggled(), and the
// owner binds `checked` to the real setting, so it can never show a state the
// device isn't in. In glass (Lens): on, the track is the deep accent with a
// caustic; off, a faint grey glass; the knob a bead of white glass.
Item {
    id: toggle
    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 76
    implicitHeight: 44
    opacity: enabled ? 1 : 0.4
    Behavior on opacity { NumberAnimation { duration: Theme.quick } }

    Lens {
        id: track
        anchors.fill: parent
        fill: toggle.checked ? Glass.primary : Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.32)
        caustic: toggle.checked ? Glass.mix(0.24, 0.3) : 0
        rim: Glass.mix(0.6, 0.4)
        sheen: Glass.mix(0.14, 0.05)
        shadow: 0
        Behavior on fill { enabled: !Theme.fading; ColorAnimation { duration: Theme.quick } }

        Lens {
            width: parent.height - 8
            height: width
            y: 4
            x: toggle.checked ? parent.width - width - 4 : 4
            fill: "white"
            rim: 1.0
            sheen: 0.25
            shadow: 0.2
            shadowY: 2
            shadowBlur: 4
            scale: tap.pressed ? 0.9 : 1
            Behavior on x { NumberAnimation { duration: Theme.quick; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on scale { NumberAnimation { duration: Theme.quick } }
        }
    }

    // A finger-sized hit area around the track.
    TapHandler {
        id: tap
        target: null
        margin: 12
        gesturePolicy: TapHandler.WithinBounds
        onTapped: toggle.toggled(!toggle.checked)
    }
}
