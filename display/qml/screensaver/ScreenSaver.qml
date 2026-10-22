import QtQuick
import QtQuick.Controls
import McFly
import McFly.Core

// Ambient mode when nobody is using the screen: Ambient (the default: the
// clock and what's next over the moving gradient, with a rail of cards from
// the feeds), Headlines (today's stories, one at a time, over their
// pictures) or Clock (the time, the latest brief and the markets). Any touch wakes the screen
// (see DisplayController).
Rectangle {
    id: saver
    color: "black"

    // Ambient unless another is picked; Headlines needs today's stories.
    readonly property string style: Device.screensaver === "clock" ? "clock"
                                  : Device.screensaver === "headlines" && Store.stories.length > 0 ? "headlines"
                                  : "ambient"

    // How often what moves on the saver updates: Theme.saverFps, then
    // Theme.saverCalmFps once the screen has gone untouched for
    // Theme.saverCalmAfter (the saver came up idleTimeoutSec after the last
    // touch). Each saver hands it to its backdrop, weather and pictures.
    // Hidden (a touch, or the panel asleep), it starts over.
    readonly property int fps: calm ? Theme.saverCalmFps : Theme.saverFps
    property bool calm: false
    property int calmAfter: Math.max(0, Theme.saverCalmAfter - Device.idleTimeoutSec * 1000)
    onVisibleChanged: if (!visible) calm = false
    Timer {
        objectName: "saverCalm"
        interval: saver.calmAfter
        running: saver.visible && !saver.calm
        onTriggered: saver.calm = true
    }

    Loader {
        id: content
        objectName: "saverContent"
        anchors.fill: parent
        // Only run while visible, and rebuild when the style changes.
        active: saver.visible
        source: saver.style === "clock" ? "ClockSaver.qml" : saver.style === "headlines" ? "HeadlinesSaver.qml" : "AmbientSaver.qml"
        onLoaded: item.fps = Qt.binding(() => saver.fps)
        opacity: status === Loader.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
    }
}
