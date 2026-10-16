import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

ApplicationWindow {
    id: window
    // Fill the panel; in a window, start at the 10.1" panel's logical size.
    width: startWindowed ? startWidth : Screen.width
    height: startWindowed ? startHeight : Screen.height
    visible: true
    visibility: startWindowed ? Window.Windowed : Window.FullScreen
    title: "McFly"
    color: Theme.background
    font.family: Theme.fontFamily

    readonly property var screenNames: ["home", "briefs", "markets", "news", "projects", "boards", "calendar"]
    property int currentScreen: Math.max(0, screenNames.indexOf(startScreen))
    readonly property real keyboardHeight: keyboard.item ? keyboard.item.visibleHeight : 0
    // "chat" while push-to-talk is feeding the assistant panel; wake-word
    // turns go to the quick answer card instead.
    property string voiceTarget: ""
    // --screen setup / saver / ask / settings: for pictures and checks.
    readonly property bool forceSetup: startScreen === "setup"

    function showToast(message) {
        if (Device.screenOff)
            return // nobody would see it, and it would redraw a sleeping panel
        toastLabel.text = message
        toastAnim.restart()
    }

    // Push-to-talk from the assistant panel or the Home card. A second tap stops it.
    function pushToTalk() {
        if (!Voice.available) {
            showToast(qsTr("Voice needs the McFly voice service (see docs/VOICE.md)"))
            return false
        }
        if (voiceTarget === "chat") {
            Voice.cancel()
            voiceTarget = ""
            return true
        }
        if (!Voice.canTranscribe) {
            showToast(qsTr("Voice needs a microphone (see docs/VOICE.md)"))
            return false
        }
        dismissKeyboard()
        Voice.stopSpeaking()
        voiceTarget = "chat"
        pttWatchdog.restart()
        Voice.listen()
        return true
    }
    // The service ends a turn within ~12 s; never leave the mic stuck "on".
    Timer { id: pttWatchdog; interval: 25000; onTriggered: window.voiceTarget = "" }

    // Leaving a screen or going idle closes the on-screen keyboard.
    function dismissKeyboard() {
        window.contentItem.forceActiveFocus()
        Qt.inputMethod.hide()
    }
    onCurrentScreenChanged: dismissKeyboard()

    // Whatever a screen pushed over its list (a reader, a story, a tile).
    function closeDetails() {
        briefs.closeDetail()
        markets.closeDetail()
        news.closeStory()
        projects.closeDetail()
        calendar.closeDetail()
    }

    // The frame and the size, from the window (docs/LAYOUTS.md).
    Binding {
        target: Theme; property: "tier"
        value: window.height > window.width ? "tall"
             : window.width < 1000 ? "mini"
             : window.width < 1600 ? "compact" : "wide"
    }
    Binding { target: Theme; property: "shortSide"; value: Math.min(window.width, window.height) }

    Component.onCompleted: {
        if (startScreen === "saver")
            Device.sleepNow()
        else if (startScreen === "ask")
            assistant.open = true
        else if (startScreen === "settings")
            settings.open()
    }

    // Drop back to the home screen after the screen saver has been up.
    Connections {
        target: Device
        function onIdleChanged() {
            if (Device.idle) {
                window.dismissKeyboard()
                assistant.open = false
                window.closeDetails()
                window.currentScreen = 0
            }
        }
    }

    // Re-pairing (or a lost session) starts over behind the setup screen.
    Connections {
        target: Store
        function onModeChanged() {
            if (Store.mode === "pairing") {
                assistant.open = false
                quick.dismiss(true)
                settings.close()
            }
        }
    }

    // Voice: wake word -> quick answer card; push-to-talk -> the chat.
    Connections {
        target: Voice
        function onWoke(source) {
            if (window.voiceTarget === "chat" || Store.mode === "pairing")
                return
            Device.wake()
            window.dismissKeyboard()
            settings.close()
            quick.start()
        }
        function onHeard(text) {
            if (window.voiceTarget === "chat") {
                window.voiceTarget = ""
                pttWatchdog.stop()
                if (AI.busy)
                    AI.stop()
                AI.ask(text)
            } else if (quick.phase === "listening") {
                quick.hear(text)
            }
        }
        function onHeardNothing() {
            if (window.voiceTarget === "chat") {
                window.voiceTarget = ""
                pttWatchdog.stop()
                window.showToast(qsTr("Sorry, I didn't catch that"))
            } else if (quick.phase === "listening") {
                quick.miss()
            }
        }
        function onAvailableChanged() {
            if (!Voice.available)
                window.voiceTarget = ""
        }
        function onErrorOccurred(message) { window.showToast(message) }
    }

    readonly property bool inSetup: (Store.mode === "pairing" || window.forceSetup) && !sleepCover.covering
    readonly property bool navBar: Theme.navMode === "bar"

    // The nav: a rail down the left, or a bar along the bottom. Plain
    // geometry, not anchors: an anchor that once set the height would
    // leave it stuck when the shape changes.
    NavRail {
        id: nav
        visible: !window.inSetup
        horizontal: window.navBar
        x: 0
        y: window.navBar ? window.height - Theme.navHeight : 0
        width: window.navBar ? window.width : Theme.navWidth
        height: window.navBar ? Theme.navHeight : window.height
        currentIndex: window.currentScreen
        // McFly is working on an answer nobody is watching (the panel is shut).
        thinking: AI.busy && !assistant.open
        onSelected: index => {
            assistant.open = false
            window.dismissKeyboard()
            if (index === window.currentScreen)
                window.closeDetails() // the item tapped again: back to its list
            window.currentScreen = index
        }
        onSettingsRequested: { window.dismissKeyboard(); settings.open() }
        onAskRequested: { assistant.open = true; assistant.focusInput() }
    }

    // The pages: right of the rail, or above the bar.
    Item {
        id: pages
        visible: !window.inSetup
        anchors.fill: parent
        anchors.leftMargin: Theme.navWidth
        anchors.bottomMargin: Theme.navHeight

        Page {
            anchors.fill: parent; index: 0; current: window.currentScreen
            HomeScreen {
                anchors.fill: parent
                shown: window.currentScreen === 0 && !assistant.open
                isCurrent: window.currentScreen === 0
                onOpenScreen: index => window.currentScreen = index
                onOpenAssistant: question => {
                    assistant.open = true
                    if (question) AI.ask(question)
                    else assistant.focusInput()
                }
                onPushToTalk: {
                    assistant.open = true
                    if (!window.pushToTalk())
                        assistant.focusInput() // no voice service: type instead
                }
            }
        }
        Page {
            anchors.fill: parent; index: 1; current: window.currentScreen
            BriefsScreen { id: briefs; anchors.fill: parent; shown: window.currentScreen === 1 && !assistant.open; isCurrent: window.currentScreen === 1 }
        }
        Page {
            anchors.fill: parent; index: 2; current: window.currentScreen
            MarketsScreen { id: markets; anchors.fill: parent; shown: window.currentScreen === 2 && !assistant.open; isCurrent: window.currentScreen === 2 }
        }
        Page {
            anchors.fill: parent; index: 3; current: window.currentScreen
            NewsScreen { id: news; anchors.fill: parent; shown: window.currentScreen === 3 && !assistant.open; isCurrent: window.currentScreen === 3 }
        }
        Page {
            anchors.fill: parent; index: 4; current: window.currentScreen
            ProjectsScreen { id: projects; anchors.fill: parent; shown: window.currentScreen === 4 && !assistant.open; isCurrent: window.currentScreen === 4 }
        }
        Page {
            anchors.fill: parent; index: 5; current: window.currentScreen
            DashboardsScreen { anchors.fill: parent; shown: window.currentScreen === 5 && !assistant.open; isCurrent: window.currentScreen === 5 }
        }
        Page {
            anchors.fill: parent; index: 6; current: window.currentScreen
            CalendarScreen { id: calendar; anchors.fill: parent; shown: window.currentScreen === 6 && !assistant.open; isCurrent: window.currentScreen === 6 }
        }
    }

    AssistantPanel {
        id: assistant
        anchors.fill: parent
        anchors.leftMargin: Theme.navWidth
        anchors.bottomMargin: Theme.navHeight
        // The keyboard rises over the bar: only what shows above it counts.
        keyboardHeight: Math.max(0, window.keyboardHeight - Theme.navHeight)
        listening: window.voiceTarget === "chat"
        // The screen behind it: its own question comes first among the chips.
        context: window.currentScreen === 2 && markets.segment === "metrics" ? "metrics"
                                                                            : window.screenNames[window.currentScreen]
        onCloseRequested: {
            window.dismissKeyboard()
            if (window.voiceTarget === "chat") window.pushToTalk() // stop listening
            open = false
        }
        onPushToTalk: window.pushToTalk()
    }

    SetupScreen {
        anchors.fill: parent
        visible: window.inSetup
        sample: window.forceSetup && Store.mode !== "pairing"
        keyboardHeight: window.keyboardHeight
        onWifiRequested: { window.dismissKeyboard(); settings.openWifi() }
    }

    SettingsSheet { id: settings }

    // Dialogs and sheets (Controls popups, z 0) are drawn over everything in
    // the window. What has to stay above them sits in Layers, bottom to top:
    // the keyboard (z 2, in KeyboardPanel), the toast (3), the screen saver
    // (4), the wake-word card (5) and the black of a sleeping screen (6).

    // On-screen keyboard (QT_IM_MODULE=qtvirtualkeyboard on the device).
    Loader {
        id: keyboard
        anchors.fill: parent
        active: Qt.application.arguments.indexOf("--no-keyboard") < 0
        source: "components/KeyboardPanel.qml"
    }

    // Toasts from the store (connected, errors, ...). The Layer is just the
    // point at the top centre of the pill, so it takes no taps.
    Layer {
        id: toast
        z: 3
        x: Math.round(window.width / 2)
        // Above the keyboard, or the bar, whichever is up.
        y: quick.shown ? 48 : window.height - Math.max(window.keyboardHeight, Theme.navHeight) - pill.height - 48
        width: 0
        height: 0
        opacity: 0
        visible: opacity > 0
        Rectangle {
            id: pill
            x: -Math.round(width / 2)
            radius: height / 2
            color: Theme.text
            width: Math.min(toastLabel.implicitWidth + 64, window.width - 32)
            height: 72
            Label {
                id: toastLabel
                anchors.centerIn: parent
                width: Math.min(implicitWidth, pill.width - 48)
                elide: Text.ElideRight
                color: Theme.background
                font.pixelSize: Theme.fontMd
            }
        }
        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: toast; property: "opacity"; to: 1; duration: Theme.quick }
            PauseAnimation { duration: 2500 }
            NumberAnimation { target: toast; property: "opacity"; to: 0; duration: Theme.quick }
        }
        Connections {
            target: Store
            function onNotify(message) { window.showToast(message) }
        }
    }

    // The screen saver covers everything but the wake-word card. It needs no
    // input of its own: DisplayController swallows the waking tap app-wide.
    property bool saverUnderSleep: false
    Connections {
        target: Device
        function onScreenOffChanged() { window.saverUnderSleep = Device.screenOff && saverLayer.opacity > 0 }
    }
    Layer {
        id: saverLayer
        z: 4
        width: window.width
        height: window.height
        visible: opacity > 0
        opacity: Device.idle && !window.inSetup
                 && (!Device.screenOff || (window.saverUnderSleep && !sleepCover.covering)) ? 1 : 0
        // It drifts in when the screen goes idle, and gets out of the way at
        // once when someone touches it.
        Behavior on opacity {
            id: saverFade
            NumberAnimation {
                duration: saverFade.targetValue > 0.5 ? Theme.ambientFade : Theme.smooth
                easing.type: Easing.InOutSine
            }
        }
        ScreenSaver { anchors.fill: parent }
    }

    // Wake-word answers float above everything, the screen saver included.
    Layer {
        z: 5
        width: window.width
        height: window.height
        visible: quick.opacity > 0
        QuickAnswer {
            id: quick
            anchors.fill: parent
            onOpenChat: {
                quick.dismiss(false)
                assistant.open = true
            }
        }
    }

    // A reminder whose time has come (Store.reminderDue): a card at the top,
    // over everything but the sleep cover, read out once. It wakes the
    // screen, as the wake word does: the person asked to be told.
    Layer {
        z: 5
        x: Math.round((window.width - width) / 2)
        y: Theme.mini ? 16 : 32
        width: Math.min(window.width - 2 * Theme.pageMargin, Theme.wide ? 760 : 640)
        height: reminderCard.implicitHeight
        visible: reminderCard.opacity > 0
        ReminderCard {
            id: reminderCard
            anchors.fill: parent
        }
    }
    Connections {
        target: Store
        function onReminderDue(reminder) {
            Device.wake()
            reminderCard.add(reminder)
            if (Voice.available)
                Voice.speak(qsTr("Reminder: %1").arg(reminder.title))
        }
    }

    // Sleep (Settings → Sleep) covers everything: fade to black, then hide
    // what's under it so nothing redraws while the panel is off (PanelPower).
    Layer {
        z: 6
        width: window.width
        height: window.height
        visible: sleepCover.opacity > 0
        Rectangle {
            id: sleepCover
            readonly property bool covering: Device.screenOff && opacity === 1
            anchors.fill: parent
            color: "black"
            opacity: 0
            states: State {
                name: "off"
                when: Device.screenOff
                PropertyChanges { target: sleepCover; opacity: 1 }
            }
            transitions: [
                Transition { to: "off"; NumberAnimation { property: "opacity"; duration: 800; easing.type: Easing.InOutQuad } },
                Transition { from: "off"; NumberAnimation { property: "opacity"; duration: Theme.smooth } }
            ]
        }
    }

    // Offline indicator: top right beside the rail, top centre over a bar
    // (so it never sits on a header's second-row controls).
    Rectangle {
        anchors.top: parent.top
        anchors.right: window.navBar ? undefined : parent.right
        anchors.horizontalCenter: window.navBar ? parent.horizontalCenter : undefined
        anchors.margins: 16
        visible: Store.mode === "live" && !Store.online
        color: Theme.warning
        radius: 12
        width: offlineLabel.implicitWidth + 32
        height: 44
        Label {
            id: offlineLabel
            anchors.centerIn: parent
            text: qsTr("Offline — reconnecting…")
            color: "#1D1E22"
            font.pixelSize: Theme.fontXs
        }
    }
}
