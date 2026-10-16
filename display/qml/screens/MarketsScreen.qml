import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly
import McFly.Core

// Markets: a tile per symbol with its sparkline; the one picked shows its
// history, the holding, what the agent noticed (signals), the day's numbers
// and its note, beside the grid or, on the small panels, on a page over it.
// Over the grid, the holdings summed. The Metrics segment is everything else
// the agents count, grouped.
Item {
    id: markets
    property bool shown: true
    property string selected: ""
    // "markets" (the quotes) or "metrics" (everything else the agents count).
    property string segment: "markets"
    readonly property var current: Store.quote(selected).symbol ? Store.quote(selected) : (Store.quotes[0] || ({}))
    readonly property var position: current.position || ({})
    readonly property bool rich: !!current.held || (current.signals || []).length > 0 || (current.stats || []).length > 0
                                 || (current.ranges || []).length > 0
    function closeDetail() { md.closeDetail() }
    function toneColor(tone) { return tone === "up" ? Theme.gain : tone === "down" ? Theme.loss : Theme.warning }

    // A number with its name over it, for the holdings summary.
    component SummaryStat: ColumnLayout {
        property string label
        property string value
        property color tone: Theme.text
        spacing: 0
        Label { text: parent.label.toUpperCase(); color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
        Label { text: parent.value; color: parent.tone; font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd; font.weight: Font.DemiBold; font.features: ({ "tnum": 1 }) }
    }

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

            // The holdings among these symbols, summed.
            Rectangle {
                visible: markets.segment === "markets" && !!Store.portfolio.held
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.mini ? 62 : 82
                radius: Theme.radiusSm
                color: Theme.surface
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.mini ? 16 : 22
                    anchors.rightMargin: Theme.mini ? 16 : 22
                    spacing: Theme.mini ? 18 : 36
                    SummaryStat {
                        label: Store.portfolio.count === 1 ? qsTr("Holding") : qsTr("%1 holdings").arg(Store.portfolio.count || 0)
                        value: Store.portfolio.valueLabel || ""
                    }
                    SummaryStat {
                        visible: !!Store.portfolio.dayChangeLabel
                        label: qsTr("Today")
                        value: (Store.portfolio.dayChangeLabel || "") + (Store.portfolio.dayPctLabel ? "  " + Store.portfolio.dayPctLabel : "")
                        tone: Store.portfolio.dayUp ? Theme.gain : Theme.loss
                    }
                    SummaryStat {
                        visible: !!Store.portfolio.totalChangeLabel
                        label: qsTr("Total gain")
                        value: (Store.portfolio.totalChangeLabel || "") + (Store.portfolio.totalPctLabel ? "  " + Store.portfolio.totalPctLabel : "")
                        tone: Store.portfolio.totalUp ? Theme.gain : Theme.loss
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // Metrics, grouped.
            FocusFlickable {
                id: metricsView
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
                                                Label { visible: modelData.hasDelta; text: modelData.deltaLabel; color: modelData.up ? Theme.gain : Theme.loss; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold }
                                            }
                                            Label { text: modelData.valueLabel; color: Theme.text; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Sparkline { Layout.fillWidth: true; Layout.fillHeight: true; points: modelData.history; color: modelData.up ? Theme.gain : Theme.loss; lineWidth: 2.5 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 1; visible: Store.metrics.length === 0 }
                }
                // Over the view, not in its (empty) content.
                EmptyState {
                    parent: metricsView
                    anchors.fill: parent
                    visible: Store.metrics.length === 0
                    icon: "chart"
                    text: qsTr("No metrics yet")
                    hint: qsTr("Agents send the numbers you track: sign-ups, uptime, revenue.")
                    url: "https://mcfly.bot/agents"
                    action: qsTr("Add an agent")
                    caption: qsTr("Scan to open Agents on your phone: pick what it's for and it gives you the prompt to paste.")
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
                                spacing: 8
                                Label { text: modelData.symbol; color: Theme.text; font.pixelSize: Theme.fontMd - 2; font.weight: Font.Bold; Layout.maximumWidth: tile.width * 0.55; elide: Text.ElideRight }
                                // The agent noticed something: its first signal's tone.
                                Rectangle {
                                    visible: modelData.signals.length > 0
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: 9; implicitHeight: 9; radius: 4.5
                                    color: markets.toneColor(modelData.signalTone)
                                }
                                Item { Layout.fillWidth: true }
                                Label {
                                    text: modelData.pctLabel
                                    color: modelData.up ? Theme.gain : Theme.loss
                                    font.pixelSize: Theme.fontSm
                                    font.weight: Font.DemiBold
                                }
                            }
                            // The holding, else the name; neither on Mini (the detail has them).
                            RowLayout {
                                visible: !Theme.mini
                                Layout.fillWidth: true
                                spacing: 6
                                Label {
                                    text: modelData.held ? [modelData.position.sharesLabel, modelData.position.valueLabel].filter(s => !!s).join(" · ") : (modelData.name || "")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontXs
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Label {
                                    visible: modelData.held && !!modelData.position.totalPctLabel
                                    text: modelData.position.totalPctLabel || ""
                                    color: modelData.position.totalUp ? Theme.gain : Theme.loss
                                    font.pixelSize: Theme.fontXs
                                    font.weight: Font.DemiBold
                                }
                            }
                            Sparkline {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                points: modelData.history
                                color: modelData.up ? Theme.gain : Theme.loss
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
                    icon: "chart"
                    text: qsTr("No quotes yet")
                    hint: qsTr("A stocks agent sends the symbols you follow.")
                    url: "https://mcfly.bot/agents"
                    action: qsTr("Add an agent")
                    caption: qsTr("Scan to open Agents on your phone: pick what it's for and it gives you the prompt to paste.")
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
            // Scrolls when the holding, signals and numbers outgrow the tile.
            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: Theme.mini ? 20 : Theme.compact ? 24 : 32
                contentHeight: body.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Connections {
                    target: markets
                    function onSelectedChanged() { flick.contentY = 0 }
                }
                ColumnLayout {
                    id: body
                    width: flick.width
                    height: Math.max(implicitHeight, flick.height)
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
                        // Shorter when there is more to read under it.
                        Layout.preferredHeight: markets.rich ? (Theme.mini ? 56 : Theme.compact ? 84 : 110)
                                                             : (Theme.mini ? 80 : Theme.compact ? 120 : 160)
                        points: markets.current.history || []
                        color: detail.strong
                        lineWidth: 4
                    }

                    // The holding.
                    ColumnLayout {
                        visible: !!markets.current.held
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 2
                        Label { text: qsTr("YOUR POSITION"); color: detail.inkMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        Label { text: markets.position.valueLabel || ""; color: detail.ink; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold; font.features: ({ "tnum": 1 }) }
                        // The gain since bought, then today's.
                        Label {
                            visible: !!markets.position.totalChangeLabel
                            text: markets.position.totalPctLabel ? qsTr("%1 (%2) overall").arg(markets.position.totalChangeLabel || "").arg(markets.position.totalPctLabel)
                                                                 : qsTr("%1 overall").arg(markets.position.totalChangeLabel || "")
                            color: detail.strong
                            font.pixelSize: Theme.fontSm
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                        }
                        Label {
                            visible: !!markets.position.dayChangeLabel
                            text: qsTr("%1 today").arg(markets.position.dayChangeLabel || "")
                            color: detail.ink
                            font.pixelSize: Theme.fontSm
                            font.features: ({ "tnum": 1 })
                        }
                        Label {
                            Layout.fillWidth: true
                            text: [markets.position.sharesLabel, markets.position.avgCostLabel, markets.position.weightLabel].filter(s => !!s).join(" · ")
                            color: detail.inkMuted
                            font.pixelSize: Theme.fontSm
                            wrapMode: Text.WordWrap
                        }
                    }

                    // What the agent noticed: facts, each with its direction.
                    ColumnLayout {
                        visible: (markets.current.signals || []).length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 4
                        Label { text: qsTr("SIGNALS"); color: detail.inkMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        Repeater {
                            model: markets.current.signals || []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                Label {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 2
                                    text: modelData.tone === "up" ? "▲" : modelData.tone === "down" ? "▼" : "●"
                                    color: detail.strong
                                    font.pixelSize: Theme.fontXs
                                }
                                Label { Layout.fillWidth: true; text: modelData.text; color: detail.ink; font.pixelSize: Theme.fontSm; wrapMode: Text.WordWrap }
                            }
                        }
                    }

                    // Where the price sits between today's and the year's low and high.
                    Repeater {
                        model: markets.current.ranges || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 4
                            Label { text: modelData.label; color: detail.inkMuted; font.pixelSize: Theme.fontXs }
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 12
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: detail.inkMuted; opacity: 0.45 }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.round(modelData.pos * (parent.width - width))
                                    width: 12; height: 12; radius: 6
                                    color: detail.ink
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: modelData.lowLabel; color: detail.ink; font.pixelSize: Theme.fontXs; font.features: ({ "tnum": 1 }); Layout.fillWidth: true }
                                Label { text: modelData.highLabel; color: detail.ink; font.pixelSize: Theme.fontXs; font.features: ({ "tnum": 1 }) }
                            }
                        }
                    }

                    // The day's numbers.
                    GridLayout {
                        visible: (markets.current.stats || []).length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        columns: md.paned || Theme.tall ? 2 : 3
                        columnSpacing: 16
                        rowSpacing: 8
                        Repeater {
                            model: markets.current.stats || []
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 0
                                Label { Layout.fillWidth: true; text: modelData.label; color: detail.inkMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    color: detail.ink
                                    font.pixelSize: Theme.fontSm
                                    font.weight: Font.DemiBold
                                    font.features: ({ "tnum": 1 })
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: text.length > 0
                        text: markets.current.note || ""
                        color: detail.ink
                        font.pixelSize: Theme.fontMd - 2
                        wrapMode: Text.WordWrap
                        lineHeight: 1.15
                    }
                    Item { Layout.fillHeight: true }
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
}
