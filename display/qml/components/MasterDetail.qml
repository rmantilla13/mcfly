import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly

// A list and the thing picked from it. On the paned tiers (Wide, Compact)
// the detail is a pane beside the master; on Mini and Tall it is a page
// pushed over the master with a back arrow, cross-fading like a Page.
//
//   MasterDetail {
//       anchors.fill: parent              // the whole screen; it applies the page margin
//       master: ColumnLayout { ... }      // the list, with its ScreenHeader
//       detail: Rectangle { ... }         // the reader, tile or history
//       hasDetail: !!current.id           // nothing picked: the pane hides
//       onOpen -> md.open()               // a tap on a row (no-op while paned)
//   }
Item {
    id: md
    property alias master: masterHolder.data
    property alias detail: detailHolder.data
    // Something to show on the detail side (otherwise the pane stays hidden
    // and the master takes the room).
    property bool hasDetail: true
    // The detail is pushed over the master (Mini and Tall only).
    property bool detailOpen: false
    // Title beside the back arrow on the pushed page.
    property string detailTitle: ""
    property string detailSubtitle: ""
    // The pane's width when the detail is the fixed side...
    property int paneWidth: Theme.paneWidth
    // ...or the master's when the list is (Briefs: list fixed, reader fills).
    property bool masterFixed: false
    property int masterWidth: Theme.listWidth

    readonly property bool paned: Theme.paned
    readonly property bool pushed: !paned && detailOpen && hasDetail
    signal closed()

    function open() { if (hasDetail) detailOpen = true }
    function back() { detailOpen = false; closed() }
    // Idle, re-pair, the nav item tapped again: nothing pushed stays up.
    function closeDetail() { if (detailOpen) back() }
    onHasDetailChanged: if (!hasDetail) detailOpen = false

    // ---- Paned
    Item {
        id: masterHolder
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        anchors.rightMargin: md.paned && md.hasDetail
                             ? Theme.pageMargin + Theme.spacing + (md.masterFixed ? Math.max(0, md.width - 2 * Theme.pageMargin - Theme.spacing - md.masterWidth) : md.paneWidth)
                             : Theme.pageMargin
    }
    Item {
        id: paneSlot
        visible: md.paned && md.hasDetail
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Theme.pageMargin
        width: md.masterFixed ? Math.max(0, md.width - 2 * Theme.pageMargin - Theme.spacing - md.masterWidth) : md.paneWidth
    }

    // ---- Pushed
    Rectangle {
        id: pushedPage
        anchors.fill: parent
        color: Theme.background
        visible: opacity > 0.001
        opacity: md.pushed ? 1 : 0
        enabled: md.pushed
        Behavior on opacity { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: md.pushed ? 0 : 24
            Behavior on y { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent } // nothing underneath takes the tap

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.pageMargin
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                IconButton { icon: "left"; fill: Theme.surface; onClicked: md.back() }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: md.detailTitle
                        color: Theme.text
                        font.pixelSize: Theme.fontMd
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: md.detailSubtitle
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontXs
                        elide: Text.ElideRight
                    }
                }
            }
            Item {
                id: pushedBody
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    // The detail lives in the pane, or on the pushed page.
    Item {
        id: detailHolder
        parent: md.paned ? paneSlot : pushedBody
        anchors.fill: parent
    }
}
