import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly

// Every screen's first row: the title, a subtitle, a back arrow while a
// detail is pushed over the list, and a slot for the screen's controls
// (chips, day arrows, a segment switch). On the small tiers the controls
// drop to a second row so titles never truncate.
Item {
    id: header
    property string title: ""
    property string subtitle: ""
    property bool backVisible: false
    signal back()
    default property alias controls: controlsRow.data
    // Controls on their own row under the title.
    readonly property bool wraps: Theme.mini || Theme.tall

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            IconButton {
                visible: header.backVisible
                icon: "left"
                fill: Theme.surface
                onClicked: header.back()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: header.title
                    color: Theme.text
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: header.subtitle
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSm
                    elide: Text.ElideRight
                }
            }
            // The controls, beside the title, on the wide tiers.
            Item {
                id: inlineSlot
                visible: !header.wraps
                implicitWidth: header.wraps ? 0 : controlsRow.implicitWidth
                implicitHeight: header.wraps ? 0 : controlsRow.implicitHeight
            }
        }
        // The controls, on their own row, on the small tiers.
        Item {
            id: wrappedSlot
            Layout.fillWidth: true
            visible: header.wraps && controlsRow.children.length > 0
            implicitHeight: header.wraps ? controlsRow.implicitHeight : 0
        }
    }

    RowLayout {
        id: controlsRow
        parent: header.wraps ? wrappedSlot : inlineSlot
        anchors.fill: parent
        spacing: 10
    }
}
