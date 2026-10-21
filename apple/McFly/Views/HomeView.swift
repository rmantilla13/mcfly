import McFlyKit
import SwiftUI

/// Home: today, in time order. The display's Home in its portrait layout
/// (display/qml/screens/HomeScreen.qml, Tall): the greeting and the clock,
/// what's up next, anything blocked, the way to ask McFly, the markets in
/// one strip, then one stream of what arrived and what is planned
/// (`Timeline`). Past rows fade, the event on now is outlined, the next one
/// is marked. Under the last row, tomorrow's events preview what's coming.
/// The moon opens the ambient screen.
///
/// On iPhone and iPad the status bar tells the time, so the big clock gives
/// its room to four glance tiles (`GlanceGrid`): what's next, the weather,
/// what needs you and the top story.
///
/// Under them, **McFly noticed**: what stands out right now (`Insights`, the
/// console's Today and the display's highlights), ranked, each opening what
/// it is about and offering its question to Ask; a snap carousel on a phone,
/// a grid with the first one wide where there's room. Over the Ask bar, the
/// questions Home suggests (`Suggestions`). Both are worked out from one
/// snapshot of the feeds each minute, and keyed by their ids, so a refresh
/// moves only what changed.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var showAsk = false
    /// The question an insight or a chip asked: set, it opens the answer page
    /// that asks it (`feedQuestion`, as Dashboards and Projects ask theirs);
    /// closing that page sets it back to nil.
    @State private var askQuestion: String?
    @State private var showVoice = false
    @State private var showAmbient = Config.opensAmbient
    @State private var weather = WeatherModel(isDemo: Config.isDemo)

    private var feeds: FeedStore { app.feeds }

    #if os(iOS)
    static let showsClock = false
    #else
    static let showsClock = true
    #endif

    var body: some View {
        // Past, now and next move once a minute, and so does the clock.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let timeline = feeds.timeline(now: now)
            let tomorrow = feeds.tomorrow(now: now)
            // One snapshot of the feeds for what stands out and what to ask.
            let feed = feeds.snapshot
            let insights = Insights.build(feed, now: now)
            let questions = Suggestions.build(for: .home, feed, now: now, insights: insights)
            let upNext = Timeline.upNext(feeds.events, now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ClockHeader(now: now, greeting: Timeline.greeting(now: now, name: feeds.displayName),
                                synced: feeds.loadedAt, isDemo: app.isDemo, showsClock: Self.showsClock) {
                        showAmbient = true
                    }
                    if let message = feeds.errorMessage {
                        ErrorBanner(message: message) { Task { await feeds.refresh() } }
                    }
                    #if os(iOS)
                    GlanceGrid(now: now, feeds: feeds, weather: weather)
                    let shownProject = GlanceGrid.shownProject(feeds, now: now)
                    let shownReport = GlanceGrid.shownReport(feeds, now: now)?.id
                    let shownBrief = GlanceGrid.todaysAlerts(feeds, now: now).first?.id
                    #else
                    if let event = upNext {
                        NavigationLink(value: event) { NextCard(event: event, now: now) }
                            .buttonStyle(PressableStyle())
                            .homeRise(0)
                    }
                    if let project = feeds.needsYou.first {
                        NavigationLink(value: project) {
                            BlockedCard(project: project, others: feeds.needsYou.count - 1)
                        }
                        .buttonStyle(PressableStyle())
                        .homeRise(1)
                    }
                    let shownProject = feeds.needsYou.first
                    // The Mac's Home has no Top story or Needs you tile.
                    let shownReport: UUID? = nil
                    let shownBrief: UUID? = nil
                    #endif
                    NoticedSection(insights: Self.noticed(insights, upNext: upNext, shownProject: shownProject,
                                                          shownReport: shownReport, shownBrief: shownBrief),
                                   feed: feed, onAsk: ask)
                    SuggestionChips(questions: questions, onAsk: ask)
                    AskBar(onAsk: { showAsk = true }, onTalk: { showVoice = true })
                    MarketsStrip(series: Array(feeds.series.prefix(6)))
                    DayHeading(title: "TODAY", note: Self.things(timeline.count))
                    if timeline.isEmpty {
                        Text(feeds.hasLoaded
                             ? "Nothing yet today. Briefs, the Pulse, project updates and your calendar land here as your agents push them."
                             : "Loading today…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(timeline.enumerated()), id: \.element.id) { index, item in
                                NavigationLink(value: HomeRoute(item, feeds: feeds)) {
                                    TimelineRow(item: item, state: Timeline.state(at: index, in: timeline, now: now), now: now)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                    // Tomorrow's events under today's last row: a preview of what's
                    // coming, on the same rows, with nothing past, on now or next.
                    if !tomorrow.isEmpty {
                        DayHeading(title: "TOMORROW", note: "\(Timeline.tomorrowLabel(now: now)) · \(Self.things(tomorrow.count))")
                        LazyVStack(spacing: 10) {
                            ForEach(tomorrow) { item in
                                NavigationLink(value: HomeRoute(item, feeds: feeds)) {
                                    TimelineRow(item: item, state: .none, now: now)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.page)
                .padding(.top, 4)
                .padding(.bottom, 28)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        // The feed fades out under the status bar, as the display's portrait feed does at its edges.
        .overlay(alignment: .top) {
            LinearGradient(stops: [.init(color: Theme.background, location: 0), .init(color: Theme.background, location: 0.55),
                                   .init(color: Theme.background.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 14)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .screenBackground()
        .refreshable {
            weather.refreshIfStale()
            await feeds.refresh()
        }
        .onAppear { weather.refreshIfStale() }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationTitle("Home")
        .navigationDestination(for: CalendarEvent.self) { EventDetailView(event: $0) }
        .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
        .navigationDestination(for: QuoteSeries.self) { SymbolDetailView(series: $0) }
        .navigationDestination(for: HomeRoute.self) { $0.destination }
        .voiceCover(isPresented: $showVoice) {
            VoiceModeView()
                .environment(app)
        }
        .voiceCover(isPresented: $showAsk) {
            AskView()
                .environment(app)
        }
        .feedQuestion($askQuestion)
        #if os(iOS)
        .fullScreenCover(isPresented: $showAmbient) {
            AmbientView()
                .environment(app)
        }
        #else
        .sheet(isPresented: $showAmbient) {
            AmbientView()
                .environment(app)
                .frame(minWidth: 900, minHeight: 600)
        }
        #endif
    }

    /// "1 thing", "3 things": a day heading's count.
    static func things(_ count: Int) -> String { count == 1 ? "1 thing" : "\(count) things" }

    /// Asks McFly a question from an insight or a chip: the answer page opens
    /// with it as its heading and the answer streaming in under it. (The Ask
    /// bar opens the Ask chat itself.)
    private func ask(_ question: String) {
        askQuestion = question
    }

    /// What stands out, less what the cards above already say (the display's
    /// rule): the blocked project the Needs you tile or card shows, the event
    /// that is up next and, on a phone, the story on the Top story tile and
    /// the alert on the Needs you tile.
    static func noticed(_ insights: [Insight], upNext: CalendarEvent?, shownProject: Project?,
                        shownReport: UUID? = nil, shownBrief: UUID? = nil) -> [Insight] {
        insights.filter { insight in
            switch insight.target {
            case .project(let id): return !(insight.kind == .blocked && id == shownProject?.id)
            case .event(let id): return id != upNext?.id
            case .report(let id): return id != shownReport
            case .brief(let id): return id != shownBrief
            default: return true
            }
        }
    }
}

/// Where a timeline row, a glance tile or an insight goes: the story, the
/// brief, the project, the event, the board, the metric or the symbol.
enum HomeRoute: Hashable {
    case story(NewsItem)
    case brief(Brief)
    case project(Project)
    case event(CalendarEvent)
    case dashboard(Dashboard)
    case metric(MetricSeries)
    case symbol(QuoteSeries)
    case none

    /// Where an insight leads, found in the snapshot it was built from; nil
    /// when that is gone (the card then doesn't open anything).
    init?(_ insight: Insight, in feed: FeedSnapshot) {
        let found: HomeRoute?
        switch insight.target {
        case .project(let id): found = feed.projects.first { $0.id == id }.map(HomeRoute.project)
        case .dashboard(let id): found = feed.dashboards.first { $0.id == id }.map(HomeRoute.dashboard)
        case .metric(let key): found = feed.metrics.first { $0.key == key }.map(HomeRoute.metric)
        case .event(let id): found = feed.events.first { $0.id == id }.map(HomeRoute.event)
        case .symbol(let symbol): found = feed.quotes.first { $0.symbol == symbol }.map(HomeRoute.symbol)
        case .brief(let id): found = feed.briefs.first { $0.id == id }.map(HomeRoute.brief)
        case .report(let id): found = feed.reports.first { $0.id == id }?.hero.map(HomeRoute.story)
        }
        guard let found else { return nil }
        self = found
    }

    @MainActor
    init(_ item: TimelineItem, feeds: FeedStore) {
        switch item.target {
        case .report(let id):
            self = feeds.report(id)?.hero.map(HomeRoute.story) ?? .none
        case .brief(let id):
            self = feeds.briefs.first { $0.id == id }.map(HomeRoute.brief) ?? .none
        case .project(let id):
            self = feeds.project(id).map(HomeRoute.project) ?? .none
        case .event(let id):
            self = feeds.events.first { $0.id == id }.map(HomeRoute.event) ?? .none
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .story(let item): StoryDetailView(item: item)
        case .brief(let brief): BriefReaderView(brief: brief)
        case .project(let project): ProjectDetailView(project: project)
        case .event(let event): EventDetailView(event: event)
        case .dashboard(let board): DashboardsView(board: board.id)
        case .metric(let series): MetricDetailView(series: series)
        case .symbol(let series): SymbolDetailView(series: series)
        case .none: EmptyView()
        }
    }
}

// MARK: The moment

/// The greeting, the big clock and the date.
private struct ClockHeader: View {
    let now: Date
    let greeting: String
    let synced: Date?
    let isDemo: Bool
    /// The display's big clock; on a phone the status bar has the time, so just the date.
    var showsClock = true
    let onAmbient: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                FluxMark()
                    .frame(width: 30, height: 30)
                Text(greeting)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isDemo {
                    Text("DEMO")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.accent)
                }
                Button(action: onAmbient) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Ambient screen")
            }
            if !showsClock {
                Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 6)
                if let syncLabel {
                    Text(syncLabel)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                }
            } else {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(Self.time(now))
                    .font(.system(size: 88, weight: .light))
                    .tracking(-4)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text(Self.period(now))
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .combine)
            Text([now.formatted(.dateTime.weekday(.wide).month(.wide).day()), syncLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 16))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }
        }
    }

    private var syncLabel: String? {
        guard let synced else { return nil }
        let text = Format.relative(synced, now: max(now, synced))
        return text == "Just now" ? "Updated just now" : "Updated \(text)"
    }

    static func time(_ date: Date) -> String { Timeline.Clock().parts(date).time }
    static func period(_ date: Date) -> String { Timeline.Clock().parts(date).ampm.uppercased() }
}

/// Up next (or on now): the display's gradient tile in the event's colour,
/// with the countdown ring on the right (the console's UpNextCard): over the
/// last hour it fills toward the start, then shows how far the event has run.
private struct NextCard: View {
    let event: CalendarEvent
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the card is on screen; its gradient rests once it's scrolled away.
    @State private var visible = true

    var body: some View {
        let base = event.color.map(Color.rgb(hex:)) ?? Theme.palette.accent
        let countdown = Countdown(event: event, now: now)
        GradientTile(base: base, rings: 1, seed: 2, fps: 15, active: visible) { tile in
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(heading)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(tile.inkMuted)
                    Text(event.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(tile.ink)
                        .lineLimit(2)
                    Text([range, event.location ?? event.calendar].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 16))
                        .foregroundStyle(tile.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HomeCountdownRing(countdown: countdown, ink: tile.ink, inkMuted: tile.inkMuted, size: 84, lineWidth: 7)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: countdown.mode)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .shadow(color: Color(rgb: base).opacity(0.3), radius: 16, y: 8)
        .homeOnScreen($visible)
        .accessibilityElement(children: .combine)
    }

    private var heading: String {
        if event.startsAt <= now {
            return "NOW · ENDS \(Timeline.untilLabel(event.endsAt, now: now).uppercased())"
        }
        if !Calendar.current.isDate(event.startsAt, inSameDayAs: now) {
            return "UP NEXT · \(Format.dayLabel(event.startsAt, now: now).uppercased())"
        }
        return "UP NEXT · \(Timeline.untilLabel(event.startsAt, now: now).uppercased())"
    }

    private var range: String {
        let clock = Timeline.Clock()
        return "\(clock.label(event.startsAt)) – \(clock.label(event.endsAt))"
    }
}

/// The first blocked project, on a warm tint; its progress as a ring when
/// the agent reports one (the console's NeedsYouCard).
private struct BlockedCard: View {
    let project: Project
    let others: Int

    var body: some View {
        let dark = Theme.palette.isDark
        HStack(spacing: 14) {
            if let progress = project.progress {
                HomeRing(value: Double(progress) / 100, color: Theme.danger, track: Theme.danger.opacity(0.16), lineWidth: 5,
                         label: "\(project.name): \(progress)% done") {
                    Text("\(progress)%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(value: Double(progress)))
                }
                .frame(width: 46, height: 46)
            } else {
                Circle()
                    .fill(Theme.coral.opacity(0.22))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "exclamationmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.danger))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(others > 0 ? "\(project.name) and \(others) more are blocked" : "\(project.name) is blocked")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let line = project.nextStep ?? (project.summary.isEmpty ? nil : project.summary) {
                    Text(line)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.coral.opacity(dark ? 0.22 : 0.16)))
        .accessibilityElement(children: .combine)
    }
}

/// "Ask McFly" on the voice glow: tap to type, the mic to talk.
private struct AskBar: View {
    let onAsk: () -> Void
    let onTalk: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false

    var body: some View {
        ZStack {
            Color(rgb: 0x1B1A1F)
            // Like the display's, it only moves while Home is showing.
            VoiceGlow(meter: .ambient, kind: .input, cornerRadius: 38, maxFPS: 30,
                      paused: !onScreen || scenePhase != .active)
                .opacity(0.8)
            HStack(spacing: 14) {
                Image(systemName: "sparkle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Ask McFly")
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                Button(action: onTalk) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Talk to McFly")
            }
            .padding(.leading, 26)
            .padding(.trailing, 11)
        }
        .frame(height: 76)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: onAsk)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Ask by typing", onAsk)
    }
}

// MARK: What McFly noticed

/// "McFly noticed": what stands out right now, ranked (`Insights`, the
/// console's InsightsStrip). Each card opens what it is about, and its
/// question asks McFly. On a phone the cards are a carousel that snaps card
/// by card with the next one peeking in; with room (iPad, the Mac) a grid,
/// the first card across the top and an odd one out at the end across its
/// row. Cards are keyed by the insight's id: a refresh that keeps one keeps
/// its card, a new one rises in, the rest slide over.
private struct NoticedSection: View {
    let insights: [Insight]
    let feed: FeedSnapshot
    let onAsk: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// The section's width; 0 until it's known, and the grid takes two
    /// columns till then (what a Mac window or an iPad has).
    @State private var width: CGFloat = 0

    private var wide: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    /// Two cards to a row, one in a narrow Mac window, where two would cut
    /// their words to a few letters.
    private var columns: Int { width > 0 && width < 520 ? 1 : 2 }

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DayHeading(title: "MCFLY NOTICED", note: "", systemImage: "sparkles")
                Group {
                    if insights.count == 1 {
                        card(insights[0], rank: 0)
                    } else if wide {
                        grid
                    } else {
                        carousel
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: insights.map(\.id))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    private func card(_ insight: Insight, rank: Int) -> some View {
        InsightCard(insight: insight, lead: rank == 0, route: HomeRoute(insight, in: feed), onAsk: onAsk)
            .homeRise(rank)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// One card a snap, the next one peeking in from the edge.
    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { rank, insight in
                    card(insight, rank: rank)
                        .containerRelativeFrame(.horizontal) { length, _ in max(220, length - 34) }
                        .frame(maxHeight: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .safeAreaPadding(.horizontal, Theme.page)
        .padding(.horizontal, -Theme.page)
    }

    /// Two to a row: the first across the top, an odd one out at the end
    /// across its row. Each row is as tall as its taller card. (Rows of
    /// stacks, not a Grid: a Grid sizes its rows before the words wrap.)
    /// One to a row when narrow.
    private var grid: some View {
        VStack(spacing: 12) {
            ForEach(Self.rows(insights.count, columns: columns), id: \.self) { row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row.map { insights[$0] }) { insight in
                        card(insight, rank: insights.firstIndex { $0.id == insight.id } ?? 0)
                            .frame(maxHeight: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// [[0], [1, 2], [3, 4]], [[0], [1, 2], [3]]: the ranks on each row;
    /// [[0], [1], [2]] in one column.
    static func rows(_ count: Int, columns: Int = 2) -> [[Int]] {
        guard count > 0 else { return [] }
        guard columns > 1 else { return (0..<count).map { [$0] } }
        var rows: [[Int]] = [[0]]
        var rank = 1
        while rank < count {
            rows.append(rank + 1 < count ? [rank, rank + 1] : [rank])
            rank += 2
        }
        return rows
    }
}

/// One thing McFly noticed: its icon on its colour, what it is and a line
/// more, then its question. The card opens what it is about; the question is
/// a button of its own under it, never inside the link. The first card is a
/// little larger, on a wash of its colour.
private struct InsightCard: View {
    let insight: Insight
    let lead: Bool
    let route: HomeRoute?
    let onAsk: (String) -> Void

    var body: some View {
        let tint = Self.tint(insight)
        let shape = RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if let route {
                NavigationLink(value: route) { summary(tint) }
                    .buttonStyle(PressableStyle())
            } else {
                summary(tint)
            }
            if !insight.question.isEmpty {
                Button { onAsk(insight.question) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        Text(insight.question)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Theme.accentSoft, in: Capsule())
                    // A touch target taller than the pill.
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Ask McFly: \(insight.question)")
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            shape.fill(Theme.surface)
            if lead { shape.fill(tint.wash.opacity(Theme.palette.isDark ? 0.12 : 0.09)) }
        }
    }

    private func summary(_ tint: (glyph: Color, wash: Color)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.systemImage)
                .font(.system(size: lead ? 17 : 15, weight: .semibold))
                .foregroundStyle(tint.glyph)
                .frame(width: lead ? 40 : 36, height: lead ? 40 : 36)
                .background(tint.wash.opacity(Theme.palette.isDark ? 0.26 : 0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(size: lead ? 17 : 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !insight.detail.isEmpty {
                    Text(insight.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.top, lead ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, insight.question.isEmpty ? 14 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The insight's colour (the display's), for the glyph and its wash. The
    /// warning amber is too light for a glyph on a light card: its ink instead.
    static func tint(_ insight: Insight) -> (glyph: Color, wash: Color) {
        if insight.colorHex.caseInsensitiveCompare(Insights.warnHex) == .orderedSame {
            return (Theme.warningInk, Theme.amber)
        }
        let color = Color(hex: insight.colorHex)
        return (color, color)
    }
}

/// Questions to ask in one tap (`Suggestions`: Home's own, "Summarize my
/// day", first, then what the feeds raise), over the Ask bar as on the
/// display. A row that scrolls on a phone; where there's room, they wrap.
private struct SuggestionChips: View {
    let questions: [String]
    let onAsk: (String) -> Void
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var wide: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        if !questions.isEmpty {
            Group {
                if wide {
                    ChipFlow(spacing: 8) { chips }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { chips }
                    }
                    .scrollClipDisabled()
                    .safeAreaPadding(.horizontal, Theme.page)
                    .padding(.horizontal, -Theme.page)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Suggested questions")
        }
    }

    private var chips: some View {
        ForEach(Array(questions.enumerated()), id: \.element) { index, question in
            Button { onAsk(question) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(question)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Ask McFly: \(question)")
            .homeRise(index)
        }
    }
}

/// Lays chips out in rows, wrapping where the next one wouldn't fit.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(Int, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if !row.items.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// The markets in one strip: symbol and change, a tap for the detail.
private struct MarketsStrip: View {
    let series: [QuoteSeries]

    var body: some View {
        if !series.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle().fill(Theme.divider).frame(width: 1, height: 24).padding(.horizontal, 14)
                        }
                        NavigationLink(value: item) {
                            HStack(spacing: 7) {
                                Text(item.symbol)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text(Format.percent(item.latest.changePct))
                                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Color.change(item.latest.changePct))
                            }
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 60)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm + 6, style: .continuous))
        }
    }
}

/// "TODAY ──── 11 things", "TOMORROW ──── Friday · 2 things": a day's heading
/// over its rows; "✦ MCFLY NOTICED ────" over the insights.
private struct DayHeading: View {
    let title: String
    let note: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, -4)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Theme.divider).frame(height: 1)
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: The day

/// One row of the day: the time, then the card.
private struct TimelineRow: View {
    let item: TimelineItem
    let state: TimelineItem.RowState
    let now: Date

    private var isEvent: Bool { item.kind == .event }
    private var color: Color { Color(hex: item.color) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(item.time)
                    .font(.system(size: item.allDay ? 13 : 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(state == .now || state == .next ? Theme.accent : Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !item.ampm.isEmpty {
                    Text(item.ampm)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 50, alignment: .trailing)
            .padding(.top, 16)

            card
        }
        .opacity(state == .past ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                if !isEvent {
                    Text(item.label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                Text(item.title)
                    .font(.system(size: item.kind == .news ? 17 : 16, weight: isEvent || item.kind == .news ? .semibold : .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(item.kind == .brief || item.kind == .alert ? 1 : 2)
                    .multilineTextAlignment(.leading)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if state == .now || state == .next {
                Text(state == .now ? "Now" : Timeline.untilLabel(item.start, now: now))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state == .now ? .white : Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(state == .now ? color : Theme.accentSoft, in: Capsule())
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous)
            if isEvent && state != .now {
                shape.strokeBorder(Theme.divider, lineWidth: 1)
            } else if state == .now {
                shape.fill(Theme.surface).overlay(shape.strokeBorder(color, lineWidth: 2))
            } else {
                shape.fill(Theme.surface)
            }
        }
    }

    /// A picture for the Pulse; else the kind, on its colour.
    @ViewBuilder
    private var badge: some View {
        if item.kind == .news, let url = item.imageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    color.opacity(0.35)
                }
            }
            .frame(width: 84, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.18), in: Circle())
        }
    }
}
