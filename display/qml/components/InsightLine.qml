import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// What stands out right now (Store.highlights), one at a time: its icon on
// its colour, the headline and a line of detail, turning to the next every
// few seconds with a cross-fade. A tap asks McFly about the one showing.
//
//   InsightLine { items: Store.highlights; running: home.shown; onPicked: item => ask(item.question) }
//
// The dots on the right say how many there are and which this is. A new
// list (each sync, each minute) keeps the one showing if it is still there.
Rectangle {
    id: line
    property var items: []
    // Turning (and fading) only while someone can see it.
    property bool running: true
    property int interval: 8000
    signal picked(var item)

    readonly property int count: (items || []).length
    property int index: 0
    readonly property var current: count > 0 ? items[Math.min(index, count - 1)] : null

    visible: count > 0
    implicitHeight: Theme.small ? 58 : 66
    radius: Theme.radiusSm + 6
    color: Theme.surface
    clip: true

    // Two slots: the one showing and the one fading in over it.
    property int _front: 0
    function _slot(i) { return i === 0 ? slotA : slotB }
    function _show(item) {
        _slot(_front).item = item
        _slot(_front).opacity = 1
        _slot(1 - _front).opacity = 0
    }
    // (Handlers read `items` itself: `count` may not have caught up yet.)
    function advance() {
        const list = items || []
        if (list.length < 2)
            return
        index = (index + 1) % list.length
        const back = _slot(1 - _front), front = _slot(_front)
        back.item = list[index]
        _front = 1 - _front
        if (Device.animatedTiles) {
            fade.stop()
            fadeIn.target = back
            fadeOut.target = front
            fade.start()
        } else {
            back.opacity = 1
            front.opacity = 0
        }
    }
    onItemsChanged: {
        const list = items || []
        const id = _slot(_front).item ? _slot(_front).item.id : ""
        const at = list.findIndex(h => h.id === id)
        index = at >= 0 ? at : 0
        fade.complete()
        _show(list.length > 0 ? list[index] : null)
    }
    Component.onCompleted: _show((items || [])[index] || null)

    Timer {
        interval: line.interval
        repeat: true
        running: line.running && line.visible && line.count > 1 && !Device.idle
        onTriggered: line.advance()
    }
    ParallelAnimation {
        id: fade
        OpacityAnimator { id: fadeIn; from: 0; to: 1; duration: Theme.enter; easing.type: Easing.InOutSine }
        OpacityAnimator { id: fadeOut; from: 1; to: 0; duration: Theme.enter; easing.type: Easing.InOutSine }
    }

    component Slot: RowLayout {
        id: slot
        property var item: null
        readonly property color tint: item && item.color ? item.color : Theme.accent
        spacing: Theme.small ? 10 : 14
        Rectangle {
            Layout.preferredWidth: Theme.small ? 34 : 40
            Layout.preferredHeight: Layout.preferredWidth
            radius: width / 2
            color: Qt.rgba(slot.tint.r, slot.tint.g, slot.tint.b, Theme.dark ? 0.26 : 0.16)
            Icon { anchors.centerIn: parent; name: slot.item ? slot.item.icon : "info"; size: Theme.small ? 18 : 20; color: slot.tint }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: slot.item ? slot.item.title : ""
                color: Theme.text
                font.pixelSize: Theme.small ? Theme.fontXs + 1 : Theme.fontSm
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: slot.item ? slot.item.detail || "" : ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
                elide: Text.ElideRight
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.small ? 12 : 14
        anchors.rightMargin: Theme.small ? 14 : 18
        spacing: 12
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Slot { id: slotA; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
            Slot { id: slotB; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; opacity: 0 }
        }
        // Which of how many.
        Column {
            visible: line.count > 1
            spacing: 5
            Repeater {
                model: line.count
                delegate: Rectangle {
                    required property int index
                    width: 6; height: 6; radius: 3
                    color: index === line.index ? Theme.accent : Theme.divider
                }
            }
        }
    }

    // A card shorter than a touch target on the small panels; the hit area is not.
    TapHandler {
        margin: Math.max(0, (Theme.touchTarget - line.height) / 2)
        onTapped: if (line.current) line.picked(line.current)
    }
}
