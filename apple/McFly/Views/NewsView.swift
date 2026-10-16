import McFlyKit
import SwiftUI

/// The newest Pulse report by section, with a picker for older ones.
struct NewsView: View {
    @Environment(AppModel.self) private var app
    @State private var chosenId: UUID?

    private var feeds: FeedStore { app.feeds }
    private var report: NewsReport? { feeds.report(chosenId) ?? feeds.latestReport }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                if let report {
                    reportHeader(report)
                    if let hero = report.hero {
                        // Its own card per story: a new hero loads under the glow afresh.
                        NavigationLink(value: hero) { HeroStoryCard(item: hero).id(hero.id) }
                            .buttonStyle(PressableStyle())
                    }
                    ForEach(report.sections) { section in
                        SectionHeader(section.name)
                        ForEach(section.items) { item in
                            NavigationLink(value: item) { StoryCard(item: item) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                } else {
                    EmptyCard(text: feeds.hasLoaded ? "No report yet. The Daily Pulse pipeline pushes one a day." : "Loading…",
                              systemImage: "newspaper")
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("News")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Report", selection: Binding(get: { report?.id }, set: { chosenId = $0 })) {
                        ForEach(feeds.reports) { r in
                            Text(r.displayDate ?? r.reportDate).tag(Optional(r.id))
                        }
                    }
                } label: {
                    Label("Older reports", systemImage: "calendar")
                }
                .disabled(feeds.reports.count < 2)
            }
        }
        .navigationDestination(for: NewsItem.self) { StoryDetailView(item: $0) }
    }

    private func reportHeader(_ report: NewsReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DAILY PULSE")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline) {
                Text(report.displayDate ?? report.reportDate)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(report.items.count) stories")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            AgentBadge(agent: feeds.agent(report.agentId))
        }
    }
}

/// Thumbnail, headline, takeaway.
struct StoryCard: View {
    let item: NewsItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StoryImage(url: item.image, height: 72)
                .frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if !item.takeaway.isEmpty {
                    Text(item.takeaway)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(item.source)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 10, radius: Theme.radiusSm)
    }
}

/// The story's picture, takeaway and source, and the link out.
struct StoryDetailView: View {
    let item: NewsItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StoryImage(url: item.image, height: 220)
                Tag(text: item.sectionName, color: Theme.coral)
                Text(item.headline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                if !item.takeaway.isEmpty {
                    Text(item.takeaway)
                        .font(.body)
                        .foregroundStyle(Theme.text.opacity(0.9))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.caption)
                    Text(item.source).font(.footnote)
                }
                .foregroundStyle(Theme.muted)
                if let link = item.link {
                    Button {
                        openURL(link)
                    } label: {
                        Label("Open Link", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.pill())
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(item.sectionName)
        .inlineTitle()
    }
}

/// The hero story as a magazine cover: the picture edge to edge, drifting in
/// a slow Ken Burns zoom, with the section, the headline and the source set
/// over its foot. With no picture, the display's gradient tile in the glow
/// colours carries the words instead.
struct HeroStoryCard: View {
    let item: NewsItem
    /// The picture is in: the glow under it goes, and the drift starts.
    @State private var loaded = false
    /// Whether the cover is on screen; its gradient rests once it's scrolled away.
    @State private var visible = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        Group {
            if let url = item.image {
                Theme.sunken
                    .overlay {
                        // A glow while the picture loads, gone once it covers it.
                        if !loaded {
                            GlowView(opacity: 0.8).scaleEffect(1.3).transition(.opacity)
                        }
                    }
                    .overlay {
                        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.6))) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill().transition(.opacity)
                                    .onAppear {
                                        // After the picture's own fade, when it hides the glow anyway.
                                        withAnimation(.easeOut(duration: 0.2).delay(0.6)) { loaded = true }
                                    }
                            }
                        }
                        .modifier(KenBurns(playing: loaded))
                    }
                    .overlay {
                        LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.35),
                                               .init(color: .black.opacity(0.72), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        words(kicker: .white.opacity(0.85), ink: .white, muted: .white.opacity(0.8))
                    }
            } else {
                GradientTile(colors: Theme.palette.glow, radius: Theme.radius, rings: 1, seed: 3.3, fps: 20, active: visible) { tile in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Spacer()
                            Image(systemName: "newspaper")
                                .font(.system(size: 54, weight: .light))
                                .foregroundStyle(tile.ink.opacity(0.14))
                        }
                        Spacer(minLength: 0)
                        words(kicker: tile.strong, ink: tile.ink, muted: tile.inkMuted)
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                }
                .homeOnScreen($visible)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .contentShape(shape)
    }

    private func words(kicker: Color, ink: Color, muted: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.sectionName.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(kicker)
                .lineLimit(1)
            Text(item.headline)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(ink)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
            Text(item.source)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(muted)
                .lineLimit(1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A slow pan and zoom over a picture (36 s there and back), drawn only once
/// the picture is in, while the app is in front and the News screen shows,
/// and (iOS 18, macOS 15) while it isn't scrolled away; still with Reduce
/// Motion on.
private struct KenBurns: ViewModifier {
    var playing = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false
    @State private var visible = true

    static let period: TimeInterval = 36

    func body(content: Content) -> some View {
        let paused = reduceMotion || !playing || !onScreen || !visible || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // 0 → 1 → 0, eased at both ends.
            let p = reduceMotion ? 0 : (1 - cos(t * 2 * .pi / Self.period)) / 2
            content
                .scaleEffect(1.04 + 0.08 * p, anchor: UnitPoint(x: 0.35 + 0.3 * p, y: 0.45 + 0.1 * p))
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .homeOnScreen($visible)
    }
}
