import QtQuick
import QtQuick.Controls
import McFly

// What a region says when the agents have sent nothing for it yet: one
// line, centred, muted, with the hint on where it comes from.
Item {
    id: empty
    property string text: ""
    property string hint: ""

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.spacing, 520)
        spacing: 6
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: empty.text
            color: Theme.textMuted
            font.pixelSize: Theme.fontSm
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
        }
        Label {
            width: parent.width
            visible: text.length > 0
            horizontalAlignment: Text.AlignHCenter
            text: empty.hint
            color: Theme.textMuted
            font.pixelSize: Theme.fontXs
            wrapMode: Text.WordWrap
        }
    }
}
