import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// News: the day's Daily Pulse report, section by section. A tapped story
// opens large, with its takeaway, its source and a QR code so the article
// can be read on a phone. On the 7" panel the page carries no pictures: the
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

    // The picture, or a tinted field with the section's initial.
    component Picture: Rectangle {
        radius: Theme.radius
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(news.story.sectionColor || Theme.accent, 1.2) }
            GradientStop { position: 1; color: Qt.darker(news.story.sectionColor || Theme.accent, 1.3) }
        }
        Image {
            anchors.fill: parent
            source: news.story.imageUrl || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 1200
            visible: status === Image.Ready
        }
        Label {
            anchors.centerIn: parent
            visible: !(news.story.imageUrl || "").length
            text: (news.story.sectionName || "").slice(0, 1)
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: Math.min(220, parent.height * 0.6)
            font.weight: Font.Bold
        }
    }
    // The section, the headline and the takeaway, with the close button.
    component Words: ColumnLayout {
        spacing: Theme.mini ? 8 : 16
        RowLayout {
            Layout.fillWidth: true
            Tag { text: news.story.sectionName || ""; tint: news.story.sectionColor ? Qt.rgba(0, 0, 0, 0) : Theme.sunken; ink: news.story.sectionColor || Theme.text }
            Label { visible: Theme.mini; text: news.story.sourceDomain || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
            Item { Layout.fillWidth: true; visible: !Theme.mini }
            IconButton { icon: "close"; fill: Theme.surface; onClicked: news.closeStory() }
        }
        Label {
            Layout.fillWidth: true
            text: news.story.headline || ""
            color: Theme.text
            font.pixelSize: Theme.mini ? Theme.fontLg : Theme.compact ? Theme.fontLg + 4 : Theme.fontXl
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            maximumLineCount: Theme.mini ? 2 : 4
            elide: Text.ElideRight
            lineHeight: 1.05
        }
        Label {
            Layout.fillWidth: true
            visible: text.length > 0
            text: news.story.takeaway || ""
            color: Theme.text
            font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd
            wrapMode: Text.WordWrap
            maximumLineCount: Theme.mini ? 3 : 6
            elide: Text.ElideRight
            lineHeight: 1.2
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: opacity > 0
        opacity: news.storyOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
        color: Theme.background
        MouseArea { anchors.fill: parent } // nothing underneath takes the tap

        // Wide and Compact: the picture beside the words.
        RowLayout {
            visible: Theme.paned
            anchors.fill: parent
            anchors.margins: Theme.pageMargin
            spacing: Theme.spacing
            Picture {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.46
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16
                Words { Layout.fillWidth: true }
                Item { Layout.fillHeight: true }
                QrPanel { Layout.fillWidth: true; url: news.story.url || ""; domain: news.story.sourceDomain || "" }
            }
        }
        // Tall: the picture on top. Mini: no picture.
        ColumnLayout {
            visible: !Theme.paned
            anchors.fill: parent
            anchors.margins: Theme.pageMargin
            spacing: Theme.mini ? 10 : 16
            Picture {
                visible: Theme.pictures
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, parent.height * 0.3)
            }
            Words { Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
            QrPanel { Layout.fillWidth: true; url: news.story.url || ""; domain: news.story.sourceDomain || "" }
        }
    }
}
