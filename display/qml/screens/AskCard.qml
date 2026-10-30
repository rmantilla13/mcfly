import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// A question an agent is waiting on (Store.asks): a card at the top of the
// screen with a button per choice, the first the main one. A tap answers it
// (Store.answer, with an undo on the bar); × puts it off for a while. It
// never wakes the screen or speaks, and the screen saver covers it: it waits
// for someone to be using the display. Several at once: the oldest shows,
// with how many more.
Item {
    id: card
    // Store.asks less the ones put off (Main.qml keeps that list).
    property var asks: []
    readonly property var ask: asks.length > 0 ? asks[0] : null
    readonly property bool shown: ask !== null
    // × on the card: put this one off.
    signal later(string id)

    implicitWidth: 640
    implicitHeight: body.implicitHeight + 2 * pad
    readonly property int pad: Theme.mini ? 18 : Theme.compact ? 22 : 28
    // The link's code, where there's room for it.
    readonly property bool showCode: !!(ask && ask.url) && !Theme.mini

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
    transform: Translate {
        y: card.shown ? 0 : -40
        Behavior on y { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
    }

    // The card takes every touch on it: a tap on its words or between its
    // buttons, a drag or a wheel would otherwise reach the page underneath
    // (it sits over the page, not in a Layer). The buttons are above this.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    // A soft shadow under the card.
    Rectangle {
        anchors.fill: face
        anchors.margins: -6
        anchors.topMargin: 4
        radius: face.radius + 6
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.14)
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: 32
        color: Theme.surface

        ColumnLayout {
            id: body
            x: card.pad
            y: card.pad
            width: parent.width - 2 * card.pad
            spacing: Theme.mini ? 12 : 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 18

                // The agent's colour, behind a speech bubble.
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: Theme.mini ? 48 : 60
                    implicitHeight: implicitWidth
                    radius: width / 2
                    readonly property color tint: card.ask && card.ask.agentColor ? card.ask.agentColor : Theme.accent
                    color: Qt.rgba(tint.r, tint.g, tint.b, Theme.dark ? 0.28 : 0.16)
                    Icon {
                        anchors.centerIn: parent
                        name: "chat"
                        size: Theme.mini ? 22 : 28
                        color: parent.tint
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 4
                    Label {
                        objectName: "askHeading"
                        Layout.fillWidth: true
                        text: {
                            const a = card.ask
                            if (!a) return ""
                            const parts = [a.agentName ? qsTr("%1 asks").arg(a.agentName) : qsTr("A question"), a.askedLabel]
                            if (a.expiresLabel) parts.push(a.expiresLabel)
                            if (card.asks.length > 1) parts.push(qsTr("%1 more").arg(card.asks.length - 1))
                            return parts.filter(p => !!p).join(" · ").toUpperCase()
                        }
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Label {
                        objectName: "askQuestion"
                        Layout.fillWidth: true
                        text: card.ask ? card.ask.question : ""
                        color: Theme.text
                        font.pixelSize: Theme.fontLg
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: Theme.mini ? 2 : 3
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: card.ask ? card.ask.detail : ""
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSm
                        wrapMode: Text.WordWrap
                        maximumLineCount: Theme.mini ? 1 : 2
                        elide: Text.ElideRight
                    }
                }

                // The link, for the phone's camera.
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    visible: card.showCode
                    implicitWidth: 104
                    implicitHeight: 104
                    radius: 12
                    color: "white"
                    Image {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        height: width
                        source: card.showCode ? "image://qr/" + encodeURIComponent(card.ask.url) : ""
                        sourceSize: Qt.size(width, width)
                        smooth: false
                    }
                }

                IconButton {
                    objectName: "askLater"
                    Layout.alignment: Qt.AlignTop
                    width: 64
                    height: 64
                    icon: "close"
                    iconSize: 22
                    fill: Theme.surfaceAlt
                    ink: Theme.textMuted
                    onClicked: if (card.ask) card.later(card.ask.id)
                }
            }

            // A button per choice; on a narrow panel they wrap. (In an Item:
            // a Flow's own implicit width is every button in one row.)
            Item {
                Layout.fillWidth: true
                implicitHeight: choices.implicitHeight
                Flow {
                    id: choices
                    objectName: "askChoices"
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: card.ask ? card.ask.choices : []
                        delegate: PillButton {
                            required property string modelData
                            required property int index
                            objectName: "askChoice" + index
                            text: modelData
                            fill: index === 0 ? Glass.primary : Theme.surfaceAlt
                            ink: index === 0 ? "white" : Theme.text
                            onClicked: if (card.ask) Store.answer(card.ask.id, modelData)
                        }
                    }
                }
            }
        }
    }
}
