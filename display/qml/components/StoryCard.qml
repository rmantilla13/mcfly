import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly

// One Daily Pulse story: its picture (or a tinted tile with the section's
// initial when there is none), the headline and the takeaway. Tap to open.
Rectangle {
    id: card
    property var story: ({})
    property bool large: false
    // How much of the card the picture takes.
    property real imageShare: large ? 0.5 : 0.52
    // Short hosts (Home's column) drop the takeaway so the source never overlaps it.
    property bool showTakeaway: true
    // The picture drifts in and out, very slowly (News' hero, while it's on
    // screen and Settings → Animated tiles is on).
    property bool kenBurns: false
    signal opened(var story)

    readonly property string tint: story.sectionColor || Theme.accent
    readonly property bool hasImage: (story.imageUrl || "").length > 0
    // The picture never pushes the words out, however wide the card is.
    readonly property int wordsMargin: large ? 22 : 16
    readonly property int pictureHeight: large ? Math.round(height * imageShare)
                                               : Math.min(Math.round(width * imageShare), Math.round(height * 0.6))
    // The room left for the takeaway: it goes when a line of it would not fit.
    readonly property int takeawayRoom: height - pictureHeight - 2 * wordsMargin - 12
                                        - headline.implicitHeight - (domain.visible ? domain.implicitHeight : 0)

    radius: Theme.radiusSm
    color: Theme.surface
    clip: true
    scale: tap.pressed ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: Theme.quick } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Picture.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: card.pictureHeight
            // A zooming picture stays in its frame, also where it stopped.
            clip: card.large
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.lighter(card.tint, Theme.dark ? 0.7 : 1.25) }
                    GradientStop { position: 1; color: Qt.darker(card.tint, Theme.dark ? 1.6 : 1.1) }
                }
                Label {
                    anchors.centerIn: parent
                    visible: !picture.visible
                    text: (card.story.sectionName || "").slice(0, 1).toUpperCase()
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: card.large ? 120 : 64
                    font.weight: Font.Bold
                }
            }
            Image {
                id: picture
                anchors.fill: parent
                source: card.story.imageUrl || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                // Decoded at the tile's size, not the source's.
                sourceSize.width: Math.max(1, Math.round(width * 1.2))
                visible: status === Image.Ready
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
                // In and out over most of a minute (to 1.08 and back, 26 s
                // each way, eased in and out), on the ambient clock: 30
                // updates a second for a drift of under a pixel a second.
                // From wherever it is, so stopping and starting again never jumps.
                scale: 1.04 - 0.04 * Math.cos(Math.PI * drift.time / 26)
                MotionClock { id: drift; playing: card.kenBurns && picture.visible }
            }
            // Section tag over the picture.
            Rectangle {
                x: 14; y: 14
                radius: 12
                height: 28
                width: tagLabel.implicitWidth + 20
                color: Qt.rgba(0, 0, 0, 0.42)
                Label {
                    id: tagLabel
                    anchors.centerIn: parent
                    text: (card.story.sectionName || "").toUpperCase()
                    color: "white"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
            }
        }

        // Words.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: card.wordsMargin
            spacing: 6
            Label {
                id: headline
                Layout.fillWidth: true
                text: card.story.headline || ""
                color: Theme.text
                font.pixelSize: card.large ? (card.height > 320 ? Theme.fontLg : Theme.fontMd) : Theme.fontSm + 1
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: card.large ? 3 : 2
                elide: Text.ElideRight
                lineHeight: 1.08
            }
            Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: card.showTakeaway && text.length > 0 && card.takeawayRoom >= font.pixelSize * 1.3
                clip: true
                text: card.story.takeaway || ""
                color: Theme.textMuted
                font.pixelSize: card.large ? Theme.fontSm : Theme.fontXs
                wrapMode: Text.WordWrap
                maximumLineCount: card.large ? 3 : 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
            }
            Label {
                id: domain
                Layout.fillWidth: true
                visible: text.length > 0
                text: card.story.sourceDomain || ""
                color: card.tint
                font.pixelSize: Theme.fontXs - 1
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }
    }
    TapHandler { id: tap; onTapped: card.opened(card.story) }
}
