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

/// A story opened: its picture and headline, then the article, as a summary
/// (the assistant's few sentences and key points, with the article's pictures
/// and videos in a strip) or as the full story (the page's own text with its
/// pictures and videos in place). The choice is remembered. The takeaway
/// shows until the article is in, and stays when the page can't be read.
struct StoryDetailView: View {
    let item: NewsItem
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @AppStorage("newsReadMode") private var mode: ReadMode = .summary
    @State private var phase: Phase = .loading
    @State private var viewing: ViewedImage?

    enum ReadMode: String { case summary, full }

    enum Phase: Equatable {
        case loading
        case loaded(NewsArticle)
        case failed(String)
    }

    private var article: NewsArticle? {
        if case .loaded(let article) = phase { return article }
        return nil
    }

    /// Grok's picture of the story, which leads the summary.
    private var drawn: URL? { shown == .summary ? article?.illustration : nil }

    /// The full story when there is one to show, else the summary.
    private var shown: ReadMode {
        guard let article else { return mode }
        return article.hasFullStory ? mode : .summary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StoryImage(url: drawn ?? article?.leadImage ?? item.image, height: 240)
                    .overlay(alignment: .bottomLeading) {
                        if drawn != nil {
                            Text("Drawn by Grok")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.5), in: Capsule())
                                .padding(12)
                        }
                    }
                HStack(spacing: 8) {
                    Tag(text: item.sectionName, color: Theme.coral)
                    Spacer(minLength: 0)
                    if let time = article?.readingTime {
                        Label(time, systemImage: "book")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Text(item.headline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                byline
                Picker("Show", selection: $mode) {
                    Text("Summary").tag(ReadMode.summary)
                    Text("Full story").tag(ReadMode.full)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(article.map { !$0.hasFullStory } ?? false)

                Group {
                    switch phase {
                    case .loading:
                        takeaway
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(mode == .summary ? "Summarizing the article…" : "Reading the article…")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    case .failed(let message):
                        takeaway
                        note("The article couldn't be loaded: \(message)", systemImage: "exclamationmark.triangle") {
                            Button("Try Again") { Task { await load(force: true) } }
                                .buttonStyle(.pill(.soft))
                        }
                    case .loaded(let article):
                        if let working = article.working {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text(working).font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                        if shown == .full {
                            ArticleBlocks(blocks: article.blocks, viewing: $viewing)
                        } else {
                            summary(article)
                        }
                    }
                }
                .transition(.opacity)

                if let link = item.link {
                    Button {
                        openURL(link)
                    } label: {
                        Label(item.source.isEmpty ? "Open Link" : "Read on \(item.source)", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.pill())
                    .padding(.top, 4)
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.25), value: phase)
            .animation(.easeOut(duration: 0.2), value: mode)
        }
        .screenBackground()
        .navigationTitle(item.sectionName)
        .inlineTitle()
        .task(id: item.id) { await load() }
        .sheet(item: $viewing) { image in ImageViewer(url: image.url) }
    }

    // MARK: Parts

    @ViewBuilder
    private var byline: some View {
        let parts = [article?.byline, item.source.isEmpty ? article?.siteName : item.source,
                     article?.publishedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var takeaway: some View {
        if !item.takeaway.isEmpty {
            Text(item.takeaway)
                .font(.body)
                .foregroundStyle(Theme.text.opacity(0.9))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func summary(_ article: NewsArticle) -> some View {
        if let summary = article.summary {
            Text(summary)
                .font(.body)
                .foregroundStyle(Theme.text)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else if article.status == .partial, case .paragraph(let teaser)? = article.blocks.first, item.takeaway.isEmpty {
            Text(teaser).font(.body).foregroundStyle(Theme.text).lineSpacing(4)
        } else {
            takeaway
        }
        if !article.points.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("KEY POINTS")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.muted)
                ForEach(Array(article.points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.coral).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(point)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .card(padding: 16, radius: Theme.radiusSm)
        }
        if !article.media.isEmpty {
            MediaStrip(media: article.media, viewing: $viewing)
        }
        if let model = article.summaryModel, article.summary != nil {
            Label(Self.summarizedBy(model), systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        switch article.status {
        case .ready:
            EmptyView()
        case .partial:
            note("\(item.source.isEmpty ? "The page" : item.source) shares only a preview. The whole story is on its site.", systemImage: "lock")
        case .unavailable:
            note("This page can't be shown here. The whole story is on its site.", systemImage: "doc.questionmark")
        }
    }

    private func note(_ text: String, systemImage: String) -> some View {
        note(text, systemImage: systemImage) { EmptyView() }
    }

    private func note<Action: View>(_ text: String, systemImage: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(text, systemImage: systemImage)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
    }

    static func summarizedBy(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.hasPrefix("claude") { return "Summarized by Claude" }
        if lower.hasPrefix("grok") { return "Summarized by Grok" }
        if lower == "demo" { return "A demo summary" }
        return "Summarized by \(model)"
    }

    // MARK: Loading

    private func load(force: Bool = false) async {
        if !force, let kept = ArticleCache.articles[item.id] {
            phase = .loaded(kept)
            return
        }
        phase = .loading
        do {
            var article = try await app.readArticle(item)
            phase = .loaded(article)
            // The summary or Grok's picture is still being made: ask again
            // every few seconds (about two minutes at most) while the story is open.
            var polls = 0
            while article.pending && polls < 25 {
                try await Task.sleep(for: .seconds(6))
                polls += 1
                if let next = try? await app.readArticle(item) {
                    article = next
                    phase = .loaded(article)
                }
            }
            if !article.pending { ArticleCache.articles[item.id] = article }
        } catch is CancellationError {
            // The story was closed; nothing to show.
        } catch {
            if case .loaded = phase { return } // a poll that failed: what's shown stays
            phase = .failed(McFlyError.describe(error))
        }
    }
}

/// Articles read this session, so going back to a story doesn't ask again.
@MainActor
private enum ArticleCache {
    static var articles: [UUID: NewsArticle] = [:]
}

private struct ViewedImage: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The page's blocks in order: paragraphs, headings, quotes, lists, pictures
/// with their captions, and videos that open where they live.
private struct ArticleBlocks: View {
    let blocks: [NewsArticle.Block]
    @Binding var viewing: ViewedImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                case .heading(let text):
                    Text(text)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 6)
                case .quote(let text, let cite):
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.coral).frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(text)
                                .font(.body.italic())
                                .foregroundStyle(Theme.text.opacity(0.9))
                                .lineSpacing(3)
                            if let cite { Text(cite).font(.caption).foregroundStyle(Theme.muted) }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .list(let items, let ordered):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, text in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(ordered ? "\(i + 1)." : "•")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(Theme.muted)
                                Text(text)
                                    .font(.body)
                                    .foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .image(let url, let caption):
                    ArticleImage(url: url, caption: caption) { viewing = ViewedImage(url: url) }
                case .video(let video):
                    VideoCard(video: video)
                }
            }
        }
    }
}

/// A picture in the story, its whole width; one that won't load is left out.
private struct ArticleImage: View {
    let url: URL
    let caption: String?
    let open: () -> Void
    @State private var failed = false

    var body: some View {
        if !failed {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Color.clear.frame(height: 0).onAppear { failed = true }
                    default:
                        Theme.sunken.frame(height: 200)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

/// A video as its poster with a play button; it opens where it lives.
private struct VideoCard: View {
    let video: NewsArticle.Video
    var height: CGFloat = 200
    var showsCaption = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(video.url)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Theme.sunken
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        if let poster = video.poster {
                            AsyncImage(url: poster) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                            }
                        }
                    }
                    .overlay(Color.black.opacity(0.18))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: height * 0.12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: height * 0.3, height: height * 0.3)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(video.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                if showsCaption, let caption = video.caption {
                    Text(caption).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Play video on \(video.label)")
    }
}

/// The article's pictures and videos in a row under the summary.
private struct MediaStrip: View {
    let media: [NewsArticle.Block]
    @Binding var viewing: ViewedImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IN THE STORY")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(media.prefix(12).enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .image(let url, let caption):
                            Button {
                                viewing = ViewedImage(url: url)
                            } label: {
                                Theme.sunken
                                    .frame(width: 168, height: 112)
                                    .overlay {
                                        AsyncImage(url: url) { phase in
                                            if let image = phase.image { image.resizable().scaledToFill() }
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel(caption ?? "Picture")
                        case .video(let video):
                            VideoCard(video: video, height: 112, showsCaption: false).frame(width: 168)
                        default:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }
}

/// One picture, as large as it goes.
private struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .padding()
            .accessibilityLabel("Close")
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
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
