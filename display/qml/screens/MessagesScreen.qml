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
// its ▶; the person's own notes too. "I'm heading out" turns away mode on
// from here (for a few hours, or till they're back).
//
// Away mode is the whole window (Main hides the rail and keeps everything
// else away): a header says who's out and counts down to when they're back,
// with "I'm home" to end it (held for two seconds, so a passing tap doesn't
// give the rest of the display back), and the chat is all there is. On the landscape
// tiers who's writing and the quick messages have a column of their own
// beside the thread, so nothing sits over it; tall and mini keep them in
// rows above and below it.
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
    // "I'm heading out" was tapped: how long?
    property bool choosingAway: false
    readonly property bool needsWriter: Messages.names.length > 0 && Messages.writer === ""
    // Landscape: who's writing and the quick messages in a column beside the thread.
    readonly property bool side: !Theme.mini && !Theme.tall
    // The away header as one line: the keyboard is up, or there's no room.
    readonly property bool shortHeader: Theme.mini || screen.keyboardHeight > 0
    // Send or the mic with nobody picked: the "Who's writing?" labels jump.
    signal nudge()

    // Who's writing?, and the prompt when Send or the mic is waiting for a name.
    component WhoLabel: Label {
        text: screen.waiting !== "" ? qsTr("Who's writing? Tap your name to send it")
              : screen.waitingToRecord ? qsTr("Who's talking? Tap your name to record")
                                       : qsTr("Who's writing?")
        color: screen.waiting !== "" || screen.waitingToRecord ? Theme.accent : Theme.textMuted
        font.pixelSize: Theme.fontXs
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
        wrapMode: Text.Wrap
        transformOrigin: Item.Left
        SequentialAnimation on scale {
            id: pulse
            running: false
            NumberAnimation { to: 1.08; duration: Theme.smooth; easing.type: Easing.OutCubic }
            NumberAnimation { to: 1; duration: Theme.smooth; easing.type: Easing.InCubic }
        }
        Connections { target: screen; function onNudge() { pulse.restart() } }
    }

    // "I'm home": held for two seconds, the button filling as it goes; let go
    // early and nothing happens.
    component HoldToEnd: PillButton {
        id: hold
        property real progress: 0
        icon.name: "home"
        text: pressed ? qsTr("Keep holding…") : qsTr("Hold: I'm home")
        onPressedChanged: {
            progress = 0
            if (pressed)
                fill.restart()
            else
                fill.stop()
        }
        NumberAnimation {
            id: fill
            target: hold
            property: "progress"
            from: 0
            to: 1
            duration: 2000
            onFinished: if (hold.pressed) Messages.setAway(false)
        }
        Rectangle {
            width: Math.max(height, parent.width * hold.progress)
            height: parent.height
            radius: height / 2
            visible: hold.progress > 0
            color: Qt.rgba(1, 1, 1, 0.28)
        }
    }

    // Chips that wrap onto more lines in the side column rather than scroll,
    // one chosen, in glass, as Settings' are. Each takes taps across its own
    // width only.
    component ChipFlow: Flow {
        id: chipFlow
        property var model: []
        property string current: ""
        property int chipHeight: 52
        property int fontSize: Theme.fontSm
        signal picked(string id)
        spacing: 8
        Repeater {
            model: chipFlow.model
            delegate: Item {
                id: chip
                required property var modelData
                // The Flow (a delegate's parent): an inline component's ids
                // don't reach its delegates.
                readonly property Item host: parent
                readonly property bool chosen: host !== null && host.current === modelData.id
                width: Math.min(host ? host.width : 0, Math.max(Theme.touchTarget, chipName.implicitWidth + 32))
                height: Math.max(Theme.touchTarget, host ? host.chipHeight : 52)
                Lens {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: chip.host ? chip.host.chipHeight : 52
                    kind: chip.chosen ? "active" : "rest"
                    fill: Theme.surfaceAlt
                    shadow: 0
                    Label {
                        id: chipName
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 24)
                        elide: Text.ElideRight
                        text: chip.modelData.label
                        color: chip.chosen ? Glass.ink : Theme.text
                        font.pixelSize: chip.host ? chip.host.fontSize : Theme.fontSm
                        font.weight: Font.DemiBold
                    }
                }
                TapHandler { onTapped: chip.host.picked(chip.modelData.id) }
            }
        }
    }

    // The mic: a voice note, once whoever's writing has said who they are.
    function record() {
        if (screen.needsWriter) {
            screen.waitingToRecord = true
            screen.nudge()
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
            screen.nudge()
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
            choosingAway = false
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
            visible: !Theme.mini && !Messages.away
            title: qsTr("Messages")
            subtitle: Messages.personName && Messages.personName !== "Parent"
                      ? qsTr("Write to %1's phone").arg(Messages.personName)
                      : qsTr("Write to the phone")
            opacity: rv.at(0)
            PillButton {
                objectName: "awayStart"
                visible: Messages.available && !Messages.away && !screen.choosingAway
                icon.name: "home"
                text: qsTr("I'm heading out")
                fill: Theme.surface
                ink: Theme.text
                onClicked: screen.choosingAway = true
            }
        }

        // How long: then the banner takes its place.
        Rectangle {
            objectName: "awayChooser"
            Layout.fillWidth: true
            visible: screen.choosingAway && !Messages.away && screen.keyboardHeight === 0
            implicitHeight: chooserCol.implicitHeight + 24
            radius: 22
            color: Theme.surface
            ColumnLayout {
                id: chooserCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 20
                anchors.rightMargin: 12
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Heading out? Messages opens first till you're back")
                        color: Theme.text
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                    IconButton {
                        objectName: "awayChooserClose"
                        width: 64; height: 64
                        icon: "close"
                        iconSize: 20
                        fill: Theme.surfaceAlt
                        ink: Theme.textMuted
                        onClicked: screen.choosingAway = false
                    }
                }
                ChipRow {
                    objectName: "awayChoices"
                    Layout.fillWidth: true
                    chipHeight: 52
                    model: [{ id: "0", label: qsTr("Till I'm back") }, { id: "60", label: qsTr("1 hour") },
                            { id: "120", label: qsTr("2 hours") }, { id: "240", label: qsTr("4 hours") },
                            { id: "480", label: qsTr("8 hours") }]
                    current: ""
                    onPicked: id => {
                        screen.choosingAway = false
                        Messages.setAway(true, Number(id))
                    }
                }
            }
        }

        // Away mode: who's out, the countdown to when they're back, and "I'm home".
        GradientTile {
            id: awayHeader
            objectName: "awayBanner"
            Layout.fillWidth: true
            visible: Messages.away
            active: screen.shown
            rings: 1
            radius: Theme.radius
            implicitHeight: (screen.shortHeader ? awayLine.implicitHeight : awayFull.implicitHeight) + 2 * awayPad
            readonly property int awayPad: Theme.mini ? 4 : screen.shortHeader ? 10 : Theme.wide ? 32 : 24
            opacity: rv.at(0)

            // The whole of it: "Dad is out", the countdown, when and why.
            RowLayout {
                id: awayFull
                visible: !screen.shortHeader
                anchors.fill: parent
                anchors.margins: awayHeader.awayPad
                anchors.leftMargin: awayHeader.awayPad + 8
                spacing: 24
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("%1 is out").arg(Messages.awayName)
                        color: awayHeader.inkMuted
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                        font.capitalization: Font.AllUppercase
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        Label {
                            objectName: "awayCountdown"
                            // No time: what the household needs to know instead.
                            text: Messages.awayCountdown || qsTr("Messages go to %1's phone").arg(Messages.awayName)
                            color: awayHeader.ink
                            font.pixelSize: Messages.awayCountdown ? Math.round(Theme.fontHuge * 0.66) : Theme.fontXl
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                            elide: Text.ElideRight
                            Layout.maximumWidth: awayFull.width - awayEnd.width - 40
                        }
                        Label {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 10
                            Layout.fillWidth: true
                            visible: !!Messages.awayCountdown
                            text: qsTr("till %1's back").arg(Messages.awayName)
                            color: awayHeader.inkMuted
                            font.pixelSize: Theme.fontMd
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: Messages.awayNote ? qsTr("%1 · “%2”").arg(Messages.awayBack).arg(Messages.awayNote) : Messages.awayBack
                        color: awayHeader.ink
                        font.pixelSize: Theme.fontMd - 2
                        elide: Text.ElideRight
                    }
                }
                HoldToEnd {
                    id: awayEnd
                    objectName: "awayEnd"
                    Layout.alignment: Qt.AlignVCenter
                    fill: awayHeader.glassFill
                    ink: awayHeader.ink
                }
            }

            // One line, while the keyboard is up (and on mini): "Dad is out · 1:42:10".
            RowLayout {
                id: awayLine
                visible: screen.shortHeader
                anchors.fill: parent
                anchors.margins: awayHeader.awayPad
                anchors.leftMargin: awayHeader.awayPad + 10
                spacing: 14
                Icon { name: "home"; size: 24; color: awayHeader.strong }
                Label {
                    Layout.fillWidth: true
                    text: Messages.awayCountdown ? qsTr("%1 is out · back in %2").arg(Messages.awayName).arg(Messages.awayCountdown)
                                                 : Messages.awayLabel
                    color: awayHeader.ink
                    font.pixelSize: Theme.fontMd - 2
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                    elide: Text.ElideRight
                }
                HoldToEnd {
                    objectName: "awayEndShort"
                    fill: awayHeader.glassFill
                    ink: awayHeader.ink
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.wide ? 24 : 16

            // The chat: (tall and mini: who's writing above it), the thread, (the
            // quick row,) the box.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.mini ? 10 : 16

                // Who's writing: a big button a name.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !screen.side && Messages.names.length > 0 && screen.keyboardHeight === 0
                    spacing: 6
                    opacity: rv.at(1)
                    WhoLabel {
                        Layout.fillWidth: true
                        visible: !Theme.mini || screen.waiting !== "" || screen.waitingToRecord
                    }
                    ChipRow {
                        objectName: screen.side ? "" : "messageWriters"
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
                        // Set after layout, not bound: the margin moves the content,
                        // which would ask for the margin again.
                        function fitTop() { topMargin = Math.max(0, height - contentHeight) }
                        onContentHeightChanged: Qt.callLater(fitTop)
                        // New ones (and a keyboard rising) keep the newest in sight.
                        onCountChanged: Qt.callLater(positionViewAtEnd)
                        onHeightChanged: {
                            Qt.callLater(fitTop)
                            Qt.callLater(positionViewAtEnd)
                        }
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

                // Tap to send: wrapped on tall, where there's room, a row that
                // scrolls on mini. Landscape has them in the side column.
                ChipFlow {
                    objectName: Theme.tall ? "quickMessages" : ""
                    Layout.fillWidth: true
                    visible: Theme.tall && screen.keyboardHeight === 0 && Messages.available
                    model: Messages.quickMessages.map(t => ({ id: t, label: t }))
                    onPicked: id => screen.send(id, false)
                    opacity: rv.at(3)
                }
                ChipRow {
                    objectName: Theme.mini ? "quickMessages" : ""
                    Layout.fillWidth: true
                    visible: Theme.mini && screen.keyboardHeight === 0 && Messages.available
                    chipHeight: 52
                    model: Messages.quickMessages.map(t => ({ id: t, label: t }))
                    current: ""
                    onPicked: id => screen.send(id, false)
                    opacity: rv.at(3)
                }

                // Type it, or record it.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.mini ? 68 : 76
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
                        PillButton {
                            objectName: "messageRecord"
                            visible: Messages.canRecord && !Messages.recording
                            height: 60
                            width: Theme.mini ? 60 : implicitWidth
                            icon.name: "mic"
                            text: Theme.mini ? "" : qsTr("Voice note")
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

            // The side column (landscape): who's writing, then the quick
            // messages, in a column of their own that scrolls if it must.
            Flickable {
                id: sideColumn
                objectName: "messageSide"
                visible: screen.side && Messages.available
                Layout.fillHeight: true
                Layout.preferredWidth: Theme.wide ? 400 : 340
                contentHeight: sideCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                clip: true
                opacity: rv.at(1)
                ColumnLayout {
                    id: sideCol
                    width: sideColumn.width
                    spacing: 16
                    Rectangle {
                        Layout.fillWidth: true
                        visible: Messages.names.length > 0
                        implicitHeight: writersCol.implicitHeight + 36
                        radius: Theme.radius
                        color: Theme.surface
                        ColumnLayout {
                            id: writersCol
                            x: 18
                            y: 18
                            width: parent.width - 36
                            spacing: 10
                            WhoLabel { Layout.fillWidth: true }
                            ChipFlow {
                                objectName: screen.side ? "messageWriters" : ""
                                Layout.fillWidth: true
                                chipHeight: 56
                                fontSize: Theme.fontMd - 2
                                model: Messages.names.map(n => ({ id: n, label: n }))
                                current: Messages.writer
                                onPicked: id => Messages.writer = (Messages.writer === id ? "" : id)
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: quickCol.implicitHeight + 36
                        radius: Theme.radius
                        color: Theme.surface
                        ColumnLayout {
                            id: quickCol
                            x: 18
                            y: 18
                            width: parent.width - 36
                            spacing: 10
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Quick messages")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontXs
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.2
                                font.capitalization: Font.AllUppercase
                            }
                            ChipFlow {
                                objectName: screen.side ? "quickMessages" : ""
                                Layout.fillWidth: true
                                model: Messages.quickMessages.map(t => ({ id: t, label: t }))
                                onPicked: id => screen.send(id, false)
                            }
                        }
                    }
                }
            }
        }
    }
}
