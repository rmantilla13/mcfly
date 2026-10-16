import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Briefs: every update the agents pushed, newest first, grouped by day; the
// one picked reads in full beside the list, or, on the small panels, on a
// page pushed over it. The picked row's outline glides to a new pick; a
// brief from the last hour has a dot by its time. The reader sets a brief's
// points ("- " lines) apart, each on a dot, where they fall in the body.
Item {
    id: briefs
    property bool shown: true
    // The page picked, under the assistant panel too: it settles in as
    // this turns true, not again when the panel goes.
    property bool isCurrent: true
    property int selected: 0
    readonly property var current: Store.briefs[selected] || Store.briefs[0] || ({})
    onCurrentChanged: if (selected >= Store.briefs.length) selected = 0
    function closeDetail() { md.closeDetail() }
    // Picked by a tap (the outline glides), not by a sync or a reset (it jumps).
    property bool _tapped: false
    function pick(index) {
        _tapped = Device.animatedTiles
        selected = index
        glideTimer.restart()
        md.open()
        if (Device.animatedTiles)
            readerFade.restart()
    }
    Timer { id: glideTimer; interval: Theme.glide + 50; onTriggered: briefs._tapped = false }
    // Arrived in the last hour. Store.nowAngle moves each minute, so it is asked again then.
    function isNew(brief) { return Store.nowAngle >= 0 && Date.now() - (brief.publishedMs || 0) < 3600000 }

    Reveal { id: rv; shown: briefs.isCurrent }
    // The reader's words, faded in as a new brief is picked.
    property real readerIn: 1
    NumberAnimation { id: readerFade; target: briefs; property: "readerIn"; from: 0; to: 1; duration: Theme.enter; easing.type: Easing.OutCubic }

    // A paragraph or a point of the reader, with its Markdown (bold, links) kept.
    component Prose: Text {
        textFormat: Text.MarkdownText
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontMd - 2
        lineHeight: 1.25
        wrapMode: Text.WordWrap
    }

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
                objectName: "briefList"
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
                // The picked row's outline, over the rows: it glides when a
                // tap picks another, and jumps when the list is rebuilt.
                // The picked row says where it is (a sync makes the rows again).
                property Item chosenRow: null
                Rectangle {
                    id: chosenOutline
                    objectName: "chosenOutline"
                    // Among the rows (a view's own children don't scroll with them).
                    parent: list.contentItem
                    readonly property Item row: list.chosenRow
                    visible: md.paned && !!row
                    z: 2
                    x: 0
                    y: row ? row.y : 0
                    width: list.width
                    height: row ? row.height : 0
                    radius: Theme.radiusSm
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.16 : 0.10)
                    border.width: 2
                    border.color: Theme.accent
                    Behavior on y { enabled: briefs._tapped; NumberAnimation { duration: Theme.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                    Behavior on height { enabled: briefs._tapped; NumberAnimation { duration: Theme.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                }
                delegate: Rectangle {
                    id: briefRow
                    required property var modelData
                    required property int index
                    readonly property bool fresh: briefs.isNew(modelData)
                    readonly property bool chosen: index === briefs.selected
                    onChosenChanged: {
                        if (chosen)
                            list.chosenRow = briefRow
                        else if (list.chosenRow === briefRow)
                            list.chosenRow = null // the pick went to a row not made yet
                    }
                    Component.onCompleted: if (chosen) list.chosenRow = briefRow
                    width: ListView.view.width
                    height: Theme.mini ? Theme.touchTarget : rowCol.implicitHeight + 32
                    radius: Theme.radiusSm
                    color: Theme.surface
                    opacity: rv.at(index)
                    transform: Translate { y: rv.rise(briefRow.index) }

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
                            // In the last hour.
                            Rectangle { visible: briefRow.fresh; width: 8; height: 8; radius: 4; color: Theme.accent }
                            Label { text: modelData.timeLabel; color: briefRow.fresh ? Theme.accent : Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: briefRow.fresh ? Font.DemiBold : Font.Normal }
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
                        Rectangle { visible: briefRow.fresh; width: 8; height: 8; radius: 4; color: Theme.accent }
                        Label { text: modelData.timeLabel; color: briefRow.fresh ? Theme.accent : Theme.textMuted; font.pixelSize: Theme.fontXs }
                    }
                    TapHandler { onTapped: briefs.pick(index) }
                }
                EmptyState {
                    anchors.fill: parent
                    visible: Store.briefs.length === 0
                    icon: "brief"
                    text: qsTr("No briefs yet")
                    hint: qsTr("A Grok bot writes one on a schedule, and any agent can send them.")
                    url: "https://mcfly.bot/bots"
                    action: qsTr("Make a Grok bot")
                    caption: qsTr("Scan to make one on your phone: what to ask Grok, and when.")
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
                    id: readerView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: readerBody.implicitHeight
                    clip: true
                    // The body in order: paragraphs and runs of points.
                    readonly property var blocks: briefs.current.blocks || []
                    readonly property bool pointed: blocks.some(b => b.kind === "points")
                    Connections {
                        target: briefs
                        function onSelectedChanged() { readerView.contentY = 0 }
                    }
                    // Each part a beat after the one before as the brief
                    // arrives (capped, so a long brief is all there by the end).
                    function beat(order) { return Math.min(1, Math.max(0, briefs.readerIn * 3 - Math.min(order, 5) * 0.4)) }
                    ColumnLayout {
                        id: readerBody
                        width: parent.width
                        spacing: Theme.mini ? 12 : 16
                        opacity: briefs.readerIn
                        // No points: the body as written.
                        Prose {
                            Layout.fillWidth: true
                            visible: !readerView.pointed
                            text: briefs.current.body || ""
                        }
                        // Points: the blocks as they come, each point on a dot.
                        Repeater {
                            model: readerView.pointed ? readerView.blocks : []
                            delegate: ColumnLayout {
                                id: block
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: Theme.mini ? 8 : 10
                                Prose {
                                    Layout.fillWidth: true
                                    visible: block.modelData.kind === "paragraph"
                                    text: block.modelData.text || ""
                                    opacity: readerView.beat(block.index)
                                }
                                Repeater {
                                    model: block.modelData.items || []
                                    delegate: RowLayout {
                                        id: point
                                        required property string modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: Theme.mini ? 12 : 16
                                        opacity: readerView.beat(block.index + point.index)
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: Math.round((Theme.fontMd - 2) * 0.62) - 4
                                            width: 8; height: 8; radius: 4
                                            color: briefs.current.agentColor || Theme.accent
                                        }
                                        Prose { Layout.fillWidth: true; text: point.modelData }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
