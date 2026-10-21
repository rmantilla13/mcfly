import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// News: the day's Daily Pulse report, section by section. A tapped story
// opens large: its summary and key points, or the full article, with the
// page's pictures and videos (Reader), and a QR code so the article can be
// read on a phone. On the 7" panel the page carries no pictures: the
// hero is a lead row and the stories are rows with the section's initial.
// The hero's picture drifts slowly closer and back (Ken Burns); the sections
// settle in one after another as the page shows.
Item {
    id: news
    property bool shown: true
    // The page picked, under the assistant panel too: it settles in as
    // this turns true, not again when the panel goes.
    property bool isCurrent: true
    property var story: ({})
    // Loops run only while someone can see them.
    readonly property bool moving: shown && !Device.idle && Device.animatedTiles
    Reveal { id: rv; shown: news.isCurrent }
    readonly property bool storyOpen: !!story.headline
    readonly property int reportIndex: Math.max(0, Store.newsReports.findIndex(r => r.id === Store.news.id))
    readonly property var hero: Store.news.hero || ({})
    // One column of a section grid, from the page's width (not the grid's own,
    // which would chase the cards it sizes).
    readonly property int storyCellWidth: Math.max(120, Math.floor((width - 2 * Theme.pageMargin - (Theme.storyColumns - 1) * Theme.spacing) / Theme.storyColumns))

    function closeStory() { story = ({}) }

    // --story: the lead story opens once the report is in, the first time.
    property bool leadPending: typeof startStory !== "undefined" && startStory === true
    function openLead() {
        if (leadPending && hero.headline) {
            leadPending = false
            story = hero
        }
    }
    onHeroChanged: openLead()
    Component.onCompleted: openLead()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: 14

        ScreenHeader {
            Layout.fillWidth: true
            title: Store.news.agentName && Store.newsSources.length > 1 ? Store.news.agentName : qsTr("Daily Pulse")
            subtitle: Store.news.displayDate ? Store.news.displayDate + " · " + qsTr("%1 stories").arg(Store.news.itemCount) : qsTr("No report yet")
            // One chip per source, when there is more than one.
            ChipRow {
                Layout.fillWidth: true
                visible: Store.newsSources.length > 1
                chipHeight: 40
                model: [{ id: "", label: qsTr("All") }].concat(Store.newsSources.map(s => ({ id: s.id, label: s.name, color: s.color })))
                current: Store.newsSource
                onPicked: id => Store.showSource(id)
            }
            Item { Layout.fillWidth: true }
            // Earlier and later reports.
            IconButton {
                icon: "left"
                fill: Theme.surface
                enabled: news.reportIndex < Store.newsReports.length - 1
                onClicked: Store.showReport(Store.newsReports[news.reportIndex + 1].id)
            }
            Label {
                text: Store.news.dayLabel || ""
                color: Theme.text
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: Theme.mini ? 96 : 120
            }
            IconButton {
                icon: "right"
                fill: Theme.surface
                enabled: news.reportIndex > 0
                onClicked: Store.showReport(news.reportIndex === 1 ? "" : Store.newsReports[news.reportIndex - 1].id)
            }
        }

        FocusFlickable {
            id: storiesView
            Layout.fillWidth: true
            Layout.fillHeight: true
            fadeColor: Theme.background
            contentHeight: body.implicitHeight
            clip: true
            ColumnLayout {
                id: body
                width: parent.width
                spacing: Theme.spacing

                // The hero, wide...
                StoryCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.heroHeight
                    visible: Theme.pictures && !!news.hero.headline
                    story: news.hero
                    large: true
                    // Only while it is on screen: scrolled away, it holds.
                    kenBurns: news.moving && !news.storyOpen && storiesView.contentY < y + height
                    opacity: rv.at(0)
                    transform: Translate { y: rv.rise(0) }
                    onOpened: s => news.story = s
                }
                // ...or, with no room for pictures, a lead row.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: leadCol.implicitHeight + 28
                    visible: !Theme.pictures && !!news.hero.headline
                    radius: Theme.radiusSm
                    color: Theme.surface
                    opacity: rv.at(0)
                    transform: Translate { y: rv.rise(0) }
                    Rectangle { width: 8; height: parent.height; radius: 4; color: news.hero.sectionColor || Theme.accent }
                    ColumnLayout {
                        id: leadCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 22
                        anchors.rightMargin: 16
                        spacing: 4
                        RowLayout {
                            spacing: 8
                            Label { text: (news.hero.sectionName || "").toUpperCase(); color: news.hero.sectionColor || Theme.textMuted; font.pixelSize: Theme.fontXs - 1; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                            Label { text: news.hero.sourceDomain || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs - 1; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: news.hero.headline || ""
                            color: Theme.text
                            font.pixelSize: Theme.fontMd
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            lineHeight: 1.05
                        }
                    }
                    TapHandler { onTapped: news.story = news.hero }
                }

                Repeater {
                    model: Store.news.sections || []
                    delegate: ColumnLayout {
                        id: section
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: Theme.mini ? 8 : 12
                        opacity: rv.at(index + 1)
                        transform: Translate { y: rv.rise(section.index + 1) }
                        RowLayout {
                            spacing: 10
                            Rectangle { width: 12; height: 12; radius: 6; color: modelData.color }
                            Label { text: modelData.name.toUpperCase(); color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        }
                        GridLayout {
                            id: sectionGrid
                            Layout.fillWidth: true
                            columns: Theme.storyColumns
                            columnSpacing: Theme.spacing
                            rowSpacing: Theme.spacing
                            Repeater {
                                model: modelData.items
                                // A card with its picture, or a row with the section's initial.
                                delegate: Theme.pictures ? storyCard : storyRow
                            }
                        }
                    }
                }

                // Centred in the room the stories would take.
                EmptyState {
                    visible: Store.stories.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(implicitHeight, storiesView.height - Theme.pageMargin)
                    icon: "news"
                    text: qsTr("Today's report hasn't arrived yet")
                    hint: qsTr("A Grok bot can write you a Daily Pulse report every morning.")
                    url: "https://mcfly.bot/bots"
                    action: qsTr("Make a Grok bot")
                    caption: qsTr("Scan to make one on your phone: what to ask Grok, and when.")
                }
                Item { height: Theme.pageMargin }
            }
        }
    }

    Component {
        id: storyCard
        StoryCard {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: news.storyCellWidth
            Layout.preferredHeight: Theme.storyCardHeight
            story: modelData
            onOpened: s => news.story = s
        }
    }
    Component {
        id: storyRow
        Rectangle {
            id: row
            required property var modelData
            readonly property color tint: modelData.sectionColor || Theme.accent
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: news.storyCellWidth
            Layout.preferredHeight: Theme.storyCardHeight
            radius: Theme.radiusSm
            color: Theme.surface
            scale: rowTap.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: Theme.quick } }
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 56; Layout.preferredHeight: 56
                    radius: 14
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(row.tint, Theme.dark ? 0.7 : 1.25) }
                        GradientStop { position: 1; color: Qt.darker(row.tint, Theme.dark ? 1.6 : 1.1) }
                    }
                    Label { anchors.centerIn: parent; text: (modelData.sectionName || "").slice(0, 1).toUpperCase(); color: Qt.rgba(1, 1, 1, 0.8); font.pixelSize: 26; font.weight: Font.Bold }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        Layout.fillWidth: true
                        text: modelData.headline || ""
                        color: Theme.text
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        lineHeight: 1.05
                    }
                    Label { Layout.fillWidth: true; text: modelData.sourceDomain || ""; color: row.tint; font.pixelSize: Theme.fontXs - 1; font.weight: Font.Medium; elide: Text.ElideRight }
                }
            }
            TapHandler { id: rowTap; onTapped: news.story = modelData }
        }
    }

    // ---- The story, large.

    // The open story's article, from Reader (C++): the assistant's summary
    // and key points with the page's pictures and videos, or the full story
    // with them in place. Summary or full story lasts the session. The QR
    // code opens the article on a phone, or a video once one is tapped.
    property string readMode: "summary"
    property string qrUrl: ""
    readonly property var article: Reader.article
    readonly property bool fullShown: readMode === "full" && !!article.hasFullStory
    onStoryChanged: {
        qrUrl = ""
        if (story.headline)
            Reader.open(story)
        else
            Reader.close()
    }

    // The picture, or a tinted field with the section's initial. With the
    // summary, Grok's picture of the story when there is one.
    component Picture: Rectangle {
        readonly property bool drawn: !news.fullShown && !!news.article.illustration
        readonly property string url: drawn ? news.article.illustration : news.article.leadImage || news.story.imageUrl || ""
        radius: Theme.radius
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(news.story.sectionColor || Theme.accent, 1.2) }
            GradientStop { position: 1; color: Qt.darker(news.story.sectionColor || Theme.accent, 1.3) }
        }
        Image {
            anchors.fill: parent
            source: parent.url
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 1200
            visible: status === Image.Ready
        }
        Label {
            anchors.centerIn: parent
            visible: !parent.url.length
            text: (news.story.sectionName || "").slice(0, 1)
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: Math.min(220, parent.height * 0.6)
            font.weight: Font.Bold
        }
        Label {
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 14
            visible: parent.drawn
            text: news.article.illustrationBy || ""
            color: "white"
            font.pixelSize: Theme.fontXs
            font.weight: Font.DemiBold
            leftPadding: 12; rightPadding: 12; topPadding: 5; bottomPadding: 5
            background: Rectangle { radius: height / 2; color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }
    // The section, the close button, the headline and who wrote it.
    component Words: ColumnLayout {
        spacing: Theme.mini ? 6 : 12
        RowLayout {
            Layout.fillWidth: true
            Tag { text: news.story.sectionName || ""; tint: news.story.sectionColor ? Qt.rgba(0, 0, 0, 0) : Theme.sunken; ink: news.story.sectionColor || Theme.text }
            Label {
                Layout.fillWidth: true
                text: news.article.readingTime || ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
                elide: Text.ElideRight
            }
            IconButton { icon: "close"; fill: Theme.surface; onClicked: news.closeStory() }
        }
        Label {
            Layout.fillWidth: true
            text: news.story.headline || ""
            color: Theme.text
            font.pixelSize: Theme.mini ? Theme.fontMd : Theme.compact ? Theme.fontLg + 2 : Theme.fontXl - 4
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            maximumLineCount: Theme.mini ? 2 : 3
            elide: Text.ElideRight
            lineHeight: 1.05
        }
        Label {
            Layout.fillWidth: true
            visible: text.length > 0
            text: news.article.byline || news.story.sourceDomain || ""
            color: Theme.textMuted
            font.pixelSize: Theme.fontXs
            elide: Text.ElideRight
        }
    }
    // Summary | Full story, when the page gave its text.
    component ModeChips: ChipRow {
        visible: !!news.article.hasFullStory
        chipHeight: Theme.mini ? 40 : 48
        model: [{ id: "summary", label: qsTr("Summary") }, { id: "full", label: qsTr("Full story") }]
        current: news.readMode
        onPicked: id => news.readMode = id
    }
    // The code for the article, or for the video last tapped.
    component StoryQr: QrPanel {
        url: news.qrUrl || news.story.url || ""
        domain: news.qrUrl ? "" : news.story.sourceDomain || ""
        title: news.qrUrl ? qsTr("Watch it on your phone") : qsTr("Read it on your phone")
        caption: news.qrUrl ? qsTr("Point the camera at the code to open the video.") : qsTr("Point the camera at the code to open the article.")
    }
    // A video: its poster with a play mark. Tapped, it's what the code opens.
    component VideoTile: Rectangle {
        property var block: ({})
        readonly property bool onCode: news.qrUrl.length > 0 && news.qrUrl === block.url
        radius: Theme.radiusSm
        clip: true
        color: Theme.sunken
        border.width: onCode ? 3 : 0
        border.color: Theme.accent
        Image {
            anchors.fill: parent
            source: Theme.pictures ? block.poster || "" : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 800
            visible: status === Image.Ready
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.22) }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(76, parent.height * 0.4); height: width; radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.5)
            Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; name: "play"; size: parent.width * 0.42; color: "white" }
        }
        Label {
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 12
            text: parent.onCode ? qsTr("On the code") : (parent.block.label || qsTr("Video"))
            color: "white"
            font.pixelSize: Theme.fontXs
            font.weight: Font.DemiBold
            leftPadding: 10; rightPadding: 10; topPadding: 4; bottomPadding: 4
            background: Rectangle { radius: height / 2; color: Qt.rgba(0, 0, 0, 0.55) }
        }
        TapHandler { onTapped: news.qrUrl = parent.block.url || "" }
    }
    // The summary or the full story, scrolling, with the small print last.
    component ArticleBody: FocusFlickable {
        id: body
        // Off where this copy's layout isn't the one showing: no blocks made twice.
        property bool live: true
        property bool withQr: false
        readonly property int textSize: Theme.mini ? Theme.fontSm : Theme.fontMd - 1
        fadeColor: Theme.background
        contentHeight: col.implicitHeight
        Connections {
            target: news
            function onStoryChanged() { body.contentY = 0 }
            function onReadModeChanged() { body.contentY = 0 }
        }
        ColumnLayout {
            id: col
            width: body.width
            spacing: Theme.mini ? 10 : 16

            // The summary, or the takeaway until there's one.
            Label {
                Layout.fillWidth: true
                visible: !news.fullShown && text.length > 0
                text: news.article.summary || news.story.takeaway || ""
                color: Theme.text
                font.pixelSize: body.textSize + 1
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
            Label {
                visible: text.length > 0
                text: Reader.state === "loading" ? qsTr("Reading the article…") : news.article.working || ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
                SequentialAnimation on opacity {
                    running: (Reader.state === "loading" || !!news.article.working) && news.moving
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            // The key points.
            Rectangle {
                Layout.fillWidth: true
                visible: !news.fullShown && (news.article.points || []).length > 0
                implicitHeight: pointsCol.implicitHeight + 32
                radius: Theme.radiusSm
                color: Theme.surface
                ColumnLayout {
                    id: pointsCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 10
                    Label { text: qsTr("KEY POINTS"); color: Theme.textMuted; font.pixelSize: Theme.fontXs - 1; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                    Repeater {
                        model: body.live && !news.fullShown ? news.article.points || [] : []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle { Layout.alignment: Qt.AlignTop; Layout.topMargin: body.textSize * 0.45; width: 8; height: 8; radius: 4; color: news.story.sectionColor || Theme.accent }
                            Label { Layout.fillWidth: true; text: modelData; color: Theme.text; font.pixelSize: body.textSize - 1; wrapMode: Text.WordWrap; lineHeight: 1.15 }
                        }
                    }
                }
            }
            // The page's pictures and videos, a row of them.
            GridLayout {
                Layout.fillWidth: true
                visible: !news.fullShown && Theme.pictures && (news.article.media || []).length > 0
                columns: Theme.wide ? 3 : 2
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: body.live && !news.fullShown && Theme.pictures ? (news.article.media || []).slice(0, Theme.wide ? 3 : 2) : []
                    delegate: Loader {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: Theme.mini ? 0 : Theme.tall ? 150 : 130
                        sourceComponent: modelData.type === "video" ? videoThumb : imageThumb
                        onLoaded: item.block = modelData
                    }
                }
            }
            // The full story, block by block.
            Repeater {
                model: body.live && news.fullShown ? news.article.blocks || [] : []
                delegate: Loader {
                    required property var modelData
                    Layout.fillWidth: true
                    sourceComponent: modelData.type === "h" ? headingBlock
                                   : modelData.type === "quote" ? quoteBlock
                                   : modelData.type === "image" ? (Theme.pictures ? imageBlock : null)
                                   : modelData.type === "video" ? videoBlock
                                   : textBlock
                    onLoaded: item.block = modelData
                }
            }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: news.article.summaryBy || ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
            }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: news.article.note || ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs + 1
                wrapMode: Text.WordWrap
            }
            StoryQr { Layout.fillWidth: true; visible: body.withQr }
            Item { implicitHeight: 4 }
        }

        Component {
            id: textBlock
            Label {
                property var block: ({})
                text: block.text || ""
                color: Theme.text
                font.pixelSize: body.textSize
                wrapMode: Text.WordWrap
                lineHeight: 1.3
                leftPadding: block.type === "list" ? 8 : 0
            }
        }
        Component {
            id: headingBlock
            Label {
                property var block: ({})
                text: block.text || ""
                color: Theme.text
                font.pixelSize: body.textSize + 4
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                topPadding: 8
            }
        }
        Component {
            id: quoteBlock
            Item {
                property var block: ({})
                implicitHeight: quoteText.implicitHeight
                Rectangle { width: 4; height: parent.height; radius: 2; color: news.story.sectionColor || Theme.accent }
                Label {
                    id: quoteText
                    anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 20
                    text: parent.block.text + (parent.block.cite ? "\n— " + parent.block.cite : "")
                    color: Theme.text
                    font.pixelSize: body.textSize
                    font.italic: true
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                }
            }
        }
        Component {
            id: imageBlock
            ColumnLayout {
                property var block: ({})
                spacing: 6
                visible: picture.status !== Image.Error
                Image {
                    id: picture
                    Layout.fillWidth: true
                    // As tall as the picture is at this width; nothing until it's in.
                    Layout.preferredHeight: status === Image.Ready && implicitWidth > 0 ? Math.min(width * implicitHeight / implicitWidth, body.height * 0.8) : 0
                    source: parent.block.url || ""
                    fillMode: Image.PreserveAspectFit
                    horizontalAlignment: Image.AlignLeft
                    asynchronous: true
                    sourceSize.width: 1200
                }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: parent.block.caption || ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                    wrapMode: Text.WordWrap
                }
            }
        }
        Component {
            id: videoBlock
            ColumnLayout {
                property var block: ({})
                spacing: 6
                VideoTile {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.pictures ? Math.min(width * 9 / 16, 340) : 72
                    block: parent.block
                }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: parent.block.caption || ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                    wrapMode: Text.WordWrap
                }
            }
        }
        Component {
            id: imageThumb
            Rectangle {
                property var block: ({})
                radius: Theme.radiusSm
                clip: true
                color: Theme.sunken
                Image {
                    anchors.fill: parent
                    source: parent.block.url || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 600
                    visible: status === Image.Ready
                }
            }
        }
        Component {
            id: videoThumb
            VideoTile {}
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: opacity > 0
        opacity: news.storyOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
        color: Theme.background
        MouseArea { anchors.fill: parent } // nothing underneath takes the tap

        // Wide and Compact: the picture and the code beside the article.
        RowLayout {
            visible: Theme.paned
            anchors.fill: parent
            anchors.margins: Theme.pageMargin
            spacing: Theme.spacing
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.4
                Layout.maximumWidth: parent.width * 0.4
                spacing: Theme.spacing
                Picture { Layout.fillWidth: true; Layout.fillHeight: true }
                StoryQr { Layout.fillWidth: true }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14
                Words { Layout.fillWidth: true }
                ModeChips { Layout.fillWidth: true }
                ArticleBody { Layout.fillWidth: true; Layout.fillHeight: true; live: Theme.paned }
            }
        }
        // Tall: the picture on top, the code below. Mini: no picture, and the
        // code at the end of the article, where there's room for it.
        ColumnLayout {
            visible: !Theme.paned
            anchors.fill: parent
            anchors.margins: Theme.pageMargin
            spacing: Theme.mini ? 8 : 14
            Picture {
                visible: Theme.pictures
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(260, parent.height * 0.2)
            }
            Words { Layout.fillWidth: true }
            ModeChips { Layout.fillWidth: true }
            ArticleBody { Layout.fillWidth: true; Layout.fillHeight: true; live: !Theme.paned; withQr: Theme.mini }
            StoryQr { Layout.fillWidth: true; visible: !Theme.mini }
        }
    }
}
