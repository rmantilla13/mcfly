import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// The navigation: one model, two shapes. A rail down the left (Wide and
// Compact) with icon + label items, or, with `horizontal`, a bar along the
// bottom (Mini and Tall) of icon-only slots where the active one widens to
// show its label. The active item is a blue pill that glides.
Rectangle {
    id: rail
    property int currentIndex: 0
    property bool horizontal: false
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
        { icon: "calendar", label: qsTr("Calendar") }
    ]

    color: Theme.surface

    // Highlight that glides to the active item.
    Rectangle {
        id: pill
        readonly property Item target: rail.horizontal
            ? (barItems.count > 0 && barRow.width > 0 ? barItems.itemAt(rail.currentIndex) : null)
            : (railItems.count > 0 && column.height > 0 ? railItems.itemAt(rail.currentIndex) : null)
        readonly property Item host: rail.horizontal ? barRow : column
        x: target ? host.x + target.x : 0
        y: target ? host.y + target.y : 0
        width: target ? target.width : 0
        height: target ? target.height : 0
        radius: rail.horizontal ? 24 : 26
        color: Theme.accent
        Behavior on y { enabled: !rail.horizontal; SpringAnimation { spring: 5; damping: 0.36; epsilon: 0.4 } }
        Behavior on x { enabled: rail.horizontal; SpringAnimation { spring: 5; damping: 0.36; epsilon: 0.4 } }
        Behavior on width { enabled: rail.horizontal; NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
    }

    // One item: the icon and, in the rail or while active in the bar, the label.
    component NavItem: Rectangle {
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
                color: active ? Theme.accentInk : Theme.textMuted
                Behavior on color { ColorAnimation { duration: Theme.quick } }
            }
            Label {
                id: itemLabel
                visible: showLabel
                text: modelData.label
                font.pixelSize: Theme.compact ? 13 : 14
                font.weight: active ? Font.DemiBold : Font.Medium
                color: active ? Theme.accentInk : Theme.textMuted
                Behavior on color { ColorAnimation { duration: Theme.quick } }
            }
        }
        TapHandler { id: navTap; onTapped: rail.selected(index) }
    }

    component NavButton: IconButton {
        implicitWidth: rail.horizontal ? 56 : (Theme.compact ? 52 : 64)
        implicitHeight: implicitWidth
    }

    // ---- The rail
    ColumnLayout {
        id: column
        visible: !rail.horizontal
        anchors.fill: parent
        anchors.topMargin: Theme.compact ? 12 : 24
        anchors.bottomMargin: Theme.compact ? 12 : 24
        spacing: Theme.compact ? 4 : 8

        // The mark.
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.compact ? 4 : 8
            width: Theme.compact ? 40 : 52; height: width; radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.glowBlue }
                GradientStop { position: 1; color: Theme.glowCoral }
            }
            Icon { anchors.centerIn: parent; name: "bolt"; size: parent.width * 0.52; color: "white"; strokeWidth: 2.2 }
        }

        Repeater {
            id: railItems
            model: rail.horizontal ? [] : rail.items
            delegate: NavItem {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Theme.compact ? 80 : 96
                // Seven items and the three buttons fit the 800 px compact panel.
                Layout.preferredHeight: Theme.compact ? 66 : 88
            }
        }

        Item { Layout.fillHeight: true }

        // Ask McFly (typed or spoken).
        NavButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "sparkle"
            fill: Theme.accentSoft
            ink: Theme.accent
            onClicked: rail.askRequested()
        }
        NavButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "settings"
            fill: Theme.surfaceAlt
            ink: Theme.textMuted
            onClicked: rail.settingsRequested()
        }
        // Show the screen saver right away.
        NavButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "moon"
            fill: Theme.surfaceAlt
            ink: Theme.textMuted
            onClicked: Device.sleepNow()
        }
    }

    // ---- The bar: 64 px slots that abut, the active one wide enough for its
    // label, a divider, then the three buttons in their own slots. About 704 px
    // in all, so it fits the 720-wide Touch Display 2 and sits centred on 800.
    Row {
        id: barRow
        visible: rail.horizontal
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            id: barItems
            model: rail.horizontal ? rail.items : []
            delegate: NavItem {
                width: active ? Math.min(136, 64 + labelWidth + 8) : 64
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
            NavButton { anchors.centerIn: parent; icon: "sparkle"; fill: Theme.accentSoft; ink: Theme.accent; onClicked: rail.askRequested() }
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
