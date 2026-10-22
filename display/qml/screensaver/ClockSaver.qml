import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// A big clock, the date, the latest brief and a line of the markets on the
// chosen backdrop (Settings → Backdrop: the slowly drifting gradient, or one
// of Backdrop's skies, with the weather over it) in the time-of-day colours
// (deep and dim at night).
// The text moves a few pixels every minute, so nothing stays on the same
// pixels all night.
Item {
    id: clock
    // Updates a second for what moves (ScreenSaver's: it eases off after a while).
    property int fps: Theme.saverFps
    property date now: new Date()
    // Against burn-in the composition slides to a new spot every minute,
    // over 3 s, eased in and out, on the saver's clock: an animation would
    // draw every one of the panel's frames while it slides.
    property real _fromX: 0
    property real _fromY: 0
    property real _toX: 0
    property real _toY: 0
    MotionClock {
        id: slide
        objectName: "slide"
        time: 3
        playing: time < 3
        fps: clock.fps
    }
    readonly property real _slid: 0.5 - 0.5 * Math.cos(Math.PI * Math.min(1, slide.time / 3))
    readonly property real shiftX: _fromX + (_toX - _fromX) * _slid
    readonly property real shiftY: _fromY + (_toY - _fromY) * _slid
    // From where it is now: the start first, then the clock, then the end.
    function _slideTo(x, y) {
        _fromX = shiftX
        _fromY = shiftY
        slide.time = 0
        _toX = x
        _toY = y
    }
    readonly property var brief: Store.latestBrief
    readonly property string markets: Store.quotes.slice(0, Theme.mini ? 3 : 5).map(q => q.symbol + " " + q.pctLabel).join("   ·   ")

    Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }
    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        onTriggered: clock._slideTo((Math.random() - 0.5) * 48, (Math.random() - 0.5) * 32)
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
            // Full screen: shaded at the skies' size (Theme.backdropResolution).
            resolution: Theme.backdropResolution / Math.max(1, Screen.devicePixelRatio)
            radius: 0
            colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
            whileIdle: true
            maxFps: clock.fps
            period: Theme.saverDrift
        }
    }
    Component {
        id: skyBackdrop
        Backdrop {
            style: Device.backdrop
            whileIdle: true
            maxFps: clock.fps
        }
    }
    // Weather over the backdrop, under the clock (Settings → Backdrop → Weather).
    Weather {
        anchors.fill: parent
        maxFps: clock.fps
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
