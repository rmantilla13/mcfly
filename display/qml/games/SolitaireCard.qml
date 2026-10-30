import QtQuick
import QtQuick.Controls
import McFly

// One playing card for Solitaire: face up, its rank and suit in the top
// band (all that shows when cards overlap) and a big suit below; face down,
// the accent with a ring. `card` is 0–51: suit × 13 + rank − 1, suits in
// CardSuit's order.
Item {
    id: face
    property int card: 0
    property bool up: true

    readonly property int suit: Math.floor(card / 13)
    readonly property int rank: card % 13 + 1
    readonly property bool red: suit === 1 || suit === 2
    readonly property string rankText: ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][rank - 1]
    readonly property color ink: red ? "#D2343A" : "#1C1C1F"
    // The band at the top that overlapping cards leave showing.
    readonly property real band: height * 0.22

    Rectangle {
        anchors.fill: parent
        visible: face.up
        radius: Math.min(Theme.radiusSm, width * 0.1)
        // A white card by day; a softer one at night, so it doesn't glare.
        color: Theme.dark ? "#DCDCE0" : "#FFFFFF"
        // An edge where cards overlap; darker on the night card, which is grey.
        border.width: 1
        border.color: Theme.dark ? "#59000000" : "#22000000"

        Label {
            id: rankLabel
            x: face.width * 0.08
            y: 0
            height: face.band
            verticalAlignment: Text.AlignVCenter
            text: face.rankText
            color: face.ink
            font.pixelSize: Math.max(12, face.band * 0.82)
            font.weight: Font.Bold
            font.letterSpacing: face.rank === 10 ? -1 : 0
        }
        CardSuit {
            x: rankLabel.x + rankLabel.width + face.width * 0.04
            y: face.band * 0.18
            width: face.band * 0.66
            height: width
            suit: face.suit
            color: face.ink
        }
        CardSuit {
            x: (face.width - width) / 2
            y: face.band + (face.height - face.band - height) / 2
            width: face.width * 0.52
            height: width
            suit: face.suit
            color: face.ink
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: !face.up
        radius: Math.min(Theme.radiusSm, width * 0.1)
        border.width: Math.max(2, width * 0.04)
        border.color: Theme.dark ? "#DCDCE0" : "#FFFFFF"
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.15) }
            GradientStop { position: 1; color: Theme.accent }
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.44
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(2, parent.width * 0.05)
            border.color: Qt.rgba(1, 1, 1, 0.5)
        }
    }
}
