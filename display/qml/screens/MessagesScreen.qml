import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Messages: the people at home write to the person's phone, and read the
// replies. Who's writing is a button each (Messages.names, set in the app or
// on the console; none: the display itself), then a message typed, tapped
// from the quick row, or a voice note of up to 30 seconds (the mic, through
// the voice service; Send ends it and sends it, × drops it). Home's
// messages sit on the right in the accent; the person's on the left under
// their name. Under home's newest: "Sending…", "Sent", "On Dad's phone",
// "Seen by Dad"; one that didn't go says why, and a tap tries it again.
// With names listed and none picked, Send (or the mic) asks who's writing
// first and goes on once someone taps their name. A voice note plays with
// its ▶; the person's own notes too.
Item {
    id: screen
    property bool shown: true
    property bool isCurrent: true
    // What the on-screen keyboard covers of this page.
    property real keyboardHeight: 0

    // A message waiting for someone to say who wrote it, or a voice note
    // waiting to start.
    property string waiting: ""
    property bool waitingToRecord: false
    readonly property bool needsWriter: Messages.names.length > 0 && Messages.writer === ""

    // The mic: a voice note, once whoever's writing has said who they are.
    function record() {
        if (screen.needsWriter) {
            screen.waitingToRecord = true
            whoPulse.restart()
            return
        }
        Qt.inputMethod.hide()
        screen.waitingToRecord = false
        Messages.startRecording()
    }

    function send(text, typed) {
        const t = (text || "").trim()
        if (!t)
            return
        if (screen.needsWriter) {
            screen.waiting = t
            whoPulse.restart()
            return
        }
        if (Messages.send(t) && typed)
            Messages.draft = ""
        screen.waiting = ""
    }

    Connections {
        target: Messages
        function onWriterChanged() {
            if (Messages.writer !== "" && screen.waiting !== "") {
                const typed = screen.waiting === Messages.draft.trim()
                screen.send(screen.waiting, typed)
            }
            if (Messages.writer !== "" && screen.waitingToRecord)
                screen.record()
        }
    }
    onIsCurrentChanged: {
        if (!isCurrent) {
            waiting = ""
            waitingToRecord = false
            Messages.cancelRecording()
        }
    }
    // How long the voice note being recorded has run, in seconds.
    property int recordedSeconds: 0
    Timer {
        interval: 250
        repeat: true
        running: Messages.recording
        property double started: 0
        onRunningChanged: { started = Date.now(); screen.recordedSeconds = 0 }
        onTriggered: screen.recordedSeconds = Math.min(30, Math.floor((Date.now() - started) / 1000))
    }

    Reveal { id: rv; shown: screen.isCurrent }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        anchors.bottomMargin: Theme.pageMargin + screen.keyboardHeight
        spacing: Theme.mini ? 10 : 16

        // Mini's 400 px go to the thread: the bar already says Messages.
        ScreenHeader {
            Layout.fillWidth: true
            visible: !Theme.mini
            title: qsTr("Messages")
            subtitle: Messages.personName && Messages.personName !== "Parent"
                      ? qsTr("Write to %1's phone").arg(Messages.personName)
                      : qsTr("Write to the phone")
            opacity: rv.at(0)
        }

        // Away mode: where the person is, and when they'll be back.
        Rectangle {
            objectName: "awayBanner"
            Layout.fillWidth: true
            visible: Messages.away && screen.keyboardHeight === 0
            implicitHeight: awayRow.implicitHeight + 24
            radius: 22
            color: Theme.accentSoft
            opacity: rv.at(1)
            RowLayout {
                id: awayRow
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 14
                Icon { name: "home"; size: 26; color: Theme.accent }
                Label {
                    Layout.fillWidth: true
                    text: Messages.awayNote ? qsTr("%1 · “%2”").arg(Messages.awayLabel).arg(Messages.awayNote) : Messages.awayLabel
                    color: Theme.text
                    font.pixelSize: Theme.fontMd - 2
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        // Who's writing: a big button a name.
        ColumnLayout {
            Layout.fillWidth: true
            visible: Messages.names.length > 0 && screen.keyboardHeight === 0
            spacing: 6
            opacity: rv.at(1)
            Label {
                id: whoLabel
                visible: !Theme.mini || screen.waiting !== "" || screen.waitingToRecord
                text: screen.waiting !== "" ? qsTr("Who's writing? Tap your name to send it")
                      : screen.waitingToRecord ? qsTr("Who's talking? Tap your name to record")
                                               : qsTr("Who's writing?")
                color: screen.waiting !== "" || screen.waitingToRecord ? Theme.accent : Theme.textMuted
                font.pixelSize: Theme.fontXs
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                font.capitalization: Font.AllUppercase
                SequentialAnimation on scale {
                    id: whoPulse
                    running: false
                    NumberAnimation { to: 1.08; duration: Theme.smooth; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 1; duration: Theme.smooth; easing.type: Easing.InCubic }
                }
                transformOrigin: Item.Left
            }
            ChipRow {
                objectName: "messageWriters"
                Layout.fillWidth: true
                chipHeight: 56
                model: Messages.names.map(n => ({ id: n, label: n }))
                current: Messages.writer
                // The same name again: nobody.
                onPicked: id => Messages.writer = (Messages.writer === id ? "" : id)
            }
        }

        // The thread, newest at the bottom.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            opacity: rv.at(2)

            ListView {
                id: list
                objectName: "messageThread"
                anchors.fill: parent
                clip: true
                spacing: 4
                model: Messages.thread
                boundsBehavior: Flickable.StopAtBounds
                // A short thread sits at the bottom, by the box, as a chat does.
                topMargin: Math.max(0, height - contentHeight)
                // New ones (and a keyboard rising) keep the newest in sight.
                onCountChanged: Qt.callLater(positionViewAtEnd)
                onHeightChanged: Qt.callLater(positionViewAtEnd)
                Component.onCompleted: positionViewAtEnd()
                readonly property real bubbleMax: Math.min(width * (Theme.mini ? 0.86 : 0.72), 760)

                delegate: Column {
                    id: row
                    required property var modelData
                    width: list.width
                    spacing: 4
                    topPadding: modelData.dayLabel ? 14 : (modelData.runStart ? 12 : 0)
                    readonly property bool home: !!modelData.home

                    Label {
                        visible: !!row.modelData.dayLabel
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        bottomPadding: 6
                        text: (row.modelData.dayLabel || "").toUpperCase()
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                    }
                    Label {
                        visible: !!row.modelData.runStart
                        x: row.home ? parent.width - width - 8 : 8
                        text: row.modelData.name ? qsTr("%1 · %2").arg(row.modelData.name).arg(row.modelData.timeLabel)
                                                 : row.modelData.timeLabel
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        id: bubble
                        readonly property bool audio: !!row.modelData.hasAudio
                        readonly property real textMax: list.bubbleMax - 2 * 22
                        readonly property bool showsText: !audio || !!row.modelData.caption
                        x: row.home ? parent.width - width : 0
                        width: Math.max(audio ? noteRow.implicitWidth : 0,
                                        showsText ? Math.min(bodyText.implicitWidth, textMax) : 0) + 2 * 22
                        height: content.implicitHeight + 2 * (audio ? 10 : 14)
                        radius: 26
                        color: row.home ? (row.modelData.pending ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                                                                 : Theme.accent)
                                        : Theme.surface
                        border.width: row.modelData.failed ? 2 : 0
                        border.color: Theme.danger
                        Column {
                            id: content
                            x: 22
                            y: bubble.audio ? 10 : 14
                            spacing: 6
                            // A voice note: ▶ (■ while it plays) and how long it is.
                            Row {
                                id: noteRow
                                objectName: "voiceNote"
                                visible: bubble.audio
                                spacing: 14
                                IconButton {
                                    width: 64; height: 64
                                    icon: Messages.playingId === row.modelData.id ? "pause" : "play"
                                    iconSize: 26
                                    fill: row.home ? Qt.rgba(1, 1, 1, 0.22) : Theme.accentSoft
                                    ink: row.home ? Theme.accentInk : Theme.accent
                                    onClicked: Messages.play(row.modelData.id)
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Label {
                                        text: qsTr("Voice note")
                                        color: row.home ? Theme.accentInk : Theme.text
                                        font.pixelSize: Theme.fontMd
                                        font.weight: Font.DemiBold
                                    }
                                    Label {
                                        text: row.modelData.audioLabel || ""
                                        color: row.home ? Qt.rgba(1, 1, 1, 0.8) : Theme.textMuted
                                        font.pixelSize: Theme.fontSm
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }
                            Text {
                                id: bodyText
                                visible: bubble.showsText
                                width: Math.min(implicitWidth, bubble.textMax)
                                text: bubble.audio ? (row.modelData.caption || "") : row.modelData.body
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: row.home ? Theme.accentInk : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontMd
                                lineHeight: 1.15
                            }
                        }
                        // One that didn't go: a tap tries again.
                        TapHandler {
                            enabled: !!row.modelData.failed
                            onTapped: Messages.retry(row.modelData.id)
                        }
                    }
                    Label {
                        visible: !!row.modelData.status
                        x: row.home ? parent.width - width - 8 : 8
                        width: Math.min(implicitWidth, list.bubbleMax)
                        horizontalAlignment: row.home ? Text.AlignRight : Text.AlignLeft
                        wrapMode: Text.Wrap
                        text: row.modelData.failed ? qsTr("%1 · Tap to try again").arg(row.modelData.status) : (row.modelData.status || "")
                        color: row.modelData.failed ? Theme.danger : Theme.textMuted
                        font.pixelSize: Theme.fontXs
                    }
                }
            }

            EmptyState {
                anchors.fill: parent
                visible: list.count === 0
                icon: "chat"
                text: Messages.available ? qsTr("Say hi") : qsTr("Messages aren't set up yet")
                hint: Messages.available ? qsTr("What you write here goes to the phone, and the replies show up here.")
                                         : qsTr("Update McFly's backend to send messages from here.")
            }
        }

        // Tap to send.
        ChipRow {
            objectName: "quickMessages"
            Layout.fillWidth: true
            visible: screen.keyboardHeight === 0 && Messages.available
            chipHeight: 52
            model: Messages.quickMessages.map(t => ({ id: t, label: t }))
            current: ""
            onPicked: id => screen.send(id, false)
            opacity: rv.at(3)
        }

        // Type it, or record it.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            radius: height / 2
            color: Theme.surface
            border.color: input.activeFocus || Messages.recording ? Theme.accent : Theme.divider
            border.width: input.activeFocus || Messages.recording ? 2 : 1
            opacity: rv.at(4)
            enabled: Messages.available

            // Recording a voice note: × drops it, the level and the time, Send sends it.
            Item {
                objectName: "recordingBar"
                anchors.left: parent.left
                anchors.right: buttons.left
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                height: parent.height
                visible: Messages.recording
                IconButton {
                    id: dropNote
                    anchors.verticalCenter: parent.verticalCenter
                    width: 60; height: 60
                    icon: "close"
                    fill: Theme.surfaceAlt
                    ink: Theme.textMuted
                    onClicked: Messages.cancelRecording()
                }
                Rectangle {
                    id: recDot
                    anchors.left: dropNote.right
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14; radius: 7
                    color: Theme.danger
                    SequentialAnimation on opacity {
                        running: Messages.recording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }
                Label {
                    id: recLabel
                    anchors.left: recDot.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Recording… 0:%1").arg(String(screen.recordedSeconds).padStart(2, "0"))
                    color: Theme.text
                    font.pixelSize: Theme.fontMd - 2
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }
                // How loud, so a kid can see it's hearing them.
                Rectangle {
                    anchors.left: recLabel.right
                    anchors.leftMargin: 18
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 10
                    radius: 5
                    color: Theme.surfaceAlt
                    Rectangle {
                        width: parent.width * Math.min(1, Voice.level * 1.4)
                        height: parent.height
                        radius: 5
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.quick } }
                    }
                }
            }

            TextField {
                id: input
                objectName: "messageInput"
                visible: !Messages.recording
                anchors.left: parent.left
                anchors.right: buttons.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 24
                anchors.rightMargin: 8
                text: Messages.draft
                onTextEdited: Messages.draft = text
                maximumLength: 500
                placeholderText: Messages.writer ? qsTr("Write a message, %1").arg(Messages.writer)
                                                 : qsTr("Write a message")
                font.pixelSize: Theme.fontMd - 2
                color: Theme.text
                placeholderTextColor: Theme.textMuted
                background: null
                // As the Ask panel's: a word still being predicted isn't in `text` yet.
                inputMethodHints: Qt.ImhNoPredictiveText
                onAccepted: {
                    Qt.inputMethod.commit()
                    screen.send(text, true)
                }
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                // A voice note (there's no mic without the voice service).
                IconButton {
                    objectName: "messageRecord"
                    visible: Messages.canRecord && !Messages.recording
                    width: 60; height: 60
                    icon: "mic"
                    fill: Theme.surfaceAlt
                    ink: Theme.text
                    onClicked: screen.record()
                }
                IconButton {
                    objectName: "messageSend"
                    width: 60; height: 60
                    icon: "send"
                    fill: Theme.accent
                    ink: Theme.accentInk
                    enabled: Messages.recording || input.text.trim().length > 0 || input.preeditText.length > 0
                    onClicked: {
                        if (Messages.recording) {
                            Messages.finishRecording()
                            return
                        }
                        Qt.inputMethod.commit()
                        screen.send(input.text, true)
                    }
                }
            }
        }
    }
}
