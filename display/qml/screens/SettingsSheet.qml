import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Display settings, from the gear in the nav rail, in tabs:
//   Screen   Home's layout, the screen saver, dark mode, the backdrop
//   Voice    the wake word, McFly's voice, the speakers, who answers, and
//            whether the voice service and a mic are there
//   Wi-Fi    on or off, the network and address, joining another
//   Account  agents, calendars, memory, re-pairing
//   System   sleep, restart and reboot, about this display
//   Admin    switches for working on McFly
// The setup screen opens it on Wi-Fi; until the display is paired the
// re-pairing part and the codes to scan stay hidden.
Popup {
    id: sheet
    modal: true
    // While the Wi-Fi password keyboard is up, the sheet fits in the room
    // above it and scrolls the field into view.
    // (Settable so a test can stand in for the keyboard.)
    property real keyboardHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    readonly property int edge: Theme.mini ? 8 : Theme.tall ? 16 : 32
    readonly property real room: (parent ? parent.height : 800) - keyboardHeight - 2 * edge
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: Math.round(edge + (room - height) / 2)
    Behavior on y { enabled: sheet.opened; NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
    width: Math.min(parent ? parent.width - 2 * edge : 1100, Theme.paned ? 1100 : 10000)
    height: Math.min(room, chrome.implicitHeight + topPadding + bottomPadding)
    Behavior on height { enabled: sheet.opened; NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
    padding: Theme.mini ? 18 : Theme.compact ? 28 : 36
    closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

    property string tab: "screen"         // one of `tabs`
    readonly property var tabs: [{ id: "screen", label: qsTr("Screen"), icon: "frame" },
                                 { id: "voice", label: qsTr("Voice"), icon: "mic" },
                                 { id: "wifi", label: qsTr("Wi-Fi"), icon: "wifi" },
                                 { id: "account", label: qsTr("Account"), icon: "link" },
                                 { id: "system", label: qsTr("System"), icon: "power" },
                                 { id: "admin", label: qsTr("Admin"), icon: "chart" }]
    readonly property Item currentPage: ({ screen: screenPage, voice: voicePage, wifi: wifiPage, account: accountPage,
                                           system: systemPage, admin: adminPage })[tab] || null
    readonly property real tallest: Math.max(screenPage.implicitHeight, voicePage.implicitHeight, wifiPage.implicitHeight,
                                             accountPage.implicitHeight, systemPage.implicitHeight, adminPage.implicitHeight)
    readonly property bool typing: keyboardHeight > 0
    property bool confirmingRepair: false
    property string confirmingPower: ""   // "" | restart | reboot
    property string joinSsid: ""
    // No join under way (Cancel, joined, another tab): the keyboard goes,
    // and with it the title and tabs come back. On the smallest panel they
    // step aside while it is up, so it must never stay up on its own.
    onJoinSsidChanged: if (joinSsid === "") Qt.inputMethod.hide()
    Connections {
        target: System
        function onWifiChanged() {
            if (sheet.joinSsid !== "" && System.wifiSsid === sheet.joinSsid)
                sheet.joinSsid = ""
        }
    }
    onOpened: System.refresh()
    onClosed: {
        confirmingRepair = false
        confirmingPower = ""
        joinSsid = ""
        tab = "screen"
        Qt.inputMethod.hide()
    }
    onTabChanged: {
        if (tab === "wifi")
            System.scanWifi()
        else
            joinSsid = ""
        confirmingRepair = false
        confirmingPower = ""
        body.contentY = 0
    }
    // Opens on a tab (an id in `tabs`; Screen for any other).
    function openTab(id) {
        tab = tabs.some(t => t.id === id) ? id : "screen"
        open()
    }
    function openWifi() { openTab("wifi") }
    function openAdmin() { openTab("admin") }
    readonly property bool paired: Store.mode !== "pairing"

    // Like every dialog and sheet, it closes when the display goes idle.
    Connections {
        target: Device
        function onIdleChanged() {
            if (Device.idle)
                sheet.close()
        }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.smooth }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Theme.smooth; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.smooth } }

    background: Rectangle { radius: 32; color: Theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }

    readonly property string modeLabel: Store.mode === "demo" ? qsTr("Demo · sample data")
                                      : Store.mode === "pairing" ? qsTr("Waiting to be paired")
                                      : Store.online ? qsTr("Live · online") : qsTr("Live · offline")

    // Choices for Sleep → Turn screen off, in seconds; 0 is never.
    readonly property var offChoices: [0, 300, 600, 900, 1800, 3600, 7200, 14400]

    // The next choice up (dir > 0) or down from the current delay, which may
    // sit between two of them; undefined at either end.
    function offStep(dir) {
        const now = Device.offAfterSec
        if (dir > 0)
            return offChoices.find(sec => sec > now)
        return offChoices.slice().reverse().find(sec => sec < now)
    }

    function durationLabel(sec) {
        if (sec <= 0)
            return qsTr("Never")
        if (sec < 3600)
            return qsTr("%1 min").arg(Math.round(sec / 60))
        const hours = Math.round(sec / 360) / 10
        return hours === 1 ? qsTr("1 hour") : qsTr("%1 hours").arg(hours)
    }

    function clockLabel(minuteOfDay) {
        return Qt.formatTime(new Date(2000, 0, 1, Math.floor(minuteOfDay / 60), minuteOfDay % 60), "h:mm AP")
    }

    // Small caps heading above each group.
    component SectionLabel: Label {
        color: Theme.textMuted
        font.pixelSize: Theme.fontXs
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }

    // A labelled row inside a group: round icon, title and detail, then a control.
    component SettingRow: RowLayout {
        id: row
        property string icon: ""
        property string title: ""
        property string detail: ""
        default property alias control: slot.data
        spacing: 16
        Layout.fillWidth: true
        // Taller when the detail wraps, as it does in a narrow column.
        Layout.preferredHeight: Math.max(84, words.implicitHeight + 24)
        Rectangle {
            Layout.preferredWidth: 52
            Layout.preferredHeight: 52
            radius: 26
            color: Theme.surface
            Icon { anchors.centerIn: parent; name: row.icon; size: 24; color: Theme.text }
        }
        ColumnLayout {
            id: words
            Layout.fillWidth: true
            spacing: 2
            Label { Layout.fillWidth: true; text: row.title; color: Theme.text; font.pixelSize: Theme.fontSm + 1; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: row.detail
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
                wrapMode: Text.WordWrap
            }
        }
        Item {
            id: slot
            Layout.preferredWidth: childrenRect.width
            Layout.preferredHeight: childrenRect.height
        }
    }

    // − value + for a setting that moves in steps.
    component Stepper: RowLayout {
        id: stepper
        property string text: ""
        property bool canDown: true
        property bool canUp: true
        signal down()
        signal up()
        spacing: 6
        IconButton {
            icon: "minus"
            fill: Theme.surface
            implicitWidth: 52
            implicitHeight: 52
            enabled: stepper.canDown
            onClicked: stepper.down()
        }
        Label {
            Layout.preferredWidth: Theme.compact ? 100 : 112
            text: stepper.text
            color: Theme.text
            font.pixelSize: Theme.fontSm
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }
        IconButton {
            icon: "plus"
            fill: Theme.surface
            implicitWidth: 52
            implicitHeight: 52
            enabled: stepper.canUp
            onClicked: stepper.up()
        }
    }

    // One fact in the About group.
    component Fact: RowLayout {
        id: fact
        property string name: ""
        property string value: ""
        property color dot: "transparent"
        Layout.fillWidth: true
        Layout.preferredHeight: 46
        spacing: 10
        Label { text: fact.name; color: Theme.textMuted; font.pixelSize: Theme.fontSm - 1; Layout.preferredWidth: 130 }
        Rectangle {
            visible: fact.dot.a > 0
            Layout.preferredWidth: 10
            Layout.preferredHeight: 10
            radius: 5
            color: fact.dot
        }
        Label {
            Layout.fillWidth: true
            text: fact.value
            color: Theme.text
            font.pixelSize: Theme.fontSm - 1
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }


    // One tab's page: two columns on the wider panels (their widths in
    // proportion to each one's `share`), one above the other on the small
    // ones. Faded out but still laid out while another tab is chosen.
    component TabPage: GridLayout {
        property string tab: ""
        readonly property bool shown: sheet.tab === tab
        width: parent ? parent.width : 0
        columns: Theme.paned ? 2 : 1
        columnSpacing: Theme.compact ? 24 : 32
        rowSpacing: Theme.compact ? 20 : 26
        opacity: shown ? 1 : 0
        visible: opacity > 0
        enabled: shown
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
    }
    // A column of a page. Neither column stretches to the other's height: a
    // layout in a layout fills by default, and a row would take the slack.
    component TabColumn: ColumnLayout {
        property int share: 1
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredWidth: share
        Layout.alignment: Qt.AlignTop
        spacing: 12
    }

    // Chips that wrap onto another line where a column is narrow, rather than
    // scroll: one chosen, in glass. Each is a touch target tall and takes taps
    // across its own width only, so a tap in a gap picks neither neighbour.
    component ChipFlow: Flow {
        id: chipFlow
        property var model: []
        property string current: ""
        signal picked(string id)
        spacing: 6
        Repeater {
            model: chipFlow.model
            delegate: Item {
                id: chip
                required property var modelData
                // The Flow (a delegate's parent): an inline component's ids
                // don't reach its delegates.
                readonly property Item host: parent
                readonly property bool chosen: host !== null && host.current === modelData.id
                width: Math.max(Theme.touchTarget, chipName.implicitWidth + 28)
                height: Theme.touchTarget
                Lens {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 48
                    kind: chip.chosen ? "active" : "rest"
                    shadow: 0
                    Label {
                        id: chipName
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        color: chip.chosen ? Glass.ink : Theme.text
                        font.pixelSize: Theme.fontXs + 1
                        font.weight: Font.DemiBold
                    }
                }
                TapHandler { onTapped: chip.host.picked(chip.modelData.id) }
            }
        }
    }

    contentItem: ColumnLayout {
        id: chrome
        spacing: Theme.compact ? 16 : 20

        RowLayout {
            // On the smallest panel the keyboard leaves room for the field only.
            visible: !(sheet.typing && Theme.mini)
            Layout.fillWidth: true
            Column {
                Layout.fillWidth: true
                Label {
                    text: qsTr("Settings")
                    color: Theme.text
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.DemiBold
                }
                Label {
                    text: qsTr("This display")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSm
                }
            }
            IconButton {
                visible: sheet.tab === "wifi"
                icon: "refresh"
                fill: Theme.surfaceAlt
                enabled: !System.busy && System.canManageWifi
                onClicked: System.scanWifi()
            }
            IconButton { icon: "close"; fill: Theme.surfaceAlt; onClicked: sheet.close() }
        }

        // Out of the way while the keyboard is up, so the field has room.
        TabStrip {
            objectName: "settingsTabs"
            visible: !sheet.typing
            Layout.fillWidth: true
            model: sheet.tabs
            current: sheet.tab
            onPicked: id => sheet.tab = id
        }

        // Every tab's page stays laid out, faded out when not chosen: the
        // sheet is as tall as the tallest (within the room there is), and
        // keeps still when the tab changes. The chosen one sets the scroll.
        FocusFlickable {
            id: body
            objectName: "settingsBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: sheet.tallest
            contentHeight: sheet.currentPage ? sheet.currentPage.implicitHeight : 0

            Item {
                id: pages
                width: body.width
                height: body.contentHeight

                TabPage {
                    id: screenPage
                    tab: "screen"

                    TabColumn {
                        share: 3

                        // Home's layout (Device.homeLayout, HomeLayouts.qml).
                        SectionLabel { text: qsTr("HOME") }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.bottomMargin: 12
                            spacing: 12
                            Repeater {
                                model: [{ id: "today", icon: "home", title: qsTr("Today"), detail: qsTr("What's next, then the day") },
                                        { id: "bento", icon: "grid", title: qsTr("Bento"), detail: qsTr("Tiles for briefs, markets, news") },
                                        { id: "assistant", icon: "sparkle", title: qsTr("Assistant"), detail: qsTr("McFly sums up the day first") }]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool chosen: Device.homeLayout === modelData.id
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.small ? 92 : 104
                                    radius: 24
                                    color: chosen ? Theme.accentSoft : Theme.surfaceAlt
                                    border.width: chosen ? 2 : 0
                                    border.color: Theme.accent
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 12
                                        Rectangle {
                                            Layout.preferredWidth: 44; Layout.preferredHeight: 44; radius: 22
                                            color: chosen ? Theme.accent : Theme.surface
                                            Icon { anchors.centerIn: parent; name: modelData.icon; size: 22; color: chosen ? Theme.accentInk : Theme.text }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Label { Layout.fillWidth: true; text: modelData.title; color: Theme.text; font.pixelSize: Theme.fontSm + 1; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.detail
                                                color: Theme.textMuted
                                                font.pixelSize: Theme.fontXs
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    TapHandler { onTapped: Device.homeLayout = modelData.id }
                                }
                            }
                        }

                        SectionLabel { text: qsTr("SCREEN SAVER") }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 12
                            Repeater {
                                model: [{ id: "ambient", icon: "sparkle", title: qsTr("Ambient"), detail: qsTr("Clock, what's next, cards") },
                                        { id: "headlines", icon: "news", title: qsTr("Headlines"), detail: qsTr("Stories, one at a time") },
                                        { id: "clock", icon: "clock", title: qsTr("Clock"), detail: qsTr("Time, brief, markets") }]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool chosen: Device.screensaver === modelData.id
                                    Layout.fillWidth: true
                                    // Fixed: two lines of detail fit beside the icon.
                                    Layout.preferredHeight: Theme.small ? 92 : 104
                                    radius: 24
                                    color: chosen ? "transparent" : Theme.surfaceAlt
                                    // Chosen: active glass (Lens), its disc the primary's.
                                    Lens { anchors.fill: parent; visible: parent.chosen; kind: "active"; radius: 24 }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 12
                                        Lens {
                                            Layout.preferredWidth: 44; Layout.preferredHeight: 44
                                            kind: chosen ? "primary" : "rest"
                                            shadowY: chosen ? 3 : 2
                                            shadowBlur: chosen ? 6 : 5
                                            Icon { anchors.centerIn: parent; name: modelData.icon; size: 22; color: chosen ? "white" : Theme.text }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Label { Layout.fillWidth: true; text: modelData.title; color: Theme.text; font.pixelSize: Theme.fontSm + 1; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.detail
                                                color: Theme.textMuted
                                                font.pixelSize: Theme.fontXs
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    TapHandler { onTapped: Device.screensaver = modelData.id }
                                }
                            }
                        }

                        SectionLabel { Layout.topMargin: 12; text: qsTr("DISPLAY") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: displayRows.implicitHeight
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: displayRows
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 18
                                anchors.rightMargin: 20
                                spacing: 0
                                SettingRow {
                                    icon: "moon"
                                    title: qsTr("Dark mode")
                                    detail: qsTr("Warm dark background for the whole screen")
                                    Toggle {
                                        checked: Device.darkMode
                                        onToggled: on => Device.darkMode = on
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider }
                                SettingRow {
                                    icon: "sparkle"
                                    title: qsTr("Animated tiles")
                                    detail: qsTr("Let the colors on Home and Setup drift slowly")
                                    Toggle {
                                        checked: Device.animatedTiles
                                        onToggled: on => Device.animatedTiles = on
                                    }
                                }
                            }
                        }
                    }

                    TabColumn {
                        share: 2

                        // What Ambient and Clock draw behind the words.
                        SectionLabel { text: qsTr("BACKDROP") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: backdropRows.implicitHeight
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: backdropRows
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                spacing: 0
                                SettingRow {
                                    icon: "sparkle"
                                    title: qsTr("Backdrop")
                                    detail: qsTr("Behind Ambient, Clock and the assistant: the drifting gradient, or a sky of its own")
                                }
                                ChipFlow {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 68
                                    Layout.bottomMargin: 8
                                    model: [{ id: "mesh", label: qsTr("Mesh") }, { id: "arc", label: qsTr("Arc") },
                                            { id: "ribbons", label: qsTr("Ribbons") }, { id: "dawn", label: qsTr("Dawn") },
                                            { id: "silk", label: qsTr("Silk") }, { id: "pillars", label: qsTr("Pillars") }]
                                    current: Device.backdrop
                                    onPicked: id => Device.backdrop = id
                                }
                                // What falls over it: by the season where the
                                // display is (DisplayController::weatherFor), or one all year.
                                SettingRow {
                                    readonly property var names: ({ snow: qsTr("Snow"), petals: qsTr("Petals"),
                                                                    fireflies: qsTr("Fireflies"), leaves: qsTr("Leaves") })
                                    icon: "sun"
                                    title: qsTr("Weather")
                                    detail: Device.weather === "season"
                                            ? qsTr("Over Ambient and Clock, by the season here: %1 now").arg(names[Device.weatherKind] || "")
                                            : qsTr("Over Ambient and Clock: by the season, or one all year")
                                }
                                ChipFlow {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 68
                                    Layout.bottomMargin: 8
                                    model: [{ id: "off", label: qsTr("Off") }, { id: "season", label: qsTr("Season") },
                                            { id: "snow", label: qsTr("Snow") }, { id: "petals", label: qsTr("Petals") },
                                            { id: "fireflies", label: qsTr("Fireflies") }, { id: "leaves", label: qsTr("Leaves") }]
                                    current: Device.weather
                                    onPicked: id => Device.weather = id
                                }
                            }
                        }
                    }
                }

                TabPage {
                    id: voicePage
                    tab: "voice"

                    TabColumn {
                        share: 3

                        SectionLabel { text: qsTr("VOICE") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: voiceRows.implicitHeight
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: voiceRows
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 18
                                anchors.rightMargin: 20
                                spacing: 0
                                SettingRow {
                                    icon: Voice.available ? "mic" : "mic-off"
                                    title: qsTr("Wake word")
                                    detail: !Voice.available ? qsTr("Needs the McFly voice service")
                                          : !Voice.micName ? qsTr("No microphone found. Plug in a USB mic; it's picked up within 10 seconds.")
                                          : Voice.wakewordLabel ? qsTr("Say “%1” to ask a quick question").arg(Voice.wakewordLabel)
                                          : qsTr("Ask a quick question hands-free")
                                    Toggle {
                                        enabled: Voice.available
                                        checked: Voice.available && Voice.wakewordEnabled
                                        onToggled: on => Voice.setWakewordEnabled(on)
                                    }
                                }
                                // Which one wakes it. The whole card's width, not under the
                                // title like Backdrop's: five fit on a line that way at
                                // 1280×800 and 1920×1080, and wrap rather than clip if not.
                                // Not a ChipRow: at its padding, five are a few pixels too
                                // wide for the card at 1920×1080, where it would scroll them.
                                Flow {
                                    visible: Voice.available
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 8
                                    spacing: 6
                                    Repeater {
                                        model: Voice.wakewords
                                        // A 48 px chip in a touch target's height, its own
                                        // width: a TapHandler margin would reach across the
                                        // gap, and a tap there would pick both neighbours.
                                        delegate: Item {
                                            id: wakeChip
                                            required property var modelData
                                            readonly property bool chosen: Voice.wakewordModel === modelData.id
                                            width: wakeName.implicitWidth + 24
                                            height: Theme.touchTarget
                                            Lens {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width
                                                height: 48
                                                kind: wakeChip.chosen ? "active" : "rest"
                                                shadow: 0
                                                Label {
                                                    id: wakeName
                                                    anchors.centerIn: parent
                                                    text: wakeChip.modelData.label
                                                    color: wakeChip.chosen ? Glass.ink : Theme.text
                                                    font.pixelSize: Theme.fontXs + 1
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                            TapHandler { onTapped: Voice.setVoiceOptions("", 0, wakeChip.modelData.id) }
                                        }
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider }
                                // Homestead's Kokoro voices, when the service speaks with Kokoro.
                                SettingRow {
                                    visible: Voice.available && Voice.voiceId.length > 0
                                    icon: "speaker"
                                    title: qsTr("Voice")
                                    detail: qsTr("The voice McFly answers in, as in Homestead")
                                    RowLayout {
                                        spacing: 6
                                        Repeater {
                                            model: [{ id: "af_heart", name: qsTr("Heart") }, { id: "af_bella", name: qsTr("Bella") },
                                                    { id: "am_michael", name: qsTr("Michael") }, { id: "am_fenrir", name: qsTr("Fenrir") }]
                                            // A 44 px chip in a touch target's height and at least its width.
                                            delegate: Item {
                                                id: voiceChip
                                                required property var modelData
                                                readonly property bool chosen: Voice.voiceId === modelData.id
                                                implicitWidth: Math.max(Theme.touchTarget, voiceName.implicitWidth + 28)
                                                implicitHeight: Theme.touchTarget
                                                Lens {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width
                                                    height: 44
                                                    kind: voiceChip.chosen ? "active" : "rest"
                                                    shadow: 0
                                                    Label {
                                                        id: voiceName
                                                        anchors.centerIn: parent
                                                        text: voiceChip.modelData.name
                                                        color: voiceChip.chosen ? Glass.ink : Theme.text
                                                        font.pixelSize: Theme.fontSm - 1
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                                TapHandler { onTapped: Voice.setVoiceOptions(voiceChip.modelData.id, 0, "") }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    visible: Voice.available && Voice.voiceId.length > 0
                                    Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider
                                }
                                SettingRow {
                                    icon: "speaker"
                                    title: qsTr("Spoken replies")
                                    detail: qsTr("Answer out loud when asked by voice")
                                    Toggle {
                                        checked: Voice.speakReplies
                                        onToggled: on => Voice.speakReplies = on
                                    }
                                }
                                Rectangle {
                                    visible: Voice.speakReplies
                                    Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider
                                }
                                // Only with spoken replies: the mic opens once an answer has been read out.
                                SettingRow {
                                    visible: Voice.speakReplies
                                    icon: "mic"
                                    title: qsTr("Follow-up questions")
                                    detail: qsTr("Keep listening after an answer, no wake word needed")
                                    Toggle {
                                        checked: Voice.followUp
                                        onToggled: on => Voice.followUp = on
                                    }
                                }
                            }
                        }

                        SectionLabel { visible: System.volumeAvailable; Layout.topMargin: 12; text: qsTr("SPEAKERS") }
                        Rectangle {
                            visible: System.volumeAvailable
                            Layout.fillWidth: true
                            Layout.preferredHeight: speakerRows.implicitHeight
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: speakerRows
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 18
                                anchors.rightMargin: 20
                                spacing: 0
                                SettingRow {
                                    icon: System.muted ? "speaker-off" : "speaker"
                                    title: qsTr("Screen speakers")
                                    detail: System.muted
                                            ? qsTr("Off. This stops the hiss from the screen.")
                                            : qsTr("Built into the screen. Its own buttons still change how loud it is.")
                                    Toggle {
                                        checked: !System.muted
                                        onToggled: on => System.setMuted(!on)
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider }
                                SettingRow {
                                    enabled: !System.muted
                                    icon: "speaker"
                                    title: qsTr("Volume")
                                    detail: System.muted ? qsTr("Turn the speakers on to change this.") : qsTr("Lower this if a hiss remains.")
                                    RowLayout {
                                        spacing: 8
                                        enabled: !System.muted
                                        Label {
                                            text: Math.round(volume.value) + "%"
                                            color: Theme.textMuted
                                            font.pixelSize: Theme.fontXs
                                            Layout.preferredWidth: 48
                                        }
                                        Slider {
                                            id: volume
                                            from: 0
                                            to: 100
                                            stepSize: 1
                                            enabled: !System.muted
                                            value: System.volume < 0 ? 0 : System.volume
                                            implicitWidth: Theme.compact ? 160 : 200
                                            implicitHeight: 44
                                            onPressedChanged: if (!pressed) System.setVolume(Math.round(value))
                                            background: Rectangle {
                                                x: volume.leftPadding
                                                y: volume.topPadding + volume.availableHeight / 2 - 3
                                                implicitWidth: 160
                                                width: volume.availableWidth
                                                height: 6
                                                radius: 3
                                                color: Theme.divider
                                                Rectangle {
                                                    width: volume.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width)
                                                y: volume.topPadding + volume.availableHeight / 2 - height / 2
                                                width: 28
                                                height: 28
                                                radius: 14
                                                color: Theme.surface
                                                border.color: Theme.divider
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    TabColumn {
                        share: 2

                        SectionLabel { text: qsTr("ASSISTANT") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: providerRows.implicitHeight
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: providerRows
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 18
                                anchors.rightMargin: 20
                                spacing: 0
                                SettingRow {
                                    icon: "sparkle"
                                    title: qsTr("Answers from")
                                    detail: AI.provider === "" ? qsTr("Your account's choice (%1). Pick one to pin it for this screen.").arg(AI.effectiveProvider === "grok" ? "Grok" : "Claude")
                                                               : qsTr("Pinned for this screen; your account's choice is %1.").arg(Store.assistantProvider === "grok" ? "Grok" : "Claude")
                                }
                                // Under the words, in the narrower column, as Backdrop's are.
                                ChipFlow {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 68
                                    Layout.bottomMargin: 8
                                    model: [{ id: "claude", label: "Claude" }, { id: "grok", label: "Grok" }]
                                    current: AI.effectiveProvider
                                    onPicked: id => AI.provider = id
                                }
                            }
                        }

                        // Whether anything can hear or answer: shown even when it can't.
                        SectionLabel { Layout.topMargin: 12; text: qsTr("STATUS") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: voiceFacts.implicitHeight + 20
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: voiceFacts
                                anchors.fill: parent
                                anchors.margins: 10
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 0
                                Fact {
                                    name: qsTr("Voice service")
                                    value: Voice.available ? qsTr("Connected") : qsTr("Not running")
                                    dot: Voice.available ? Theme.success : Theme.textMuted
                                }
                                Fact {
                                    name: qsTr("Microphone")
                                    value: !Voice.available ? "—" : (Voice.micName || qsTr("Not found"))
                                    dot: Voice.available ? (Voice.micName ? Theme.success : Theme.danger) : Theme.textMuted
                                }
                            }
                        }
                    }
                }

                TabPage {
                    id: wifiPage
                    tab: "wifi"

                    TabColumn {
                        share: 2

                        SectionLabel { text: qsTr("WI-FI") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: radioRows.implicitHeight + (System.wifiAvailable ? 10 : 20)
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: radioRows
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: System.wifiAvailable ? 0 : 10
                                anchors.leftMargin: 18
                                anchors.rightMargin: 20
                                spacing: 0
                                SettingRow {
                                    visible: System.wifiAvailable
                                    icon: "wifi"
                                    title: qsTr("Wi-Fi")
                                    detail: System.wifiEnabled ? qsTr("On") : qsTr("Off")
                                    Toggle {
                                        enabled: System.canManageWifi && !System.busy
                                        checked: System.wifiEnabled
                                        onToggled: function (on) { System.setWifiEnabled(on) }
                                    }
                                }
                                Rectangle { visible: System.wifiAvailable; Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider }
                                Fact {
                                    Layout.leftMargin: 2
                                    name: qsTr("Network")
                                    value: !System.wifiAvailable ? qsTr("No Wi-Fi controls here")
                                         : !System.wifiEnabled ? qsTr("Off")
                                         : System.wifiSsid ? System.wifiSsid + (System.wifiSignal >= 0 ? qsTr(" · %1%").arg(System.wifiSignal) : "")
                                         : qsTr("Not joined")
                                }
                                Fact { Layout.leftMargin: 2; name: qsTr("Address"); value: System.ipAddress || "—" }
                            }
                        }

                        Label {
                            visible: System.message.length > 0
                            Layout.fillWidth: true
                            text: System.message
                            color: Theme.text
                            font.pixelSize: Theme.fontSm
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            visible: !System.wifiAvailable
                            Layout.fillWidth: true
                            text: qsTr("Wi-Fi controls are on the Pi. Run the display install again, then open this tab.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSm
                            wrapMode: Text.WordWrap
                        }
                    }

                    TabColumn {
                        share: 3

                        SectionLabel {
                            visible: System.wifiAvailable
                            text: System.busy ? qsTr("NETWORKS · LOOKING…") : qsTr("NETWORKS")
                        }

                        Rectangle {
                            visible: sheet.joinSsid.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: joinBox.implicitHeight + 28
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: joinBox
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 16
                                spacing: 12
                                Label {
                                    text: qsTr("Join %1").arg(sheet.joinSsid)
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSm
                                    font.weight: Font.DemiBold
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 64
                                    radius: 32
                                    color: Theme.surface
                                    border.color: wifiPassword.activeFocus ? Theme.accent : Theme.divider
                                    border.width: wifiPassword.activeFocus ? 2 : 1
                                    TextField {
                                        id: wifiPassword
                                        objectName: "wifiPassword"
                                        anchors.fill: parent
                                        anchors.leftMargin: 22
                                        anchors.rightMargin: 22
                                        placeholderText: qsTr("Password, usually 8 or more characters")
                                        font.pixelSize: Theme.fontSm
                                        color: Theme.text
                                        placeholderTextColor: Theme.textMuted
                                        background: null
                                        echoMode: TextInput.Password
                                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                                        onAccepted: System.connectWifi(sheet.joinSsid, text, false)
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    PillButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Cancel")
                                        fill: Theme.surface
                                        ink: Theme.text
                                        onClicked: sheet.joinSsid = ""
                                    }
                                    PillButton {
                                        Layout.fillWidth: true
                                        text: System.busy ? qsTr("Joining…") : qsTr("Join")
                                        enabled: !System.busy && wifiPassword.text.length > 0
                                        onClicked: System.connectWifi(sheet.joinSsid, wifiPassword.text, false)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: System.wifiAvailable
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(72, netCol.implicitHeight)
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: netCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                spacing: 0
                                Repeater {
                                    model: System.networks
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 76
                                        color: modelData.inUse ? Theme.accentSoft : "transparent"
                                        radius: 18
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 18
                                            anchors.rightMargin: 18
                                            spacing: 14
                                            Icon { name: "wifi"; size: 22; color: Theme.text }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Label {
                                                    text: modelData.ssid
                                                    color: Theme.text
                                                    font.pixelSize: Theme.fontSm
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Label {
                                                    text: modelData.signal + "%"
                                                          + (modelData.secure ? (modelData.saved ? qsTr(" · Saved") : qsTr(" · Password")) : qsTr(" · Open"))
                                                          + (modelData.inUse ? qsTr(" · Connected") : "")
                                                    color: Theme.textMuted
                                                    font.pixelSize: Theme.fontXs
                                                }
                                            }
                                        }
                                        TapHandler {
                                            enabled: !modelData.inUse && !System.busy
                                            onTapped: {
                                                if (modelData.secure && !modelData.saved) {
                                                    sheet.joinSsid = modelData.ssid
                                                    wifiPassword.text = ""
                                                    wifiPassword.forceActiveFocus()
                                                } else {
                                                    sheet.joinSsid = ""
                                                    System.connectWifi(modelData.ssid, "", modelData.saved)
                                                }
                                            }
                                        }
                                    }
                                }
                                Label {
                                    visible: System.networks.length === 0 && !System.busy
                                    Layout.fillWidth: true
                                    Layout.margins: 18
                                    text: System.wifiEnabled ? qsTr("No networks found. Try refresh.") : qsTr("Turn Wi-Fi on to look for networks.")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSm
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                TabPage {
                    id: accountPage
                    tab: "account"

                    TabColumn {
                        share: 3

                        // Agents: who feeds this screen, how recently, and what
                        // each may read. Adding or changing one happens on the web.
                        SectionLabel { text: qsTr("AGENTS") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: agentRows.implicitHeight + 20
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: agentRows
                                anchors.fill: parent
                                anchors.margins: 10
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 0
                                Label {
                                    visible: Store.agents.length === 0
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    Layout.bottomMargin: 8
                                    text: sheet.paired ? qsTr("No agents yet. Scan the code below to add one.")
                                                   : qsTr("Once this display is paired, agents are added on mcfly.bot/agents.")
                                    wrapMode: Text.WordWrap
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSm - 1
                                }
                                Repeater {
                                    model: Store.agents.filter(a => a.active)
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 56
                                        spacing: 12
                                        Rectangle {
                                            Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 16
                                            color: modelData.color
                                            Label { anchors.centerIn: parent; text: modelData.initial; color: "white"; font.pixelSize: Theme.fontXs; font.weight: Font.Bold }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Label { Layout.fillWidth: true; text: modelData.name; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                            Label {
                                                Layout.fillWidth: true
                                                text: [qsTr("Last push %1").arg(modelData.seenLabel)].concat(modelData.scopeLabels || []).join(" · ")
                                                color: Theme.textMuted
                                                font.pixelSize: Theme.fontXs
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 10; Layout.preferredHeight: 10; radius: 5
                                            color: modelData.seenRecently ? Theme.success : Theme.textMuted
                                            opacity: modelData.seenRecently ? 1 : 0.5
                                        }
                                    }
                                }
                            }
                        }
                        QrPanel {
                            Layout.fillWidth: true
                            visible: sheet.paired
                            url: "https://mcfly.bot/agents"
                            title: qsTr("Add or change agents")
                            caption: qsTr("Scan to open Agents on your phone: pick what it's for and it gives you the prompt to paste.")
                            domain: "mcfly.bot/agents"
                            codeSize: Theme.small ? 96 : 120
                        }
                    }

                    TabColumn {
                        share: 2

                        // Calendars: the subscriptions McFly reads every 15 minutes.
                        SectionLabel { text: qsTr("CALENDARS") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: calendarRows.implicitHeight + 20
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: calendarRows
                                anchors.fill: parent
                                anchors.margins: 10
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 0
                                Label {
                                    visible: Store.calendarSources.length === 0
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    Layout.bottomMargin: 8
                                    text: qsTr("No calendars yet. Subscribe to Google, iCloud or Outlook on mcfly.bot/calendars.")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSm - 1
                                    wrapMode: Text.WordWrap
                                }
                                Repeater {
                                    model: Store.calendarSources
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 52
                                        spacing: 12
                                        Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: modelData.color }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Label { Layout.fillWidth: true; text: modelData.name; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                            Label {
                                                Layout.fillWidth: true
                                                text: !modelData.enabled ? qsTr("Paused")
                                                    : modelData.error ? modelData.error
                                                    : qsTr("%1 events · synced %2").arg(modelData.eventCount).arg(modelData.syncedLabel)
                                                color: modelData.error && modelData.enabled ? Theme.danger : Theme.textMuted
                                                font.pixelSize: Theme.fontXs
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        QrPanel {
                            Layout.fillWidth: true
                            visible: sheet.paired
                            url: "https://mcfly.bot/calendars"
                            title: qsTr("Add a calendar")
                            caption: qsTr("Scan to paste your calendar's iCal link on your phone. The link stays on the server.")
                            domain: "mcfly.bot/calendars"
                            codeSize: Theme.small ? 96 : 120
                        }

                        // Memory: what McFly knows about you. The assistant and
                        // agents you allow read these notes.
                        SectionLabel { Layout.topMargin: 12; text: qsTr("MEMORY") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: memoryRows.implicitHeight + 24
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: memoryRows
                                anchors.fill: parent
                                anchors.margins: 12
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 8
                                Label {
                                    visible: Store.memories.length === 0
                                    Layout.fillWidth: true
                                    text: qsTr("Nothing yet. Add notes on mcfly.bot/memory: where you live, what you follow, how you like briefs.")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSm - 1
                                    wrapMode: Text.WordWrap
                                }
                                Repeater {
                                    model: Store.memories.slice(0, 6)
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Icon { Layout.alignment: Qt.AlignTop; Layout.topMargin: 3; name: modelData.pinned ? "star" : "brief"; size: 16; color: modelData.pinned ? Theme.accent : Theme.textMuted }
                                        Label {
                                            Layout.fillWidth: true
                                            text: modelData.text
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSm - 1
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                Label {
                                    visible: Store.memories.length > 6
                                    text: qsTr("%1 more on mcfly.bot/memory").arg(Store.memories.length - 6)
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontXs
                                }
                            }
                        }
                        QrPanel {
                            Layout.fillWidth: true
                            visible: sheet.paired && Store.memories.length === 0
                            url: "https://mcfly.bot/memory"
                            title: qsTr("Tell McFly about you")
                            caption: qsTr("Scan to add notes on your phone. The assistant reads them, and agents you allow.")
                            domain: "mcfly.bot/memory"
                            codeSize: Theme.small ? 96 : 120
                        }

                        SectionLabel { visible: sheet.paired; Layout.topMargin: 12; text: qsTr("PAIRING") }
                        Rectangle {
                            visible: sheet.paired
                            Layout.fillWidth: true
                            Layout.preferredHeight: repair.implicitHeight + 36
                            radius: 24
                            color: sheet.confirmingRepair ? Qt.rgba(0.94, 0.5, 0.35, 0.14) : Theme.surfaceAlt
                            Behavior on color { ColorAnimation { duration: Theme.quick } }

                            ColumnLayout {
                                id: repair
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 14

                                Label {
                                    Layout.fillWidth: true
                                    text: sheet.confirmingRepair
                                          ? qsTr("Re-pair this display? It forgets your account and shows a new code to enter from your phone or mcfly.bot.")
                                          : Store.mode === "demo" ? qsTr("Pairing isn't available in demo mode.")
                                          : qsTr("Connect this screen to another account, or pair it again after a reset.")
                                    color: sheet.confirmingRepair ? Theme.text : Theme.textMuted
                                    font.pixelSize: Theme.fontXs + 1
                                    wrapMode: Text.WordWrap
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    PillButton {
                                        visible: !sheet.confirmingRepair
                                        Layout.fillWidth: true
                                        text: qsTr("Re-pair this display")
                                        fill: Theme.surface
                                        ink: Theme.text
                                        enabled: Store.mode === "live"
                                        onClicked: sheet.confirmingRepair = true
                                    }
                                    PillButton {
                                        visible: sheet.confirmingRepair
                                        Layout.fillWidth: true
                                        text: qsTr("Cancel")
                                        fill: Theme.surface
                                        ink: Theme.text
                                        onClicked: sheet.confirmingRepair = false
                                    }
                                    PillButton {
                                        visible: sheet.confirmingRepair
                                        Layout.fillWidth: true
                                        text: qsTr("Re-pair")
                                        fill: "#E2604A"
                                        ink: "white"
                                        onClicked: { sheet.close(); Store.unpair() }
                                    }
                                }
                            }
                        }
                    }
                }

                TabPage {
                    id: systemPage
                    tab: "system"

                    TabColumn {
                        share: 3

                        SectionLabel { text: qsTr("SLEEP") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: sleepRows.implicitHeight
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: sleepRows
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 18
                                anchors.rightMargin: 20
                                spacing: 0
                                SettingRow {
                                    icon: "clock"
                                    title: qsTr("Turn screen off")
                                    detail: Device.offAfterSec > 0
                                            ? qsTr("After %1 without a touch. A tap turns it back on.").arg(sheet.durationLabel(Device.offAfterSec))
                                            : qsTr("Never. The screen saver stays on.")
                                    Stepper {
                                        text: sheet.durationLabel(Device.offAfterSec)
                                        canDown: sheet.offStep(-1) !== undefined
                                        canUp: sheet.offStep(1) !== undefined
                                        onDown: Device.offAfterSec = sheet.offStep(-1)
                                        onUp: Device.offAfterSec = sheet.offStep(1)
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider }
                                SettingRow {
                                    icon: "bed"
                                    title: qsTr("Off overnight")
                                    detail: qsTr("%1 to %2. Off once nobody is using it; a tap still wakes it.")
                                            .arg(sheet.clockLabel(Device.bedtime)).arg(sheet.clockLabel(Device.wakeTime))
                                    Toggle {
                                        checked: Device.offAtNight
                                        onToggled: on => Device.offAtNight = on
                                    }
                                }
                                Rectangle { visible: Device.offAtNight; Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider }
                                SettingRow {
                                    visible: Device.offAtNight
                                    icon: "moon"
                                    title: qsTr("Bedtime")
                                    detail: qsTr("The screen saver turns off")
                                    Stepper {
                                        text: sheet.clockLabel(Device.bedtime)
                                        onDown: Device.bedtime = Device.bedtime - 30
                                        onUp: Device.bedtime = Device.bedtime + 30
                                    }
                                }
                                Rectangle { visible: Device.offAtNight; Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider }
                                SettingRow {
                                    visible: Device.offAtNight
                                    icon: "sun"
                                    title: qsTr("Wake up")
                                    detail: qsTr("The screen saver comes back on")
                                    Stepper {
                                        text: sheet.clockLabel(Device.wakeTime)
                                        onDown: Device.wakeTime = Device.wakeTime - 30
                                        onUp: Device.wakeTime = Device.wakeTime + 30
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.leftMargin: 68; height: 1; color: Theme.divider }
                                SettingRow {
                                    icon: "power"
                                    title: qsTr("Turn off now")
                                    detail: qsTr("Until someone taps the screen")
                                    PillButton {
                                        text: qsTr("Turn off")
                                        fill: Theme.surface
                                        ink: Theme.text
                                        onClicked: {
                                            sheet.close()
                                            Device.turnOffNow()
                                        }
                                    }
                                }
                            }
                        }

                        SectionLabel { Layout.topMargin: 12; text: qsTr("POWER") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: power.implicitHeight + 36
                            radius: 24
                            color: sheet.confirmingPower === "" ? Theme.surfaceAlt : Qt.rgba(0.94, 0.5, 0.35, 0.14)
                            Behavior on color { ColorAnimation { duration: Theme.quick } }
                            ColumnLayout {
                                id: power
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 14
                                Label {
                                    Layout.fillWidth: true
                                    text: sheet.confirmingPower === "reboot"
                                          ? qsTr("Reboot the Pi? The screen stays dark for about a minute.")
                                          : sheet.confirmingPower === "restart"
                                          ? qsTr("Restart McFly? The screen goes blank for a few seconds.")
                                          : qsTr("Restart the app, or reboot the Pi, without unplugging it.")
                                    color: sheet.confirmingPower === "" ? Theme.textMuted : Theme.text
                                    font.pixelSize: Theme.fontXs + 1
                                    wrapMode: Text.WordWrap
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    PillButton {
                                        visible: sheet.confirmingPower === ""
                                        Layout.fillWidth: true
                                        text: qsTr("Restart")
                                        fill: Theme.surface
                                        ink: Theme.text
                                        onClicked: sheet.confirmingPower = "restart"
                                    }
                                    PillButton {
                                        visible: sheet.confirmingPower === ""
                                        Layout.fillWidth: true
                                        text: qsTr("Reboot")
                                        fill: Theme.surface
                                        ink: Theme.text
                                        enabled: System.canReboot
                                        onClicked: sheet.confirmingPower = "reboot"
                                    }
                                    PillButton {
                                        visible: sheet.confirmingPower !== ""
                                        Layout.fillWidth: true
                                        text: qsTr("Cancel")
                                        fill: Theme.surface
                                        ink: Theme.text
                                        onClicked: sheet.confirmingPower = ""
                                    }
                                    PillButton {
                                        visible: sheet.confirmingPower !== ""
                                        Layout.fillWidth: true
                                        text: sheet.confirmingPower === "reboot" ? qsTr("Reboot") : qsTr("Restart")
                                        fill: "#E2604A"
                                        ink: "white"
                                        onClicked: {
                                            var which = sheet.confirmingPower
                                            sheet.close()
                                            if (which === "reboot")
                                                System.reboot()
                                            else
                                                System.restartApp()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    TabColumn {
                        share: 2

                        SectionLabel { text: qsTr("ABOUT") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: facts.implicitHeight + 20
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: facts
                                anchors.fill: parent
                                anchors.margins: 10
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 0
                                Fact { name: qsTr("Mode"); value: sheet.modeLabel }
                                Fact { visible: sheet.paired; name: qsTr("Display"); value: Store.displayName || "—" }
                                Fact { visible: sheet.paired; name: qsTr("Feeds"); value: Store.lastSyncLabel }
                                Fact { name: qsTr("Version"); value: "McFly " + Qt.application.version }
                            }
                        }
                    }
                }

                TabPage {
                    id: adminPage
                    tab: "admin"
                    columns: 1

                    TabColumn {
                        share: 1

                        SectionLabel { text: qsTr("PERFORMANCE") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: perfRow.implicitHeight
                            radius: 24
                            color: Theme.surfaceAlt
                            ColumnLayout {
                                id: perfRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 18
                                anchors.rightMargin: 20
                                SettingRow {
                                    icon: "chart"
                                    title: qsTr("Performance overlay")
                                    detail: Perf.forced
                                            ? qsTr("Frames, GPU, CPU and temperature in the top right corner. On at every start: MCFLY_PERF_HUD is set in display.env.")
                                            : qsTr("Frames, GPU, CPU and temperature in the top right corner, once a second.")
                                    Toggle {
                                        checked: Perf.enabled
                                        onToggled: function (on) { Perf.enabled = on }
                                    }
                                }
                                SettingRow {
                                    icon: "refresh"
                                    title: qsTr("Draw every frame")
                                    detail: qsTr("For measuring: the overlay's fps is then what this screen can keep up. 60 is the panel's most; under 30 is too slow. It heats the Pi, and turns off with the overlay.")
                                    Toggle {
                                        enabled: Perf.enabled
                                        checked: Perf.stress
                                        onToggled: function (on) { Perf.stress = on }
                                    }
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: qsTr("From a computer, display/scripts/pi-perf.sh shows the same and the rest of the Pi (docs/PI_SETUP.md).")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontXs
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
