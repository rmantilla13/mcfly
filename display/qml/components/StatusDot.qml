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

    Rectangle {
        id: halo
        anchors.centerIn: parent
        width: dot.size * 2.2
        height: width
        radius: width / 2
        color: dot.color
        opacity: 0
        visible: breath.running
    }
    Rectangle {
        anchors.centerIn: parent
        width: dot.size
        height: width
        radius: width / 2
        color: dot.color
    }

    SequentialAnimation {
        id: breath
        running: dot.breathing && dot.running && dot.visible && Device.animatedTiles && !Device.idle
        loops: Animation.Infinite
        onStopped: { halo.opacity = 0; halo.scale = 1 }
        ParallelAnimation {
            OpacityAnimator { target: halo; from: 0.08; to: 0.34; duration: Theme.breath; easing.type: Easing.InOutSine }
            ScaleAnimator { target: halo; from: 0.6; to: 1; duration: Theme.breath; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            OpacityAnimator { target: halo; from: 0.34; to: 0.08; duration: Theme.breath; easing.type: Easing.InOutSine }
            ScaleAnimator { target: halo; from: 1; to: 0.6; duration: Theme.breath; easing.type: Easing.InOutSine }
        }
    }
}
