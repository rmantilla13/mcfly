import McFlyKit
import SwiftUI

/// The top of Home on iPhone and iPad, where the display has its big clock (the
/// status bar already tells the time): four tiles to take in at a glance. What's
/// next, the weather here, what needs you (today's alerts and blocked projects)
/// and the top story. Each opens what it shows.
///
/// What's next is the display's gradient tile in the event's colour, with Up
/// next's ring: over the last hour it fills toward the start, then shows how
/// far the event has run (`Countdown`, the console's UpNextCard). A blocked
/// project's progress is a ring too. The tiles rise in once, staggered, when
/// Home first shows.
struct GlanceGrid: View {
    let now: Date
    let feeds: FeedStore
    let weather: WeatherModel

    var body: some View {
        let alerts = Self.todaysAlerts(feeds, now: now)
        // Rows of two, each as tall as its taller tile. (A Grid sizes its rows
        // before the words wrap, which cut a two-line title to one.)
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NextTile(event: Timeline.upNext(feeds.events, now: now), now: now)
                    .homeRise(0)
                WeatherTile(weather: weather)
                    .homeRise(1)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                NeedsYouTile(alerts: alerts, blocked: feeds.blockedProjects)
                    .homeRise(2)
                TopStoryTile(report: Self.shownReport(feeds, now: now), now: now, feeds: feeds)
                    .homeRise(3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Alert briefs from today, newest first. The Needs you tile shows the first.
    static func todaysAlerts(_ feeds: FeedStore, now: Date) -> [Brief] {
        feeds.briefs.filter { $0.kind == .alert && Calendar.current.isDate($0.publishedAt, inSameDayAs: now) }
    }

    /// The report the Top story tile leads with: today's, else the newest;
    /// none when it has no lead story to show.
    static func shownReport(_ feeds: FeedStore, now: Date) -> NewsReport? {
        guard let report = feeds.todaysReport(now: now) ?? feeds.latestReport, report.hero != nil else { return nil }
        return report
    }

    /// The blocked project the Needs you tile shows (none when an alert takes it).
    static func shownProject(_ feeds: FeedStore, now: Date) -> Project? {
        todaysAlerts(feeds, now: now).isEmpty ? feeds.blockedProjects.first : nil
    }
}

// MARK: Motion and rings, shared with Home

/// A ring that fills clockwise from twelve o'clock: the console's RingGauge
/// and the display's Ring.qml. A faint track all the way round, the value's
/// arc over it with round ends (none at zero, where a round cap would still
/// draw a dot), and whatever is passed in the middle. The arc sweeps in once
/// when the ring first appears and eases to later values.
///
///     HomeRing(value: 0.8, color: Theme.danger, label: "Onyx: 80% done") { Text("80%") }
///         .frame(width: 46, height: 46)
struct HomeRing<Center: View>: View {
    /// 0…1.
    var value: Double
    var color: Color
    /// The track; a faint wash of `color` when nil.
    var track: Color?
    var lineWidth: CGFloat = 6
    /// What the ring says, for VoiceOver ("Onyx: 80% done").
    var label: String
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swept = false

    private var fill: Double { value.isFinite ? min(1, max(0, value)) : 0 }

    var body: some View {
        let shown = (swept || reduceMotion) ? fill : 0
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(track ?? color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(shown > 0.002 ? 1 : 0)
            center
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: fill)
        .onAppear {
            guard !swept else { return }
            if reduceMotion {
                swept = true
            } else {
                withAnimation(.smooth(duration: 0.9).delay(0.12)) { swept = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Up next's ring (the console's UpNextCard, the display's Home): within the
/// hour before an event it fills toward the start; once on, it fills through
/// the event. The minutes sit in the middle and roll over as they change.
/// Nothing at all while the event is more than an hour away.
struct HomeCountdownRing: View {
    let countdown: Countdown
    let ink: Color
    let inkMuted: Color
    var size: CGFloat = 46
    var lineWidth: CGFloat = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if countdown.mode != .later {
            HomeRing(value: countdown.value, color: ink, track: ink.opacity(0.16), lineWidth: lineWidth, label: spoken) {
                VStack(spacing: 0) {
                    Text("\(countdown.minutes)")
                        .font(.system(size: size * 0.32, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ink)
                        .contentTransition(.numericText(value: Double(countdown.minutes)))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: countdown.minutes)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(size >= 70 && countdown.mode == .now ? "MIN LEFT" : "MIN")
                        .font(.system(size: max(8, size * 0.13), weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(inkMuted)
                }
                .padding(lineWidth + 2)
            }
            .frame(width: size, height: size)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    /// For VoiceOver: "Starts in 1 minute", "25 minutes left", "Ending now".
    private var spoken: String {
        let minutes = countdown.minutes
        let count = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if countdown.mode == .now { return minutes < 1 ? "Ending now" : "\(count) left" }
        return minutes < 1 ? "Starting now" : "Starts in \(count)"
    }
}

extension View {
    /// Home's entrance: a short rise and fade, staggered by `index`, played
    /// once per view (a refresh, a new minute or coming back to the tab
    /// doesn't replay it). Nothing moves with Reduce Motion on.
    func homeRise(_ index: Int) -> some View { modifier(HomeRise(index: index)) }
}

private struct HomeRise: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let settled = shown || reduceMotion
        content
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.smooth(duration: 0.42).delay(Double(min(index, 6)) * 0.06)) { shown = true }
                }
            }
    }
}

extension View {
    /// Keeps `visible` saying whether any of this view is on screen in its
    /// scroll view, so a moving tile or picture can rest once it's scrolled
    /// away (iOS 18, macOS 15). Earlier systems leave it as it is, true:
    /// the motion then rests only when its screen goes.
    func homeOnScreen(_ visible: Binding<Bool>) -> some View { modifier(HomeOnScreen(visible: visible)) }
}

private struct HomeOnScreen: ViewModifier {
    @Binding var visible: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            // A sliver counts: a tile half off the edge still moves.
            content.onScrollVisibilityChange(threshold: 0.05) { visible = $0 }
        } else {
            content
        }
    }
}

// MARK: The tiles

/// What a tile looks like: a kicker over its content, on a card (or a colour),
/// with an optional accessory (a ring) in the bottom corner.
private struct Tile<Content: View, Accessory: View>: View {
    let kicker: String
    let systemImage: String
    var tint: Color = Theme.accent
    var fill: Color?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
                Text(kicker.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.1).lineLimit(1)
            }
            .foregroundStyle(fill == nil ? tint : .white.opacity(0.88))
            content
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) { accessory.padding(12) }
        .background(fill ?? Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous))
        .shadow(color: (fill ?? .black).opacity(fill == nil ? 0.04 : 0.3), radius: fill == nil ? 10 : 14, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous))
    }
}

extension Tile where Accessory == EmptyView {
    init(kicker: String, systemImage: String, tint: Color = Theme.accent, fill: Color? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(kicker: kicker, systemImage: systemImage, tint: tint, fill: fill, content: content) { EmptyView() }
    }
}

/// The event on now, else the next one: the display's gradient tile in the
/// event's colour, with the countdown ring in the corner.
private struct NextTile: View {
    let event: CalendarEvent?
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the tile is on screen; its gradient rests once it's scrolled away.
    @State private var visible = true

    var body: some View {
        if let event {
            let base = event.color.map(Color.rgb(hex:)) ?? Theme.palette.accent
            let countdown = Countdown(event: event, now: now)
            NavigationLink(value: event) {
                GradientTile(base: base, radius: Theme.radiusSm + 4, rings: 1, seed: 2, fps: 15, active: visible) { tile in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar").font(.system(size: 11, weight: .bold))
                            Text(heading(event).uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.1).lineLimit(1)
                        }
                        .foregroundStyle(tile.inkMuted)
                        Text(event.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tile.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom, spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Timeline.Clock().label(event.startsAt))
                                    .font(.system(size: 13, weight: .medium))
                                if let location = event.location, !location.isEmpty {
                                    Text(location).font(.system(size: 13))
                                }
                            }
                            .foregroundStyle(tile.inkMuted)
                            .lineLimit(1)
                            Spacer(minLength: 0)
                            HomeCountdownRing(countdown: countdown, ink: tile.ink, inkMuted: tile.inkMuted)
                        }
                        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: countdown.mode)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 132, maxHeight: .infinity, alignment: .topLeading)
                }
                .shadow(color: Color(rgb: base).opacity(0.28), radius: 14, y: 5)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .homeOnScreen($visible)
        } else {
            Tile(kicker: "Up next", systemImage: "calendar", tint: Theme.muted) {
                Text("Nothing else on the calendar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func heading(_ event: CalendarEvent) -> String {
        if event.startsAt <= now { return "Now · ends \(Timeline.untilLabel(event.endsAt, now: now))" }
        if !Calendar.current.isDate(event.startsAt, inSameDayAs: now) { return "Next · \(Format.dayLabel(event.startsAt, now: now))" }
        return "Next · \(Timeline.untilLabel(event.startsAt, now: now))"
    }
}

/// Today's weather here, once location is allowed.
private struct WeatherTile: View {
    let weather: WeatherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch weather.state {
        case .ready(let today, let place):
            Tile(kicker: place.map { "Weather · \($0)" } ?? "Weather", systemImage: "location.fill", tint: Theme.blue) {
                HStack(alignment: .center, spacing: 8) {
                    Text(Weather.degrees(today.temperature))
                        .font(.system(size: 34, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(value: today.temperature))
                    Image(systemName: today.systemImage)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 26))
                        // The multicolour cloud is white: a faint edge keeps it on a white card.
                        .shadow(color: .black.opacity(Theme.palette.isDark ? 0 : 0.18), radius: 1.5, y: 0.5)
                        .contentTransition(.symbolEffect(.replace))
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: today.temperature)
                Text(today.condition)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("H \(Weather.degrees(today.high))  L \(Weather.degrees(today.low))")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: today.high + today.low)
            }
            .onTapGesture { weather.turnOn() }
            .accessibilityElement(children: .combine)
        case .off:
            Button { weather.turnOn() } label: {
                Tile(kicker: "Weather", systemImage: "cloud.sun.fill", tint: Theme.blue) {
                    Text("See today's weather")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("From this phone's approximate location")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(PressableStyle())
        case .denied:
            Tile(kicker: "Weather", systemImage: "location.slash", tint: Theme.muted) {
                Text("Location is off for McFly. Settings → McFly → Location.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        case .loading:
            Tile(kicker: "Weather", systemImage: "cloud.sun.fill", tint: Theme.blue) {
                ProgressView().padding(.top, 8)
            }
        case .failed(let message):
            Button { weather.turnOn() } label: {
                Tile(kicker: "Weather", systemImage: "exclamationmark.triangle", tint: Theme.muted) {
                    Text(message).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Text("Tap to try again").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(PressableStyle())
        }
    }
}

/// Today's alerts and the blocked projects: the newest, and how many more. A
/// blocked project's progress is a ring in the corner (the console's
/// NeedsYouCard); all clear is a full green one.
private struct NeedsYouTile: View {
    let alerts: [Brief]
    let blocked: [Project]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The ring's room, kept clear of the words beside it.
    private static let ring: CGFloat = 46

    var body: some View {
        let more = alerts.count + blocked.count - 1
        if let alert = alerts.first {
            NavigationLink(value: HomeRoute.brief(alert)) {
                content(title: alert.title, detail: BriefText.summary(alert.body), more: more, progress: nil, name: alert.title)
            }
            .buttonStyle(PressableStyle())
        } else if let project = blocked.first {
            NavigationLink(value: project) {
                content(title: "\(project.name) is blocked", detail: project.nextStep ?? project.summary, more: more,
                        progress: project.progress, name: project.name)
            }
            .buttonStyle(PressableStyle())
        } else {
            Tile(kicker: "Needs you", systemImage: "checkmark.circle.fill", tint: Theme.success) {
                Text("All clear")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("No alerts today, nothing blocked")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.trailing, Self.ring)
            } accessory: {
                HomeRing(value: 1, color: Theme.success, lineWidth: 5, label: "All clear") {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.success)
                }
                .frame(width: Self.ring - 6, height: Self.ring - 6)
            }
        }
    }

    private func content(title: String, detail: String, more: Int, progress: Int?, name: String) -> some View {
        Tile(kicker: "Needs you", systemImage: "exclamationmark.circle.fill", tint: Theme.danger) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(more > 0 ? 1 : (progress == nil ? 2 : 3))
                    .multilineTextAlignment(.leading)
                    .padding(.trailing, progress == nil ? 0 : Self.ring)
            }
            if more > 0 {
                Text("and \(more) more")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .contentTransition(.numericText(value: Double(more)))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: more)
                    .padding(.trailing, progress == nil ? 0 : Self.ring)
            }
        } accessory: {
            if let progress {
                HomeRing(value: Double(progress) / 100, color: Theme.danger, lineWidth: 5, label: "\(name): \(progress)% done") {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(progress)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText(value: Double(progress)))
                        Text("%")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.text)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: progress)
                }
                .frame(width: Self.ring, height: Self.ring)
            }
        }
    }
}

/// Today's lead story (else the newest report's). Its picture, when it has
/// one, settles in over the top of the tile as it loads.
private struct TopStoryTile: View {
    let report: NewsReport?
    let now: Date
    let feeds: FeedStore

    var body: some View {
        if let report, let hero = report.hero {
            let source = feeds.agent(report.agentId)?.name ?? "Daily Pulse"
            let today = report.reportDate == Timeline.dayKey(now)
            let kicker = today ? "Top story" : "Top story · \(report.displayDate ?? report.reportDate)"
            NavigationLink(value: HomeRoute.story(hero)) {
                if let url = hero.image {
                    pictured(url: url, kicker: kicker, headline: hero.headline, source: source)
                } else {
                    Tile(kicker: kicker, systemImage: "newspaper.fill", tint: Theme.coral) {
                        Text(hero.headline)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        Text(source)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PressableStyle())
        } else {
            Tile(kicker: "Top story", systemImage: "newspaper", tint: Theme.muted) {
                Text("No Pulse report yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    /// The picture across the top, then the kicker and the headline.
    private func pictured(url: URL, kicker: String, headline: String, source: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            RevealImage(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "newspaper.fill").font(.system(size: 11, weight: .bold))
                    Text(kicker.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.1).lineLimit(1)
                }
                .foregroundStyle(Theme.coral)
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(source)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: shape)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
        .contentShape(shape)
    }
}

/// A picture that settles in as it loads: it fades up from a touch larger
/// (only fading, with Reduce Motion on). On the sunken colour until then.
private struct RevealImage: View {
    let url: URL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Theme.sunken
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: reduceMotion ? 0.25 : 0.7))) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.08)))
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
