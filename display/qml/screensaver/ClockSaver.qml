import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// A big clock, the date, the latest brief and a line of the markets on the
// chosen backdrop (Settings → Backdrop: the slowly drifting gradient, or one
// of Backdrop's skies) in the time-of-day colours (deep and dim at night).
// The text moves a few pixels every minute, so nothing stays on the same
// pixels all night.
Item {
    id: clock
    property date now: new Date()
    property real shiftX: 0
    property real shiftY: 0
    Behavior on shiftX { NumberAnimation { duration: 3000; easing.type: Easing.InOutSine } }
    Behavior on shiftY { NumberAnimation { duration: 3000; easing.type: Easing.InOutSine } }
    readonly property var brief: Store.latestBrief
    readonly property string markets: Store.quotes.slice(0, Theme.mini ? 3 : 5).map(q => q.symbol + " " + q.pctLabel).join("   ·   ")

    Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }
    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        onTriggered: {
            clock.shiftX = (Math.random() - 0.5) * 48
            clock.shiftY = (Math.random() - 0.5) * 32
        }
    }

    // The backdrop (Device.backdrop): the mesh, or one of Backdrop's skies.
    // Only the chosen one is built.
    readonly property bool mesh: Device.backdrop === "mesh"
    Loader {
        id: backdrop
        anchors.fill: parent
        sourceComponent: clock.mesh ? meshBackdrop : skyBackdrop
        readonly property color ink: item ? item.ink : "#1D1B24"
        readonly property color inkMuted: item ? item.inkMuted : "#4A4555"
    }
    Component {
        id: meshBackdrop
        GradientTile {
            radius: 0
            colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
            whileIdle: true
            maxFps: Theme.saverFps
            period: Theme.saverDrift
        }
    }
    Component {
        id: skyBackdrop
        Backdrop {
            style: Device.backdrop
            whileIdle: true
            maxFps: Theme.saverFps
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: clock.shiftX
        anchors.verticalCenterOffset: clock.shiftY
        spacing: 8
        width: clock.width * 0.8

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.now, "h:mm AP").split(" ")[0]
            color: backdrop.ink
            font.pixelSize: Math.min(clock.width * 0.2, clock.height * 0.34)
            font.weight: Font.Light
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.now, "dddd, MMMM d")
            color: backdrop.ink
            font.pixelSize: Theme.fontLg
        }
        Item { width: 1; height: 28 }
        Label {
            visible: !!clock.brief.title
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: clock.brief.title ? (clock.brief.agentName + " · " + clock.brief.whenLabel + "   " + clock.brief.title) : ""
            color: backdrop.ink
            font.pixelSize: Theme.fontMd
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Label {
            visible: clock.markets.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: clock.markets
            color: backdrop.inkMuted
            font.pixelSize: Theme.fontMd
            wrapMode: Text.WordWrap
        }
    }
}
