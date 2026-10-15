import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// A big clock, the date, the latest brief and a line of the markets on a
// soft gradient in the time-of-day colours (deep and dim at night). The
// text moves a few pixels every minute, so nothing stays on the same pixels
// all night.
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

    GradientTile {
        id: backdrop
        anchors.fill: parent
        radius: 0
        colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
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
