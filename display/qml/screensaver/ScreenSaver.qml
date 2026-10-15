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

    Loader {
        id: content
        objectName: "saverContent"
        anchors.fill: parent
        // Only run while visible, and rebuild when the style changes.
        active: saver.visible
        source: saver.style === "clock" ? "ClockSaver.qml" : saver.style === "headlines" ? "HeadlinesSaver.qml" : "AmbientSaver.qml"
        opacity: status === Loader.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
    }
}
