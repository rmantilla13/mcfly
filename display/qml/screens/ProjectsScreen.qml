import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Projects: what's in flight as the agents report it, blocked ones first;
// the one picked shows its history of commits, pull requests, CI runs,
// deploys and notes, beside the board or on a page pushed over it.
//
// A card's progress is a ring that sweeps in as the board settles; a
// blocked card's outline breathes. The picked project heads its detail on a
// gradient tile in its status colour, a big ring beside its name, over its
// updates as a thread of moments, newest first.
Item {
    id: projects
    property bool shown: true
    // The page picked, under the assistant panel too: it settles in as
    // this turns true, not again when the panel goes.
    property bool isCurrent: true
    property string selected: ""
    readonly property var current: Store.project(selected).id ? Store.project(selected) : (Store.projects[0] || ({}))
    readonly property int blocked: Store.projects.filter(p => p.status === "blocked").length
    function closeDetail() { md.closeDetail() }
    // Loops run only while someone can see them.
    readonly property bool moving: shown && !Device.idle && Device.animatedTiles
    // The blocked cards' breath, on the ambient clock's 30 updates a second
    // (MotionClock). A card breathes only while it is on screen, so its
    // edge changes, and a frame is drawn, only where someone can see it.
    MotionClock { id: breath; playing: projects.moving && projects.blocked > 0 }

    Reveal { id: rv; shown: projects.isCurrent }
    // The detail's ring and updates, played again for each project picked.
    property real detailIn: 1
    NumberAnimation { id: detailAnim; target: projects; property: "detailIn"; from: 0; to: 1; duration: Theme.revealDuration }
    function pick(id) {
        const again = id !== current.id
        selected = id
        md.open()
        if (again && Device.animatedTiles)
            detailAnim.restart()
    }

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
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    opacity: rv.at(index)
                    transform: Translate { y: rv.rise(cell.index) }
                    Rectangle {
                        id: card
                        anchors.fill: parent
                        anchors.rightMargin: Theme.spacing
                        anchors.bottomMargin: Theme.spacing
                        readonly property bool chosen: md.paned && cell.modelData.id === projects.current.id
                        readonly property bool isBlocked: cell.modelData.status === "blocked"
                        readonly property int ringSize: Theme.mini ? 50 : Theme.tall ? 62 : Theme.wide ? 76 : 68
                        radius: Theme.radiusSm
                        color: chosen ? "transparent" : Theme.surface
                        border.width: !chosen && isBlocked ? 2 : 0
                        border.color: Theme.danger
                        opacity: cell.modelData.status === "done" ? 0.7 : 1
                        scale: tap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.quick } }
                        // Chosen: active glass (Lens), as the nav pill is.
                        Lens { anchors.fill: parent; visible: card.chosen; kind: "active"; radius: card.radius }
                        // Blocked: a soft second edge inside the first breathes
                        // in and out, slowly (to 0.4 and back, Theme.breath each
                        // way, eased in and out), from nothing each time it
                        // starts. Stopped, or scrolled out of sight, it is
                        // simply not there.
                        readonly property bool breathes: isBlocked && !chosen && projects.moving
                                                         && cell.y + cell.height > grid.contentY && cell.y < grid.contentY + grid.height
                        property real breathFrom: 0
                        onBreathesChanged: if (breathes) breathFrom = breath.time
                        Component.onCompleted: if (breathes) breathFrom = breath.time
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.radius - 2
                            color: "transparent"
                            border.width: 4
                            border.color: Theme.danger
                            visible: card.breathes
                            opacity: visible ? 0.2 * (1 - Math.cos(Math.PI * (breath.time - card.breathFrom) * 1000 / Theme.breath)) : 0
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: Theme.mini ? 10 : 16
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: Theme.mini ? 6 : 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Rectangle { width: 12; height: 12; radius: 6; color: cell.modelData.statusColor }
                                    Label { text: cell.modelData.name; color: Theme.text; font.pixelSize: Theme.fontMd - 2; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Label {
                                    text: (cell.modelData.statusLabel || "").toUpperCase()
                                    color: cell.modelData.statusColor
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1
                                }
                                Label {
                                    Layout.fillWidth: true
                                    visible: !Theme.mini
                                    text: cell.modelData.summary || ""
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontXs + 1
                                    wrapMode: Text.WordWrap
                                    // Portrait's cards are shorter.
                                    maximumLineCount: Theme.tall ? 1 : 2
                                    elide: Text.ElideRight
                                }
                                Item { Layout.fillHeight: true }
                                Label {
                                    Layout.fillWidth: true
                                    visible: !!cell.modelData.lastUpdate
                                    text: cell.modelData.lastUpdate ? cell.modelData.lastUpdate.text : ""
                                    color: Theme.text
                                    font.pixelSize: Theme.fontXs
                                    elide: Text.ElideRight
                                }
                            }
                            // Progress: a ring that sweeps in with the board.
                            Ring {
                                visible: !!cell.modelData.hasProgress
                                Layout.preferredWidth: card.ringSize
                                Layout.preferredHeight: card.ringSize
                                Layout.alignment: Qt.AlignVCenter
                                value: (cell.modelData.progress || 0) / 100
                                shown: rv.at(cell.index + 1)
                                color: cell.modelData.statusColor
                                Label {
                                    anchors.centerIn: parent
                                    text: (cell.modelData.progress || 0) + "%"
                                    color: Theme.text
                                    font.pixelSize: Theme.mini ? Theme.fontXs : Theme.fontSm - 1
                                    font.weight: Font.DemiBold
                                    font.features: ({ "tnum": 1 })
                                }
                            }
                        }
                        TapHandler { id: tap; onTapped: projects.pick(cell.modelData.id) }
                    }
                }
                EmptyState {
                    anchors.fill: parent
                    visible: Store.projects.length === 0
                    icon: "chores"
                    text: qsTr("No projects yet")
                    hint: qsTr("A code or task agent reports what it's working on here.")
                    url: "https://mcfly.bot/agents"
                    action: qsTr("Add an agent")
                    caption: qsTr("Scan to open Agents on your phone: pick what it's for and it gives you the prompt to paste.")
                }
            }
        }

        // The picked project: its status, name and progress on a tile in its
        // colour, then what's next and its history, as a thread.
        detail: ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacing
            GradientTile {
                id: head
                Layout.fillWidth: true
                Layout.preferredHeight: headRow.implicitHeight + 2 * headRow.anchors.margins
                radius: Theme.radius
                baseColor: projects.current.statusColor || Theme.accent
                active: projects.shown && (md.paned || md.pushed)
                seed: 4.2
                rings: 1
                ringBias: 0.85
                RowLayout {
                    id: headRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.mini ? 18 : Theme.compact ? 22 : 28
                    spacing: Theme.mini ? 14 : 20
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.mini ? 4 : 6
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Label {
                                text: (projects.current.statusLabel || "").toUpperCase()
                                color: head.inkMuted
                                font.pixelSize: Theme.fontXs
                                font.weight: Font.Bold
                                font.letterSpacing: 1.2
                            }
                            Label {
                                Layout.fillWidth: true
                                text: projects.current.agentName ? "· " + projects.current.agentName : ""
                                color: head.inkMuted
                                font.pixelSize: Theme.fontXs
                                elide: Text.ElideRight
                            }
                        }
                        Label {
                            visible: md.paned
                            Layout.fillWidth: true
                            text: projects.current.name || ""
                            color: head.ink
                            font.pixelSize: Theme.wide ? Theme.fontXl : Theme.fontLg
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: projects.current.summary || ""
                            color: head.inkMuted
                            font.pixelSize: Theme.fontSm
                            wrapMode: Text.WordWrap
                            maximumLineCount: Theme.mini ? 2 : 3
                            elide: Text.ElideRight
                        }
                    }
                    Ring {
                        visible: !!projects.current.hasProgress
                        readonly property int big: Theme.mini ? 84 : Theme.compact ? 108 : 132
                        Layout.preferredWidth: big
                        Layout.preferredHeight: big
                        Layout.alignment: Qt.AlignVCenter
                        value: (projects.current.progress || 0) / 100
                        shown: Math.min(rv.at(1), 1 - Math.pow(1 - projects.detailIn, 3))
                        color: head.ink
                        track: Qt.rgba(head.ink.r, head.ink.g, head.ink.b, 0.16)
                        lineWidth: Theme.mini ? 7 : 9
                        Column {
                            anchors.centerIn: parent
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (projects.current.progress || 0) + "%"
                                color: head.ink
                                font.pixelSize: Theme.mini ? Theme.fontMd : Theme.fontLg
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("done")
                                color: head.inkMuted
                                font.pixelSize: Theme.fontXs - 1
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radius
                color: Theme.surface
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.mini ? 18 : Theme.compact ? 22 : 28
                    spacing: Theme.mini ? 8 : 12
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
                    Label { Layout.topMargin: 2; text: qsTr("UPDATES"); color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                    // The updates as a thread: each a node with its icon, the
                    // line running on to the next.
                    ListView {
                        id: updates
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: projects.current.updates || []
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Item {
                            id: update
                            required property var modelData
                            required property int index
                            readonly property bool alert: modelData.kind === "alert"
                            readonly property int node: Theme.mini ? 32 : 36
                            width: ListView.view.width
                            height: Math.max(node, words.implicitHeight) + (Theme.mini ? 12 : 16)
                            // Each a beat after the one above, as the project is picked.
                            opacity: Math.max(0, Math.min(1, projects.detailIn * 2.5 - Math.min(update.index, 5) * 0.25))
                            Rectangle {
                                visible: update.index < updates.count - 1
                                x: update.node / 2 - 1
                                y: update.node + 4
                                width: 2
                                height: update.height - update.node - 4
                                radius: 1
                                color: Theme.divider
                            }
                            Rectangle {
                                width: update.node; height: width; radius: width / 2
                                color: update.alert ? Qt.rgba(0.94, 0.50, 0.35, 0.2) : Theme.surfaceAlt
                                border.width: update.index === 0 ? 2 : 0
                                border.color: update.alert ? Theme.danger : (projects.current.statusColor || Theme.accent)
                                Icon { anchors.centerIn: parent; name: update.modelData.icon || "chat"; size: Theme.mini ? 16 : 18; color: update.alert ? Theme.danger : Theme.text }
                            }
                            ColumnLayout {
                                id: words
                                x: update.node + (Theme.mini ? 12 : 14)
                                width: update.width - x
                                spacing: 2
                                Label { Layout.fillWidth: true; text: update.modelData.text; color: Theme.text; font.pixelSize: Theme.fontSm; wrapMode: Text.WordWrap }
                                Label { text: (update.modelData.kind || "note").toUpperCase() + " · " + (update.modelData.whenLabel || ""); color: Theme.textMuted; font.pixelSize: Theme.fontXs - 1; font.letterSpacing: 0.6 }
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
}
