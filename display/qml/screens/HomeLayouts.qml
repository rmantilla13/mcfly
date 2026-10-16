import QtQuick
import McFly
import McFly.Core

// Home in the layout this display chose (Settings → Home, or the console's
// Customize; Device.homeLayout): today (HomeScreen, the day as a timeline),
// bento (HomeBento, a grid of tiles) or assistant (HomeAssistant, McFly's
// summary first). Main.qml puts this where Home goes. Every layout takes
// `shown` and raises the same three signals, so Main.qml doesn't know which
// one is up. Only the chosen layout exists; switching builds the new one.
Item {
    id: layouts

    property bool shown: true
    // Picked (Main.qml): the screens animate in on it (Reveal.qml).
    property bool isCurrent: true
    signal openScreen(int index)
    signal openAssistant(string question)
    signal pushToTalk()

    Loader {
        anchors.fill: parent
        sourceComponent: Device.homeLayout === "bento" ? bento
                       : Device.homeLayout === "assistant" ? assistantFirst
                       : today
    }

    Component {
        id: today
        HomeScreen {
            shown: layouts.shown
            isCurrent: layouts.isCurrent
            onOpenScreen: index => layouts.openScreen(index)
            onOpenAssistant: question => layouts.openAssistant(question)
            onPushToTalk: layouts.pushToTalk()
        }
    }
    Component {
        id: bento
        HomeBento {
            shown: layouts.shown
            isCurrent: layouts.isCurrent
            onOpenScreen: index => layouts.openScreen(index)
            onOpenAssistant: question => layouts.openAssistant(question)
            onPushToTalk: layouts.pushToTalk()
        }
    }
    Component {
        id: assistantFirst
        HomeAssistant {
            shown: layouts.shown
            isCurrent: layouts.isCurrent
            onOpenScreen: index => layouts.openScreen(index)
            onOpenAssistant: question => layouts.openAssistant(question)
            onPushToTalk: layouts.pushToTalk()
        }
    }
}
