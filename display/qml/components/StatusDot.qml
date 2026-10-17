import QtQuick
import McFly
import McFly.Core

// A status's colour as a dot. One that needs a look (warn, down) breathes:
// a soft halo swells and fades around it, slowly, rather than the dot
// blinking. The halo runs only while `running` (the screen is up and
// Settings → Animated tiles is on); stopped, it is gone, not frozen
// mid-breath, and the dot itself never changes.
Item {
    id: dot
    property color color: Theme.textMuted
    property bool breathing: false
    property bool running: true
    property real size: 16

    implicitWidth: size
    implicitHeight: size

    // The breath, on the ambient clock's 30 updates a second (MotionClock),
    // not every frame the panel draws: from 0.08 to 0.34 and from 0.6 to
    // full size and back, Theme.breath each way, eased in and out, from the
    // start each time it starts.
    readonly property bool breathes: breathing && running && visible && Device.animatedTiles && !Device.idle
    property real breathFrom: 0
    onBreathesChanged: if (breathes) breathFrom = clock.time
    readonly property real _f: (1 - Math.cos(Math.PI * (clock.time - breathFrom) * 1000 / Theme.breath)) / 2
    MotionClock { id: clock; objectName: "breath"; playing: dot.breathes }

    Rectangle {
        id: halo
        objectName: "halo"
        anchors.centerIn: parent
        width: dot.size * 2.2
        height: width
        radius: width / 2
        color: dot.color
        visible: dot.breathes
        opacity: 0.08 + 0.26 * dot._f
        scale: 0.6 + 0.4 * dot._f
    }
    Rectangle {
        anchors.centerIn: parent
        width: dot.size
        height: width
        radius: width / 2
        color: dot.color
    }
}
