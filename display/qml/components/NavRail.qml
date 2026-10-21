import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import McFly
import McFly.Core

// The navigation: one model, two shapes. A rail down the left (Wide and
// Compact) with icon + label items, or, with `horizontal`, a bar along the
// bottom (Mini and Tall) of icon-only slots where the active one widens to
// show its label. The active item is a glass pill (Lens) that glides along
// the rail, bending the aura the rail shows faintly beneath it. While McFly
// is `thinking` (an answer on its way, the panel shut), a ring in the voice
// glow's colours turns around the Ask button.
Rectangle {
    id: rail
    property int currentIndex: 0
    property bool horizontal: false
    property bool thinking: false
    signal selected(int index)
    signal settingsRequested()
    signal askRequested()

    readonly property var items: [
        { icon: "home",     label: qsTr("Home") },
        { icon: "brief",    label: qsTr("Briefs") },
        { icon: "chart",    label: qsTr("Markets") },
        { icon: "news",     label: qsTr("News") },
        { icon: "chores",   label: qsTr("Projects") },
        { icon: "grid",     label: qsTr("Boards") },
        { icon: "calendar", label: qsTr("Calendar") },
        { icon: "games",    label: qsTr("Games") }
    ]
    // The bar's slots: 64 px where they fit, narrower where they don't (the
    // 720 px Touch Display 2), so every item, the divider and the three
    // buttons share the width with room for the active item's label.
    // The rail's round buttons: a disc smaller than a touch target, each in a
    // slot a touch target tall that it takes taps across (IconButton.hitMargin),
    // so the three sit apart and the rail fits 800 px with room to spare.
    readonly property real buttonSize: Theme.compact ? 44 : 52
    readonly property real barSlot: Math.max(44, Math.min(64, Math.floor((width - 16 - 17 - 3 * 64 - (items.length + 3) * 2 - 72) / items.length)))

    color: Theme.surface

    // The aura, faint and still, for the pill to bend (Glass.qml). Cached as
    // a quarter-size layer: it only redraws while the palette fades.
    Lens {
        anchors.fill: parent
        kind: "wash"
        radius: 0
        layer.enabled: !fallback
        layer.smooth: true
        layer.textureSize: Qt.size(Math.ceil(width / 4), Math.ceil(height / 4))
    }

    // Highlight that glides to the active item: clear glass over the aura.
    Lens {
        id: pill
        kind: "active"
        readonly property Item target: rail.horizontal
            ? (barItems.count > 0 && barRow.width > 0 ? barItems.itemAt(rail.currentIndex) : null)
            : (railItems.count > 0 && column.height > 0 ? railItems.itemAt(rail.currentIndex) : null)
        readonly property Item host: rail.horizontal ? barRow : column
        x: target ? host.x + target.x : 0
        y: target ? host.y + target.y : 0
        width: target ? target.width : 0
        height: target ? target.height : 0
        radius: rail.horizontal ? 24 : 26
        Behavior on y { enabled: !rail.horizontal; SpringAnimation { spring: 5; damping: 0.36; epsilon: 0.4 } }
        Behavior on x { enabled: rail.horizontal; SpringAnimation { spring: 5; damping: 0.36; epsilon: 0.4 } }
        Behavior on width { enabled: rail.horizontal; NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
    }

    // One item: the icon and, in the rail or while active in the bar, the label.
    component NavItem: Rectangle {
        objectName: "navItem"
        required property var modelData
        required property int index
        readonly property bool active: index === rail.currentIndex
        readonly property bool showLabel: !rail.horizontal || active
        readonly property real labelWidth: itemLabel.implicitWidth
        radius: 24
        color: "transparent"
        scale: navTap.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: Theme.quick } }

        // Rail: icon over label. Bar: icon beside the label.
        Grid {
            id: inner
            anchors.centerIn: parent
            columns: rail.horizontal ? 2 : 1
            rows: rail.horizontal ? 1 : 2
            verticalItemAlignment: Grid.AlignVCenter
            horizontalItemAlignment: Grid.AlignHCenter
            spacing: rail.horizontal ? 8 : (Theme.compact ? 3 : 6)
            Icon {
                name: modelData.icon
                size: Theme.compact ? 24 : 30
                color: active ? Glass.ink : Theme.textMuted
                Behavior on color { ColorAnimation { duration: Theme.quick } }
            }
            Label {
                id: itemLabel
                visible: showLabel
                text: modelData.label
                font.pixelSize: Theme.compact ? 13 : 14
                font.weight: active ? Font.DemiBold : Font.Medium
                color: active ? Glass.ink : Theme.textMuted
                Behavior on color { ColorAnimation { duration: Theme.quick } }
            }
        }
        TapHandler { id: navTap; onTapped: rail.selected(index) }
    }

    component NavButton: IconButton {
        implicitWidth: rail.horizontal ? 56 : rail.buttonSize
        implicitHeight: implicitWidth
        iconSize: rail.horizontal ? 24 : (Theme.compact ? 20 : 22)
        hitMargin: rail.horizontal ? 0 : (Theme.touchTarget - rail.buttonSize) / 2
    }

    // A ring that fades from nothing into the voice spectrum, turning once
    // every couple of seconds: a spinner that doesn't nag. It turns as a
    // whole (an Animator), so nothing is redrawn but its angle; with
    // Settings → Animated tiles off it holds still.
    component ThinkingRing: Item {
        id: thinkingRing
        objectName: "thinkingRing"
        readonly property real thickness: 3
        // Under the button: whatever the renderer makes of the ring's hole,
        // the button's own disc covers the middle.
        z: -1
        opacity: rail.thinking ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.enter; easing.type: Easing.InOutSine } }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                fillGradient: ConicalGradient {
                    centerX: thinkingRing.width / 2
                    centerY: thinkingRing.height / 2
                    angle: 90
                    GradientStop { position: 0.0; color: Qt.rgba(0.56, 0.34, 0.90, 0) }
                    GradientStop { position: 0.45; color: Qt.rgba(0.56, 0.34, 0.90, 0.55) }
                    GradientStop { position: 0.75; color: Theme.spectrum[2] }
                    GradientStop { position: 1.0; color: Theme.spectrum[3] }
                }
                PathAngleArc {
                    centerX: thinkingRing.width / 2; centerY: thinkingRing.height / 2
                    radiusX: thinkingRing.width / 2; radiusY: radiusX
                    startAngle: 0; sweepAngle: 360
                }
                PathAngleArc {
                    centerX: thinkingRing.width / 2; centerY: thinkingRing.height / 2
                    radiusX: thinkingRing.width / 2 - thinkingRing.thickness; radiusY: radiusX
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
        RotationAnimator on rotation {
            objectName: "spin"
            running: thinkingRing.visible && Device.animatedTiles && !Device.idle
            from: 0
            to: 360
            duration: 2400
            loops: Animation.Infinite
        }
    }

    // ---- The rail
    ColumnLayout {
        id: column
        visible: !rail.horizontal
        anchors.fill: parent
        anchors.topMargin: Theme.compact ? 12 : 24
        anchors.bottomMargin: Theme.compact ? 12 : 24
        spacing: Theme.compact ? 4 : 8

        Repeater {
            id: railItems
            model: rail.horizontal ? [] : rail.items
            delegate: NavItem {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Theme.compact ? 80 : 96
                // Eight items, a touch target tall, and the three buttons fit
                // the 800 px compact panel; 84 on a 1080 px wall.
                Layout.preferredHeight: Theme.compact ? 64 : 84
            }
        }

        Item { Layout.fillHeight: true }

        // Ask, Settings and Sleep: a disc to each touch-target slot.
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.touchTarget - rail.buttonSize

            // Ask McFly (typed or spoken).
            NavButton {
                id: railAsk
                objectName: "railAsk"
                Layout.alignment: Qt.AlignHCenter
                icon: "sparkle"
                kind: "active"
                fill: Theme.accentSoft
                ink: Glass.ink
                onClicked: rail.askRequested()
                ThinkingRing { anchors.centerIn: parent; width: railAsk.width + 10; height: width }
            }
            NavButton {
                objectName: "railSettings"
                Layout.alignment: Qt.AlignHCenter
                icon: "settings"
                fill: Theme.surfaceAlt
                ink: Theme.textMuted
                onClicked: rail.settingsRequested()
            }
            // Show the screen saver right away.
            NavButton {
                objectName: "railSleep"
                Layout.alignment: Qt.AlignHCenter
                icon: "moon"
                fill: Theme.surfaceAlt
                ink: Theme.textMuted
                onClicked: Device.sleepNow()
            }
        }
    }

    // ---- The bar: slots that abut (barSlot, 64 px where there is room), the
    // active one wide enough for its label, a divider, then the three buttons
    // in their own 64 px slots. Never more than the bar is wide: on the
    // 720-wide Touch Display 2 the slots narrow to about 50 px, and the bar
    // sits centred on 800.
    Row {
        id: barRow
        visible: rail.horizontal
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            id: barItems
            model: rail.horizontal ? rail.items : []
            delegate: NavItem {
                width: active ? Math.min(rail.barSlot + 72, rail.barSlot + labelWidth + 8) : rail.barSlot
                height: 64
                Behavior on width { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
            }
        }
        Item {
            width: 17; height: 64
            Rectangle { anchors.centerIn: parent; width: 1; height: 32; color: Theme.divider }
        }
        Item {
            width: 64; height: 64
            NavButton { anchors.centerIn: parent; icon: "sparkle"; kind: "active"; fill: Theme.accentSoft; ink: Glass.ink; onClicked: rail.askRequested() }
            ThinkingRing { anchors.centerIn: parent; width: 64; height: 64 }
        }
        Item {
            width: 64; height: 64
            NavButton { anchors.centerIn: parent; icon: "settings"; fill: Theme.surfaceAlt; ink: Theme.textMuted; onClicked: rail.settingsRequested() }
        }
        Item {
            width: 64; height: 64
            NavButton { anchors.centerIn: parent; icon: "moon"; fill: Theme.surfaceAlt; ink: Theme.textMuted; onClicked: Device.sleepNow() }
        }
    }
    // A hairline over the bar, so it reads as a shelf under the page.
    Rectangle {
        visible: rail.horizontal
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Theme.divider
    }
}
