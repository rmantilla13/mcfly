import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Briefs: every update the agents pushed, newest first, grouped by day; the
// one picked reads in full beside the list, or, on the small panels, on a
// page pushed over it.
Item {
    id: briefs
    property int selected: 0
    readonly property var current: Store.briefs[selected] || Store.briefs[0] || ({})
    onCurrentChanged: if (selected >= Store.briefs.length) selected = 0
    function closeDetail() { md.closeDetail() }

    MasterDetail {
        id: md
        anchors.fill: parent
        masterFixed: true
        masterWidth: Theme.listWidth
        hasDetail: !!briefs.current.title
        detailTitle: briefs.current.agentName || ""
        detailSubtitle: (briefs.current.kindLabel || "") + " · " + (briefs.current.dayLabel || "") + " · " + (briefs.current.timeLabel || "")

        // The list.
        master: ColumnLayout {
            anchors.fill: parent
            spacing: 14
            ScreenHeader {
                Layout.fillWidth: true
                title: qsTr("Briefs")
                subtitle: Store.latestBrief.whenLabel ? qsTr("Latest %1").arg(Store.latestBrief.whenLabel) : ""
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.mini ? 6 : 10
                model: Store.briefs
                boundsBehavior: Flickable.StopAtBounds
                section.property: "dayLabel"
                section.criteria: ViewSection.FullString
                section.delegate: Label {
                    width: ListView.view.width
                    topPadding: Theme.mini ? 8 : 12
                    bottomPadding: 6
                    text: section.toUpperCase()
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === briefs.selected && md.paned
                    width: ListView.view.width
                    height: Theme.mini ? Theme.touchTarget : rowCol.implicitHeight + 32
                    radius: Theme.radiusSm
                    color: chosen ? Theme.accentSoft : Theme.surface
                    border.width: chosen ? 2 : 0
                    border.color: Theme.accent

                    // Meta, title and summary stacked...
                    ColumnLayout {
                        id: rowCol
                        visible: !Theme.mini
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 18
                        spacing: 6
                        RowLayout {
                            spacing: 8
                            Rectangle { width: 10; height: 10; radius: 5; color: modelData.agentColor }
                            Label { text: modelData.agentName; color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.Medium }
                            Tag { text: modelData.kindLabel; tint: modelData.kind === "alert" ? Qt.rgba(0.94, 0.50, 0.35, 0.22) : Theme.sunken; ink: modelData.kind === "alert" ? Theme.danger : Theme.textMuted }
                            Item { Layout.fillWidth: true }
                            Label { text: modelData.timeLabel; color: Theme.textMuted; font.pixelSize: Theme.fontXs }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: Theme.text
                            font.pixelSize: Theme.fontMd - 2
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: modelData.summary
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontXs + 1
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                    // ...or, on Mini, one line: who, what kind, the title, when.
                    RowLayout {
                        visible: Theme.mini
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8
                        Rectangle { width: 10; height: 10; radius: 5; color: modelData.agentColor }
                        Label { text: modelData.agentName; color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.Medium }
                        Tag { text: modelData.kindLabel; tint: modelData.kind === "alert" ? Qt.rgba(0.94, 0.50, 0.35, 0.22) : Theme.sunken; ink: modelData.kind === "alert" ? Theme.danger : Theme.textMuted }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: Theme.text
                            font.pixelSize: Theme.fontSm
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label { text: modelData.timeLabel; color: Theme.textMuted; font.pixelSize: Theme.fontXs }
                    }
                    TapHandler { onTapped: { briefs.selected = index; md.open() } }
                }
                EmptyState {
                    anchors.fill: parent
                    visible: Store.briefs.length === 0
                    text: qsTr("No briefs yet.")
                    hint: qsTr("Agents push them to McFly; see docs/AGENTS.md.")
                }
            }
        }

        // The reader.
        detail: Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.surface
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.mini ? 20 : Theme.compact ? 28 : 40
                spacing: Theme.mini ? 10 : 16
                RowLayout {
                    visible: md.paned
                    spacing: 12
                    Rectangle {
                        width: 44; height: 44; radius: 22
                        color: briefs.current.agentColor || Theme.accent
                        Label {
                            anchors.centerIn: parent
                            text: (briefs.current.agentName || "M").slice(0, 1)
                            color: "white"
                            font.pixelSize: Theme.fontSm
                            font.weight: Font.Bold
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Label { text: briefs.current.agentName || ""; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                        Label { text: md.detailSubtitle; color: Theme.textMuted; font.pixelSize: Theme.fontXs }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: briefs.current.title || ""
                    color: Theme.text
                    font.pixelSize: Theme.compact ? Theme.fontLg : Theme.fontXl
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    lineHeight: 1.05
                }
                FocusFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: bodyText.implicitHeight
                    clip: true
                    Text {
                        id: bodyText
                        width: parent.width
                        text: briefs.current.body || ""
                        textFormat: Text.MarkdownText
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontMd - 2
                        lineHeight: 1.25
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
