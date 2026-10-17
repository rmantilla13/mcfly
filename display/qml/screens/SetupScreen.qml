import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// First run: a full-screen, slowly drifting colour field (the same mesh
// gradient as the Home tiles, with its glass rings) and the voice glow along
// the bottom. Two steps on a glass card: join Wi-Fi, then connect this
// screen to your account with the 6-digit code, typed into the phone app or
// mcfly.bot/pair, or by scanning the code.
Item {
    id: setup
    signal wifiRequested()
    // For pictures and checks (--screen setup): shows a sample code.
    property bool sample: false
    property real keyboardHeight: 0

    readonly property bool online: !!(System.ipAddress || System.wifiSsid)
    readonly property string code: sample ? "123456" : Store.pairingCode
    readonly property bool haveCode: code.length === 6
    readonly property int step: !setup.online && System.wifiAvailable ? 1 : 2
    readonly property string pairUrl: "https://mcfly.bot/pair?code=" + code

    // A network came up (e.g. Wi-Fi joined here): ask for a code right away
    // instead of waiting for the next retry.
    Connections {
        target: System
        function onWifiChanged() { setup.retry() }
        function onIpChanged() { setup.retry() }
    }
    function retry() {
        if (Store.mode === "pairing" && setup.online)
            Store.refresh()
    }
    property string joinSsid: ""
    onVisibleChanged: if (visible) System.refresh()

    // The drifting lights, the card's float and the digits' wave keep the
    // ambient clock's 30 updates a second (MotionClock), not every frame the
    // panel draws. Stopped, each holds where it is, as its Animation did; a
    // light rises from below the screen again each time the drift starts.
    readonly property bool drifting: setup.visible && !Device.idle && Device.animatedTiles
    readonly property bool waving: setup.visible && setup.haveCode && Device.animatedTiles
    property real riseFrom: 0
    onDriftingChanged: if (drifting) riseFrom = lightsClock.time
    MotionClock { id: lightsClock; objectName: "lights"; playing: setup.drifting }
    MotionClock { id: floatClock; objectName: "float"; playing: setup.drifting && setup.keyboardHeight === 0 }
    MotionClock { id: waveClock; objectName: "wave"; playing: setup.waving }

    // The colour field.
    GradientTile {
        // Full screen: shaded at half its pixels (GradientTile.resolution).
        resolution: 0.5
        id: field
        anchors.fill: parent
        radius: 0
        colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
        active: setup.visible
        seed: 2.2
        period: 42000
        ringScale: 1.35
        ringBias: 0.76
        grain: 0.02
    }
    // Floating light: slow, soft discs drifting up, from below the screen to
    // above it in 26 s and 5 s more per disc, eased in and out, again and
    // again. Each waits 1.8 s per disc, fades in to 0.22 over 4 s and down to
    // 0.06 over 6 s, again and again (from nothing the first time).
    Repeater {
        model: 6
        delegate: Rectangle {
            objectName: "light"
            required property int index
            readonly property real size: 120 + index * 46
            readonly property real rise: 26 + index * 5
            readonly property real wait: index * 1.8
            width: size; height: size; radius: size / 2
            color: index % 2 === 0 ? Theme.glowCream : Theme.glowAmber
            x: setup.width * (0.08 + 0.15 * index)
            y: setup.height + 100 - (setup.height + 300) * (1 - Math.cos(Math.PI * ((lightsClock.time - setup.riseFrom) % rise) / rise)) / 2
            opacity: {
                const n = Math.floor(lightsClock.time / (wait + 10))
                const s = lightsClock.time - n * (wait + 10) - wait
                const low = n === 0 ? 0 : 0.06
                return s < 0 ? low : s < 4 ? low + (0.22 - low) * s / 4 : 0.22 - 0.16 * (s - 4) / 6
            }
        }
    }
    SpectrumGlow {
        anchors.fill: parent
        ambient: true
        intensity: 0.75
        cornerRadius: 0
        active: setup.visible
        processing: Store.mode === "pairing" && !setup.haveCode && setup.online
    }

    // The card.
    Rectangle {
        id: card
        objectName: "card"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // A gentle float: up from -10 to -16 over 5 s, then down to -4 and
        // back, 5 s each way, eased in and out.
        anchors.verticalCenterOffset: -setup.keyboardHeight / 2 - 10 + (setup.keyboardHeight > 0 ? 0
            : floatClock.time < 5 ? -3 * (1 - Math.cos(Math.PI * floatClock.time / 5))
            : -6 * Math.cos(Math.PI * (floatClock.time - 5) / 5))
        width: Math.min(parent.width - 2 * Theme.pageMargin, Theme.compact ? 1120 : 1240)
        height: Math.min(parent.height - 2 * Theme.pageMargin - setup.keyboardHeight, content.implicitHeight + 2 * pad)
        readonly property int pad: Theme.mini ? 20 : Theme.compact ? 32 : 44
        radius: 40
        color: Qt.rgba(1, 1, 1, Theme.dark ? 0.08 : 0.55)
        border.color: Qt.rgba(1, 1, 1, Theme.dark ? 0.16 : 0.75)
        border.width: 1
        Behavior on height { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }

        // Squeezed (the keyboard is up, or the panel is short), it scrolls.
        FocusFlickable {
            anchors.fill: parent
            anchors.margins: card.pad
            contentHeight: content.implicitHeight
            fadeColor: "transparent"

        // Two columns side by side; on Tall, one under the other.
        GridLayout {
            id: content
            width: parent.width
            columns: Theme.tall ? 1 : 2
            columnSpacing: Theme.mini ? 20 : Theme.compact ? 32 : 48
            rowSpacing: 24

            // Left: the mark and the steps.
            ColumnLayout {
                Layout.preferredWidth: 4
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Theme.mini ? 12 : 18
                RowLayout {
                    spacing: 14
                    Rectangle {
                        width: Theme.mini ? 44 : 56; height: width; radius: width / 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.glowBlue }
                            GradientStop { position: 1; color: Theme.glowCoral }
                        }
                        Icon { anchors.centerIn: parent; name: "bolt"; size: parent.width * 0.54; color: "white"; strokeWidth: 2.2 }
                    }
                    Label { text: "McFly"; color: field.ink; font.pixelSize: Theme.fontLg; font.weight: Font.Bold }
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Let's get this screen set up")
                    color: field.ink
                    font.pixelSize: Theme.mini ? 28 : Theme.compact ? 38 : 46
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    lineHeight: 1.0
                }
                Label {
                    Layout.fillWidth: true
                    visible: !Theme.mini
                    text: qsTr("Two steps: join your Wi-Fi, then connect the screen to your account. Your agents' briefs, markets and news show up right after.")
                    color: field.inkMuted
                    font.pixelSize: Theme.fontSm
                    wrapMode: Text.WordWrap
                }

                // Step 1: Wi-Fi.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    Layout.preferredHeight: wifiRow.implicitHeight + 32
                    radius: 24
                    color: Qt.rgba(1, 1, 1, Theme.dark ? 0.08 : 0.5)
                    RowLayout {
                        id: wifiRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 16
                        spacing: 14
                        Rectangle {
                            width: 44; height: 44; radius: 22
                            color: setup.online ? Theme.success : field.strong
                            Icon { anchors.centerIn: parent; name: setup.online ? "check" : "wifi"; size: 22; color: "white" }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { text: qsTr("1. Wi-Fi"); color: field.ink; font.pixelSize: Theme.fontSm + 1; font.weight: Font.DemiBold }
                            Label {
                                Layout.fillWidth: true
                                text: !System.wifiAvailable ? (setup.online ? qsTr("Connected") : qsTr("This computer has no Wi-Fi controls"))
                                    : System.wifiSsid ? qsTr("Joined %1").arg(System.wifiSsid)
                                    : System.wifiEnabled ? qsTr("Pick a network on the right") : qsTr("Wi-Fi is off")
                                color: field.inkMuted
                                font.pixelSize: Theme.fontXs + 1
                                elide: Text.ElideRight
                            }
                        }
                        PillButton {
                            visible: System.wifiAvailable && setup.step !== 1
                            text: qsTr("Change")
                            fill: Qt.rgba(1, 1, 1, Theme.dark ? 0.12 : 0.7)
                            ink: field.ink
                            onClicked: setup.wifiRequested()
                        }
                    }
                }

                // Step 2: the account.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: accountRow.implicitHeight + 32
                    radius: 24
                    color: Qt.rgba(1, 1, 1, Theme.dark ? 0.08 : 0.5)
                    opacity: setup.step === 2 ? 1 : 0.6
                    RowLayout {
                        id: accountRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 16
                        spacing: 14
                        Rectangle {
                            width: 44; height: 44; radius: 22
                            color: field.strong
                            Icon { anchors.centerIn: parent; name: "qr"; size: 22; color: "white" }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { text: qsTr("2. Connect to your account"); color: field.ink; font.pixelSize: Theme.fontSm + 1; font.weight: Font.DemiBold }
                            Label {
                                Layout.fillWidth: true
                                text: setup.haveCode ? qsTr("Open McFly on your phone, or mcfly.bot/pair, and enter the code. Or scan it.")
                                    : Store.lastError ? qsTr("Can't reach McFly cloud yet. Retrying…")
                                    : qsTr("Getting a code…")
                                color: field.inkMuted
                                font.pixelSize: Theme.fontXs + 1
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
                Label {
                    visible: Store.mode === "demo" && !setup.sample
                    text: qsTr("Demo mode: no backend is configured (display.env).")
                    color: field.inkMuted
                    font.pixelSize: Theme.fontXs
                }
            }

            // Right: the networks, or the code.
            Item {
                Layout.preferredWidth: 5
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                implicitHeight: setup.step === 1 ? networks.implicitHeight : codeCol.implicitHeight

                // Networks.
                ColumnLayout {
                    id: networks
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: setup.step === 1
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Networks"); color: field.ink; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        IconButton { icon: "refresh"; fill: Qt.rgba(1, 1, 1, 0.5); ink: field.ink; enabled: !System.busy; onClicked: System.scanWifi() }
                    }
                    Rectangle {
                        visible: setup.joinSsid.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: joinBox.implicitHeight + 28
                        radius: 24
                        color: Qt.rgba(1, 1, 1, Theme.dark ? 0.1 : 0.6)
                        ColumnLayout {
                            id: joinBox
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10
                            Label { text: qsTr("Join %1").arg(setup.joinSsid); color: field.ink; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                            FormField {
                                id: wifiPassword
                                placeholderText: qsTr("Password")
                                echoMode: TextInput.Password
                                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                                onAccepted: System.connectWifi(setup.joinSsid, text, false)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                PillButton { Layout.fillWidth: true; text: qsTr("Cancel"); fill: Qt.rgba(1, 1, 1, 0.5); ink: field.ink; onClicked: setup.joinSsid = "" }
                                PillButton {
                                    Layout.fillWidth: true
                                    text: System.busy ? qsTr("Joining…") : qsTr("Join")
                                    enabled: !System.busy && wifiPassword.text.length > 0
                                    onClicked: System.connectWifi(setup.joinSsid, wifiPassword.text, false)
                                }
                            }
                        }
                    }
                    Label {
                        visible: System.message.length > 0
                        Layout.fillWidth: true
                        text: System.message
                        color: field.ink
                        font.pixelSize: Theme.fontXs + 1
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: System.networks.slice(0, 6)
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 66
                            radius: 18
                            color: Qt.rgba(1, 1, 1, Theme.dark ? 0.08 : 0.5)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12
                                Icon { name: "wifi"; size: 22; color: field.ink }
                                Label { Layout.fillWidth: true; text: modelData.ssid; color: field.ink; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Label {
                                    text: modelData.signal + "%" + (modelData.secure ? (modelData.saved ? qsTr(" · Saved") : qsTr(" · Password")) : qsTr(" · Open"))
                                    color: field.inkMuted
                                    font.pixelSize: Theme.fontXs
                                }
                            }
                            TapHandler {
                                enabled: !System.busy
                                onTapped: {
                                    if (modelData.secure && !modelData.saved) {
                                        setup.joinSsid = modelData.ssid
                                        wifiPassword.text = ""
                                        wifiPassword.forceActiveFocus()
                                    } else {
                                        setup.joinSsid = ""
                                        System.connectWifi(modelData.ssid, "", modelData.saved)
                                    }
                                }
                            }
                        }
                    }
                    Label {
                        visible: System.networks.length === 0
                        Layout.fillWidth: true
                        text: System.busy ? qsTr("Looking for networks…") : System.wifiEnabled ? qsTr("No networks found. Try refresh.") : qsTr("Turn Wi-Fi on in Settings to look for networks.")
                        color: field.inkMuted
                        font.pixelSize: Theme.fontSm
                        wrapMode: Text.WordWrap
                    }
                }

                // The code.
                ColumnLayout {
                    id: codeCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: setup.step === 2
                    spacing: 18
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.mini ? 8 : Theme.compact ? 10 : 14
                        Repeater {
                            model: setup.haveCode ? setup.code.split("") : ["", "", "", "", "", ""]
                            delegate: Rectangle {
                                objectName: "digit"
                                required property string modelData
                                required property int index
                                // Six digits always fit the column, whatever its width.
                                implicitWidth: Math.max(32, Math.min(Theme.mini ? 56 : Theme.compact ? 76 : 92, Math.floor((codeCol.width - 5 * (Theme.mini ? 8 : Theme.compact ? 10 : 14)) / 6)))
                                implicitHeight: Math.round(implicitWidth * 1.36)
                                Layout.preferredWidth: implicitWidth
                                Layout.preferredHeight: implicitHeight
                                radius: Math.round(implicitWidth * 0.28)
                                color: Qt.rgba(1, 1, 1, Theme.dark ? 0.1 : 0.72)
                                border.color: Qt.rgba(1, 1, 1, 0.8)
                                Label {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: field.ink
                                    font.pixelSize: Math.round(parent.width * 0.82)
                                    font.weight: Font.DemiBold
                                }
                                // Each digit lights up in turn while the code is fresh:
                                // to 1.06 and back, 420 ms each way, eased in and out,
                                // 220 ms after the one before, every 4.24 s, from the
                                // first digit each time it starts and for each new code.
                                readonly property bool waves: setup.waving
                                property real waveFrom: 0
                                onWavesChanged: if (waves) waveFrom = waveClock.time
                                Component.onCompleted: waveFrom = waveClock.time
                                readonly property real wavePhase: (waveClock.time - waveFrom) % 4.24 - index * 0.22
                                scale: wavePhase > 0 && wavePhase < 0.84 ? 1.03 - 0.03 * Math.cos(Math.PI * wavePhase / 0.42) : 1
                            }
                        }
                    }
                    BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: !setup.haveCode
                        visible: running
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        visible: setup.haveCode
                        spacing: 20
                        Rectangle {
                            Layout.preferredWidth: Theme.mini ? 120 : Theme.compact ? 148 : 168
                            Layout.preferredHeight: Layout.preferredWidth
                            radius: 18
                            color: "white"
                            Image {
                                anchors.centerIn: parent
                                width: parent.width - 16; height: width
                                source: setup.haveCode ? "image://qr/" + encodeURIComponent(setup.pairUrl) : ""
                                sourceSize: Qt.size(width, width)
                                smooth: false
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Label { text: qsTr("Scan with your phone"); color: field.ink; font.pixelSize: Theme.fontSm + 1; font.weight: Font.DemiBold }
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("It opens mcfly.bot/pair with the code filled in. Sign in with your account and the screen connects by itself.")
                                color: field.inkMuted
                                font.pixelSize: Theme.fontXs + 1
                                wrapMode: Text.WordWrap
                            }
                            Label { text: qsTr("The code changes every 10 minutes."); color: field.inkMuted; font.pixelSize: Theme.fontXs }
                        }
                    }
                }
            }
        }
        }
    }
}
