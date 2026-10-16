import Charts
import McFlyKit
import SwiftUI

/// Agent-built dashboards, one at a time, as a bento: the display's Boards
/// screen (DashboardsScreen.qml) and the console's dashboard page. The kit's
/// `BoardLayout` places the widgets on 2 columns (iPhone), 4 (iPad portrait,
/// a narrow Mac window) or 6 (wide), in the agent's order with no holes: the
/// first metric on a gradient tile (2×2 from four columns up, a compact one
/// in its cell on a phone), a run of
/// statuses as one health strip across, charts wide and tall, lists and notes
/// half a row. Tiles settle in once as a board shows and glide when the width
/// changes the columns; a status that needs a look breathes, progress is a
/// ring, a chart draws itself on, and a move is green when it's good news.
struct DashboardsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chosenId: UUID?
    /// The content's width; 0 until it's known, and the grid waits for it.
    @State private var width: CGFloat = 0
    @State private var asking: String?

    /// Opens on `board` (a Home insight's, say) when it's given and still
    /// there; else on the first board.
    init(board: UUID? = nil) {
        _chosenId = State(initialValue: board)
    }

    private var feeds: FeedStore { app.feeds }
    private var dashboard: Dashboard? { feeds.dashboard(chosenId) ?? feeds.dashboards.first }

    /// Two columns on a phone, four on an iPad in portrait or a narrow Mac window, six when wide.
    static func columns(for width: CGFloat) -> Int {
        width < 560 ? 2 : width < 940 ? 4 : 6
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                if feeds.dashboards.count > 1 {
                    BoardChips(boards: feeds.dashboards, chosen: dashboard?.id) { chosenId = $0 }
                }
                if let dashboard {
                    BoardHeader(dashboard: dashboard, agent: feeds.agent(dashboard.agentId))
                    if width > 0 {
                        // A board of its own: picking another settles it in afresh.
                        BoardGrid(dashboard: dashboard, columns: Self.columns(for: width), width: width) { asking = $0 }
                            .id(dashboard.id)
                    }
                    unknownNote(dashboard)
                    if let updated = dashboard.updatedAt {
                        Text(["Updated \(Format.relative(updated).lowercased())", feeds.agent(dashboard.agentId).map { "by \($0.name)" }]
                            .compactMap { $0 }.joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    EmptyCard(text: feeds.hasLoaded ? "No dashboards yet. An agent builds them from its widgets." : "Loading…",
                              systemImage: "rectangle.3.group")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured($0) }
            .padding(Theme.page)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("Dashboards")
        .feedQuestion($asking)
    }

    /// The first width lands as is; a later one that changes the columns
    /// glides the tiles to their new places.
    private func measured(_ new: CGFloat) {
        guard width > 0, !reduceMotion, Self.columns(for: new) != Self.columns(for: width) else {
            width = new
            return
        }
        withAnimation(.smooth(duration: 0.45)) { width = new }
    }

    /// The widgets this version can't draw, said rather than hidden (the
    /// layout leaves them out, as the display does).
    @ViewBuilder
    private func unknownNote(_ dashboard: Dashboard) -> some View {
        let unknown = BoardLayout.unknownIndexes(dashboard.widgets)
        if dashboard.widgets.isEmpty {
            EmptyCard(text: "This board has no widgets yet.", systemImage: "rectangle.3.group")
        } else if !unknown.isEmpty {
            let types = Array(Set(unknown.map { dashboard.widgets[$0].typeName })).sorted()
                .filter { $0 != "?" }.map { "“\($0)”" }
            let count = unknown.count == 1 ? "1 widget" : "\(unknown.count) widgets"
            EmptyCard(text: "\(count) this version can't show" + (types.isEmpty ? "." : ": \(types.joined(separator: ", "))."),
                      systemImage: "questionmark.square.dashed")
        }
    }
}

// MARK: Header and picker

/// The board's title, what it's for and who keeps it.
private struct BoardHeader: View {
    let dashboard: Dashboard
    let agent: Agent?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dashboard.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                if let subtitle = dashboard.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                AgentBadge(agent: agent)
            }
        }
    }
}

/// One chip per board; the picked one's fill glides to the next.
private struct BoardChips: View {
    let boards: [Dashboard]
    let chosen: UUID?
    let pick: (UUID) -> Void
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(boards) { board in
                    let on = board.id == chosen
                    Button { pick(board.id) } label: {
                        Text(board.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(on ? Theme.accentInk : Theme.text)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background {
                                if on {
                                    Capsule().fill(Theme.accent).matchedGeometryEffect(id: "chosen", in: space)
                                } else {
                                    Capsule().fill(Theme.surface)
                                }
                            }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84), value: chosen)
    }
}

// MARK: The bento

/// The board's tiles where `BoardLayout` puts them. They fade up into place
/// once, a beat apart, when the board first shows; a tile that arrives with
/// a later push is simply there.
///
/// The board's first metric is its hero. From four columns the kit makes it
/// a 2×2 gradient tile; under four it stays a one-cell metric, and it's drawn
/// as a compact hero there, on the same gradient, so a phone gets one too.
/// It's the same widget either way (the kit's hero is the first metric), so
/// turning the device glides one tile rather than swapping two.
private struct BoardGrid: View {
    let dashboard: Dashboard
    let columns: Int
    /// The grid's width: a health strip spans it, and fits its statuses to it.
    let width: CGFloat
    let ask: (String) -> Void
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let widgets = dashboard.widgets
        let tiles = BoardLayout.layout(widgets, columns: columns)
        let settled = revealed || reduceMotion
        let firstMetric = widgets.firstIndex { if case .metric = $0 { return true } else { return false } }
        BentoGrid(columns: columns, spacing: 12, minRowHeight: columns <= 2 ? 112 : 128) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { order, tile in
                BoardTileView(tile: tile, widgets: widgets, width: width,
                              compactHero: columns < 4 && tile.kind == .metric && tile.index == firstMetric, ask: ask)
                    .opacity(settled ? 1 : 0)
                    .offset(y: settled ? 0 : 14)
                    .animation(.smooth(duration: 0.4).delay(Double(min(order, 6)) * 0.035), value: revealed)
                    .layoutValue(key: BentoCellKey.self, value: BentoCell(tile))
            }
        }
        .onAppear { revealed = true }
    }
}

/// Where a tile sits on the grid, in cells.
private struct BentoCell: Equatable {
    var row = 0, col = 0, rowSpan = 1, colSpan = 1
    /// As tall as its content and no taller: a health strip's rows (one
    /// per row of statuses) are as tall as the statuses need, not a widget row each.
    var hugs = false

    init() {}

    init(_ tile: BoardTile) {
        row = tile.row
        col = tile.col
        rowSpan = max(1, tile.rowSpan)
        colSpan = max(1, tile.colSpan)
        hugs = tile.kind == .health
    }
}

private struct BentoCellKey: LayoutValueKey {
    static let defaultValue = BentoCell()
}

/// Equal columns; each row as tall as the tallest one-row tile in it needs
/// at its width (and `minRowHeight` at least, unless only a strip that hugs
/// its content is in it), and a taller tile shares out whatever more it needs
/// over its rows. So nothing is cut off, and a row of short metrics stays short.
private struct BentoGrid: Layout {
    var columns: Int
    var spacing: CGFloat
    var minRowHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        return CGSize(width: width, height: plan(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = plan(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func plan(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let cols = max(1, columns)
        let column = max(0, (width - CGFloat(cols - 1) * spacing) / CGFloat(cols))
        let cells = subviews.map { $0[BentoCellKey.self] }
        let rows = cells.map { $0.row + $0.rowSpan }.max() ?? 0
        guard rows > 0 else { return ([], 0) }
        func across(_ cell: BentoCell) -> CGFloat {
            let span = min(cell.colSpan, cols)
            return CGFloat(span) * column + CGFloat(span - 1) * spacing
        }
        func span(_ cell: BentoCell) -> Range<Int> { cell.row..<min(rows, cell.row + cell.rowSpan) }

        var heights = (0..<rows).map { r in
            cells.contains { !$0.hugs && span($0).contains(r) } ? minRowHeight : 0
        }
        // One-row tiles set their rows; then the taller ones top up theirs.
        for tall in [false, true] {
            for (subview, cell) in zip(subviews, cells) where (cell.rowSpan > 1) == tall {
                let need = subview.sizeThatFits(ProposedViewSize(width: across(cell), height: nil)).height
                let range = span(cell)
                guard !range.isEmpty else { continue }
                let have = range.reduce(0) { $0 + heights[$1] } + CGFloat(range.count - 1) * spacing
                if need > have {
                    let extra = (need - have) / CGFloat(range.count)
                    for r in range { heights[r] += extra }
                }
            }
        }
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for h in heights {
            tops.append(y)
            y += h + spacing
        }
        let frames = cells.map { cell -> CGRect in
            let range = span(cell)
            let top = tops[min(cell.row, rows - 1)]
            let tall = range.reduce(0) { $0 + heights[$1] } + CGFloat(max(0, range.count - 1)) * spacing
            return CGRect(x: CGFloat(cell.col) * (column + spacing), y: top, width: across(cell), height: tall)
        }
        return (frames, y - spacing)
    }
}

// MARK: Tiles

/// One tile, drawn for its kind.
private struct BoardTileView: View {
    let tile: BoardTile
    let widgets: [DashboardWidget]
    /// The grid's width (a health strip's).
    let width: CGFloat
    /// The board's first metric under four columns: a hero, compact.
    var compactHero = false
    let ask: (String) -> Void

    var body: some View {
        if tile.kind == .health {
            BoardHealthStrip(statuses: tile.indexes.compactMap { BoardStatus(widgets.indices.contains($0) ? widgets[$0] : nil) },
                             perRow: tile.perRow, width: width, ask: ask)
        } else {
            let widget = widgets.indices.contains(tile.index) ? widgets[tile.index] : .unknown(type: "")
            switch widget {
            case let .metric(label, value, unit, delta, deltaPct):
                let metric = BoardMetric(label: label, value: value, unit: unit, delta: delta, deltaPct: deltaPct, trend: widget.trend)
                if tile.kind == .hero || compactHero {
                    BoardHero(metric: metric, compact: tile.kind != .hero)
                } else {
                    BoardMetricCard(metric: metric)
                }
            case let .status(label, state, detail):
                BoardStatusCard(status: BoardStatus(label: label, state: state, detail: detail), ask: ask)
            case let .progress(label, value, max, unit):
                BoardProgressCard(label: label, value: value, limit: max, unit: unit)
            case let .chart(label, points, unit):
                BoardChartCard(label: label, points: points, unit: unit)
            case let .list(title, items):
                BoardListCard(title: title, items: items)
            case let .text(title, body):
                BoardTextCard(title: title, text: body)
            case .unknown:
                EmptyView()
            }
        }
    }
}

/// A metric widget's numbers, and whether its move is good news.
private struct BoardMetric {
    let label: String
    let value: Double
    let unit: String?
    let delta: Double?
    let deltaPct: Double?
    let trend: MetricTrend?

    var valueText: String { Format.metric(value, unit: unit) }
    var deltaText: String { Format.metricDelta(delta, pct: deltaPct, unit: unit) }
    var move: Trend { trend?.trend ?? .flat }
    var good: Bool { trend?.good ?? true }

    /// "Up 4.2%, good news" for VoiceOver.
    var spokenMove: String {
        guard move != .flat, !deltaText.isEmpty else { return deltaText }
        return "\(move == .up ? "Up" : "Down") \(deltaText.trimmingCharacters(in: CharacterSet(charactersIn: "+−-"))), \(good ? "good news" : "worth a look")"
    }
}

/// A status widget's parts.
private struct BoardStatus: Identifiable {
    let label: String
    let state: DashboardWidget.State
    let detail: String?
    var id: String { label }

    init(label: String, state: DashboardWidget.State, detail: String?) {
        self.label = label
        self.state = state
        self.detail = detail
    }

    init?(_ widget: DashboardWidget?) {
        guard case let .status(label, state, detail) = widget else { return nil }
        self.init(label: label, state: state, detail: detail)
    }

    var needsLook: Bool { state == .warn || state == .error }

    var word: String {
        switch state {
        case .ok: return "OK"
        case .warn: return "Warning"
        case .error: return "Down"
        case .unknown: return "Unknown"
        }
    }

    /// The state's word in a colour that reads on a card.
    var ink: Color {
        switch state {
        case .ok: return Theme.up
        case .warn: return Theme.warningInk
        case .error: return Theme.danger
        case .unknown: return Theme.muted
        }
    }

    /// What to ask about it, in the kit's words (`Insights` status).
    var question: String {
        state == .error ? "Why is \(label) down?" : "What's wrong with \(label)?"
    }
}

/// The board's first metric, large, on a gradient tile in the accent: the
/// number in light type, and its move on glass with an arrow that's green
/// when the move is good news. Compact in a one-cell tile (a phone's two
/// columns): the same parts, smaller, so it sits level with the cards beside it.
private struct BoardHero: View {
    let metric: BoardMetric
    var compact = false

    var body: some View {
        let disc: CGFloat = compact ? 20 : 24
        GradientTile(base: Theme.palette.accent, radius: Theme.radiusSm + 6, rings: 1, ringBias: 0.8, seed: 6.1) { tile in
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                Text(metric.label.uppercased())
                    .font(.system(size: compact ? 11 : 12, weight: .bold))
                    .tracking(compact ? 0.9 : 1.2)
                    .foregroundStyle(tile.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: compact ? 6 : 12)
                Text(metric.valueText)
                    .font(.system(size: compact ? 44 : 64, weight: .light).monospacedDigit())
                    .tracking(compact ? -1 : -1.5)
                    .foregroundStyle(tile.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .contentTransition(.numericText(value: metric.value))
                if !metric.deltaText.isEmpty {
                    HStack(spacing: compact ? 6 : 8) {
                        if metric.move != .flat {
                            Image(systemName: metric.move == .up ? "arrow.up" : "arrow.down")
                                .font(.system(size: compact ? 10 : 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: disc, height: disc)
                                .background(metric.good ? Theme.gain : Theme.loss, in: Circle())
                        }
                        Text(metric.deltaText)
                            .font(.system(size: compact ? 15 : 17, weight: .semibold).monospacedDigit())
                            .foregroundStyle(tile.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                    }
                    .padding(.leading, metric.move == .flat ? (compact ? 10 : 12) : (compact ? 3 : 4))
                    .padding(.trailing, compact ? 10 : 12)
                    .padding(.vertical, compact ? 3 : 4)
                    .background(tile.glassFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(tile.glassStroke, lineWidth: 1))
                }
            }
            .padding(compact ? 16 : 24)
            .animation(.smooth, value: metric.value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.label), \(metric.valueText)")
        .accessibilityValue(metric.spokenMove)
    }
}

/// A metric on a card: the figure, and its move coloured by whether that's good news.
private struct BoardMetricCard: View {
    let metric: BoardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            boardCaption(metric.label)
            Spacer(minLength: 8)
            Text(metric.valueText)
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText(value: metric.value))
            if !metric.deltaText.isEmpty {
                BoardDelta(metric: metric)
            }
        }
        .animation(.smooth, value: metric.value)
        .boardCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.label), \(metric.valueText)")
        .accessibilityValue(metric.spokenMove)
    }
}

/// "↗ +4.2%" in green, "↘ −30%" in green too when falling is the good news.
private struct BoardDelta: View {
    let metric: BoardMetric

    var body: some View {
        HStack(spacing: 3) {
            if metric.move != .flat {
                Image(systemName: metric.move == .up ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.bold))
            }
            Text(metric.deltaText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(metric.move == .flat ? Theme.muted : metric.good ? Theme.gain : Theme.loss)
        .lineLimit(1)
    }
}

/// Two or more statuses in a row as one strip: how many need a look up top,
/// then each status's dot, name, state and detail, `perRow` to a row (fewer
/// where the strip is too narrow for that many names) with a hairline
/// between them. A dot that needs a look breathes, and the worst one gets a
/// question to ask about it.
private struct BoardHealthStrip: View {
    let statuses: [BoardStatus]
    let perRow: Int
    /// The strip's width, padding and all.
    let width: CGFloat
    let ask: (String) -> Void

    /// Each status's room at the least: a dot and a name like "Payments API".
    static let leastCell: CGFloat = 110
    static let padding: CGFloat = 16
    /// A hairline and the room either side of it.
    static let gap: CGFloat = 1 + 2 * 14

    /// The kit's `perRow` while each status gets `leastCell`; fewer to a row
    /// where it wouldn't (two on a phone), the rows kept even (5 → 2 + 2 + 1).
    static func across(perRow: Int, count: Int, width: CGFloat) -> Int {
        let most = max(1, min(perRow, count))
        let inner = width - 2 * padding
        guard width > 0 else { return most }
        var fits = most
        while fits > 1 && (inner - CGFloat(fits - 1) * gap) / CGFloat(fits) < leastCell { fits -= 1 }
        if fits == most { return most }
        let rows = (count + fits - 1) / fits
        return (count + rows - 1) / rows
    }

    var body: some View {
        let needs = statuses.filter(\.needsLook).count
        let worst = statuses.first { $0.state == .error } ?? statuses.first { $0.state == .warn }
        let across = Self.across(perRow: perRow, count: statuses.count, width: width)
        let rows = stride(from: 0, to: statuses.count, by: across).map { Array(statuses[$0..<min($0 + across, statuses.count)]) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: BoardHealth(statuses.map { .status(label: $0.label, state: $0.state, detail: $0.detail) }).colorHex))
                    .frame(width: 8, height: 8)
                boardCaption("Health")
                Spacer(minLength: 8)
                Text(needs > 0 ? "\(needs) of \(statuses.count) need\(needs == 1 ? "s" : "") a look" : "All \(statuses.count) OK")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(needs == 0 ? Theme.up : worst?.state == .error ? Theme.danger : Theme.warningInk)
                    .contentTransition(.numericText())
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<across, id: \.self) { slot in
                            if slot > 0 {
                                Rectangle()
                                    .fill(Theme.divider)
                                    .frame(width: 1)
                                    .padding(.horizontal, 14)
                                    .opacity(slot < row.count ? 1 : 0)
                            }
                            if slot < row.count {
                                cell(row[slot])
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let worst {
                FeedAskChip(title: worst.question) { ask(worst.question) }
            }
        }
        .animation(.smooth, value: needs)
        .boardCard()
    }

    private func cell(_ status: BoardStatus) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                BoardStatusDot(state: status.state, size: 10)
                Text(status.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(status.word)
                .font(.callout.weight(.semibold))
                .foregroundStyle(status.ink)
            if let detail = status.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A status on its own.
private struct BoardStatusCard: View {
    let status: BoardStatus
    var ask: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                BoardStatusDot(state: status.state, size: 12)
                Text(status.label)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            Text(status.word)
                .font(.title3.weight(.semibold))
                .foregroundStyle(status.ink)
            if let detail = status.detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status.needsLook, let ask {
                Spacer(minLength: 4)
                FeedAskChip(title: "Ask why") { ask(status.question) }
            }
        }
        .boardCard()
    }
}

/// Progress as a ring with the percentage in it; a count ("14 of 20") beside
/// it. Where the tile is narrow the ring is smaller, then the count goes under it.
private struct BoardProgressCard: View {
    let label: String
    let value: Double
    let limit: Double
    let unit: String?

    private var fraction: Double { limit > 0 ? min(1, max(0, value / limit)) : 0 }
    private var percent: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            boardCaption(label)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    words
                    Spacer(minLength: 0)
                    ring(76)
                }
                HStack(alignment: .center, spacing: 8) {
                    words
                    Spacer(minLength: 0)
                    ring(60)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ring(60)
                    words
                }
            }
            .frame(maxHeight: .infinity)
        }
        .animation(.smooth, value: value)
        .boardCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit == "%" ? "\(percent) percent" : "\(count), \(percent) percent")
    }

    /// "14 of 20" and "6 to go"; a share ("68%") is in the ring, with what's left beside it.
    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            if unit != "%" {
                Text(count)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: value))
            }
            Text(remaining)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func ring(_ size: CGFloat) -> some View {
        BoardRing(value: fraction, color: Theme.accent, lineWidth: size >= 70 ? 8 : 7, delay: 0.2) {
            Text("\(percent)%")
                .font(.system(size: size >= 70 ? 16 : 14, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(value: Double(percent)))
        }
        .frame(width: size, height: size)
    }

    private var count: String { "\(Format.metric(value, unit: unit)) of \(Format.metric(limit, unit: unit))" }

    /// "6 to go", "32% left", or "Complete".
    private var remaining: String {
        if value >= limit { return "Complete" }
        return unit == "%" ? "\(100 - percent)% left" : "\(Format.metric(limit - value, unit: unit)) to go"
    }
}

/// A chart: the newest value up top, the area under a smooth line drawing
/// itself on, the low and the high underneath.
private struct BoardChartCard: View {
    let label: String?
    let points: [Double]
    let unit: String?

    var body: some View {
        let values = points.filter(\.isFinite)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                boardCaption(label ?? "Chart")
                Spacer(minLength: 8)
                if let last = values.last {
                    Text(Format.metric(last, unit: unit))
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(value: last))
                        .animation(.smooth, value: last)
                }
            }
            if values.count >= 2, let low = values.min(), let high = values.max() {
                BoardAreaChart(values: values, color: Theme.accent)
                    .frame(minHeight: 96, maxHeight: .infinity)
                if high > low {
                    HStack {
                        Text("Low \(Text(Format.metric(low, unit: unit)).foregroundStyle(Theme.text))")
                        Spacer(minLength: 8)
                        Text("High \(Text(Format.metric(high, unit: unit)).foregroundStyle(Theme.text))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                }
            } else {
                Text(values.isEmpty ? "No points yet." : "One point so far.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .boardCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Chart")
        .accessibilityValue(Self.spoken(values, unit: unit))
    }

    static func spoken(_ values: [Double], unit: String?) -> String {
        guard let last = values.last, let low = values.min(), let high = values.max() else { return "No points" }
        let parts = ["latest \(Format.metric(last, unit: unit))"] + (high > low
            ? ["high \(Format.metric(high, unit: unit))", "low \(Format.metric(low, unit: unit))"] : [])
        return parts.joined(separator: ", ")
    }
}

private struct BoardListCard: View {
    let title: String?
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty { boardCaption(title) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(y: -2)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .boardCard()
    }
}

private struct BoardTextCard: View {
    let title: String?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty { boardCaption(title) }
            MarkdownText(text: text)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
        }
        .boardCard()
    }
}

/// Small caps over a tile's content.
private func boardCaption(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.caption2.weight(.bold))
        .tracking(0.8)
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
}

private extension View {
    /// A tile's plain card: filling its cell, large and round.
    func boardCard() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm + 6, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 14, y: 4)
    }
}

// MARK: Charts, rings and dots (Projects uses them too)

/// A trend as a smooth line over a soft fill, dashed guides at the high and
/// the low, the newest point marked. It draws itself on from the left the
/// first time it shows. Monotone, so the curve never overshoots the high or
/// the low it's labelled with.
struct BoardAreaChart: View {
    let values: [Double]
    var color: Color = Theme.accent
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let span = high - low
        let pad = span > 0 ? span * 0.12 : max(abs(high) * 0.05, 1)
        let base = low - pad
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("Point", index), yStart: .value("Base", base), yEnd: .value("Value", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Point", index), y: .value("Value", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if span > 0 {
                RuleMark(y: .value("High", high))
                    .foregroundStyle(Theme.muted.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                RuleMark(y: .value("Low", low))
                    .foregroundStyle(Theme.muted.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if let last = values.last {
                PointMark(x: .value("Point", values.count - 1), y: .value("Value", last))
                    .symbolSize(56)
                    .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(1, values.count - 1))
        .chartYScale(domain: base...(high + pad))
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        // Drawn on from the left: a mask that opens once.
        .mask(alignment: .leading) {
            Rectangle().scaleEffect(x: drawn || reduceMotion ? 1 : 0.001, anchor: .leading)
        }
        .onAppear {
            guard !drawn, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.55).delay(0.2)) { drawn = true }
        }
        .accessibilityHidden(true)
    }
}

/// Progress as a ring: a faint track all the way round and an arc over it
/// from 12 o'clock, clockwise, with round ends; whatever's given sits in the
/// middle. The arc sweeps in the first time it shows and eases to a new value.
struct BoardRing<Center: View>: View {
    let value: Double
    var color: Color = Theme.accent
    /// Nil: the colour, faint.
    var track: Color?
    var lineWidth: CGFloat = 8
    /// How long after it shows the arc starts to sweep.
    var delay: Double = 0.1
    @ViewBuilder var center: () -> Center
    @State private var swept = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(track ?? color.opacity(0.16), lineWidth: lineWidth)
            // Nothing at zero: a round cap on an empty arc would still draw a dot.
            if fraction > 0 {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: swept || reduceMotion ? fraction : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            center()
        }
        .animation(.smooth(duration: 0.5), value: fraction)
        .onAppear {
            guard !swept, !reduceMotion else { return }
            withAnimation(.smooth(duration: 0.5).delay(delay)) { swept = true }
        }
    }
}

extension BoardRing where Center == EmptyView {
    init(value: Double, color: Color = Theme.accent, track: Color? = nil, lineWidth: CGFloat = 8, delay: Double = 0.1) {
        self.init(value: value, color: color, track: track, lineWidth: lineWidth, delay: delay) { EmptyView() }
    }
}

/// A status's colour as a dot (the display's): green OK, amber warning,
/// coral down, grey unknown. One that needs a look breathes, a soft halo
/// swelling and fading around it, rather than blinking.
struct BoardStatusDot: View {
    let state: DashboardWidget.State
    var size: CGFloat = 10

    var body: some View {
        let color = Color(hex: BoardLayout.colorHex(state))
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if state == .warn || state == .error {
                    BoardBreath { phase in
                        Circle()
                            .fill(color)
                            .frame(width: size * 2.2, height: size * 2.2)
                            .scaleEffect(0.6 + 0.4 * (phase ?? 0))
                            .opacity(phase.map { 0.08 + 0.26 * $0 } ?? 0)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

/// A slow breath for something that needs a look: `phase` runs 0 → 1 → 0
/// over `period` seconds (the display's Theme.breath, twice), and is nil
/// while it's still: its screen gone (navigated away from, another tab),
/// the app in the background, or Reduce Motion on. Scrolled out of sight on
/// a screen that's showing, it keeps going, at 20 frames a second for a dot
/// or a border: onAppear/onDisappear don't fire for that in a plain VStack,
/// and `onScrollVisibilityChange` needs iOS 18 (GradientTile is the same).
/// Read from the clock, so no animation transaction (a tile settling in or
/// gliding) can carry it along.
struct BoardBreath<Content: View>: View {
    var period: Double = 4.4
    @ViewBuilder var content: (_ phase: Double?) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false

    var body: some View {
        let playing = onScreen && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing)) { context in
            let turn = (context.date.timeIntervalSinceReferenceDate / period).truncatingRemainder(dividingBy: 1)
            content(playing ? 0.5 - 0.5 * cos(2 * .pi * turn) : nil)
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }
}

// MARK: Asking about what's on screen

/// A question to ask in place: "Ask why" on a status that needs a look.
struct FeedAskChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "sparkle")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.accentSoft, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

extension View {
    /// Asks McFly `question` when it's set, in Ask's look (full screen on
    /// iPhone, a sheet on the Mac); closing it sets it back to nil.
    func feedQuestion(_ question: Binding<String?>) -> some View {
        modifier(FeedQuestionPresenter(question: question))
    }
}

private struct FeedQuestionPresenter: ViewModifier {
    @Binding var question: String?
    /// The last one asked, so the page keeps its words while it closes.
    @State private var asked = ""
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .voiceCover(isPresented: Binding(get: { question != nil }, set: { if !$0 { question = nil } })) {
                FeedQuestionSheet(question: question ?? asked)
                    .environment(app)
            }
            .onChange(of: question) { _, new in
                if let new { asked = new }
            }
    }
}

/// One question about what's on screen, answered as the full-screen Ask
/// answers (`read` mode, laid out with `AnswerMarkdown`): the question as a
/// heading, the answer streaming in under it, Copy and Ask again once it's
/// done. The question goes out as it opens; closing it stops the answer.
struct FeedQuestionSheet: View {
    let question: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    @State private var replying = false
    @State private var failure: String?
    @State private var copied = false
    @State private var round = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Ask McFly", systemImage: "sparkle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.pill(.neutral))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Theme.page)
            .padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(question)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    if replying && answer.isEmpty {
                        FeedThinking()
                    }
                    if !answer.isEmpty {
                        AnswerMarkdown(text: answer)
                    }
                    if let failure, !replying {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(failure)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Try again") { ask() }
                                .buttonStyle(.pill(.soft))
                        }
                    }
                    if !replying && !answer.isEmpty {
                        HStack(spacing: 10) {
                            Button {
                                Pasteboard.copy(answer)
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.pill(.neutral))
                            Button { ask() } label: {
                                Label("Ask again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.pill(.neutral))
                        }
                    }
                }
                .padding(.horizontal, Theme.page)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .screenBackground()
        .macOSFrame(width: 680, height: 720)
        .onAppear {
            if task == nil { ask() }
        }
        .onDisappear { task?.cancel() }
    }

    private func ask() {
        task?.cancel()
        round += 1
        let current = round
        answer = ""
        failure = nil
        copied = false
        replying = true
        let question = question
        let provider = app.feeds.settings?.assistantProvider
        task = Task {
            do {
                try await app.answer(question, .read, [], provider) { event in
                    guard round == current else { return }
                    switch event {
                    case .delta(let piece):
                        answer += piece
                    case .done(let final):
                        if !final.reply.isEmpty { answer = final.reply }
                    case .error(let message):
                        if answer.isEmpty { failure = message }
                    }
                }
            } catch {
                // Stopped: what arrived stays. Anything else is said under the question.
                if round == current && !Task.isCancelled && answer.isEmpty { failure = McFlyError.describe(error) }
            }
            if round == current { replying = false }
        }
    }
}

/// Three dots while the first words are on their way; still under Reduce Motion.
private struct FeedThinking: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .opacity(reduceMotion ? 0.6 : 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.2 - Double(i) * 0.7)))
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityLabel("Thinking")
    }
}

// MARK: Kept for other screens

/// One widget on a plain card, rendered for its type (the bento above draws
/// a board; this is a single widget anywhere else).
struct WidgetCard: View {
    let widget: DashboardWidget

    var body: some View {
        Group {
            switch widget {
            case let .metric(label, value, unit, delta, deltaPct):
                BoardMetricCard(metric: BoardMetric(label: label, value: value, unit: unit, delta: delta, deltaPct: deltaPct,
                                                    trend: widget.trend))
            case let .status(label, state, detail):
                BoardStatusCard(status: BoardStatus(label: label, state: state, detail: detail))
            case let .progress(label, value, max, unit):
                BoardProgressCard(label: label, value: value, limit: max, unit: unit)
            case let .list(title, items):
                BoardListCard(title: title, items: items)
            case let .text(title, body):
                BoardTextCard(title: title, text: body)
            case let .chart(label, points, unit):
                BoardChartCard(label: label, points: points, unit: unit)
            case let .unknown(type):
                VStack(alignment: .leading, spacing: 6) {
                    boardCaption("Unsupported widget")
                    Text(type.isEmpty || type == "?" ? "This version can't show it." : "“\(type)” isn't a type this version shows.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .boardCard()
            }
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
