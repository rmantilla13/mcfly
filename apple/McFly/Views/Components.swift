import McFlyKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: Platform helpers

extension View {
    /// Inline titles on iPhone; the Mac has no large titles to begin with.
    @ViewBuilder
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func emailField() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }

    @ViewBuilder
    func digitsField() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    /// A fixed window size on the Mac; nothing on iOS, where the screen decides.
    @ViewBuilder
    func macOSFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        self
        #endif
    }

    /// Full screen on iPhone, a sheet on the Mac.
    @ViewBuilder
    func voiceCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: Shared pieces

/// Shows the model's errors as an alert on any screen.
struct ErrorAlert: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.alert("Something went wrong", isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

extension View {
    func showsAppErrors() -> some View { modifier(ErrorAlert()) }
}

/// An agent's dot and name, in its color.
struct AgentBadge: View {
    let agent: Agent?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(agent.map { Color(hex: $0.color) } ?? Theme.muted)
                .frame(width: 8, height: 8)
            Text(agent?.name ?? "Agent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }
}

/// Bold section title with an optional trailing action.
struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Muted placeholder card for empty sections.
struct EmptyCard: View {
    let text: String
    var systemImage = "sparkles"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(Theme.muted)
            Text(text).font(.subheadline).foregroundStyle(Theme.muted)
        }
        .card(padding: 16)
    }
}

/// A feed error, inline rather than modal: the screen keeps its old data.
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(Theme.down)
            Text(message).font(.footnote).foregroundStyle(Theme.text)
            Spacer()
            if let retry { Button("Retry", action: retry).buttonStyle(.pill(.soft)) }
        }
        .card(padding: 12, radius: Theme.radiusSm)
    }
}

/// A price's change, colored.
struct ChangeText: View {
    let change: Double?
    let pct: Double?
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        Text(Format.change(change, pct: pct))
            .font(font.monospacedDigit())
            .foregroundStyle(Color.change(pct ?? change))
    }
}

/// A small line chart of prices, oldest to newest, colored by the move.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.accent
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size)
            if points.count >= 2 {
                ZStack {
                    Path { path in
                        path.move(to: points[0])
                        for p in points.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        for p in points { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
            } else if let only = points.first {
                Circle().fill(color).frame(width: 5, height: 5).position(only)
            }
        }
        .accessibilityHidden(true)
    }

    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let span = max(high - low, 0.0001)
        let inset: CGFloat = 3
        let usable = size.height - inset * 2
        return values.enumerated().map { i, v in
            let x = values.count == 1 ? size.width / 2 : size.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = inset + usable * (1 - CGFloat((v - low) / span))
            return CGPoint(x: x, y: y)
        }
    }
}

/// Plain text with light markdown: `- ` bullets as rows, inline emphasis
/// through the kit's `Markdown.inline`. Never a link: Voice's answers and the
/// Boards text widget come from what agents push, so a link keeps its words
/// and loses its address.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Spacer().frame(height: 2)
                } else if let bullet = Self.bullet(line) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(Markdown.inline(bullet))
                    }
                } else {
                    Text(Markdown.inline(line))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    private static func bullet(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "• "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }
}

/// An answer from the full-screen Ask, set for reading: `Markdown` in the kit
/// parses it, this lays the blocks out (the console's components/ask/Markdown.tsx).
/// Headings, lists, tables, quotes and code on the theme's colours; the words
/// only ever land as text, never a link. The assistant's own shapes (its
/// `layout` skill, docs/ASSISTANT.md) are drawn to be taken in at a glance: a
/// tagged item's tag is a chip, a stats block is a row of tiles, and a table
/// is a grid only while it fits the page, each row a card otherwise.
struct AnswerMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(Markdown.blocks(text).enumerated()), id: \.offset) { index, block in
                AnswerBlockView(block: block, first: index == 0)
            }
        }
        .foregroundStyle(Theme.text)
        .textSelection(.enabled)
    }
}

private struct AnswerBlockView: View {
    let block: Markdown.Block
    let first: Bool

    var body: some View {
        switch block {
        case .heading(let level, let text):
            if level <= 2 {
                Text(Markdown.inline(text))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, first ? 0 : 14)
                    .accessibilityAddTraits(.isHeader)
            } else {
                AnswerKicker(text: text)
                    .padding(.top, first ? 0 : 12)
            }
        case .paragraph(let text):
            // The answer itself comes first: a size up, so it's read before the detail.
            if first {
                Text(Markdown.inline(text))
                    .font(.system(.title3, design: .default, weight: .regular))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                AnswerText(text: text)
            }
        case .list(let list):
            if list.items.contains(where: { $0.tag != nil }) {
                AnswerItems(list: list)
            } else {
                AnswerList(list: list, depth: 0)
            }
        case .table(let table):
            AnswerTable(table: table)
                .padding(.vertical, 4)
        case .stats(let stats):
            AnswerStats(stats: stats)
                .padding(.vertical, 2)
        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(Theme.accent.opacity(0.55)).frame(width: 3)
                AnswerText(text: text).foregroundStyle(Theme.muted)
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        case .rule:
            Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 8)
        }
    }
}

/// A paragraph's words, with room between the lines for reading.
private struct AnswerText: View {
    let text: String

    var body: some View {
        Text(Markdown.inline(text))
            .font(.body)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `### Due Monday`: a section's name in small spaced capitals with a
/// hairline after it, as Home's "MCFLY NOTICED", so the sections are found
/// at a glance and the facts under them stay the loudest thing.
private struct AnswerKicker: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(Markdown.inline(text))
                .font(.system(size: 13, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                // The words take the width first; the hairline has what's left.
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }
}

/// What follows an item's name, starting with a capital as a line of its own
/// should ("confirm the card" → "Confirm the card").
private func detailLine(_ detail: String) -> String {
    guard let first = detail.first, first.isLowercase else { return detail }
    return first.uppercased() + detail.dropFirst()
}

/// An item's words: a bold name opening it (`**Armra** — due Monday`) on a
/// line of its own and the rest under it, a little quieter; anything else
/// as one paragraph.
private struct AnswerItemText: View {
    let text: String

    var body: some View {
        let (lead, detail) = Markdown.lead(text)
        if let detail {
            VStack(alignment: .leading, spacing: 3) {
                Text(Markdown.inline(lead))
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(Markdown.inline(detailLine(detail)))
                    .font(.callout)
                    .foregroundStyle(Theme.text.opacity(0.78))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            AnswerText(text: text)
        }
    }
}

/// A list whose items carry tags: one card, a row an item. The name leads
/// each row, the tag sits at the row's end as a chip (so the names line up
/// whatever the chips say), and the detail runs the card's full width
/// under them.
private struct AnswerItems: View {
    let list: Markdown.List

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Rectangle().fill(Theme.divider).frame(height: 1) }
                row(item, number: list.ordered ? list.start + index : nil)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous).stroke(Theme.divider, lineWidth: 1))
    }

    private func row(_ item: Markdown.ListItem, number: Int?) -> some View {
        let (lead, detail) = Markdown.lead(item.text)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let number {
                    Text("\(number).").font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.muted)
                }
                Text(Markdown.inline(lead))
                    .font(detail == nil ? .body : .body.weight(.semibold))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let tag = item.tag { AnswerChip(tag: tag) }
            }
            if let detail {
                Text(Markdown.inline(detailLine(detail)))
                    .font(.callout)
                    .foregroundStyle(Theme.text.opacity(0.78))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sub = item.sub { AnswerList(list: sub, depth: 1).padding(.top, 4) }
        }
    }
}

/// Bullets in the accent, numbers muted; a sub-list sits under its item. A
/// bold name opening an item gets a line of its own (`AnswerItemText`).
private struct AnswerList: View {
    let list: Markdown.List
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    marker(index)
                    VStack(alignment: .leading, spacing: 9) {
                        AnswerItemText(text: item.text)
                        if let sub = item.sub { AnswerList(list: sub, depth: depth + 1) }
                    }
                }
            }
        }
        .padding(.leading, depth == 0 ? 2 : 0)
    }

    @ViewBuilder
    private func marker(_ index: Int) -> some View {
        if list.ordered {
            Text("\(list.start + index).")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 20, alignment: .trailing)
        } else if depth == 0 {
            Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(y: -2).frame(width: 12)
        } else {
            Circle().stroke(Theme.muted, lineWidth: 1.2).frame(width: 6, height: 6).offset(y: -2).frame(width: 12)
        }
    }
}

/// The colour a tag's first word (or a stat's tone) carries: what's late, blocked
/// or down in the loss red, what's done or up in the gain green, what's
/// waiting in the palette's warning ink (a dark amber by day, so it reads
/// as text on white), and a day or a time in the accent.
private enum AnswerTone {
    static func color(for tag: String) -> Color {
        let word = tag.lowercased().split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
        switch word {
        case "down", "overdue", "late", "blocked", "missed", "off": return Theme.loss
        case "up", "done", "paid", "sent", "shipped", "on": return Theme.gain
        case "watch", "waiting", "pending", "soon", "risk": return Theme.warningInk
        default: return Theme.accent
        }
    }
}

/// `[Mon]`, `[Blocked]`: the tag on a list item, as a small capsule.
private struct AnswerChip: View {
    let tag: String

    var body: some View {
        let color = AnswerTone.color(for: tag)
        Text(tag)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .offset(y: -1)
    }
}

/// Key figures as tiles, two to a row on a phone: the label small and
/// muted, the figure large, in the tone's colour when it has one.
private struct AnswerStats: View {
    let stats: [Markdown.Stat]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .topLeading)], alignment: .leading, spacing: 8) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Text(Markdown.inline(stat.value))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(stat.tone.map { AnswerTone.color(for: $0.rawValue) } ?? Theme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous).stroke(Theme.divider, lineWidth: 1))
            }
        }
    }
}

/// A table on a card. While it fits the page it is a grid: the header on
/// the sunken colour, a rule between rows, figures in even digits, every
/// cell on one line (a long one wraps past a point). Wider than the page, as
/// on a phone, it is a stack of cards instead: each row's first cell is the
/// card's title and the other cells sit under it with the header's words as
/// labels, so nothing is squeezed, cut off or drawn over its neighbour.
private struct AnswerTable: View {
    let table: Markdown.Table

    /// The header cells' bounds: the tallest one's bottom edge is where its shading ends.
    private struct HeaderBounds: PreferenceKey {
        static let defaultValue: [Anchor<CGRect>] = []
        static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) { value += nextValue() }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid
            stacked
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous).stroke(Theme.divider, lineWidth: 1))
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Rectangle().fill(Theme.divider).frame(height: 1) }
                VStack(alignment: .leading, spacing: table.header.count == 2 ? 3 : 6) {
                    if let title = row.first, !title.isEmpty {
                        Text(Markdown.inline(title))
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(row.enumerated().dropFirst()), id: \.offset) { column, text in
                        if !text.isEmpty && table.header.count == 2 {
                            // Two columns: the name, then what it says. The label would only repeat the header.
                            Text(Markdown.inline(text))
                                .font(.callout)
                                .foregroundStyle(Theme.text.opacity(0.78))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !text.isEmpty {
                            let label = column < table.header.count ? table.header[column] : ""
                            if text.count <= 24 {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(Markdown.inline(label)).font(.subheadline).foregroundStyle(Theme.muted)
                                    Spacer(minLength: 8)
                                    Text(Markdown.inline(text)).font(.subheadline).monospacedDigit().multilineTextAlignment(.trailing)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Markdown.inline(label)).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                                    Text(Markdown.inline(text)).font(.subheadline).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(table.header.enumerated()), id: \.offset) { column, text in
                    cell(text, column: column, header: true)
                        .anchorPreference(key: HeaderBounds.self, value: .bounds) { [$0] }
                        .gridColumnAlignment(alignment(column).horizontal)
                }
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(Theme.divider).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, text in
                        cell(text, column: column, header: false)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // The header's shading, edge to edge across the row.
        .backgroundPreferenceValue(HeaderBounds.self) { cells in
            GeometryReader { proxy in
                Theme.sunken.frame(height: cells.map { proxy[$0].maxY }.max() ?? 0)
            }
        }
    }

    @ViewBuilder
    private func cell(_ text: String, column: Int, header: Bool) -> some View {
        let alignment = alignment(column)
        let words = Text(Markdown.inline(text))
            .font(header ? .subheadline.weight(.semibold) : .subheadline.weight(column == 0 ? .medium : .regular))
            .monospacedDigit()
            .multilineTextAlignment(alignment.text)
        let sized = Group {
            if text.count <= 24 {
                words.fixedSize()
            } else {
                words.fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: alignment.frame)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        if column == 0 {
            sized.frame(maxWidth: .infinity, alignment: alignment.frame)
        } else {
            sized
        }
    }

    private func alignment(_ column: Int) -> (frame: Alignment, horizontal: HorizontalAlignment, text: TextAlignment) {
        switch column < table.alignments.count ? table.alignments[column] : nil {
        case .trailing: return (.trailing, .trailing, .trailing)
        case .center: return (.center, .center, .center)
        case .leading, nil: return (.leading, .leading, .leading)
        }
    }
}

/// A brief's body: paragraphs with blank lines between, `- ` lines as bullets.
struct BriefBody: View {
    let text: String
    var font: Font = .body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(BriefText.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(text).font(font)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(y: -2)
                                Text(item).font(font)
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
}

/// An agent key, shown the one time it exists in the clear.
struct KeyRevealView: View {
    let title: String
    let key: String
    let onDone: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: "key.fill")
                .font(.headline)
            Text("Copy it now. McFly keeps only a hash, so it can't be shown again; you can rotate it later.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(key)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
            HStack(spacing: 10) {
                Button {
                    Pasteboard.copy(key)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.pill(.soft))
                ShareLink(item: key) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.pill(.neutral))
                Spacer()
                Button("Done", action: onDone).buttonStyle(.pill())
            }
        }
        .padding(Theme.page)
    }
}

/// A story's picture, or the glow when the agent sent none. The box is as
/// wide as the column and `height` tall; the picture fills it in an overlay,
/// because a filled picture reports the width it fills to (391 pt for a 16:9
/// picture 220 pt tall), and as a stacked child that width pushed the whole
/// page past its margins.
struct StoryImage: View {
    let url: URL?
    var height: CGFloat = 180

    var body: some View {
        Theme.sunken
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { GlowView(opacity: 0.8).scaleEffect(1.3) }
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                } else {
                    Image(systemName: "newspaper")
                        .font(.system(size: height * 0.22, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
    }
}
