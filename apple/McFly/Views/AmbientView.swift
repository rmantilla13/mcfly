import McFlyKit
import SwiftUI

/// The display's ambient screen saver (display/qml/screensaver/AmbientSaver.qml)
/// full screen on the phone, for a stand or a nightstand: the backdrop the
/// displays show (`AccountBackdrop`: the moving gradient with an aurora
/// hanging over it at night, `AuroraGlow`, fading in, or one of the display's
/// skies, `Backdrop`), a big clock, the date, what's next and what follows, and a rail
/// of cards from the feeds (the latest brief, the markets, a blocked
/// project, today's top story, the rest of the day). With no feeds yet it is
/// just the clock. The composition drifts a few points every minute, the
/// screen stays awake, and a tap anywhere goes back.
///
/// Under the date, what McFly noticed (`Insights`, as on the console's
/// ambient view) turns over one line at a time, cross-fading every 12 s.
struct AmbientView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var shift = CGSize.zero

    private var feeds: FeedStore { app.feeds }

    var body: some View {
        let night = Theme.palette.isDark
        let backdrop = app.backdrop
        TimelineView(.everyMinute) { context in
            let now = context.date
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height
                // The backdrop (the displays' Settings → Backdrop): the mesh is
                // the moving gradient with an aurora hanging over it at night; the
                // rest are skies of their own (Backdrop), at the saver's pace.
                Group {
                    if backdrop == AccountBackdrop.mesh {
                        GradientTile(colors: Theme.palette.glow, dark: night, radius: 0, ringScale: 1.3, period: 72, fps: 15) { tile in
                            ZStack(alignment: .topLeading) {
                                // At night an aurora in the night glow hangs over the
                                // clock, edge to edge and still while the rest drifts,
                                // as on the display's saver. It ticks with the gradient.
                                if night {
                                    AuroraGlow(lightMode: false, hem: 0.36, amplitude: 1.1, blend: 0.7, layers: 2,
                                               opacity: 0.5, speed: 0.35, maxFps: 15)
                                        .transition(.opacity)
                                }
                                placed(composition(now: now, tile: tile, night: night, wide: wide, size: geo.size), wide: wide, geo: geo)
                            }
                        }
                    } else {
                        Backdrop(style: backdrop, colors: Theme.palette.glow, dark: night) { sky in
                            placed(composition(now: now, tile: sky, night: night, wide: wide, size: geo.size), wide: wide, geo: geo)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: context.date) {
                withAnimation(.easeInOut(duration: 4)) {
                    shift = CGSize(width: .random(in: -10...10), height: .random(in: -8...8))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .accessibilityAction(named: "Close") { dismiss() }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .onAppear { ScreenAwake.hold("ambient") }
        .onDisappear { ScreenAwake.release("ambient") }
        // The displays' backdrop may have been changed since the app opened.
        .task { await app.syncBackdrop() }
    }

    /// The composition in its place: in from the edges, clear of the notch and
    /// the home indicator, and drifting.
    private func placed(_ composition: some View, wide: Bool, geo: GeometryProxy) -> some View {
        composition
            .padding(.horizontal, wide ? 48 : 28)
            .padding(.top, geo.safeAreaInsets.top + (wide ? 28 : 24))
            .padding(.bottom, geo.safeAreaInsets.bottom + 24)
            .offset(shift)
    }

    // MARK: What to say

    private func todaysEvents(_ now: Date) -> [CalendarEvent] {
        feeds.events.filter { !$0.allDay && $0.endsAt > now && Calendar.current.isDate($0.startsAt, inSameDayAs: now) }
    }

    private func nextLine(_ events: [CalendarEvent], now: Date) -> String? {
        guard let event = events.first else { return nil }
        let clock = Timeline.Clock()
        if event.startsAt <= now { return "\(event.title), until \(clock.label(event.endsAt))" }
        let minutes = Int((event.startsAt.timeIntervalSince(now) / 60).rounded())
        return minutes < 60 ? "\(event.title) \(Timeline.untilLabel(event.startsAt, now: now, long: true))"
                            : "\(event.title) at \(clock.label(event.startsAt))"
    }

    private func thenLine(_ events: [CalendarEvent]) -> String? {
        let later = events.dropFirst().prefix(2)
        guard !later.isEmpty else { return nil }
        let clock = Timeline.Clock()
        return "Then " + later.map { "\($0.title) at \(clock.label($0.startsAt))" }.joined(separator: " · ")
    }

    private enum Card: Hashable { case brief, markets, blocked, pulse, later }

    /// What McFly noticed, less what the screen already says: the event the
    /// next line names, and the brief, the blocked project and the Pulse on
    /// the rail's cards.
    private func noticed(now: Date, events: [CalendarEvent], shown: [Card]) -> [Insight] {
        let brief = shown.contains(.brief) ? feeds.latestBrief?.id : nil
        let report = shown.contains(.pulse) ? feeds.todaysReport(now: now)?.id : nil
        return HomeView.noticed(feeds.insights(now: now), upNext: events.first,
                                shownProject: shown.contains(.blocked) ? feeds.blockedProjects.first : nil)
            .filter { insight in
                switch insight.target {
                case .brief(let id): return id != brief
                case .report(let id): return id != report
                default: return true
                }
            }
    }

    private func cards(_ events: [CalendarEvent], now: Date) -> [Card] {
        var list: [Card] = []
        if feeds.latestBrief != nil { list.append(.brief) }
        if !feeds.series.isEmpty { list.append(.markets) }
        if !feeds.blockedProjects.isEmpty { list.append(.blocked) }
        if feeds.todaysReport(now: now)?.hero != nil { list.append(.pulse) }
        if events.count > 3 { list.append(.later) }
        return list
    }

    // MARK: The look

    @ViewBuilder
    private func composition(now: Date, tile: some BackdropInks, night: Bool, wide: Bool, size: CGSize) -> some View {
        let events = todaysEvents(now)
        let shown = Array(cards(events, now: now).prefix(wide ? 3 : 4))
        let face = Timeline.Clock().parts(now)
        VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty { Spacer() }
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(face.time)
                    .font(.system(size: wide ? 150 : 124, weight: .light))
                    .tracking(-6)
                    .monospacedDigit()
                    .foregroundStyle(tile.ink)
                Text(face.ampm.uppercased())
                    .font(.system(size: 28))
                    .foregroundStyle(tile.inkMuted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 26))
                .foregroundStyle(tile.ink)
            // Built once a minute, with the clock; the line turns on its own.
            NoticedLine(insights: noticed(now: now, events: events, shown: shown), now: now, ink: tile.ink, wide: wide)
                .padding(.top, 10)
            if let next = nextLine(events, now: now) {
                Text(next)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tile.ink)
                    .lineLimit(2)
                    .padding(.top, 18)
            }
            if let then = thenLine(events) {
                Text(then)
                    .font(.system(size: 18))
                    .foregroundStyle(tile.inkMuted)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            Spacer(minLength: 24)
            if !shown.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: wide ? 3 : 2), spacing: 14) {
                    ForEach(shown, id: \.self) { card in
                        cardView(card, events: events, night: night, now: now)
                            .frame(height: wide ? 190 : 168)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private struct CardStyle {
        let fill: Color, ink: Color, muted: Color
        init(night: Bool) {
            fill = night ? Color(.sRGB, red: 0.08, green: 0.08, blue: 0.12, opacity: 0.55) : .white.opacity(0.86)
            ink = night ? .white.opacity(0.78) : Color(rgb: 0x1D1B24)
            muted = night ? .white.opacity(0.55) : Color(rgb: 0x4A4555)
        }
    }

    @ViewBuilder
    private func cardView(_ card: Card, events: [CalendarEvent], night: Bool, now: Date) -> some View {
        let style = CardStyle(night: night)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Group {
            switch card {
            case .brief:
                if let brief = feeds.latestBrief {
                    let agent = feeds.agent(brief.agentId)
                    // As the display says when: the time if it's today's, else the day and the time.
                    let when = Calendar.current.isDate(brief.publishedAt, inSameDayAs: now)
                        ? Timeline.Clock().label(brief.publishedAt)
                        : "\(Format.dayLabel(brief.publishedAt, now: now)) · \(Timeline.Clock().label(brief.publishedAt))"
                    TextCard(kicker: [agent?.name, when].compactMap { $0 }.joined(separator: " · "),
                             kickerColor: night ? style.muted : (agent.map { Color(hex: $0.color) } ?? Theme.accent),
                             title: brief.title, text: BriefText.summary(brief.body), style: style)
                }
            case .markets:
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "MARKETS", color: night ? style.muted : Theme.success)
                    ForEach(feeds.series.prefix(4)) { series in
                        HStack {
                            Text(series.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(style.ink)
                            Spacer()
                            Text(Format.percent(series.latest.changePct))
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(night ? style.ink : ((series.latest.changePct ?? 0) >= 0 ? Color(rgb: 0x1C7A4E) : Color(rgb: 0xB5432A)))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            case .blocked:
                if let project = feeds.blockedProjects.first {
                    let others = feeds.blockedProjects.count - 1
                    TextCard(kicker: "NEEDS YOU", kickerColor: night ? Color(rgb: 0xFF9B8A) : Color(rgb: 0xB23224),
                             title: others > 0 ? "\(project.name) and \(others) more are blocked" : "\(project.name) is blocked",
                             text: [project.nextStep ?? project.summary, project.progress.map { "\($0)% done" } ?? ""]
                                .filter { !$0.isEmpty }.joined(separator: " · "),
                             style: style, titleColor: night ? nil : Color(rgb: 0x3B1D12), textColor: night ? nil : Color(rgb: 0x5A3426))
                }
            case .pulse:
                if let report = feeds.todaysReport(now: now), let hero = report.hero {
                    let source = feeds.agent(report.agentId)?.name ?? "Daily Pulse"
                    VStack(alignment: .leading, spacing: 0) {
                        if let url = hero.image {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.accent.opacity(0.3) }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .clipped()
                            .opacity(night ? 0.7 : 1)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ViewThatFits(in: .horizontal) {
                                Kicker(text: "\(source.uppercased()) · \(report.items.count) STORIES", color: night ? style.muted : Theme.accent)
                                Kicker(text: source.uppercased(), color: night ? style.muted : Theme.accent)
                            }
                            Text(hero.headline)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(style.ink)
                                .lineLimit(hero.image == nil ? 4 : 2)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                    }
                }
            case .later:
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "LATER TODAY", color: night ? style.muted : Theme.accent)
                    ForEach(events.dropFirst(3).prefix(3)) { event in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(event.color.map(Color.init(hex:)) ?? Theme.accent).frame(width: 4, height: 20)
                            Text(Timeline.Clock().parts(event.startsAt).time)
                                .font(.system(size: 14).monospacedDigit())
                                .foregroundStyle(style.muted)
                            Text(event.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(style.ink)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(card == .blocked && !night ? Color(rgb: 0xFFE7DF) : style.fill, in: shape)
        .clipShape(shape)
    }

    /// What McFly noticed, one line at a time: every line is there, stacked,
    /// and only the one whose turn it is shows, so the composition never
    /// moves as they change. The turn follows the clock (12 s each); with
    /// Reduce Motion on, the lines change without the fade.
    private struct NoticedLine: View {
        let insights: [Insight]
        let now: Date
        let ink: Color
        let wide: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        static let turn: TimeInterval = 12

        var body: some View {
            if !insights.isEmpty {
                // Turns on the clock's 12 s marks, counted from the minute (one of them).
                let minute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
                TimelineView(.periodic(from: minute, by: Self.turn)) { context in
                    let current = Int(context.date.timeIntervalSinceReferenceDate / Self.turn) % insights.count
                    ZStack(alignment: .leading) {
                        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: wide ? 18 : 16, weight: .semibold))
                                Text(insight.title)
                                    .lineLimit(1)
                            }
                            .font(.system(size: wide ? 22 : 19, weight: .medium))
                            .foregroundStyle(ink)
                            .opacity(index == current ? 0.82 : 0)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("McFly noticed: \(insight.title)")
                            .accessibilityHidden(index != current)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.4), value: current)
                }
            }
        }
    }

    private struct Kicker: View {
        let text: String
        let color: Color
        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private struct TextCard: View {
        let kicker: String
        let kickerColor: Color
        let title: String
        let text: String
        let style: CardStyle
        var titleColor: Color?
        var textColor: Color?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: kicker.uppercased(), color: kickerColor)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(titleColor ?? style.ink)
                    .lineLimit(2)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(textColor ?? style.muted)
                    .lineLimit(4)
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }
}
