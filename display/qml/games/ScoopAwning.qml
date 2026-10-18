import QtQuick
import QtQuick.Controls
import McFly

// Scoop Shop's awning: stripes in two colours across the top, each ending
// in a scallop, under a frame. With `sign` set and room for it, the shop's
// name hangs on a plaque in the middle.
Item {
    id: awning
    property color stripe: "#F28DB2"
    property color between: "#FFFFFF"
    property color frame: "#D65C8A"
    property color plaque: "#FFFBF2"
    property color plaqueInk: "#C2457A"
    property string sign: ""
    property real stripeWidth: 28

    readonly property real frameHeight: Math.max(3, height * 0.12)
    // Stripes fill the width exactly, and hang a scallop each.
    readonly property int count: Math.max(2, Math.round(width / stripeWidth))
    readonly property real step: width / count
    readonly property real scallop: Math.min(step / 2, height * 0.3)

    Repeater {
        model: awning.count
        delegate: Item {
            required property int index
            readonly property color tone: index % 2 ? awning.between : awning.stripe
            x: index * awning.step
            width: awning.step + 0.5
            height: awning.height
            Rectangle {
                width: parent.width
                height: parent.height - awning.scallop
                color: parent.tone
            }
            Rectangle {
                y: parent.height - 2 * awning.scallop
                width: awning.step
                height: 2 * awning.scallop
                radius: height / 2
                color: parent.tone
            }
        }
    }
    // A fold of shade where the stripes turn down.
    Rectangle {
        y: awning.frameHeight
        width: parent.width
        height: Math.max(2, awning.height * 0.12)
        color: "black"
        opacity: 0.06
    }
    Rectangle {
        width: parent.width
        height: awning.frameHeight
        radius: height / 2
        color: awning.frame
    }

    Rectangle {
        visible: awning.sign !== "" && awning.height >= 30
        anchors.horizontalCenter: parent.horizontalCenter
        y: awning.height * 0.2
        width: signLabel.implicitWidth + awning.height * 0.8
        height: awning.height * 0.62
        radius: height / 2
        color: awning.plaque
        border.width: Math.max(2, height * 0.08)
        border.color: awning.frame
        Label {
            id: signLabel
            anchors.centerIn: parent
            text: awning.sign
            color: awning.plaqueInk
            font.pixelSize: Math.max(12, parent.height * 0.5)
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
    }
}
