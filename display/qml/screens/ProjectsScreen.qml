import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Projects: everything the agents report, as the console's List view lays
// it out: a group per status (Blocked, Active, Paused, Up next for the
// planned ones, Done), chips over them to show one group, and a row per
// project with its stages as a bar (or its progress), what's next and when
// it last moved. The one picked shows its history of commits, pull
// requests, CI runs, deploys and notes, beside the list or on a page pushed
// over it.
//
// The picked project heads its detail on a gradient tile in its status
// colour, a big ring beside its name, over its stages as a step each and its
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
    readonly property int inFlight: Store.projects.filter(p => p.status !== "planned" && p.status !== "done").length
    readonly property int upNext: Store.projects.filter(p => p.status === "planned").length
    // The chip picked: "all" or a status. One whose group has emptied shows all.
    property string filter: "all"
    readonly property string showing: filter === "all" || Store.projectGroups.some(g => g.status === filter && g.count > 0) ? filter : "all"
    function closeDetail() { md.closeDetail() }

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

    // A project's stages as a bar (the console's StageBar): the headline and
    // its place ("Blocked in App Review", "3 of 4") over a segment per stage,
    // the ones behind it in the project's colour, the one it is in taller (in
    // its status colour while blocked or paused), the rest a faint track. It
    // grows in from the left as `shown` goes to 1. On a gradient tile
    // (`onTile`) it is drawn in the tile's ink instead.
    component StageBar: ColumnLayout {
        id: stageBar
        property var project: ({})
        property real shown: 1
        property bool onTile: false
        property color ink: Theme.text
        property color inkMuted: Theme.textMuted
        readonly property var track: project.track || ({})
        readonly property var steps: track.steps || []
        readonly property int here: track.index === undefined ? -1 : track.index
        readonly property string hereState: here >= 0 && here < steps.length ? steps[here].state : ""
        function fill(phase) {
            if (onTile)
                return Qt.rgba(ink.r, ink.g, ink.b, phase === "next" ? 0.16 : phase === "done" ? 0.7 : 1)
            if (phase === "blocked" || phase === "paused")
                return project.statusColor
            if (phase === "next")
                return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
            return project.color || Theme.accent
        }
        spacing: Theme.mini ? 4 : 6
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label {
                Layout.fillWidth: true
                text: stageBar.track.headline || ""
                color: stageBar.onTile ? stageBar.ink
                     : stageBar.hereState === "blocked" ? Theme.danger : stageBar.hereState === "paused" ? Theme.warningInk : Theme.text
                font.pixelSize: Theme.fontXs
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Label {
                text: stageBar.track.position || ""
                color: stageBar.inkMuted
                font.pixelSize: Theme.fontXs - 1
                font.features: ({ "tnum": 1 })
            }
        }
        Item {
            id: segments
            Layout.fillWidth: true
            implicitHeight: 10
            transform: Scale { xScale: stageBar.shown }
            Repeater {
                model: stageBar.steps
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property real slot: (segments.width + 4) / Math.max(1, stageBar.steps.length)
                    x: index * slot
                    width: slot - 4
                    height: index === stageBar.here ? 10 : 6
                    y: (segments.height - height) / 2
                    radius: height / 2
                    color: stageBar.fill(modelData.state)
                    opacity: modelData.state === "done" && !stageBar.onTile ? 0.55 : 1
                }
            }
        }
    }

    // A project's stages as steps (the console's StageSteps): a node per
    // stage with its name under it, joined by a line drawn in the project's
    // colour once the next one is reached too. Done stages are ticked, the
    // one it is in is ringed (blocked and paused say so), the rest are
    // numbered. Too many to fit side by side, it flicks, opening on the one
    // it is in.
    component StageSteps: Flickable {
        id: stepper
        property var project: ({})
        property real shown: 1
        readonly property var track: project.track || ({})
        readonly property var steps: track.steps || []
        readonly property int here: track.index === undefined ? -1 : track.index
        readonly property color tint: project.color || Theme.accent
        readonly property color faint: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
        readonly property int node: Theme.wide ? 34 : 30
        readonly property real stepWidth: Math.max(92, width / Math.max(1, steps.length))
        function fill(phase) {
            if (phase === "blocked" || phase === "paused")
                return project.statusColor
            return phase === "next" ? faint : tint
        }
        function settle() {
            contentX = Math.max(0, Math.min(contentWidth - width, (here + 0.5) * stepWidth - width / 2))
        }
        implicitHeight: row.implicitHeight
        contentWidth: steps.length * stepWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width + 1
        clip: true
        onWidthChanged: settle()
        onContentWidthChanged: settle()
        onHereChanged: settle()
        Row {
            id: row
            Repeater {
                model: stepper.steps
                Item {
                    id: step
                    required property var modelData
                    required property int index
                    readonly property string phase: modelData.state
                    readonly property bool reached: phase !== "next"
                    readonly property bool onward: index < stepper.steps.length - 1 && stepper.steps[index + 1].state !== "next"
                    width: stepper.stepWidth
                    height: stepWord.y + stepWord.height
                    // Each a beat after the one before, as the project is picked.
                    opacity: Math.max(0, Math.min(1, stepper.shown * 2.5 - Math.min(index, 6) * 0.2))
                    Rectangle {
                        visible: step.index < stepper.steps.length - 1
                        x: (step.width + stepper.node) / 2 + 6
                        y: stepper.node / 2 - 1
                        width: step.width - stepper.node - 12
                        height: 2
                        radius: 1
                        color: step.onward ? stepper.tint : stepper.faint
                        opacity: step.onward ? 0.55 : 1
                    }
                    Item {
                        id: dot
                        width: stepper.node
                        height: width
                        x: (step.width - width) / 2
                        // The one it is in wears a soft ring.
                        Rectangle {
                            visible: step.index === stepper.here
                            anchors.centerIn: parent
                            width: parent.width + 10
                            height: width
                            radius: width / 2
                            color: Qt.rgba(dotFill.color.r, dotFill.color.g, dotFill.color.b, 0.22)
                        }
                        Rectangle {
                            id: dotFill
                            anchors.fill: parent
                            radius: width / 2
                            color: step.phase === "paused" ? Theme.surface : step.reached ? stepper.fill(step.phase) : "transparent"
                            opacity: step.phase === "done" ? 0.8 : 1
                            border.width: step.phase === "paused" ? 3 : step.reached ? 0 : 2
                            border.color: step.phase === "paused" ? stepper.project.statusColor : stepper.faint
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: name.length > 0
                            name: step.phase === "done" ? "check" : step.phase === "blocked" ? "info" : step.phase === "paused" ? "pause" : ""
                            size: Math.round(stepper.node * 0.5)
                            color: step.phase === "paused" ? Theme.warningInk : Theme.accentInk
                        }
                        Rectangle {
                            visible: step.phase === "current"
                            anchors.centerIn: parent
                            width: Math.round(stepper.node * 0.32)
                            height: width
                            radius: width / 2
                            color: Theme.accentInk
                        }
                        Label {
                            visible: !step.reached
                            anchors.centerIn: parent
                            text: step.index + 1
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontXs - 2
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                        }
                    }
                    Label {
                        id: stepName
                        x: 4
                        y: dot.height + 8
                        width: step.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        text: step.modelData.name
                        color: step.reached ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Label {
                        id: stepWord
                        x: 4
                        y: stepName.y + stepName.height + 2
                        width: step.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        text: step.modelData.word || ""
                        color: step.phase === "blocked" ? Theme.danger : step.phase === "paused" ? Theme.warningInk
                             : step.phase === "current" ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.fontXs - 2
                        font.weight: step.phase === "next" || step.phase === "done" ? Font.Normal : Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // A project in the list: its colour down the left, its name and whose it
    // is, its stages as a bar (or its progress), and what's next (what
    // happened last once it's done). The picked one is clear glass.
    component ProjectRow: Item {
        id: row
        property var project: ({})
        property int place: 0
        property bool last: false
        readonly property bool chosen: md.paned && project.id === projects.current.id
        readonly property bool done: project.status === "done"
        readonly property int pad: Theme.mini ? 12 : 16
        readonly property string said: !done && project.next_step ? project.next_step : (project.lastUpdate ? project.lastUpdate.text : "")
        height: Math.max(Theme.touchTarget, body.implicitHeight + 2 * pad)
        opacity: rv.at(place) * (done ? 0.75 : 1)
        transform: Translate { y: rv.rise(row.place) }
        Lens { anchors.fill: parent; anchors.margins: 4; visible: row.chosen; kind: "active"; radius: Theme.radiusSm - 4 }
        Rectangle {
            x: 10
            y: row.pad
            width: 5
            height: row.height - 2 * row.pad
            radius: 2.5
            color: row.project.color || Theme.accent
        }
        ColumnLayout {
            id: body
            x: 28
            width: row.width - x - row.pad - 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.mini ? 5 : 7
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Label {
                        Layout.fillWidth: true
                        text: row.project.name || ""
                        color: row.done ? Theme.textMuted : Theme.text
                        font.pixelSize: Theme.fontMd - 2
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: [row.project.kind, row.project.agentName].filter(s => !!s).join(" · ")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontXs - 1
                        elide: Text.ElideRight
                    }
                }
                Label {
                    Layout.alignment: Qt.AlignTop
                    visible: text.length > 0
                    text: row.project.updatedLabel || ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontXs - 1
                }
            }
            StageBar {
                Layout.fillWidth: true
                visible: !!row.project.hasStages
                project: row.project
                shown: rv.at(row.place + 1)
            }
            // No stages: its progress, when it has one.
            RowLayout {
                Layout.fillWidth: true
                visible: !row.project.hasStages && !!row.project.hasProgress
                spacing: 10
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    Rectangle { anchors.fill: parent; radius: 3; color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) }
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, (row.project.progress || 0) / 100)) * rv.at(row.place + 1)
                        height: parent.height
                        radius: 3
                        color: row.project.color || Theme.accent
                    }
                }
                Label { text: qsTr("%1% done").arg(row.project.progress || 0); color: Theme.textMuted; font.pixelSize: Theme.fontXs - 1; font.features: ({ "tnum": 1 }) }
            }
            Label {
                Layout.fillWidth: true
                visible: row.said.length > 0
                text: !row.done && row.project.next_step ? qsTr("Next: %1").arg(row.said) : row.said
                color: !row.done && row.project.next_step ? Theme.text : Theme.textMuted
                font.pixelSize: Theme.fontXs
                elide: Text.ElideRight
            }
        }
        Rectangle {
            visible: !row.last
            x: 28
            width: row.width - x
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.divider
        }
        TapHandler { onTapped: projects.pick(row.project.id) }
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
                subtitle: [projects.blocked > 0 ? qsTr("%1 blocked").arg(projects.blocked) : qsTr("%1 in flight").arg(projects.inFlight),
                           projects.upNext > 0 ? qsTr("%1 up next").arg(projects.upNext) : ""].filter(s => !!s).join(" · ")
            }
            // Which groups to show: all of them, or one status's.
            ChipRow {
                Layout.fillWidth: true
                visible: Store.projects.length > 0
                current: projects.showing
                model: [{ id: "all", label: qsTr("All  %1").arg(Store.projects.length) }].concat(
                           Store.projectGroups.filter(g => g.count > 0).map(g => ({ id: g.status, label: g.label + "  " + g.count, color: g.color })))
                onPicked: id => { projects.filter = id; list.contentY = 0 }
            }
            Flickable {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Store.projects.length > 0
                clip: true
                contentHeight: groupsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: groupsCol
                    width: list.width
                    spacing: Theme.mini ? 16 : 22
                    Repeater {
                        model: Store.projectGroups
                        ColumnLayout {
                            id: group
                            required property var modelData
                            visible: modelData.count > 0 && (projects.showing === "all" || projects.showing === modelData.status)
                            Layout.fillWidth: true
                            spacing: Theme.mini ? 8 : 10
                            RowLayout {
                                Layout.leftMargin: 4
                                spacing: 10
                                Rectangle { width: 10; height: 10; radius: 5; color: group.modelData.color }
                                Label { text: group.modelData.label; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                                Label { text: group.modelData.count; color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.features: ({ "tnum": 1 }) }
                            }
                            // The group's rows on one card; a blocked group's has a coral edge.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: rows.implicitHeight
                                radius: Theme.radiusSm
                                color: Theme.surface
                                border.width: group.modelData.status === "blocked" ? 2 : 0
                                border.color: Theme.danger
                                Column {
                                    id: rows
                                    width: parent.width
                                    Repeater {
                                        model: group.modelData.projects
                                        ProjectRow {
                                            required property var modelData
                                            required property int index
                                            width: rows.width
                                            project: modelData
                                            place: group.modelData.offset + index
                                            last: index === group.modelData.count - 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            EmptyState {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Store.projects.length === 0
                icon: "chores"
                text: qsTr("No projects yet")
                hint: qsTr("A code or task agent reports what it's working on here.")
                url: "https://mcfly.bot/agents"
                action: qsTr("Add an agent")
                caption: qsTr("Scan to open Agents on your phone: pick what it's for and it gives you the prompt to paste.")
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
                            maximumLineCount: Theme.mini ? (projects.current.hasStages ? 1 : 2) : 3
                            elide: Text.ElideRight
                        }
                        // Mini's page has no room for the stages' own card: its bar rides on the tile.
                        StageBar {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: Theme.mini && !!projects.current.hasStages
                            project: projects.current
                            onTile: true
                            ink: head.ink
                            inkMuted: head.inkMuted
                            shown: Math.min(rv.at(1), projects.detailIn)
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

            // Its stages, when the agent lays them out: the one it is in (and
            // for how long), its place, and a step per stage.
            Rectangle {
                visible: !Theme.mini && !!projects.current.hasStages
                Layout.fillWidth: true
                Layout.preferredHeight: stagesCol.implicitHeight + 2 * stagesCol.anchors.margins
                radius: Theme.radius
                color: Theme.surface
                ColumnLayout {
                    id: stagesCol
                    readonly property var track: projects.current.track || ({})
                    readonly property string hereState: track.index >= 0 && track.steps && track.index < track.steps.length ? track.steps[track.index].state : ""
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.compact ? 20 : 24
                    spacing: 14
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: qsTr("STAGES"); color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                            Label {
                                text: stagesCol.track.position || ""
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontXs
                                font.features: ({ "tnum": 1 })
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: (stagesCol.track.headline || "") + (projects.current.stageFor ? qsTr(" for %1").arg(projects.current.stageFor) : "")
                            color: stagesCol.hereState === "blocked" ? Theme.danger : stagesCol.hereState === "paused" ? Theme.warningInk : Theme.text
                            font.pixelSize: Theme.fontSm
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                    StageSteps {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        project: projects.current
                        shown: Math.min(rv.at(1), projects.detailIn)
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
