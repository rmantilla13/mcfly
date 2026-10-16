import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Today's stories, one at a time: the picture slowly zooms (or a tinted
// colour field stands in), with the section, the headline, the takeaway and
// the source, and the clock in the corner. Every 12 seconds the next one
// cross-fades in.
Item {
    id: headlines
    property int index: 0
    property date now: new Date()
    readonly property var stories: Store.stories
    readonly property var story: stories[index % Math.max(1, stories.length)] || ({})
    // The words' inset from the edges.
    readonly property int edge: Theme.mini ? 32 : Theme.tall ? 40 : 72

    Timer { interval: 1000; running: true; repeat: true; onTriggered: headlines.now = new Date() }
    Timer {
        interval: 12000
        running: headlines.stories.length > 1
        repeat: true
        onTriggered: headlines.index = (headlines.index + 1) % headlines.stories.length
    }

    Rectangle { anchors.fill: parent; color: "black" }

    // Two slots cross-fade: the one showing and the one coming.
    Repeater {
        model: 2
        delegate: Item {
            id: slot
            required property int modelData
            readonly property bool current: headlines.index % 2 === modelData
            // Each slot shows the story it was given when it became current.
            property var shown: ({})
            onCurrentChanged: if (current) shown = headlines.story
            Component.onCompleted: if (current) shown = headlines.story
            anchors.fill: parent
            opacity: current ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 1400; easing.type: Easing.InOutQuad } }
            visible: opacity > 0

            // The colour field behind a story without a picture; a picture
            // covers it, so then it isn't drawn at all.
            GradientTile {
                anchors.fill: parent
                visible: picture.status !== Image.Ready
                radius: 0
                baseColor: shown.sectionColor || Theme.accent
                active: slot.opacity > 0
                dark: true
                seed: modelData * 1.9
                whileIdle: true
                maxFps: Theme.saverFps
                period: Theme.saverDrift
            }
            Image {
                id: picture
                anchors.fill: parent
                source: shown.imageUrl || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1920
                visible: status === Image.Ready
                transformOrigin: Item.Center
                scale: 1
                // Ken Burns: a slow push in while this story is up, and on
                // through its fade out (12 s up + 1.4 s out), so it never
                // stops mid-move.
                SequentialAnimation on scale {
                    running: (current || slot.opacity > 0) && picture.visible && Device.animatedTiles
                    NumberAnimation { from: 1.0; to: 1.08; duration: 14000; easing.type: Easing.InOutSine }
                }
            }
            // Shade for the words.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.1) }
                    GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.2) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.82) }
                }
            }
            ColumnLayout {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: headlines.edge }
                spacing: 12
                RowLayout {
                    spacing: 10
                    Rectangle { width: 14; height: 14; radius: 7; color: shown.sectionColor || "white" }
                    Label { text: (shown.sectionName || "").toUpperCase(); color: "#DDFFFFFF"; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; font.letterSpacing: 1.4 }
                }
                Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: headlines.width * (Theme.mini ? 0.92 : 0.78)
                    text: shown.headline || ""
                    color: "white"
                    font.pixelSize: Theme.wide ? 64 : Theme.mini ? 36 : Theme.tall ? 44 : 54
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    lineHeight: 1.0
                }
                Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: headlines.width * 0.7
                    visible: text.length > 0 && !Theme.mini
                    text: shown.takeaway || ""
                    color: "#E6FFFFFF"
                    font.pixelSize: Theme.fontMd
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Label { text: shown.sourceDomain || ""; color: "#B3FFFFFF"; font.pixelSize: Theme.fontSm }
            }
        }
    }

    // Clock, top right.
    Column {
        anchors { top: parent.top; right: parent.right; margins: Theme.mini ? 24 : Theme.tall ? 32 : 64 }
        spacing: 2
        Label {
            anchors.right: parent.right
            text: Qt.formatTime(headlines.now, "h:mm AP").split(" ")[0]
            color: "white"
            font.pixelSize: Theme.mini ? 56 : Theme.tall ? 72 : 96
            font.weight: Font.Light
        }
        Label {
            anchors.right: parent.right
            text: Qt.formatDate(headlines.now, "dddd, MMMM d")
            color: "#DDFFFFFF"
            font.pixelSize: Theme.fontMd
        }
    }
    // Progress dots.
    Row {
        visible: !Theme.mini
        anchors { right: parent.right; bottom: parent.bottom; margins: headlines.edge }
        spacing: 8
        Repeater {
            model: Math.min(headlines.stories.length, 12)
            delegate: Rectangle {
                required property int index
                width: 10; height: 10; radius: 5
                color: index === headlines.index % 12 ? "white" : "#55FFFFFF"
            }
        }
    }
}
