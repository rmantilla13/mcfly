import Foundation

// What stands out and what to ask, from the store's own feeds: the
// display's `Store.highlights` and `AI.suggestions` / `suggestionsFor`.
// Each call reads the feeds as they are; nothing is cached, so a view that
// calls them in `body` follows every refresh. Key the results by `Insight.id`
// (stable across refreshes) so nothing replays.

@MainActor
public extension FeedStore {
    /// The feeds the insights read, each series grouped once.
    var snapshot: FeedSnapshot {
        FeedSnapshot(projects: projects, dashboards: dashboards, metrics: metricSeries, quotes: series,
                     events: events, briefs: briefs, reports: reports, agents: agents)
    }

    /// At most five things that stand out, in the display's order (`Insights.build`),
    /// less what's been dismissed: a dismissed blocked project gives way to the
    /// next one.
    func insights(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> [Insight] {
        var shown = snapshot
        shown.projects = projects.filter { !($0.status == .blocked && isDismissed("blocked:\($0.id.uuidString)", now: now)) }
        return Insights.build(shown, now: now, calendar: calendar, locale: locale).filter { !isDismissed($0.id, now: now) }
    }

    /// The Ask bar's four questions (`Suggestions.build`).
    func suggestions(now: Date = Date(), calendar: Calendar = .current, skip: [String] = []) -> [String] {
        Suggestions.build(snapshot, now: now, calendar: calendar, skip: skip)
    }

    /// A screen's own question; nil when it has nothing to ask about.
    func suggestion(for screen: SuggestionScreen, now: Date = Date(), calendar: Calendar = .current) -> String? {
        Suggestions.suggestion(for: screen, in: snapshot, now: now, calendar: calendar)
    }

    /// The same, from the insights already on show, so the metrics' and the
    /// boards' questions don't build them a second time.
    func suggestion(for screen: SuggestionScreen, now: Date = Date(), calendar: Calendar = .current,
                    insights: [Insight]) -> String? {
        Suggestions.suggestion(for: screen, in: snapshot, now: now, calendar: calendar, insights: insights)
    }

    /// A screen's chip row: its own question, then the general ones, four at most.
    func suggestions(for screen: SuggestionScreen, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        Suggestions.build(for: screen, snapshot, now: now, calendar: calendar)
    }

    /// The same, from the insights already on show (`store.insights(now:)`),
    /// so they aren't built a second time. Each call still regroups the feeds;
    /// a view that wants both from one pass takes `snapshot` once and calls
    /// `Insights.build` and `Suggestions.build(for:_:now:calendar:insights:)`.
    func suggestions(for screen: SuggestionScreen, now: Date = Date(), calendar: Calendar = .current,
                     insights: [Insight]) -> [String] {
        Suggestions.build(for: screen, snapshot, now: now, calendar: calendar, insights: insights)
    }
}
