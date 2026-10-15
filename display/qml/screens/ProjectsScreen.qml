import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Projects: what's in flight as the agents report it, blocked ones first;
// the one picked shows its history of commits, pull requests, CI runs,
// deploys and notes, beside the board or on a page pushed over it.
Item {
    id: projects
    property string selected: ""
    readonly property var current: Store.project(selected).id ? Store.project(selected) : (Store.projects[0] || ({}))
    readonly property int blocked: Store.projects.filter(p => p.status === "blocked").length
    function closeDetail() { md.closeDetail() }

    MasterDetail {
        id: md
        anchors.fill: parent
        paneWidth: Theme.wide ? 460 : 400
        hasDetail: !!projects.current.id
        detailTitle: projects.current.name || ""
        detailSubtitle: (projects.current.statusLabel || "") + (projects.current.agentName ? " · " + projects.current.agentName : "")

        master: ColumnLayout {
            anchors.fill: parent
            spacing: 14
            ScreenHeader {
                Layout.fillWidth: true
                title: qsTr("Projects")
                subtitle: projects.blocked > 0 ? qsTr("%1 blocked").arg(projects.blocked) : qsTr("%1 in flight").arg(Store.projects.filter(p => p.status !== "done").length)
            }
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Store.projects
                cellWidth: Math.floor(width / Theme.projectColumns)
                cellHeight: Theme.projectCardHeight
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: Theme.spacing
                        anchors.bottomMargin: Theme.spacing
                        readonly property bool chosen: md.paned && modelData.id === projects.current.id
                        radius: Theme.radiusSm
                        color: chosen ? Theme.accentSoft : Theme.surface
                        border.width: chosen ? 2 : modelData.status === "blocked" ? 2 : 0
                        border.color: chosen ? Theme.accent : Theme.danger
                        opacity: modelData.status === "done" ? 0.7 : 1
                        scale: tap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.quick } }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: Theme.mini ? 6 : 8
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle { width: 12; height: 12; radius: 6; color: modelData.statusColor }
                                Label { text: modelData.name; color: Theme.text; font.pixelSize: Theme.fontMd - 2; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Tag { text: modelData.statusLabel; tint: Qt.rgba(0, 0, 0, 0); ink: modelData.statusColor }
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: !Theme.mini
                                text: modelData.summary || ""
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontXs + 1
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            Item { Layout.fillHeight: true }
                            // Progress.
                            RowLayout {
                                visible: modelData.hasProgress
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 8; radius: 4
                                    color: Theme.sunken
                                    Rectangle {
                                        height: parent.height; radius: 4
                                        width: parent.width * (modelData.progress || 0) / 100
                                        color: modelData.statusColor
                                        Behavior on width { NumberAnimation { duration: Theme.smooth; easing.type: Easing.OutCubic } }
                                    }
                                }
                                Label { text: (modelData.progress || 0) + "%"; color: Theme.text; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold }
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: !!modelData.lastUpdate
                                text: modelData.lastUpdate ? modelData.lastUpdate.text : ""
                                color: Theme.text
                                font.pixelSize: Theme.fontXs
                                elide: Text.ElideRight
                            }
                        }
                        TapHandler { id: tap; onTapped: { projects.selected = modelData.id; md.open() } }
                    }
                }
                EmptyState {
                    anchors.fill: parent
                    visible: Store.projects.length === 0
                    text: qsTr("No projects yet.")
                    hint: qsTr("A code or task agent pushes them to McFly; see docs/AGENTS.md.")
                }
            }
        }

        // The picked project: its history.
        detail: Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.surface
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.mini ? 20 : Theme.compact ? 24 : 32
                spacing: Theme.mini ? 8 : 12
                RowLayout {
                    spacing: 10
                    Rectangle { width: 14; height: 14; radius: 7; color: projects.current.statusColor || Theme.accent }
                    Label { text: (projects.current.statusLabel || "") + (projects.current.hasProgress ? " · " + projects.current.progress + "%" : ""); color: projects.current.statusColor || Theme.text; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                    Item { Layout.fillWidth: true }
                    Label { text: projects.current.agentName || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs }
                }
                Label { visible: md.paned; Layout.fillWidth: true; text: projects.current.name || ""; color: Theme.text; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold; wrapMode: Text.WordWrap }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: projects.current.summary || ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSm
                    wrapMode: Text.WordWrap
                    maximumLineCount: Theme.mini ? 2 : 4
                    elide: Text.ElideRight
                }
                Rectangle {
                    visible: !!projects.current.next_step
                    Layout.fillWidth: true
                    Layout.preferredHeight: nextCol.implicitHeight + 24
                    radius: Theme.radiusSm
                    color: Theme.accentSoft
                    ColumnLayout {
                        id: nextCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 14
                        spacing: 2
                        Label { text: qsTr("NEXT"); color: Theme.accent; font.pixelSize: Theme.fontXs - 2; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        Label { Layout.fillWidth: true; text: projects.current.next_step || ""; color: Theme.text; font.pixelSize: Theme.fontSm; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                    }
                }
                Label { Layout.topMargin: 6; text: qsTr("UPDATES"); color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 10
                    model: projects.current.updates || []
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width
                        spacing: 12
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            width: 36; height: 36; radius: 18
                            color: modelData.kind === "alert" ? Qt.rgba(0.94, 0.50, 0.35, 0.2) : Theme.surfaceAlt
                            Icon { anchors.centerIn: parent; name: modelData.icon || "chat"; size: 18; color: modelData.kind === "alert" ? Theme.danger : Theme.text }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { Layout.fillWidth: true; text: modelData.text; color: Theme.text; font.pixelSize: Theme.fontSm; wrapMode: Text.WordWrap }
                            Label { text: (modelData.kind || "note").toUpperCase() + " · " + (modelData.whenLabel || ""); color: Theme.textMuted; font.pixelSize: Theme.fontXs - 1; font.letterSpacing: 0.6 }
                        }
                    }
                    EmptyState {
                        anchors.fill: parent
                        visible: (projects.current.updates || []).length === 0
                        text: qsTr("No updates yet")
                    }
                }
                Label {
                    visible: !!projects.current.link
                    text: projects.current.link || ""
                    color: Theme.accent
                    font.pixelSize: Theme.fontXs
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }
        }
    }
}
