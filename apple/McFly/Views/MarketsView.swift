import McFlyKit
import SwiftUI

/// A tile per symbol with a sparkline from its history, the holding when the
/// agent sends one, and the holdings summed over the grid.
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
                    let markets = feeds.markets
                    if !markets.portfolio.isEmpty {
                        HoldingsSummary(portfolio: markets.portfolio)
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(feeds.series) { series in
                            NavigationLink(value: series) {
                                SymbolTile(series: series, insight: markets.insights[series.symbol])
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

/// The holdings among the shown symbols, summed: the bar over the display's
/// Markets grid.
struct HoldingsSummary: View {
    let portfolio: Portfolio

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                MarketKicker(text: portfolio.count == 1 ? "Holding" : "\(portfolio.count) holdings")
                Text(Format.price(portfolio.value))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.text)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) { moves }
                VStack(alignment: .leading, spacing: 8) { moves }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: Theme.radiusSm + 2)
    }

    @ViewBuilder
    private var moves: some View {
        if let day = portfolio.dayChange {
            move("Today", Format.signedPrice(day), pct: portfolio.dayChangePct, digits: 2, value: day)
        }
        if let gain = portfolio.totalChange {
            move("Total gain", Format.signedPrice(gain), pct: portfolio.totalChangePct, digits: 1, value: gain)
        }
    }

    private func move(_ label: String, _ amount: String, pct: Double?, digits: Int, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MarketKicker(text: label)
            Text(amount + (pct.map { "  " + Format.signed($0, fractionDigits: digits) + "%" } ?? ""))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.change(value))
                .lineLimit(1)
        }
    }
}

/// A small caps label over a number, as the display's.
private struct MarketKicker: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1)
            .foregroundStyle(color)
    }
}

extension QuoteData.Signal.Tone {
    var color: Color {
        switch self {
        case .up: Theme.gain
        case .down: Theme.loss
        case .watch: Theme.warning
        }
    }

    var symbol: String {
        switch self {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .watch: "eye"
        }
    }
}

struct SymbolTile: View {
    let series: QuoteSeries
    var insight: QuoteInsight?

    var body: some View {
        let quote = series.latest
        let color = Color.change(quote.changePct ?? quote.change)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(series.symbol)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    // The agent noticed something: its first signal's tone.
                    if let tone = insight?.signals.first?.tone {
                        Circle().fill(tone.color).frame(width: 8, height: 8)
                            .accessibilityLabel("Has signals")
                    }
                }
                Spacer()
                Text(Format.percent(quote.changePct))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
            // The holding's value and gain (the shares are in the detail), else the name.
            if let holding = insight?.holding {
                HStack(spacing: 4) {
                    Text("You · " + Format.price(holding.value, currency: quote.currency))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    if let pct = holding.totalChangePct {
                        Text(Format.signed(pct, fractionDigits: 1) + "%")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.change(pct))
                    }
                }
                .font(.caption.monospacedDigit())
            } else {
                Text(series.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
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
                if let insight = app.feeds.markets.insights[series.symbol] {
                    if let holding = insight.holding {
                        PositionCard(holding: holding, currency: quote.currency)
                    }
                    if !insight.signals.isEmpty {
                        SignalsCard(signals: insight.signals)
                    }
                    if !insight.ranges.isEmpty || !insight.stats.isEmpty {
                        NumbersCard(ranges: insight.ranges, stats: insight.stats, currency: quote.currency)
                    }
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

/// The holding: its value, the gain since bought and today's, then shares,
/// cost and its share of the holdings.
private struct PositionCard: View {
    let holding: Holding
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MarketKicker(text: "Your position")
            Text(Format.price(holding.value, currency: currency))
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.text)
            if let gain = holding.totalChange {
                Text(Format.signedPrice(gain, currency: currency)
                     + (holding.totalChangePct.map { " (" + Format.signed($0, fractionDigits: 1) + "%)" } ?? "") + " overall")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.change(gain))
            }
            if let day = holding.dayChange {
                Text(Format.signedPrice(day, currency: currency) + " today")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.change(day))
            }
            let details = [holding.shares.map(Format.shares),
                           holding.avgCost.map { "avg " + Format.price($0, currency: currency) },
                           holding.weightPct.map { $0.formatted(.number.precision(.fractionLength($0 < 10 ? 1 : 0))) + "% of holdings" }]
                .compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// What the agent noticed: facts, each with its direction.
private struct SignalsCard: View {
    let signals: [QuoteData.Signal]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarketKicker(text: "Signals")
            ForEach(Array(signals.enumerated()), id: \.offset) { _, signal in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: signal.tone.symbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(signal.tone.color)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(signal.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Where the price sits between today's and the year's low and high, then
/// the day's numbers.
private struct NumbersCard: View {
    let ranges: [PriceRange]
    let stats: [MarketStat]
    let currency: String

    private let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(ranges) { range in
                VStack(alignment: .leading, spacing: 6) {
                    MarketKicker(text: range.label)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.divider).frame(height: 4)
                            Circle()
                                .fill(Theme.text)
                                .frame(width: 12, height: 12)
                                .offset(x: range.position * (geo.size.width - 12))
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 12)
                    .accessibilityHidden(true)
                    HStack {
                        Text(Format.price(range.low, currency: currency))
                        Spacer()
                        Text(Format.price(range.high, currency: currency))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
            }
            if !stats.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(stats) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.label).font(.caption).foregroundStyle(Theme.muted)
                            Text(stat.value)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
