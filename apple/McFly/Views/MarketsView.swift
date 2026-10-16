import McFlyKit
import SwiftUI

/// A tile per symbol with a sparkline from its history.
struct MarketsView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case markets = "Markets", metrics = "Metrics"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var app
    @State private var segment: Segment = .markets

    private var feeds: FeedStore { app.feeds }
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Show", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                if segment == .metrics {
                    metricsGrid
                } else if feeds.series.isEmpty {
                    EmptyCard(text: feeds.hasLoaded ? "No quotes yet. A stocks agent pushes them." : "Loading…",
                              systemImage: "chart.line.uptrend.xyaxis")
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(feeds.series) { series in
                            NavigationLink(value: series) {
                                SymbolTile(series: series)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    if let asOf = feeds.series.map(\.latest.asOf).max() {
                        Text("As of \(asOf.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle(segment == .metrics ? "Metrics" : "Markets")
        .navigationDestination(for: QuoteSeries.self) { SymbolDetailView(series: $0) }
        .navigationDestination(for: MetricSeries.self) { MetricDetailView(series: $0) }
    }

    @ViewBuilder
    private var metricsGrid: some View {
        let groups = feeds.metricGroups
        if groups.isEmpty {
            EmptyCard(text: feeds.hasLoaded ? "No metrics yet. An agent pushes them with a key, a value and a group." : "Loading…",
                      systemImage: "gauge.with.dots.needle.33percent")
        } else {
            ForEach(groups, id: \.id) { group in
                SectionHeader(group.title)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(group.series) { series in
                        NavigationLink(value: series) { MetricTile(series: series) }
                            .buttonStyle(PressableStyle())
                    }
                }
            }
            if let asOf = feeds.metricSeries.map(\.latest.asOf).max() {
                Text("As of \(asOf.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Label, value with its unit, the delta, and a sparkline of the history.
struct MetricTile: View {
    let series: MetricSeries

    var body: some View {
        let m = series.latest
        let delta = m.deltaPct ?? m.delta
        let color = Color.metricChange(delta, key: series.key)
        VStack(alignment: .leading, spacing: 6) {
            Text(series.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Text(Format.metric(m.value, unit: m.unit))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if series.values.count >= 2 {
                Sparkline(values: series.values, color: delta == nil ? Theme.accent : color)
                    .frame(height: 36)
            } else {
                Spacer().frame(height: 36)
            }
            Text(delta == nil ? Format.relative(m.asOf) : Format.metricDelta(m.delta, pct: m.deltaPct, unit: m.unit))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(delta == nil ? Theme.muted : color)
                .frame(minHeight: 14)
        }
        .card(padding: 14, radius: Theme.radiusSm + 2)
    }
}

/// The metric on the Markets detail's tile, then the history behind it. The
/// display shows metrics only as cards, so this borrows the quote's tile;
/// it is green when the move is good news, as the grid colours it.
struct MetricDetailView: View {
    let series: MetricSeries
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = series.latest
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MarketTile(good: series.isGoodNews, value: Format.metric(m.value, unit: m.unit), move: m.deltaPct ?? m.delta,
                           change: Format.metricDelta(m.delta, pct: m.deltaPct, unit: m.unit), values: series.values,
                           note: m.note, source: Format.source(app.feeds.agent(m.agentId), asOf: m.asOf, points: series.history.count)) { tile in
                    if let group = series.group {
                        Text(group.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(tile.inkMuted)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("History").font(.caption.weight(.bold)).foregroundStyle(Theme.muted).padding(.bottom, 8)
                    ForEach(series.history.prefix(60)) { row in
                        HStack {
                            Text(row.asOf.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(Format.metric(row.value, unit: row.unit ?? m.unit)).font(.footnote.monospacedDigit()).foregroundStyle(Theme.text)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
                .card()
                Text("Key: \(series.key)").font(.caption.monospaced()).foregroundStyle(Theme.muted)
            }
            .padding(Theme.page)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(series.label)
        .inlineTitle()
    }
}

extension Color {
    /// A delta's color: up is green unless the metric is one where down is good (latency, errors, open orders).
    static func metricChange(_ value: Double?, key: String) -> Color {
        guard let value, value != 0 else { return Theme.muted }
        return (value > 0) != MetricSeries.lowerIsBetter(key) ? Theme.up : Theme.down
    }
}

private extension MetricSeries {
    static func lowerIsBetter(_ key: String) -> Bool {
        ["p95", "p99", "latency", "error", "errors", "open", "cost", "spend", "bounce"].contains { key.lowercased().contains($0) }
    }

    /// The move as the display reads one (FeedStore.cpp): the agent's delta,
    /// else the step from the value before. None counts as good news.
    var isGoodNews: Bool {
        let m = latest
        let move = m.delta ?? m.deltaPct ?? (history.count > 1 ? m.value - history[1].value : 0)
        return move == 0 || (move > 0) != Self.lowerIsBetter(key)
    }
}

private extension QuoteSeries {
    /// The display's `up`: the agent's change, else the step from the price
    /// before; no change counts as up.
    var isUp: Bool {
        let q = latest
        return (q.change ?? q.changePct ?? (history.count > 1 ? q.price - history[1].price : 0)) >= 0
    }
}

/// The display's Markets detail (MarketsScreen.qml): the value large and
/// light, the move with its arrow, the sparkline, the note and who sent it,
/// in the tile's inks, on a gradient tile with the display's seed and single
/// ring: green for good news, coral for bad.
private struct MarketTile<Heading: View>: View {
    let good: Bool
    let value: String
    /// What the agent sent; its sign picks the arrow.
    let move: Double?
    let change: String
    let values: [Double]
    let note: String?
    let source: String
    @ViewBuilder var heading: (TileColors) -> Heading

    var body: some View {
        GradientTile(base: good ? 0x3DB37A : 0xF07F5A, rings: 1, ringBias: 0.8, seed: 3.3) { tile in
            VStack(alignment: .leading, spacing: 10) {
                heading(tile)
                // The change beside the value where it fits, as on the display's page; else under it.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .lastTextBaseline, spacing: 14) {
                        valueText(tile)
                        changeText(tile)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        valueText(tile)
                        changeText(tile)
                    }
                }
                if values.count >= 2 {
                    Sparkline(values: values, color: tile.strong, lineWidth: 3)
                        .frame(height: 120)
                        .padding(.vertical, 4)
                }
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .foregroundStyle(tile.ink)
                        .textSelection(.enabled)
                }
                Text(source)
                    .font(.caption)
                    .foregroundStyle(tile.inkMuted)
            }
            .padding(22)
        }
    }

    private func valueText(_ tile: TileColors) -> some View {
        Text(value)
            .font(.system(size: 44, weight: .light).monospacedDigit())
            .foregroundStyle(tile.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private func changeText(_ tile: TileColors) -> some View {
        if !change.isEmpty {
            HStack(spacing: 5) {
                if let move, move != 0 {
                    Image(systemName: move > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(change)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(tile.strong)
            .lineLimit(1)
        }
    }
}

extension Format {
    /// "Market desk · 4:00 PM · 30 points": who sent it, when, and how much
    /// history there is, as the foot of the display's Markets detail.
    static func source(_ agent: Agent?, asOf: Date, points: Int, now: Date = .now) -> String {
        let when = Calendar.current.isDate(asOf, inSameDayAs: now) ? time(asOf) : "\(dayLabel(asOf, now: now)), \(time(asOf))"
        return [agent?.name, when, points == 1 ? "1 point" : "\(points) points"].compactMap { $0 }.joined(separator: " · ")
    }
}

struct SymbolTile: View {
    let series: QuoteSeries

    var body: some View {
        let quote = series.latest
        let color = Color.change(quote.changePct ?? quote.change)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(Format.percent(quote.changePct))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
            Text(series.displayName)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Sparkline(values: series.prices, color: color)
                .frame(height: 44)
                .padding(.vertical, 4)
            Text(Format.price(quote.price, currency: quote.currency))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .card(padding: 14, radius: Theme.radiusSm + 2)
    }
}

/// The quote on the display's detail tile (MarketsScreen.qml), green when
/// it's up and coral when it's down, then the history behind it.
struct SymbolDetailView: View {
    let series: QuoteSeries
    @Environment(AppModel.self) private var app

    var body: some View {
        let quote = series.latest
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MarketTile(good: series.isUp, value: Format.price(quote.price, currency: quote.currency),
                           move: quote.changePct ?? quote.change, change: Format.change(quote.change, pct: quote.changePct),
                           values: series.prices, note: quote.note,
                           source: Format.source(app.feeds.agent(quote.agentId), asOf: quote.asOf, points: series.history.count)) { tile in
                    Text(series.displayName)
                        .font(.subheadline)
                        .foregroundStyle(tile.inkMuted)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("History").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        .padding(.bottom, 8)
                    ForEach(series.history.prefix(60)) { row in
                        HStack {
                            Text(row.asOf.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Text(Format.price(row.price, currency: row.currency))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Theme.text)
                            Text(Format.percent(row.changePct))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Color.change(row.changePct))
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
                .card()
            }
            .padding(Theme.page)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(series.symbol)
        .inlineTitle()
    }
}
