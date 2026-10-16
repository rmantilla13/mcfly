import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Home with the assistant first (Settings → Home → Assistant): McFly speaks
// before you ask. A dark card on the voice glow says what matters now
// (Glance.summary, put together from the feed in HomeGlance.cpp), offers the
// follow-ups to tap, and has the one big button to talk. Beside it, the
// cards the summary came from: what's next, the markets, what's blocked, the
// lead story (or the latest brief). A card with nothing to show steps aside.
//
// Wide and Compact: the card | the evidence column. Mini: the card alone.
// Tall: the card on top, the evidence two by two under it.
Item {
    id: home

    // On screen and not covered (Main.qml via HomeLayouts): the glow only
    // moves while it is.
    property bool shown: true
    // Picked (Main.qml, as every screen gets it); this layout doesn't animate in yet.
    property bool isCurrent: true
    signal openScreen(int index)
    signal openAssistant(string question)
    signal pushToTalk()

    property date now: new Date()
    Timer { interval: 1000; running: home.visible; repeat: true; triggeredOnStart: true; onTriggered: home.now = new Date() }

    // Glance.summary (tests give their own).
    property var summary: Glance.summary
    readonly property var nextEvent: summary.next && summary.next.title ? summary.next : null
    readonly property var blockedProject: summary.blocked && summary.blocked.length > 0 ? summary.blocked[0] : null
    readonly property var marketRows: summary.movers && summary.movers.length > 0 ? summary.movers : Store.quotes.slice(0, 3)
    readonly property var story: Store.news && Store.news.hero && Store.news.hero.headline ? Store.news.hero : null
    readonly property var brief: Store.latestBrief && Store.latestBrief.title ? Store.latestBrief : null
    readonly property bool hasEvidence: !!nextEvent || marketRows.length > 0 || !!blockedProject || !!story || !!brief
    readonly property string provider: AI.effectiveProvider || "claude"

    component Caps: Label {
        font.pixelSize: Theme.fontXs - 1
        font.weight: Font.Bold
        font.letterSpacing: 1.3
        elide: Text.ElideRight
    }

    // A card in the evidence column: a door into `target`'s screen.
    component Evidence: Rectangle {
        property int target: -1
        radius: Theme.radius - 2
        color: Theme.surface
        clip: true
        TapHandler { onTapped: home.openScreen(parent.target) }
    }

    // ---- The card where McFly speaks.
    component SpeakingCard: Rectangle {
        id: card
        objectName: "speakingCard"
        readonly property bool roomy: !Theme.mini && height > 520
        readonly property int headlineSize: Theme.mini ? Theme.fontLg : roomy ? (Theme.wide ? 48 : 40) : 32
        radius: Theme.mini ? Theme.radius : 36
        color: "#1B1A1F"
        clip: true

        // The room the summary and the detail share: the column less what has
        // a size of its own in it (the time, the follow-ups, the talk button)
        // and the gaps. The summary comes first: at its full size where both
        // fit, else set smaller (Text.Fit) in what the detail leaves it, but
        // never so small it would stop at "…" while the detail has lines to
        // give: then the detail gives them up, a line at a time. So a long
        // morning never pushes the talk button out of the card.
        readonly property real _gaps: column.spacing * (detail.visible ? 5 : 4)
        readonly property real _chipsHeight: Math.max(0, chips.implicitHeight + chips.Layout.topMargin + chips.Layout.bottomMargin)
        readonly property real _room: column.height - topRow.implicitHeight - _chipsHeight - talkRow.implicitHeight - _gaps
        // Whole at its smallest size, and as it would like to be (its full
        // size, its usual lines; taller only when that couldn't hold it whole).
        readonly property real _headlineNeed: Math.min(smallHeadline.implicitHeight, _room)
        readonly property real _headlineIdeal: Math.max(fullHeadline.implicitHeight, smallHeadline.implicitHeight)
        readonly property real _headlineHeight: Math.max(_headlineNeed, Math.min(_headlineIdeal,
                                                         _room - (detail.visible ? fullDetail.implicitHeight : 0)))
        readonly property real _detailHeight: Math.max(0, Math.min(fullDetail.implicitHeight, _room - _headlineHeight))

        SpectrumGlow {
            anchors.fill: parent
            kind: "screen"
            cornerRadius: card.radius
            ambient: true
            intensity: 0.7
            active: home.shown
            processing: AI.busy
            level: Voice.level
            speaking: Voice.state === "speaking"
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.leftMargin: Theme.mini ? 22 : 40
            anchors.rightMargin: Theme.mini ? 22 : 40
            anchors.topMargin: Theme.mini ? 18 : 34
            anchors.bottomMargin: Theme.mini ? 18 : 32
            spacing: Theme.mini ? 10 : 20

            // The time, and who answers.
            RowLayout {
                id: topRow
                Layout.fillWidth: true
                spacing: 12
                Label {
                    Layout.fillWidth: true
                    text: Qt.formatTime(home.now, "h:mm AP") + " · " + Qt.formatDate(home.now, "dddd")
                    color: "#B8B5BF"
                    font.pixelSize: Theme.fontSm
                    elide: Text.ElideRight
                }
                Rectangle {
                    implicitWidth: whoRow.implicitWidth + 8
                    implicitHeight: (Theme.mini ? 40 : 48)
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.1)
                    Row {
                        id: whoRow
                        anchors.centerIn: parent
                        spacing: 0
                        Repeater {
                            model: [{ id: "claude", label: qsTr("Claude") }, { id: "grok", label: qsTr("Grok") }]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool chosen: home.provider === modelData.id
                                width: whoLabel.implicitWidth + (Theme.mini ? 28 : 36)
                                height: (Theme.mini ? 32 : 40)
                                radius: height / 2
                                color: chosen ? "white" : "transparent"
                                Label {
                                    id: whoLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: chosen ? "#1B1A1F" : "white"
                                    font.pixelSize: Theme.fontXs + 1
                                    font.weight: Font.DemiBold
                                }
                                // 64 px tall to the finger (the pill is drawn smaller), no wider:
                                // the two halves don't take each other's taps.
                                Item {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: Math.max(parent.height, Theme.touchTarget)
                                    TapHandler { onTapped: AI.provider = modelData.id }
                                }
                            }
                        }
                    }
                }
            }

            // What matters now: at its size where it fits in its lines, else
            // smaller (Text.Fit) in the room the card has for it (_room).
            Label {
                id: headline
                objectName: "headline"
                Layout.fillWidth: true
                Layout.preferredHeight: card._headlineHeight
                Layout.minimumHeight: card._headlineHeight
                Layout.maximumHeight: card._headlineHeight
                text: home.summary.headline || ""
                color: "white"
                font.pixelSize: card.headlineSize
                font.weight: Font.Medium
                font.letterSpacing: -0.5
                fontSizeMode: Text.Fit
                minimumPixelSize: Theme.mini ? 18 : 24
                lineHeight: 1.16
                wrapMode: Text.WordWrap
                maximumLineCount: 8
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
            }
            // The summary at its full size in its usual lines, and whole at
            // its smallest: how tall it would like to be, and must be. Never
            // shown, so the layout leaves them out.
            Label {
                id: fullHeadline
                visible: false
                width: headline.width
                text: headline.text
                font.pixelSize: card.headlineSize
                font.weight: Font.Medium
                font.letterSpacing: -0.5
                lineHeight: 1.16
                wrapMode: Text.WordWrap
                maximumLineCount: Theme.mini ? 3 : 4
            }
            Label {
                id: smallHeadline
                visible: false
                width: headline.width
                text: headline.text
                font.pixelSize: headline.minimumPixelSize
                font.weight: Font.Medium
                font.letterSpacing: -0.5
                lineHeight: 1.16
                wrapMode: Text.WordWrap
                maximumLineCount: headline.maximumLineCount
            }
            // Where it came from: the lines there is room for, and none at all
            // (it fades out) rather than half of one.
            Label {
                id: detail
                Layout.fillWidth: true
                Layout.preferredHeight: card._detailHeight
                Layout.minimumHeight: card._detailHeight
                Layout.maximumHeight: card._detailHeight
                visible: text.length > 0
                opacity: card._detailHeight >= detailMetrics.height * lineHeight - 1 ? 1 : 0
                text: home.summary.detail || ""
                color: "#D4D1DB"
                font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd - 4
                lineHeight: 1.4
                wrapMode: Text.WordWrap
                maximumLineCount: Theme.mini ? 2 : 3
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
                FontMetrics { id: detailMetrics; font: detail.font }
            }
            Label {
                id: fullDetail
                visible: false
                width: detail.width
                text: detail.text
                font: detail.font
                lineHeight: 1.4
                wrapMode: Text.WordWrap
                maximumLineCount: Theme.mini ? 2 : 3
            }
            // The follow-ups. Each is a touch target's height (the pill is drawn
            // smaller, centred), so rows never share a finger's width of space.
            Flow {
                id: chips
                Layout.fillWidth: true
                Layout.topMargin: -(Theme.touchTarget - chipHeight) / 2
                Layout.bottomMargin: -(Theme.touchTarget - chipHeight) / 2
                readonly property int chipHeight: Theme.mini ? 44 : 52
                spacing: 10
                Repeater {
                    model: (home.summary.chips || []).slice(0, Theme.mini ? 2 : 3)
                    delegate: Item {
                        id: chip
                        required property string modelData
                        width: Math.min(chipLabel.implicitWidth + 44, card.width - 80)
                        height: Theme.touchTarget
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: Theme.mini ? 44 : 52
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.22)
                        }
                        Label {
                            id: chipLabel
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - 44)
                            text: chip.modelData
                            color: "white"
                            font.pixelSize: Theme.mini ? Theme.fontXs + 1 : Theme.fontSm
                            elide: Text.ElideRight
                        }
                        TapHandler { onTapped: home.openAssistant(chip.modelData) }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // The one button: talk (or type, without the voice service).
            RowLayout {
                id: talkRow
                Layout.fillWidth: true
                spacing: 16
                Rectangle {
                    objectName: "talkButton"
                    width: Theme.mini ? 64 : 84
                    height: width
                    radius: width / 2
                    color: "white"
                    Icon { anchors.centerIn: parent; name: Voice.available ? "mic" : "chat"; size: Theme.mini ? 24 : 30; color: "#1B1A1F" }
                    TapHandler { onTapped: Voice.available ? home.pushToTalk() : home.openAssistant("") }
                }
                Label {
                    Layout.fillWidth: true
                    text: !Voice.available ? qsTr("Tap to ask McFly")
                          : Voice.wakewordEnabled && Voice.wakewordLabel ? qsTr("Tap to talk, or say “%1”").arg(Voice.wakewordLabel)
                          : qsTr("Tap to talk")
                    color: "#E4E1EA"
                    font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd - 4
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- The evidence: where each part of the summary came from.

    component NextCard: Evidence {
        target: 6
        visible: !!home.nextEvent
        color: home.nextEvent && home.nextEvent.color ? home.nextEvent.color : Theme.accent
        implicitHeight: nextCol.implicitHeight + 36
        ColumnLayout {
            id: nextCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 20
            spacing: 4
            Caps {
                Layout.fillWidth: true
                color: Qt.rgba(1, 1, 1, 0.88)
                text: home.nextEvent ? (home.nextEvent.day === Store.today ? qsTr("NEXT · %1").arg((home.nextEvent.startLabel || "").toUpperCase())
                                                                           : qsTr("NEXT · %1").arg((home.nextEvent.dayLabel || "").toUpperCase())) : ""
            }
            Label {
                Layout.fillWidth: true
                text: home.nextEvent ? home.nextEvent.title : ""
                color: "white"
                font.pixelSize: Theme.fontMd - 1
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
    }

    component MarketsCard: Evidence {
        target: 2
        visible: home.marketRows.length > 0
        implicitHeight: marketsCol.implicitHeight + 34
        ColumnLayout {
            id: marketsCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 20
            spacing: 8
            Caps { Layout.fillWidth: true; color: Theme.textMuted; text: qsTr("MARKETS") }
            Repeater {
                model: home.marketRows
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Label { Layout.preferredWidth: 64; text: modelData.symbol; color: Theme.text; font.pixelSize: Theme.fontSm + 1; font.weight: Font.Bold; elide: Text.ElideRight }
                    Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: modelData.priceLabel || ""; color: Theme.text; font.pixelSize: Theme.fontSm + 1 }
                    Label {
                        Layout.preferredWidth: 72
                        horizontalAlignment: Text.AlignRight
                        text: modelData.pctLabel || ""
                        color: modelData.flat ? Theme.textMuted : modelData.up ? Theme.gain : Theme.loss
                        font.pixelSize: Theme.fontSm + 1
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    component BlockedCard: Evidence {
        target: 4
        visible: !!home.blockedProject
        color: Qt.tint(Theme.surface, Qt.rgba(0.94, 0.42, 0.33, Theme.dark ? 0.22 : 0.16))
        implicitHeight: blockedCol.implicitHeight + 34
        ColumnLayout {
            id: blockedCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 20
            spacing: 4
            Caps { Layout.fillWidth: true; color: Theme.danger; text: qsTr("BLOCKED") }
            Label {
                Layout.fillWidth: true
                text: {
                    const p = home.blockedProject
                    if (!p) return ""
                    return p.hasProgress ? qsTr("%1 · %2%").arg(p.name).arg(Math.round(p.progress || 0)) : p.name
                }
                color: Theme.text
                font.pixelSize: Theme.fontMd - 3
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: home.blockedProject ? (home.blockedProject.next_step || home.blockedProject.summary || "") : ""
                color: Theme.text
                opacity: 0.8
                font.pixelSize: Theme.fontXs + 1
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    // The lead story with its picture; without news, the latest brief.
    component StoryCard: Evidence {
        id: storyCard
        target: home.story ? 3 : 1
        visible: !!home.story || !!home.brief
        readonly property color section: home.story && home.story.sectionColor ? home.story.sectionColor
                                       : home.brief && home.brief.agentColor ? home.brief.agentColor : Theme.glowBlue
        implicitHeight: 200
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 56
                clip: true
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.lighter(storyCard.section, 1.35) }
                        GradientStop { position: 1; color: storyCard.section }
                    }
                }
                Image {
                    anchors.fill: parent
                    visible: Theme.pictures && status === Image.Ready
                    source: Theme.pictures && home.story && home.story.imageUrl ? home.story.imageUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // Decoded to cover the tile, not at the source's size: with
                    // a crop fill, Qt sizes the decode to cover both sides.
                    sourceSize: Qt.size(Math.max(1, Math.round(width * 1.2)), Math.max(1, Math.round(height * 1.2)))
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                spacing: 2
                Caps {
                    Layout.fillWidth: true
                    color: storyCard.section
                    text: home.story ? (Store.news.agentName || home.story.sectionName || qsTr("NEWS")).toUpperCase()
                                     : home.brief ? [home.brief.agentName, home.brief.whenLabel].filter(s => !!s).join(" · ").toUpperCase() : ""
                }
                Label {
                    Layout.fillWidth: true
                    text: home.story ? home.story.headline : home.brief ? home.brief.title : ""
                    color: Theme.text
                    font.pixelSize: Theme.fontMd - 4
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- Wide, Compact, Mini: the card | the evidence (none on Mini).
    RowLayout {
        visible: !Theme.tall
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.spacing + 6

        SpeakingCard { Layout.fillWidth: true; Layout.fillHeight: true }

        ColumnLayout {
            visible: !Theme.mini && home.hasEvidence
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.wide ? 400 : 340
            Layout.maximumWidth: Theme.wide ? 400 : 340
            spacing: 14
            NextCard { Layout.fillWidth: true }
            MarketsCard { Layout.fillWidth: true }
            BlockedCard { Layout.fillWidth: true }
            StoryCard { Layout.fillWidth: true; Layout.fillHeight: true }
            Item { visible: !home.story && !home.brief; Layout.fillHeight: true }
        }
    }

    // ---- Tall: the card on top, the evidence under it, two by two.
    ColumnLayout {
        visible: Theme.tall
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.spacing

        SpeakingCard { Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 3 }

        GridLayout {
            visible: home.hasEvidence
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 2
            columns: 2
            columnSpacing: Theme.spacing
            rowSpacing: Theme.spacing
            NextCard { Layout.fillWidth: true; Layout.fillHeight: true }
            MarketsCard { Layout.fillWidth: true; Layout.fillHeight: true }
            BlockedCard { Layout.fillWidth: true; Layout.fillHeight: true }
            StoryCard { Layout.fillWidth: true; Layout.fillHeight: true }
        }
    }
}
