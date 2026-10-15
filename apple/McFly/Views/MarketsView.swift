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

/// The metric, its note and the history behind it.
struct MetricDetailView: View {
    let series: MetricSeries

    var body: some View {
        let m = series.latest
        let delta = m.deltaPct ?? m.delta
        let color = Color.metricChange(delta, key: series.key)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    if let group = series.group {
                        Text(group.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                    }
                    Text(Format.metric(m.value, unit: m.unit))
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.text)
                    if delta != nil {
                        Text(Format.metricDelta(m.delta, pct: m.deltaPct, unit: m.unit))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(color)
                    }
                    Text("As of \(m.asOf.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if series.values.count >= 2 {
                    Sparkline(values: series.values, color: delta == nil ? Theme.accent : color, lineWidth: 2.5)
                        .frame(height: 140)
                        .card(padding: 14)
                }
                if let note = m.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        Text(note).font(.body).foregroundStyle(Theme.text).textSelection(.enabled)
                    }
                    .card()
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
        let lowerIsBetter = ["p95", "p99", "latency", "error", "errors", "open", "cost", "spend", "bounce"]
            .contains { key.lowercased().contains($0) }
        return (value > 0) != lowerIsBetter ? Theme.up : Theme.down
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

/// The quote, its note, a bigger sparkline and the history behind it.
struct SymbolDetailView: View {
    let series: QuoteSeries

    var body: some View {
        let quote = series.latest
        let color = Color.change(quote.changePct ?? quote.change)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Text(Format.price(quote.price, currency: quote.currency))
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.text)
                    ChangeText(change: quote.change, pct: quote.changePct, font: .headline)
                    Text("As of \(quote.asOf.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Sparkline(values: series.prices, color: color, lineWidth: 2.5)
                    .frame(height: 140)
                    .card(padding: 14)
                if let note = quote.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        Text(note).font(.body).foregroundStyle(Theme.text).textSelection(.enabled)
                    }
                    .card()
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
