import McFlyKit
import SwiftUI

/// Home: today, in time order. The display's Home in its portrait layout
/// (display/qml/screens/HomeScreen.qml, Tall): the greeting and the clock,
/// what's up next, anything blocked, the way to ask McFly, the markets in
/// one strip, then one stream of what arrived and what is planned
/// (`Timeline`). Past rows fade, the event on now is outlined, the next one
/// is marked. The moon opens the ambient screen.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var showAsk = false
    @State private var showVoice = false
    @State private var showAmbient = false

    private var feeds: FeedStore { app.feeds }

    var body: some View {
        // Past, now and next move once a minute, and so does the clock.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let timeline = feeds.timeline(now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ClockHeader(now: now, greeting: Timeline.greeting(now: now, name: feeds.displayName),
                                synced: feeds.loadedAt, isDemo: app.isDemo) {
                        showAmbient = true
                    }
                    if let message = feeds.errorMessage {
                        ErrorBanner(message: message) { Task { await feeds.refresh() } }
                    }
                    if let event = Timeline.upNext(feeds.events, now: now) {
                        NavigationLink(value: event) { NextCard(event: event, now: now) }
                            .buttonStyle(PressableStyle())
                    }
                    if let project = feeds.blockedProjects.first {
                        NavigationLink(value: project) {
                            BlockedCard(project: project, others: feeds.blockedProjects.count - 1)
                        }
                        .buttonStyle(PressableStyle())
                    }
                    AskBar(onAsk: { showAsk = true }, onTalk: { showVoice = true })
                    MarketsStrip(series: Array(feeds.series.prefix(6)))
                    TodayHeading(count: timeline.count)
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
        .refreshable { await feeds.refresh() }
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
        .sheet(isPresented: $showAsk) {
            AskSheet()
                .environment(app)
        }
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
}

/// Where a timeline row goes: the story, the brief, the project or the event.
private enum HomeRoute: Hashable {
    case story(NewsItem)
    case brief(Brief)
    case project(Project)
    case event(CalendarEvent)
    case none

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
    let onAmbient: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(colors: [Theme.glow[0], Theme.glow[1]], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "bolt.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
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

    private var syncLabel: String? {
        guard let synced else { return nil }
        let text = Format.relative(synced, now: max(now, synced))
        return text == "Just now" ? "Updated just now" : "Updated \(text)"
    }

    static func time(_ date: Date) -> String { Timeline.Clock().parts(date).time }
    static func period(_ date: Date) -> String { Timeline.Clock().parts(date).ampm.uppercased() }
}

/// Up next (or on now), on the event's colour.
private struct NextCard: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        let color = event.color.map(Color.init(hex:)) ?? Theme.accent
        VStack(alignment: .leading, spacing: 3) {
            Text(heading)
                .font(.system(size: 13, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.88))
            Text(event.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text([range, event.location ?? event.calendar].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: color.opacity(0.35), radius: 16, y: 8)
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

/// The first blocked project, on a warm tint.
private struct BlockedCard: View {
    let project: Project
    let others: Int

    var body: some View {
        let dark = Theme.palette.isDark
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.coral.opacity(0.22))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "exclamationmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.danger))
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

private struct TodayHeading: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("TODAY")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.muted)
            Rectangle().fill(Theme.divider).frame(height: 1)
            Text(count == 1 ? "1 thing" : "\(count) things")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
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
