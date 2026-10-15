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

    // The colour field.
    GradientTile {
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
    // Floating light: slow, soft discs drifting up.
    Repeater {
        model: 6
        delegate: Rectangle {
            required property int index
            readonly property real size: 120 + index * 46
            width: size; height: size; radius: size / 2
            color: index % 2 === 0 ? Theme.glowCream : Theme.glowAmber
            opacity: 0
            x: setup.width * (0.08 + 0.15 * index)
            SequentialAnimation on y {
                running: setup.visible
                loops: Animation.Infinite
                NumberAnimation { from: setup.height + 100; to: -200; duration: 26000 + index * 5000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on opacity {
                running: setup.visible
                loops: Animation.Infinite
                PauseAnimation { duration: index * 1800 }
                NumberAnimation { to: 0.22; duration: 4000 }
                NumberAnimation { to: 0.06; duration: 6000 }
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
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -setup.keyboardHeight / 2 - 10
        width: Math.min(parent.width - 2 * Theme.pageMargin, Theme.compact ? 1120 : 1240)
        height: Math.min(parent.height - 2 * Theme.pageMargin - setup.keyboardHeight, content.implicitHeight + 2 * pad)
        readonly property int pad: Theme.mini ? 20 : Theme.compact ? 32 : 44
        radius: 40
        color: Qt.rgba(1, 1, 1, Theme.dark ? 0.08 : 0.55)
        border.color: Qt.rgba(1, 1, 1, Theme.dark ? 0.16 : 0.75)
        border.width: 1
        Behavior on height { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
        // A gentle float.
        SequentialAnimation on anchors.verticalCenterOffset {
            running: setup.visible && Device.animatedTiles && setup.keyboardHeight === 0
            loops: Animation.Infinite
            NumberAnimation { to: -16; duration: 5000; easing.type: Easing.InOutSine }
            NumberAnimation { to: -4; duration: 5000; easing.type: Easing.InOutSine }
        }

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
                                // Each digit lights up in turn while the code is fresh.
                                SequentialAnimation on scale {
                                    running: setup.visible && setup.haveCode && Device.animatedTiles
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 220 }
                                    NumberAnimation { to: 1.06; duration: 420; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
                                    PauseAnimation { duration: 3400 - index * 220 }
                                }
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
