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
//
// How the day went across the symbols is a bar of ups and downs (breadth).
// A tile's line draws on as the page settles; a price pushed in the last
// minutes sends a slow ring out from its newest point; a price this display
// saw change slides in from the way it moved. Under the line, where the
// price sits between its low and high. Portrait has room under the grid:
// the biggest mover, large. Metrics are coloured by whether the move is the
// good way for that number, not by up or down.
Item {
    id: markets
    property bool shown: true
    // The page picked, under the assistant panel too: it settles in as
    // this turns true, not again when the panel goes.
    property bool isCurrent: true
    // Loops run only while someone can see them.
    readonly property bool moving: shown && !Device.idle && Device.animatedTiles
    Reveal { id: rv; shown: markets.isCurrent }
    // A value this display saw change in the last few seconds slides in.
    function justChanged(row) { return !!row && row.changedMs > 0 && Date.now() - row.changedMs < 3000 }
    // The end dot pings for a couple of minutes after a value moves, not for
    // as long as the feed is live. Read at each sync's rebuild, which is enough.
    function justMoved(row) { return !!row && row.changedMs > 0 && Date.now() - row.changedMs < 120000 }
    // The detail's line, drawn on again for each symbol picked.
    property real detailIn: 1
    NumberAnimation { id: detailAnim; target: markets; property: "detailIn"; from: 0; to: 1; duration: Theme.revealDuration; easing.type: Easing.OutCubic }
    function pick(symbol) {
        const again = symbol !== current.symbol
        selected = symbol
        md.open()
        if (again && Device.animatedTiles)
            detailAnim.restart()
    }
    // Portrait's featured symbol: the mover McFly singled out, else the one
    // that moved most today.
    readonly property var featured: {
        const mover = Store.highlights.find(h => h.kind === "mover")
        const q = mover ? Store.quote(mover.itemId) : ({})
        // Its detail without the price ("$402.10 · 4.8× its usual daily move"): the tile shows that large.
        if (q.symbol)
            return Object.assign({ why: (mover.detail || "").split(" · ").slice(1).join(" · ") }, q)
        let best = null
        for (const row of Store.quotes)
            if (!best || Math.abs(row.heat || 0) > Math.abs(best.heat || 0))
                best = row
        return best || ({})
    }
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

    // Where a value sits between its low and its high: a track and a dot.
    component RangeBar: Item {
        id: range
        property real pos: 0.5
        property color tone: Theme.accent
        property color track: Theme.sunken
        implicitHeight: 12
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: range.track }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: Math.round(Math.max(0, Math.min(1, range.pos)) * (range.width - width))
            width: 12; height: 12; radius: 6
            color: range.tone
            border.width: 2
            border.color: Theme.surface
        }
    }

    // A price that slides in from the way it moved when this display saw it
    // change a moment ago (changedMs), a tint behind it fading as it lands.
    // Checked as the tile is made: a sync makes them all again.
    component Price: Item {
        id: price
        property var row: ({})
        property alias label: priceLabel
        implicitWidth: priceLabel.implicitWidth
        implicitHeight: priceLabel.implicitHeight
        Rectangle {
            id: tint
            anchors.fill: priceLabel
            anchors.margins: -4
            anchors.leftMargin: -8
            anchors.rightMargin: -8
            radius: 8
            color: price.row.changedUp ? Theme.gain : Theme.loss
            opacity: 0
            visible: swap.running
        }
        Label {
            id: priceLabel
            text: price.row.priceLabel || ""
            color: Theme.text
            font.features: ({ "tnum": 1 })
            transform: Translate { id: shift }
        }
        function play() {
            if (!markets.moving || !markets.justChanged(row))
                return
            slide.from = row.changedUp ? 14 : -14
            swap.restart()
        }
        // A tile's row is set as it is made; the detail's changes with each sync.
        onRowChanged: play()
        Component.onCompleted: play()
        ParallelAnimation {
            id: swap
            NumberAnimation { id: slide; target: shift; property: "y"; to: 0; duration: Theme.enter; easing.type: Easing.OutCubic }
            OpacityAnimator { target: priceLabel; from: 0; to: 1; duration: Theme.enter; easing.type: Easing.OutCubic }
            SequentialAnimation {
                OpacityAnimator { target: tint; from: 0; to: 0.22; duration: Theme.enter }
                OpacityAnimator { target: tint; from: 0.22; to: 0; duration: 1400; easing.type: Easing.InOutSine }
            }
        }
    }

    // Ups and downs across the symbols today, end to end.
    component Breadth: RowLayout {
        id: breadth
        readonly property var b: Store.marketBreadth
        visible: (b.total || 0) > 0
        spacing: 14
        Label { text: breadth.b.label || ""; color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.features: ({ "tnum": 1 }) }
        Item {
            id: bar
            Layout.fillWidth: true
            implicitHeight: 8
            readonly property real total: Math.max(1, breadth.b.total || 0)
            // It sweeps in from the left with the page.
            transform: Scale { xScale: rv.at(1) }
            Rectangle {
                id: ups
                // A 2 px gap before whatever follows it.
                width: Math.max(0, bar.width * (breadth.b.up || 0) / bar.total - ((breadth.b.flat || 0) + (breadth.b.down || 0) > 0 ? 2 : 0))
                height: parent.height; radius: 4
                color: Theme.gain
                visible: (breadth.b.up || 0) > 0
            }
            Rectangle {
                x: ups.visible ? ups.width + 2 : 0
                width: Math.max(0, bar.width * (breadth.b.flat || 0) / bar.total - ((breadth.b.down || 0) > 0 ? 2 : 0))
                height: parent.height; radius: 4
                color: Theme.divider
                visible: (breadth.b.flat || 0) > 0
            }
            Rectangle {
                id: downs
                anchors.right: parent.right
                width: Math.max(0, bar.width * (breadth.b.down || 0) / bar.total)
                height: parent.height; radius: 4
                color: Theme.loss
                visible: (breadth.b.down || 0) > 0
            }
        }
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
                        : Store.quotes.length === 0 ? ""
                        // The 7" panel has no row to spare for the breadth bar: its words go here.
                        : Theme.mini && Store.marketBreadth.label ? qsTr("As of %1").arg(Store.quotes[0].asOfLabel) + " · " + Store.marketBreadth.label
                        : qsTr("As of %1").arg(Store.quotes[0].asOfLabel)
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

            Breadth {
                Layout.fillWidth: true
                visible: markets.segment === "markets" && !Theme.mini && (Store.marketBreadth.total || 0) > 0
                opacity: rv.at(1)
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
                            id: group
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 10
                            opacity: rv.at(index + 1)
                            transform: Translate { y: rv.rise(group.index + 1) }
                            Label { text: modelData.name.toUpperCase(); color: Theme.textMuted; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: Theme.metricColumns
                                columnSpacing: Theme.spacing
                                rowSpacing: Theme.spacing
                                Repeater {
                                    model: modelData.metrics
                                    delegate: Rectangle {
                                        id: metric
                                        required property var modelData
                                        // The good way for this number (fewer errors is good news).
                                        readonly property color tone: modelData.trend === "flat" ? Theme.textMuted : modelData.good ? Theme.gain : Theme.loss
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: Theme.mini ? 120 : 150
                                        radius: Theme.radiusSm
                                        color: Theme.surface
                                        // Far off its usual: an edge in its colour.
                                        border.width: modelData.anomaly ? 2 : 0
                                        border.color: tone
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 16
                                            spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Label { text: metric.modelData.label; color: Theme.textMuted; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; Layout.fillWidth: true }
                                                Label {
                                                    visible: metric.modelData.hasDelta
                                                    text: (metric.modelData.trend === "up" ? "\u25B2 " : metric.modelData.trend === "down" ? "\u25BC " : "") + metric.modelData.deltaLabel
                                                    color: metric.tone
                                                    font.pixelSize: Theme.fontXs
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10
                                                Price { row: metric.modelData; label.text: metric.modelData.valueLabel; label.font.pixelSize: Theme.fontLg; label.font.weight: Font.DemiBold }
                                                Label {
                                                    Layout.fillWidth: true
                                                    visible: !Theme.mini && !!metric.modelData.usualLabel
                                                    text: qsTr("usually %1").arg(metric.modelData.usualLabel || "")
                                                    color: Theme.textMuted
                                                    font.pixelSize: Theme.fontXs
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            Sparkline {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                points: metric.modelData.history
                                                color: metric.tone
                                                lineWidth: 2.5
                                                progress: rv.at(group.index + 2)
                                                pulse: markets.justMoved(metric.modelData)
                                                running: markets.moving && markets.segment === "metrics"
                                            }
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

            // The tiles; in portrait, the biggest mover large under them
            // when the grid leaves the lower half empty.
            Item {
                id: gridArea
                visible: markets.segment === "markets"
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property real rowsHeight: Math.ceil(Store.quotes.length / Theme.quoteColumns) * grid.cellHeight
                readonly property bool featuring: Theme.tall && !!markets.featured.symbol
                                                  && height - rowsHeight - Theme.spacing >= 300

                GridView {
                    id: grid
                    width: parent.width
                    height: gridArea.featuring ? gridArea.rowsHeight : parent.height
                    interactive: !gridArea.featuring
                    clip: true
                    model: Store.quotes
                    cellWidth: Math.floor(width / Theme.quoteColumns)
                    cellHeight: Theme.quoteTileHeight
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight
                        opacity: rv.at(index + 1)
                        transform: Translate { y: rv.rise(cell.index + 1) }
                        Rectangle {
                            id: tile
                            anchors.fill: parent
                            anchors.rightMargin: Theme.spacing
                            anchors.bottomMargin: Theme.spacing
                            readonly property bool chosen: md.paned && modelData.symbol === markets.current.symbol
                            readonly property color tone: modelData.up ? Theme.gain : Theme.loss
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
                                        color: tile.tone
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
                                    color: tile.tone
                                    lineWidth: Theme.mini ? 2 : 3
                                    // Drawn on a beat after its tile arrives.
                                    progress: rv.at(cell.index + 2)
                                    pulse: markets.justMoved(modelData)
                                    running: markets.moving && markets.segment === "markets"
                                }
                                // The price, and where it sits between its low and high.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 14
                                    Price {
                                        row: cell.modelData
                                        label.font.pixelSize: Theme.mini ? Theme.fontSm : Theme.fontMd
                                        label.font.weight: Font.Medium
                                    }
                                    RangeBar {
                                        visible: !Theme.mini && cell.modelData.high > cell.modelData.low
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 140
                                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                        pos: cell.modelData.rangePos
                                        tone: tile.tone
                                    }
                                }
                            }
                            TapHandler { id: tileTap; onTapped: markets.pick(modelData.symbol) }
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

                // Portrait: the featured symbol, large, filling the room under the grid.
                GradientTile {
                    id: hero
                    readonly property var q: markets.featured
                    visible: gridArea.featuring
                    y: gridArea.rowsHeight
                    width: parent.width - Theme.spacing
                    height: Math.max(0, gridArea.height - gridArea.rowsHeight)
                    radius: Theme.radius
                    baseColor: q.up ? "#3DB37A" : "#F07F5A"
                    active: markets.shown && visible && !md.pushed
                    seed: 7.7
                    rings: 1
                    ringBias: 0.8
                    opacity: rv.at(Store.quotes.length + 1)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 26
                        spacing: 8
                        Label {
                            Layout.fillWidth: true
                            text: (hero.q.why || qsTr("Biggest move today")).toUpperCase()
                            color: hero.inkMuted
                            font.pixelSize: Theme.fontXs
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Label { text: hero.q.symbol || ""; color: hero.ink; font.pixelSize: Theme.fontXl; font.weight: Font.Bold }
                            Label { Layout.fillWidth: true; text: hero.q.name || ""; color: hero.inkMuted; font.pixelSize: Theme.fontSm; elide: Text.ElideRight; Layout.alignment: Qt.AlignBaseline }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            Label { text: hero.q.priceLabel || ""; color: hero.ink; font.pixelSize: 56; font.weight: Font.Light; font.features: ({ "tnum": 1 }) }
                            RowLayout {
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 8
                                spacing: 8
                                Icon { name: hero.q.up ? "arrow-up" : "arrow-down"; size: 20; color: hero.strong }
                                Label { text: (hero.q.changeLabel || "") + "  " + (hero.q.pctLabel || ""); color: hero.strong; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold }
                            }
                        }
                        Sparkline {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 60
                            points: hero.q.history || []
                            color: hero.strong
                            lineWidth: 4
                            progress: rv.at(Store.quotes.length + 2)
                            pulse: markets.justMoved(hero.q)
                            running: markets.moving && hero.visible
                        }
                        ColumnLayout {
                            visible: (hero.q.high || 0) > (hero.q.low || 0)
                            Layout.fillWidth: true
                            spacing: 4
                            RangeBar {
                                Layout.fillWidth: true
                                pos: hero.q.rangePos || 0
                                tone: hero.ink
                                track: Qt.rgba(hero.ink.r, hero.ink.g, hero.ink.b, 0.2)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: hero.q.lowLabel || ""; color: hero.inkMuted; font.pixelSize: Theme.fontXs; font.features: ({ "tnum": 1 }); Layout.fillWidth: true }
                                Label { text: hero.q.highLabel || ""; color: hero.inkMuted; font.pixelSize: Theme.fontXs; font.features: ({ "tnum": 1 }) }
                            }
                        }
                    }
                    TapHandler { onTapped: markets.pick(hero.q.symbol) }
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
                        Price {
                            row: markets.current
                            label.color: detail.ink
                            label.font.pixelSize: Theme.mini ? 40 : Theme.compact ? 48 : 56
                            label.font.weight: Font.Light
                        }
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
                        // Drawn on again for each symbol picked.
                        progress: Math.min(rv.at(2), markets.detailIn)
                        pulse: markets.justMoved(markets.current)
                        running: markets.moving && (md.paned || md.pushed)
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
