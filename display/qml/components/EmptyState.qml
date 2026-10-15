import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// What a region says while nothing has arrived for it yet: its icon, a line,
// where it comes from and, with a `url`, a code to scan that opens the page on
// mcfly.bot that sets it up. Centred in the region, sized to read across the
// room. (A new account shows these everywhere, so they say what to do.)
//
//   EmptyState { icon: "brief"; text: …; hint: …
//                url: "https://mcfly.bot/bots"; action: qsTr("Make a Grok bot"); caption: … }
Item {
    id: empty
    property string icon: ""
    property string text: ""
    property string hint: ""
    property string url: ""
    property string action: ""    // the code's title
    property string caption: ""   // what scanning it does
    // For a layout that sizes it, rather than filling a region.
    implicitHeight: column.implicitHeight + 2 * Theme.spacing

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.spacing, 560)
        spacing: Theme.mini ? 6 : 10
        Rectangle {
            visible: empty.icon.length > 0 && !Theme.mini
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 4
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            radius: 32
            color: Theme.accentSoft
            Icon { anchors.centerIn: parent; name: empty.icon; size: 28; color: Theme.accent }
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: empty.text
            color: Theme.text
            font.pixelSize: Theme.mini ? Theme.fontSm + 1 : Theme.fontMd
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
        Label {
            Layout.fillWidth: true
            visible: text.length > 0
            horizontalAlignment: Text.AlignHCenter
            text: empty.hint
            color: Theme.textMuted
            font.pixelSize: Theme.mini ? Theme.fontXs : Theme.fontSm
            wrapMode: Text.WordWrap
        }
        QrPanel {
            visible: empty.url.length > 0 && Store.mode !== "pairing"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.mini ? 4 : 12
            Layout.preferredWidth: Math.min(parent.width, 480)
            url: empty.url
            title: empty.action
            caption: empty.caption
            domain: empty.url.replace(/^https?:\/\//, "")
            codeSize: Theme.small ? 88 : 112
        }
    }
}
