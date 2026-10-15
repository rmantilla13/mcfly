import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Markets: a tile per symbol with its sparkline; the one picked shows its
// history, its note and where it came from, beside the grid or, on the
// small panels, on a page over it. The Metrics segment is everything else
// the agents count, grouped.
Item {
    id: markets
    property bool shown: true
    property string selected: ""
    // "markets" (the quotes) or "metrics" (everything else the agents count).
    property string segment: "markets"
    readonly property var current: Store.quote(selected).symbol ? Store.quote(selected) : (Store.quotes[0] || ({}))
    function closeDetail() { md.closeDetail() }

    MasterDetail {
        id: md
        anchors.fill: parent
        paneWidth: Theme.paneWidth
        hasDetail: markets.segment === "markets" && !!markets.current.symbol
        detailTitle: markets.current.symbol || ""
        detailSubtitle: markets.current.name || ""

        master: ColumnLayout {
            anchors.fill: parent
            spacing: 14
            ScreenHeader {
                Layout.fillWidth: true
                title: markets.segment === "metrics" ? qsTr("Metrics") : qsTr("Markets")
                subtitle: markets.segment === "metrics" ? (Store.metrics.length > 0 ? qsTr("As of %1").arg(Store.metrics[0].asOfLabel) : "")
                        : (Store.quotes.length > 0 ? qsTr("As of %1").arg(Store.quotes[0].asOfLabel) : "")
                ChipRow {
                    model: [{ id: "markets", label: qsTr("Markets") }, { id: "metrics", label: qsTr("Metrics") }]
                    current: markets.segment
                    onPicked: id => markets.segment = id
                }
            }

            // Metrics, grouped.
            FocusFlickable {
                visible: markets.segment === "metrics"
                Layout.fillWidth: true
                Layout.fillHeight: true
                fadeColor: Theme.background
                contentHeight: metricsCol.implicitHeight
                clip: true
                ColumnLayout {
                    id: metricsCol
                    width: parent.width
                    spacing: 16
                    Repeater {
                        model: Store.metricGroups
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            Label { text: modelData.name.toUpperCase(); color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: Theme.metricColumns
                                columnSpacing: Theme.spacing
                                rowSpacing: Theme.spacing
                                Repeater {
                                    model: modelData.metrics
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: Theme.mini ? 120 : 150
                                        radius: Theme.radiusSm
                                        color: Theme.surface
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 16
                                            spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Label { text: modelData.label; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                                                Label { visible: modelData.hasDelta; text: modelData.deltaLabel; color: modelData.up ? Theme.success : Theme.glowCoral; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold }
                                            }
                                            Label { text: modelData.valueLabel; color: Theme.text; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Sparkline { Layout.fillWidth: true; Layout.fillHeight: true; points: modelData.history; color: modelData.up ? Theme.success : Theme.glowCoral; lineWidth: 2.5 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 1; visible: Store.metrics.length === 0 }
                }
                EmptyState {
                    anchors.fill: parent
                    visible: Store.metrics.length === 0
                    text: qsTr("No metrics yet.")
                    hint: qsTr("Agents push numbers to McFly; see docs/AGENTS.md.")
                }
            }

            GridView {
                id: grid
                visible: markets.segment === "markets"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Store.quotes
                cellWidth: Math.floor(width / Theme.quoteColumns)
                cellHeight: Theme.quoteTileHeight
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    Rectangle {
                        id: tile
                        anchors.fill: parent
                        anchors.rightMargin: Theme.spacing
                        anchors.bottomMargin: Theme.spacing
                        readonly property bool chosen: md.paned && modelData.symbol === markets.current.symbol
                        radius: Theme.radiusSm
                        color: chosen ? Theme.accentSoft : Theme.surface
                        border.width: chosen ? 2 : 0
                        border.color: Theme.accent
                        scale: tileTap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.quick } }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.mini ? 14 : 18
                            spacing: Theme.mini ? 2 : 4
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: modelData.symbol; color: Theme.text; font.pixelSize: Theme.fontMd - 2; font.weight: Font.Bold; Layout.fillWidth: true; elide: Text.ElideRight }
                                Label {
                                    text: modelData.pctLabel
                                    color: modelData.up ? Theme.success : Theme.glowCoral
                                    font.pixelSize: Theme.fontSm
                                    font.weight: Font.DemiBold
                                }
                            }
                            // The name goes on Mini (the detail has it).
                            Label { visible: !Theme.mini; text: modelData.name || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                            Sparkline {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                points: modelData.history
                                color: modelData.up ? Theme.success : Theme.glowCoral
                                lineWidth: Theme.mini ? 2 : 3
                            }
                            Label { text: modelData.priceLabel; color: Theme.text; font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd; font.weight: Font.Medium }
                        }
                        TapHandler { id: tileTap; onTapped: { markets.selected = modelData.symbol; md.open() } }
                    }
                }
                EmptyState {
                    anchors.fill: parent
                    visible: Store.quotes.length === 0
                    text: qsTr("No quotes yet.")
                    hint: qsTr("A stocks agent pushes them to McFly; see docs/AGENTS.md.")
                }
            }
        }

        // The picked symbol.
        detail: GradientTile {
            id: detail
            anchors.fill: parent
            radius: Theme.radius
            baseColor: markets.current.up ? "#3DB37A" : "#F07F5A"
            active: markets.shown && (md.paned || md.pushed)
            seed: 3.3
            rings: 1
            ringBias: 0.8
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.mini ? 20 : Theme.compact ? 24 : 32
                spacing: Theme.mini ? 6 : 10
                Label { visible: md.paned; text: markets.current.symbol || ""; color: detail.ink; font.pixelSize: Theme.fontLg; font.weight: Font.Bold }
                Label { visible: md.paned; text: markets.current.name || ""; color: detail.inkMuted; font.pixelSize: Theme.fontSm; elide: Text.ElideRight; Layout.fillWidth: true }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Label { text: markets.current.priceLabel || ""; color: detail.ink; font.pixelSize: Theme.mini ? 40 : Theme.compact ? 48 : 56; font.weight: Font.Light }
                    RowLayout {
                        visible: !md.paned
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 8
                        spacing: 8
                        Icon { name: markets.current.up ? "arrow-up" : "arrow-down"; size: 20; color: detail.strong }
                        Label { text: (markets.current.changeLabel || "") + "  " + (markets.current.pctLabel || ""); color: detail.strong; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold }
                    }
                }
                RowLayout {
                    visible: md.paned
                    spacing: 8
                    Icon { name: markets.current.up ? "arrow-up" : "arrow-down"; size: 20; color: detail.strong }
                    Label { text: (markets.current.changeLabel || "") + "  " + (markets.current.pctLabel || ""); color: detail.strong; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold }
                }
                Sparkline {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.mini ? 80 : Theme.compact ? 120 : 160
                    points: markets.current.history || []
                    color: detail.strong
                    lineWidth: 4
                }
                Label {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: text.length > 0
                    text: markets.current.note || ""
                    color: detail.ink
                    font.pixelSize: Theme.fontMd - 2
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignTop
                    lineHeight: 1.15
                    elide: Text.ElideRight
                }
                Item { Layout.fillHeight: true; visible: !(markets.current.note || "").length }
                Label {
                    text: qsTr("%1 · %2 · %3 points").arg(markets.current.agentName || "").arg(markets.current.asOfLabel || "").arg((markets.current.history || []).length)
                    color: detail.inkMuted
                    font.pixelSize: Theme.fontXs
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }
}
