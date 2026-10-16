import McFlyKit
import SwiftUI

/// The top of Home on iPhone and iPad, where the display has its big clock (the
/// status bar already tells the time): four tiles to take in at a glance. What's
/// next, the weather here, what needs you (today's alerts and blocked projects)
/// and the top story. Each opens what it shows.
struct GlanceGrid: View {
    let now: Date
    let feeds: FeedStore
    let weather: WeatherModel

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                NextTile(event: Timeline.upNext(feeds.events, now: now), now: now)
                WeatherTile(weather: weather)
            }
            GridRow {
                NeedsYouTile(alerts: todaysAlerts, blocked: feeds.blockedProjects)
                TopStoryTile(report: feeds.todaysReport(now: now) ?? feeds.latestReport, now: now, feeds: feeds)
            }
        }
    }

    /// Alert briefs from today, newest first.
    private var todaysAlerts: [Brief] {
        feeds.briefs.filter { $0.kind == .alert && Calendar.current.isDate($0.publishedAt, inSameDayAs: now) }
    }
}

// MARK: The tiles

/// What a tile looks like: a kicker over its content, on a card (or a colour).
private struct Tile<Content: View>: View {
    let kicker: String
    let systemImage: String
    var tint: Color = Theme.accent
    var fill: Color?
    @ViewBuilder var content: Content

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
        .background(fill ?? Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous))
        .shadow(color: (fill ?? .black).opacity(fill == nil ? 0.04 : 0.3), radius: fill == nil ? 10 : 14, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous))
    }
}

/// The event on now, else the next one, on its colour.
private struct NextTile: View {
    let event: CalendarEvent?
    let now: Date

    var body: some View {
        if let event {
            NavigationLink(value: event) {
                Tile(kicker: heading(event), systemImage: "calendar",
                     fill: event.color.map(Color.init(hex:)) ?? Theme.accent) {
                    Text(event.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text([Timeline.Clock().label(event.startsAt), event.location].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
            .buttonStyle(PressableStyle())
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

    var body: some View {
        switch weather.state {
        case .ready(let today, let place):
            Tile(kicker: place.map { "Weather · \($0)" } ?? "Weather", systemImage: "location.fill", tint: Theme.blue) {
                HStack(alignment: .center, spacing: 8) {
                    Text(Weather.degrees(today.temperature))
                        .font(.system(size: 34, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Image(systemName: today.systemImage)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 26))
                }
                Text(today.condition)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("H \(Weather.degrees(today.high))  L \(Weather.degrees(today.low))")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.muted)
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

/// Today's alerts and the blocked projects: the newest, and how many more.
private struct NeedsYouTile: View {
    let alerts: [Brief]
    let blocked: [Project]

    var body: some View {
        let more = alerts.count + blocked.count - 1
        if let alert = alerts.first {
            NavigationLink(value: HomeRoute.brief(alert)) {
                content(title: alert.title, detail: more > 0 ? "and \(more) more" : BriefText.summary(alert.body))
            }
            .buttonStyle(PressableStyle())
        } else if let project = blocked.first {
            NavigationLink(value: project) {
                content(title: "\(project.name) is blocked",
                        detail: more > 0 ? "and \(more) more" : (project.nextStep ?? project.summary))
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
            }
        }
    }

    private func content(title: String, detail: String) -> some View {
        Tile(kicker: "Needs you", systemImage: "exclamationmark.circle.fill", tint: Theme.danger) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

/// Today's lead story (else the newest report's).
private struct TopStoryTile: View {
    let report: NewsReport?
    let now: Date
    let feeds: FeedStore

    var body: some View {
        if let report, let hero = report.hero {
            let source = feeds.agent(report.agentId)?.name ?? "Daily Pulse"
            let today = report.reportDate == Timeline.dayKey(now)
            NavigationLink(value: HomeRoute.story(hero)) {
                Tile(kicker: today ? "Top story" : "Top story · \(report.displayDate ?? report.reportDate)",
                     systemImage: "newspaper.fill", tint: Theme.coral) {
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
            .buttonStyle(PressableStyle())
        } else {
            Tile(kicker: "Top story", systemImage: "newspaper", tint: Theme.muted) {
                Text("No Pulse report yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}
