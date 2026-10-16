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

/// Plain text with light markdown: `- ` bullets as rows, inline emphasis.
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
                        Text(Self.inline(bullet))
                    }
                } else {
                    Text(Self.inline(line))
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

    private static func inline(_ line: String) -> AttributedString {
        (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(line)
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
