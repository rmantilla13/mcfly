import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// A reminder whose time has come (Store.reminderDue): a card at the top of
// the screen, over whatever is showing, read out once by the voice service.
// It stays until it's closed, or for ten minutes. Several at once stack in
// the one card. The display only reads, so it can't check one off; asking
// McFly ("I called mom") does.
Item {
    id: card
    property var reminders: []
    readonly property bool shown: reminders.length > 0

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

    function add(reminder) {
        const list = reminders.filter(r => r.id !== reminder.id)
        list.push(reminder)
        reminders = list
        hideTimer.restart()
    }
    function dismiss() {
        reminders = []
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
        anchors.fill: parent
        radius: 32
        color: Theme.surface

        ColumnLayout {
            id: body
            x: card.pad
            y: card.pad
            width: parent.width - 2 * card.pad
            spacing: 14

            Repeater {
                model: card.reminders
                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 18

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: Theme.mini ? 48 : 60
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: Theme.accentSoft
                        Icon {
                            anchors.centerIn: parent
                            name: "clock"
                            size: Theme.mini ? 22 : 28
                            color: Theme.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("REMINDER · %1").arg(modelData.timeLabel.toUpperCase())
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontXs
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.2
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: Theme.text
                            font.pixelSize: Theme.fontLg
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: modelData.notes || ""
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSm
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignTop
                        visible: index === 0
                        width: 64
                        height: 64
                        icon: "close"
                        iconSize: 22
                        fill: Theme.surfaceAlt
                        ink: Theme.textMuted
                        onClicked: {
                            Voice.stopSpeaking()
                            card.dismiss()
                        }
                    }
                    // Keeps the rows below the first aligned with it.
                    Item { visible: index > 0; implicitWidth: 64 }
                }
            }
        }
    }
}
