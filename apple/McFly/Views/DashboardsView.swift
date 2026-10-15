import McFlyKit
import SwiftUI

/// Agent-built dashboards: pick one, see its widgets as a grid of cards.
struct DashboardsView: View {
    @Environment(AppModel.self) private var app
    @State private var chosenId: UUID?

    private var feeds: FeedStore { app.feeds }
    private var dashboard: Dashboard? { feeds.dashboard(chosenId) ?? feeds.dashboards.first }
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 320), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                if feeds.dashboards.count > 1 {
                    Picker("Dashboard", selection: Binding(get: { dashboard?.id }, set: { chosenId = $0 })) {
                        ForEach(feeds.dashboards) { d in
                            Text(d.title).tag(Optional(d.id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if let dashboard {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dashboard.title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        HStack(spacing: 8) {
                            if let subtitle = dashboard.subtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            AgentBadge(agent: feeds.agent(dashboard.agentId))
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(dashboard.widgets.enumerated()), id: \.offset) { _, widget in
                            WidgetCard(widget: widget)
                        }
                    }
                    if let updated = dashboard.updatedAt {
                        Text("Updated \(Format.relative(updated).lowercased())")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    EmptyCard(text: feeds.hasLoaded ? "No dashboards yet. An agent builds them from its widgets." : "Loading…",
                              systemImage: "rectangle.3.group")
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("Dashboards")
    }
}

/// One widget, rendered for its type.
struct WidgetCard: View {
    let widget: DashboardWidget

    var body: some View {
        Group {
            switch widget {
            case let .metric(label, value, unit, delta, deltaPct):
                metric(label: label, value: value, unit: unit, delta: delta, deltaPct: deltaPct)
            case let .status(label, state, detail):
                status(label: label, state: state, detail: detail)
            case let .progress(label, value, max, unit):
                progress(label: label, value: value, max: max, unit: unit)
            case let .list(title, items):
                list(title: title, items: items)
            case let .text(title, body):
                text(title: title, body: body)
            case let .chart(label, points, unit):
                chart(label: label, points: points, unit: unit)
            case let .unknown(type):
                VStack(alignment: .leading, spacing: 6) {
                    caption("Unsupported widget")
                    Text(type.isEmpty ? "This version can't show it." : "“\(type)” isn't a type this version shows.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 14, radius: Theme.radiusSm + 2)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
    }

    private func metric(label: String, value: Double, unit: String?, delta: Double?, deltaPct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption(label)
            Text(Format.metric(value, unit: unit))
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if delta != nil || deltaPct != nil {
                ChangeText(change: delta, pct: deltaPct, font: .caption.weight(.semibold))
            }
        }
    }

    private func status(label: String, state: DashboardWidget.State, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.status(state))
                .frame(width: 12, height: 12)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.headline).foregroundStyle(Theme.text)
                Text(detail ?? state.rawValue.capitalized)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progress(label: String, value: Double, max: Double, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            caption(label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Format.metric(value, unit: unit)).font(.title3.weight(.bold).monospacedDigit())
                Text("of \(Format.metric(max, unit: unit))").font(.caption).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.text)
            ProgressBar(value: max > 0 ? value / max : 0)
        }
    }

    private func list(title: String?, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { caption(title) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(y: -2)
                    Text(item).font(.subheadline).foregroundStyle(Theme.text)
                }
            }
        }
    }

    private func text(title: String?, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { caption(title) }
            MarkdownText(text: body).font(.subheadline).foregroundStyle(Theme.text)
        }
    }

    private func chart(label: String?, points: [Double], unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                caption(label ?? "Chart")
                Spacer()
                if let last = points.last {
                    Text(Format.metric(last, unit: unit))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                }
            }
            Sparkline(values: points, color: Theme.accent)
                .frame(height: 60)
        }
    }
}

extension Color {
    static func status(_ state: DashboardWidget.State) -> Color {
        switch state {
        case .ok: return Theme.up
        case .warn: return Theme.amber
        case .error: return Theme.down
        case .unknown: return Theme.muted
        }
    }
}
