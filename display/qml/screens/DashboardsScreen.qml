import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Dashboards: the boards agents lay out themselves, one at a time, as a
// bento of widgets: metrics, statuses, progress, charts, lists and notes.
// Six columns on a wall, four on the panel, two on the small ones.
//
// Store.boardLayout packs the board with no holes: its first metric as a
// 2×2 hero (from four columns up), two or more statuses in a row as one
// health strip across (a row taller for each row a long run wraps to),
// charts wide and two rows tall. The tiles are placed
// by hand from that, and keep their delegates when the board or the tier
// changes, so they glide to their new places rather than blinking. A status
// that needs a look breathes; progress is a ring.
Item {
    id: boards
    property bool shown: true
    // The page picked, under the assistant panel too: it settles in as
    // this turns true, not again when the panel goes.
    property bool isCurrent: true
    property int index: 0
    readonly property int shownIndex: Math.min(index, Math.max(0, Store.dashboards.length - 1))
    readonly property var board: Store.dashboards[shownIndex] || ({})
    readonly property var widgets: board.widgets || []
    readonly property int columns: Theme.widgetColumns
    // boardLayout doesn't notify; reading Store.dashboards follows a sync.
    readonly property var cells: Store.dashboards.length > 0 ? Store.boardLayout(shownIndex, columns) : []
    // As many tiles as the fullest board needs, made once: a change of board
    // reuses them, so they move instead of being made again.
    readonly property int slots: {
        let n = 0
        for (let i = 0; i < Store.dashboards.length; ++i)
            n = Math.max(n, Store.boardLayout(i, columns).length)
        return n
    }
    // Loops run only while someone can see them.
    readonly property bool moving: shown && !Device.idle && Device.animatedTiles

    Reveal { id: rv; shown: boards.isCurrent }

    // Tiles glide only just after the board or the tier changed, never as a
    // sync or the first layout puts them in place (the tier is set once the
    // window is up, after the tiles are made).
    property bool gliding: false
    property bool _placed: false
    Component.onCompleted: Qt.callLater(() => boards._placed = true)
    function glide() {
        gliding = moving && _placed && boardsView.width > 0
        glideOff.restart()
    }
    onShownIndexChanged: glide()
    onColumnsChanged: glide()
    Timer { id: glideOff; interval: Theme.glide + 100; onTriggered: boards.gliding = false }

    // ---- Geometry: columns of equal width; a row is a widget row tall, or
    // taller where a list or a note sits in it alone.
    readonly property real gap: Theme.spacing
    readonly property real colWidth: (boardsView.width - (columns - 1) * gap) / columns
    readonly property var rowHeights: {
        const rows = cells.reduce((n, c) => Math.max(n, c.row + c.rowSpan), 0)
        const out = []
        for (let r = 0; r < rows; ++r)
            out.push(Theme.widgetRowHeight)
        for (const c of cells)
            if ((c.kind === "list" || c.kind === "text") && c.rowSpan === 1)
                out[c.row] = Theme.widgetRowHeight + 40
        return out
    }
    readonly property var rowTops: {
        const out = []
        let y = 0
        for (const h of rowHeights) {
            out.push(y)
            y += h + gap
        }
        out.push(y)
        return out
    }
    readonly property real contentHeight: rowHeights.length > 0 ? rowTops[rowHeights.length] - gap : 0
    function cellHeight(c) { return rowTops[c.row + c.rowSpan] - rowTops[c.row] - gap }

    // Everything but the hero and the health strip sits on a plain card.
    component Plain: Rectangle {
        radius: Theme.radiusSm
        color: Theme.surface
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: 14

        ScreenHeader {
            Layout.fillWidth: true
            title: boards.board.title || qsTr("Dashboards")
            subtitle: boards.board.subtitle ? boards.board.subtitle + (boards.board.updatedLabel ? " · " + boards.board.updatedLabel : "")
                    : boards.board.updatedLabel ? qsTr("Updated %1 by %2").arg(boards.board.updatedLabel).arg(boards.board.agentName) : ""
            // One chip per board.
            ChipRow {
                Layout.fillWidth: true
                visible: Store.dashboards.length > 1
                model: Store.dashboards.map((d, i) => ({ id: String(i), label: d.title }))
                current: String(boards.shownIndex)
                onPicked: id => boards.index = parseInt(id)
            }
        }

        FocusFlickable {
            id: boardsView
            Layout.fillWidth: true
            Layout.fillHeight: true
            fadeColor: Theme.background
            contentHeight: boards.contentHeight
            clip: true

            Repeater {
                model: boards.slots
                delegate: Item {
                    id: tile
                    objectName: "tile"
                    required property int index
                    readonly property var cell: boards.cells[index] || null
                    readonly property var widget: cell ? boards.widgets[cell.index] || ({}) : ({})
                    readonly property string kind: cell ? cell.kind : ""
                    visible: !!cell
                    x: cell ? cell.col * (boards.colWidth + boards.gap) : 0
                    y: cell ? boards.rowTops[cell.row] : 0
                    width: cell ? cell.colSpan * boards.colWidth + (cell.colSpan - 1) * boards.gap : 0
                    height: cell ? boards.cellHeight(cell) : 0
                    opacity: rv.at(index)
                    Behavior on x {
                        enabled: boards.gliding
                        NumberAnimation { duration: Theme.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
                    }
                    Behavior on y {
                        enabled: boards.gliding
                        NumberAnimation { duration: Theme.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
                    }

                    Loader {
                        anchors.fill: parent
                        sourceComponent: tile.kind === "hero" ? heroView
                                       : tile.kind === "health" ? healthView
                                       : tile.kind === "metric" ? metricView
                                       : tile.kind === "status" ? statusView
                                       : tile.kind === "progress" ? progressView
                                       : tile.kind === "chart" ? chartView
                                       : tile.kind === "list" ? listView
                                       : tile.kind === "text" ? textView : null
                    }

                    // The board's first metric, large, on a gradient tile.
                    Component {
                        id: heroView
                        GradientTile {
                            id: hero
                            radius: Theme.radiusSm + 6
                            baseColor: Theme.accent
                            active: boards.shown
                            seed: 6.1
                            rings: 1
                            ringBias: 0.8
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.compact ? 22 : 28
                                spacing: 4
                                Label {
                                    Layout.fillWidth: true
                                    text: (tile.widget.label || "").toUpperCase()
                                    color: hero.inkMuted
                                    font.pixelSize: Theme.fontXs
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                    elide: Text.ElideRight
                                }
                                Item { Layout.fillHeight: true }
                                Label {
                                    Layout.fillWidth: true
                                    text: tile.widget.valueLabel || ""
                                    color: hero.ink
                                    font.pixelSize: Theme.wide ? 88 : 72
                                    font.weight: Font.Light
                                    font.letterSpacing: -2
                                    font.features: ({ "tnum": 1 })
                                    fontSizeMode: Text.HorizontalFit
                                    minimumPixelSize: Theme.fontXl
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    visible: !!tile.widget.hasDelta
                                    spacing: 8
                                    Icon { name: tile.widget.up ? "arrow-up" : "arrow-down"; size: 20; color: hero.strong }
                                    Label {
                                        text: tile.widget.deltaLabel || ""
                                        color: hero.ink
                                        font.pixelSize: Theme.fontMd
                                        font.weight: Font.DemiBold
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }
                        }
                    }

                    // Two or more statuses in a row, as one strip (wrapped when long).
                    Component {
                        id: healthView
                        HealthStrip {
                            statuses: (tile.cell ? tile.cell.indexes : []).map(i => boards.widgets[i] || ({}))
                            summary: tile.cell ? tile.cell.summary || "" : ""
                            stateColor: tile.cell && tile.cell.stateColor ? tile.cell.stateColor : Theme.textMuted
                            perRow: tile.cell ? tile.cell.perRow || statuses.length : 0
                            running: boards.moving
                        }
                    }

                    Component {
                        id: metricView
                        Plain {
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.mini ? 14 : 18
                                spacing: 4
                                Label { Layout.fillWidth: true; text: tile.widget.label || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight }
                                Item { Layout.fillHeight: true }
                                Label { Layout.fillWidth: true; text: tile.widget.valueLabel || ""; color: Theme.text; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Label {
                                    visible: !!tile.widget.hasDelta
                                    text: tile.widget.deltaLabel || ""
                                    color: (tile.widget.good ?? tile.widget.up) ? Theme.gain : Theme.loss
                                    font.pixelSize: Theme.fontXs
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    Component {
                        id: statusView
                        Plain {
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.mini ? 14 : 18
                                spacing: 6
                                RowLayout {
                                    spacing: 10
                                    StatusDot {
                                        size: 16
                                        color: tile.widget.stateColor || Theme.textMuted
                                        breathing: tile.widget.state === "warn" || tile.widget.state === "down"
                                        running: boards.moving
                                    }
                                    Label { text: tile.widget.label || ""; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Label { text: tile.widget.stateLabel || ""; color: tile.widget.stateColor || Theme.text; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold }
                                Label { Layout.fillWidth: true; visible: !!tile.widget.detail; text: tile.widget.detail || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }

                    // Progress as a ring, the value in its middle.
                    Component {
                        id: progressView
                        Plain {
                            id: progressCard
                            readonly property real ringSize: Math.min(height - (Theme.mini ? 28 : 36), Theme.mini ? 76 : 96)
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.mini ? 14 : 18
                                spacing: 14
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 4
                                    Label { Layout.fillWidth: true; text: tile.widget.label || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight }
                                    Item { Layout.fillHeight: true }
                                    Label {
                                        Layout.fillWidth: true
                                        // The ring holds a percentage; a count ("14 / 20") reads beside it.
                                        visible: (tile.widget.valueLabel || "").indexOf("/") >= 0
                                        text: tile.widget.valueLabel || ""
                                        color: Theme.text
                                        font.pixelSize: Theme.fontMd
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                }
                                Ring {
                                    Layout.preferredWidth: progressCard.ringSize
                                    Layout.preferredHeight: progressCard.ringSize
                                    Layout.alignment: Qt.AlignVCenter
                                    value: tile.widget.fraction || 0
                                    shown: rv.at(tile.index + 1)
                                    color: Theme.accent
                                    Label {
                                        anchors.centerIn: parent
                                        text: Math.round((tile.widget.fraction || 0) * 100) + "%"
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSm
                                        font.weight: Font.DemiBold
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }
                        }
                    }

                    // A chart, drawn on from the left as the board settles.
                    Component {
                        id: chartView
                        Plain {
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.mini ? 14 : 18
                                spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: tile.widget.label || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Label { text: tile.widget.valueLabel || ""; color: Theme.text; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                                }
                                Sparkline {
                                    objectName: "chart"
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    points: tile.widget.points || []
                                    color: Theme.accent
                                    progress: rv.at(tile.index + 2)
                                }
                            }
                        }
                    }

                    Component {
                        id: listView
                        Plain {
                            id: listCard
                            // As many as fit the tile.
                            readonly property int fits: Math.max(1, Math.floor((height - (Theme.mini ? 28 : 36) - 26) / 30))
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.mini ? 14 : 18
                                spacing: 6
                                Label { visible: !!tile.widget.title; text: tile.widget.title || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                                Repeater {
                                    model: (tile.widget.items || []).slice(0, listCard.fits)
                                    delegate: RowLayout {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Rectangle { width: 6; height: 6; radius: 3; color: Theme.accent }
                                        Label { Layout.fillWidth: true; text: modelData; color: Theme.text; font.pixelSize: Theme.fontSm; elide: Text.ElideRight }
                                    }
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }

                    Component {
                        id: textView
                        Plain {
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.mini ? 14 : 18
                                spacing: 6
                                Label { visible: !!tile.widget.title; text: tile.widget.title || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { Layout.fillWidth: true; Layout.fillHeight: true; text: tile.widget.body || ""; color: Theme.text; font.pixelSize: Theme.fontSm; wrapMode: Text.WordWrap; elide: Text.ElideRight; verticalAlignment: Text.AlignTop }
                            }
                        }
                    }
                }
            }

            // Over the view, not in its (empty, zero-height) content.
            EmptyState {
                parent: boardsView
                anchors.fill: parent
                visible: Store.dashboards.length === 0
                icon: "grid"
                text: qsTr("No dashboards yet")
                hint: qsTr("An agent sends one with a title and its widgets.")
                url: "https://mcfly.bot/agents"
                action: qsTr("Add an agent")
                caption: qsTr("Scan to open Agents on your phone: pick what it's for and it gives you the prompt to paste.")
            }
        }
    }
}
