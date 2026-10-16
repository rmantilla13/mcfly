import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// The voice card: floats bottom-centre over any screen, including the screen
// saver. "Hey McFly" or the mic on Home opens it. It listens, shows what it
// heard, streams a short answer and reads it out, then listens again for a
// follow-up, no wake word needed, so one question can turn into a
// conversation. Silence, or "thanks" / "that's all", ends it. With
// follow-ups off it gets out of the way 6 s after it finishes speaking.
// Tapping outside dismisses it and stops the speech; tapping the orb while
// McFly talks cuts in and listens.
Item {
    id: quick
    signal openChat()

    // hidden | listening | thinking | answering | done | missed
    property string phase: "hidden"
    readonly property bool shown: phase !== "hidden"
    property string question: ""
    property bool awaitingSpeech: false
    // The answer being read out (Voice.speak's id): its `spoken` is what
    // opens the mic for a follow-up.
    property string speechId: ""
    // This turn is a follow-up: the card opened the mic itself, with no wake
    // word. Main.qml leaves the service's `wake` for it alone.
    property bool followingUp: false
    // Answers so far in this conversation, and the exchange before the
    // current one, shown above it so a follow-up reads in context.
    property int turns: 0
    property int maxTurns: 6
    property string earlierQuestion: ""
    property string earlierAnswer: ""
    // The last answer was an error ("I couldn't reach McFly cloud…"): say it,
    // but don't keep the mic open after it.
    property bool replyFailed: false
    readonly property bool canFollowUp: Voice.followUp && Voice.available && Voice.canTranscribe
                                        && !replyFailed && turns < maxTurns

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }

    // Voice.woke: a new conversation starts (also restarts an open card).
    function start() {
        stopTimers()
        question = ""
        awaitingSpeech = false
        speechId = ""
        followingUp = false
        turns = 0
        earlierQuestion = ""
        earlierAnswer = ""
        replyFailed = false
        phase = "listening"
        stallTimer.restart()
        dropPendingAnswer()
    }
    // Listen again, without the wake word: after an answer has been read out,
    // or when the orb is tapped (which also cuts a reply short).
    function followUp() {
        if (!Voice.available || !Voice.canTranscribe || turns >= maxTurns)
            return false
        stopTimers()
        earlierQuestion = question
        earlierAnswer = AI.replyText
        question = ""
        awaitingSpeech = false // the reply's `spoken`, if it's cut short, is old news
        speechId = ""
        followingUp = true
        phase = "listening"
        stallTimer.restart()
        startCheck.restart()
        Voice.listen()
        return true
    }
    // Voice.heard: ask the assistant for a quick answer.
    function hear(text) {
        stallTimer.stop()
        startCheck.stop()
        // "Thanks", "that's all", or McFly hearing the end of its own answer:
        // nothing to ask, the conversation is over.
        if (followingUp && (AI.endsConversation(text) || AI.echoesReply(text, earlierAnswer))) {
            dismiss(false)
            return
        }
        question = text
        phase = "thinking"
        replyFailed = false
        AI.askQuick(text)
    }
    // Voice.heardNothing (or the service went away mid-turn).
    function miss() {
        stallTimer.stop()
        startCheck.stop()
        if (followingUp) {
            dismiss(false) // nobody said anything more: that's the end of it
            return
        }
        phase = "missed"
        dismissIn(2600)
    }
    function dismiss(stopSpeech) {
        if (!shown)
            return
        // Never leave the mic open behind a closed card.
        if (phase === "listening" && (Voice.state === "listening" || Voice.state === "transcribing"))
            Voice.cancel()
        if (stopSpeech)
            Voice.stopSpeaking()
        phase = "hidden"
        awaitingSpeech = false
        speechId = ""
        followingUp = false
        stopTimers()
        if (stopSpeech)
            dropPendingAnswer()
    }
    function stopTimers() {
        dismissTimer.stop()
        speechTimer.stop()
        stallTimer.stop()
        followUpTimer.stop()
        startCheck.stop()
    }
    // A quick answer still on its way belongs to a question this card no
    // longer shows: stop it so it neither lands here nor gets read out.
    // (Called once the phase has moved on, so its last update is ignored.)
    function dropPendingAnswer() {
        if (AI.busy && AI.replyMode === "quick")
            AI.stop()
    }
    function quoted(text) {
        return "“" + text.charAt(0).toUpperCase() + text.slice(1) + "”"
    }
    function dismissIn(ms) {
        dismissTimer.interval = ms
        dismissTimer.restart()
    }

    Timer { id: dismissTimer; onTriggered: quick.dismiss(false) }
    // If `spoken` never comes (speech failed), don't hang around forever.
    Timer { id: speechTimer; onTriggered: { quick.awaitingSpeech = false; quick.dismissIn(6000) } }
    // The service ends a turn within ~12 s; give up quietly if it doesn't.
    Timer { id: stallTimer; interval: 20000; onTriggered: if (quick.phase === "listening") quick.miss() }
    // After an answer is read out, the room's echo fades before the mic opens
    // again, or McFly would hear the end of its own sentence.
    Timer {
        id: followUpTimer
        interval: 700
        onTriggered: {
            // Only into a quiet room: never over a reminder being read out.
            if (quick.phase === "done" && Voice.state === "idle" && quick.followUp())
                return
            if (quick.phase === "done")
                quick.dismissIn(6000)
        }
    }
    // A follow-up the service never started listening for (it said why in an
    // error): close rather than show "Listening…" to nobody.
    Timer {
        id: startCheck
        interval: 2500
        onTriggered: if (quick.followingUp && quick.phase === "listening" && Voice.state === "idle") quick.dismiss(false)
    }

    Connections {
        target: AI
        enabled: quick.shown
        function onReplyChanged() {
            if (quick.phase === "thinking" && AI.busy && AI.replyMode === "quick" && AI.replyText.length > 0)
                quick.phase = "answering"
        }
        function onReplyFinished(text, mode, speechId, error) {
            if (mode !== "quick" || (quick.phase !== "thinking" && quick.phase !== "answering"))
                return
            quick.phase = "done"
            quick.turns += 1
            quick.replyFailed = error === true
            if (speechId) {
                quick.awaitingSpeech = true
                quick.speechId = speechId
                speechTimer.interval = 10000 + text.length * 90
                speechTimer.restart()
            } else {
                // Nothing to listen to: leave it up long enough to read.
                quick.dismissIn(6000 + Math.min(text.length * 45, 9000))
            }
        }
    }
    Connections {
        target: Voice
        enabled: quick.shown
        function onSpoken(id) {
            if (!quick.awaitingSpeech || id !== quick.speechId)
                return
            quick.awaitingSpeech = false
            speechTimer.stop()
            if (quick.canFollowUp)
                followUpTimer.restart()
            else
                quick.dismissIn(6000)
        }
        function onAvailableChanged() {
            if (!Voice.available && quick.phase === "listening")
                quick.miss()
        }
    }

    readonly property string orbMode: phase === "listening" ? (Voice.state === "listening" ? "listening" : "thinking")
                                    : phase === "thinking" || phase === "answering" ? "thinking"
                                    : Voice.state === "speaking" ? "speaking" : "idle"
    readonly property string stateLabel: phase === "listening" ? (Voice.state === "transcribing" ? qsTr("Thinking…") : qsTr("Listening…"))
                                       : phase === "thinking" ? qsTr("Thinking…")
                                       : phase !== "done" || followUpTimer.running ? ""
                                       : Voice.state === "speaking" ? qsTr("Speaking · tap to cut in")
                                       : Voice.canTranscribe && turns < maxTurns ? qsTr("Tap to ask more")
                                       : ""

    // Shade toward the card so it reads over busy photos; taps here dismiss.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.38) }
        }
        MouseArea { anchors.fill: parent; onClicked: quick.dismiss(true) }
    }

    Item {
        id: cardArea
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (Theme.mini ? 20 : Theme.compact ? 32 : 48) + Theme.navHeight
        width: Math.min(parent.width - 2 * Theme.pageMargin, Theme.wide ? 880 : Theme.tall ? 680 : 760)
        height: Math.max(body.implicitHeight, orbHolder.height - 24) + 2 * pad
        readonly property int pad: Theme.mini ? 18 : Theme.compact ? 24 : 32
        Behavior on height { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }

        transform: Translate {
            y: quick.shown ? 0 : 60
            Behavior on y { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
        }
        scale: quick.shown ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }

        // A soft shadow under the card.
        Rectangle {
            anchors.fill: card
            anchors.margins: -6
            anchors.topMargin: 4
            radius: card.radius + 6
            color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.14)
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 36
            color: Theme.surface

            // Taps on the card itself don't dismiss it. Once there's an
            // answer they ask a follow-up, cutting McFly short if it's still
            // talking.
            MouseArea {
                anchors.fill: parent
                onClicked: if (quick.phase === "done") quick.followUp()
            }

            // The voice glow in a small dark host, like the phone app's.
            Rectangle {
                id: orbHolder
                x: cardArea.pad - 8
                y: cardArea.pad - 8
                width: Theme.mini ? 120 : Theme.compact ? 150 : 172
                height: Theme.mini ? 88 : Theme.compact ? 108 : 124
                radius: 28
                color: "#1B1A1F"
                clip: true
                SpectrumGlow {
                    anchors.fill: parent
                    kind: "input"
                    cornerRadius: parent.radius
                    level: Voice.level
                    processing: quick.orbMode === "thinking"
                    speaking: quick.orbMode === "speaking"
                    ambient: quick.orbMode === "idle"
                    active: quick.shown
                }
                Icon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -8
                    name: quick.orbMode === "listening" ? "mic" : quick.orbMode === "speaking" ? "speaker" : "sparkle"
                    size: 28
                    color: Qt.rgba(1, 1, 1, 0.85)
                }
            }

            ColumnLayout {
                id: body
                anchors.left: orbHolder.right
                anchors.leftMargin: 18
                anchors.right: parent.right
                anchors.rightMargin: cardArea.pad
                // Centred on the orb while short; grows downward from there.
                y: cardArea.pad + Math.max(0, (orbHolder.height - 24 - implicitHeight) / 2)
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    Layout.rightMargin: corner.width // clear of the buttons
                    visible: text.length > 0
                    text: quick.stateLabel.toUpperCase()
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }

                // The exchange before this one, so a follow-up reads in context.
                Label {
                    Layout.fillWidth: true
                    Layout.rightMargin: corner.width
                    visible: quick.followingUp && quick.earlierQuestion.length > 0
                    text: quick.quoted(quick.earlierQuestion) + "  " + quick.earlierAnswer
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSm
                    wrapMode: Text.WordWrap
                    maximumLineCount: Theme.mini ? 1 : 2
                    elide: Text.ElideRight
                }

                // What was heard: the live transcript, then the question.
                Label {
                    Layout.fillWidth: true
                    Layout.rightMargin: corner.width
                    visible: text.length > 0
                    text: quick.phase === "missed" ? qsTr("Sorry, I didn't catch that")
                        : quick.question ? quick.quoted(quick.question)
                        : Voice.transcript ? quick.quoted(Voice.transcript)
                        : Voice.state === "listening" ? (quick.followingUp ? qsTr("Anything else? Or say “thanks”")
                                                                           : qsTr("Ask about the markets, the news, your briefs…"))
                        : ""
                    color: quick.question || quick.phase === "missed" || Voice.transcript ? Theme.text : Theme.textMuted
                    font.pixelSize: quick.question ? Theme.fontMd : Theme.fontLg
                    font.weight: quick.phase === "missed" ? Font.Medium : Font.Normal
                    wrapMode: Text.WordWrap
                    maximumLineCount: Theme.mini ? 2 : 3
                    elide: Text.ElideRight
                }

                // The answer, as it streams.
                Label {
                    id: answer
                    Layout.fillWidth: true
                    visible: quick.phase === "answering" || quick.phase === "done"
                    text: AI.replyText
                    color: Theme.text
                    font.pixelSize: Theme.compact ? Theme.fontLg - 2 : Theme.fontLg
                    font.weight: Font.Medium
                    lineHeight: 1.12
                    wrapMode: Text.WordWrap
                    maximumLineCount: Theme.mini ? 4 : 6
                    elide: Text.ElideRight
                }
            }

            // Top right: back to the full chat, and close.
            Row {
                id: corner
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 16
                spacing: 10
                PillButton {
                    visible: quick.phase === "answering" || quick.phase === "done"
                    text: qsTr("Open chat")
                    fill: Theme.accentSoft
                    ink: Theme.accent
                    implicitHeight: 48
                    implicitWidth: contentItem.implicitWidth + 44
                    onClicked: quick.openChat()
                }
                IconButton {
                    width: 48
                    height: 48
                    icon: "close"
                    iconSize: 20
                    fill: Theme.surfaceAlt
                    ink: Theme.textMuted
                    onClicked: quick.dismiss(true)
                }
            }
        }
    }
}
