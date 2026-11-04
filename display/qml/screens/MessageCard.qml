import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// A reply from the person (Messages.arrived): a card at the top of the
// screen, over whatever is showing, as a reminder is. Reply opens Messages;
// × puts it away. It stays for ten minutes, and a newer reply takes its
// place. Main.qml wakes the screen for it and reads it out, unless the
// screen is asleep: then it waits under the sleep cover for the next touch.
Item {
    id: card
    property var message: ({})
    readonly property bool shown: !!message.id
    signal reply()

    implicitWidth: 640
    implicitHeight: body.implicitHeight + 2 * pad
    readonly property int pad: Theme.mini ? 18 : Theme.compact ? 22 : 28

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
    transform: Translate {
        y: card.shown ? 0 : -40
        Behavior on y { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
    }

    function show(m) {
        message = m
        hideTimer.restart()
    }
    function dismiss() {
        message = ({})
        hideTimer.stop()
    }

    Timer { id: hideTimer; interval: 10 * 60 * 1000; onTriggered: card.dismiss() }

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
        objectName: "messageCard"
        anchors.fill: parent
        radius: 32
        color: Theme.surface

        RowLayout {
            id: body
            x: card.pad
            y: card.pad
            width: parent.width - 2 * card.pad
            spacing: 18

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Theme.mini ? 48 : 60
                implicitHeight: implicitWidth
                radius: width / 2
                color: Theme.accentSoft
                Icon {
                    anchors.centerIn: parent
                    name: "chat"
                    size: Theme.mini ? 22 : 28
                    color: Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label {
                    Layout.fillWidth: true
                    text: qsTr("%1 · %2").arg((card.message.name || "").toUpperCase()).arg((card.message.timeLabel || "").toUpperCase())
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }
                Text {
                    Layout.fillWidth: true
                    text: card.message.body || ""
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.topMargin: 6
                    spacing: 12
                    // A voice note: play it (again), or stop it.
                    PillButton {
                        visible: !!card.message.audio && Messages.canPlay
                        text: Messages.playingId === card.message.id ? qsTr("Stop") : qsTr("Play")
                        fill: Theme.surfaceAlt
                        ink: Theme.text
                        onClicked: Messages.play(card.message.id)
                    }
                    PillButton {
                        text: qsTr("Reply")
                        onClicked: {
                            Voice.stopSpeaking()
                            card.reply()
                        }
                    }
                }
            }

            IconButton {
                Layout.alignment: Qt.AlignTop
                width: 64
                height: 64
                icon: "close"
                iconSize: 22
                fill: Theme.surfaceAlt
                ink: Theme.textMuted
                onClicked: {
                    Voice.stopSpeaking()
                    Messages.markRead()
                    card.dismiss()
                }
            }
        }
    }
}
