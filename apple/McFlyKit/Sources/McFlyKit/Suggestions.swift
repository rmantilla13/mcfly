import Foundation

// Questions to offer under the Ask bar, built from what is on screen so a
// chip always points at something real: the blocked project, the biggest
// mover, the next meeting, the Pulse's lead story, a fresh brief, then
// questions that fit any day. At most four, each short enough for two chips
// to share a row. The console's admin/lib/suggestions.ts and the display's
// `Assistant::buildSuggestions` / `suggestionsFor`, ported. Pure, so
// SuggestionsTests can check them.

/// The screens with a question of their own (the display's
/// `suggestionsFor` names; Metrics is a segment of Markets). The raw values
/// match the app's own screens where they share one.
public enum SuggestionScreen: String, CaseIterable, Hashable, Sendable {
    case home, briefs, markets, metrics, news, projects, dashboards, calendar
}

public enum Suggestions {
    public static let maxSuggestions = 4
    /// Two chips share a row at this length.
    public static let maxCharacters = 42
    public static let summarizeDay = "Summarize my day"
    /// Below this, "why is it up?" has no answer worth asking.
    public static let moverMinPct = 1.0
    public static let eventWindow: TimeInterval = 3 * 60 * 60
    public static let briefFresh: TimeInterval = 3 * 60 * 60

    /// The four for the Ask bar: from the feeds first, then questions that
    /// fit any day, skipping ones about feeds that are empty. `skip`: those a
    /// surface already offers its own way, left out before the four are picked.
    public static func build(_ feed: FeedSnapshot, now: Date, calendar: Calendar = .current, skip: [String] = []) -> [String] {
        var out: [String?] = []
        if let blocked = feed.projects.first(where: { $0.status == .blocked }) {
            out.append(fit("What's blocking ", blocked.name, "?"))
        }
        if let mover = biggestMover(feed.quotes, now: now, calendar: calendar) {
            out.append(moverQuestion(symbol: mover.symbol, pct: mover.pct))
        }
        if let next = nextEvent(feed.events, now: now, within: eventWindow) {
            out.append(fit("What do I need for ", next.title, "?"))
        }
        if let lead = Insights.todaysLead(feed.reports, now: now, calendar: calendar) {
            out.append(fit("More on ", lead.hero.headline, ""))
        }
        if let agent = freshBriefAgent(feed, now: now) {
            out.append(fit("What did ", agent, " just say?"))
        }
        out.append(summarizeDay)
        out.append(feed.events.contains { $0.endsAt >= now } ? "What's next on my calendar?" : nil)
        out.append(feed.quotes.isEmpty ? nil : "How are the markets doing?")
        out.append(feed.metrics.isEmpty ? nil : "How are my metrics looking?")
        out.append("Anything I should know?")
        return firstFour(out, skip: skip)
    }

    /// A screen's own question, the one its chip row leads with; nil when the
    /// screen has nothing to ask about. `insights` are the ones on show (the
    /// metrics' and boards' questions come from them); built when not given.
    public static func suggestion(for screen: SuggestionScreen, in feed: FeedSnapshot, now: Date,
                                  calendar: Calendar = .current, insights: [Insight]? = nil) -> String? {
        let own: String?
        switch screen {
        case .home:
            own = summarizeDay
        case .briefs:
            if let agent = freshBriefAgent(feed, now: now) {
                own = fit("What did ", agent, " just say?")
            } else {
                own = feed.briefs.isEmpty ? nil : "What's the latest brief?"
            }
        case .markets:
            if let mover = biggestMover(feed.quotes, now: now, calendar: calendar) {
                own = moverQuestion(symbol: mover.symbol, pct: mover.pct)
            } else {
                own = feed.quotes.isEmpty ? nil : "How are the markets doing?"
            }
        case .metrics:
            let shown = insights ?? Insights.build(feed, now: now, calendar: calendar)
            own = question(of: .metric, in: shown) ?? (feed.metrics.isEmpty ? nil : "How are my metrics looking?")
        case .news:
            if let lead = Insights.todaysLead(feed.reports, now: now, calendar: calendar) {
                own = fit("More on ", lead.hero.headline, "")
            } else {
                own = feed.reports.contains { !$0.items.isEmpty } ? "What's in the news today?" : nil
            }
        case .projects:
            // The blocked one first, else what's next on an active one (the
            // display's projects come blocked first; the store's don't).
            let blocked = feed.projects.lazy.filter { $0.status == .blocked }.compactMap { fit("What's blocking ", $0.name, "?") }.first
            let active = feed.projects.lazy.filter { $0.status == .active }.compactMap { fit("What's next for ", $0.name, "?") }.first
            own = blocked ?? active ?? (feed.projects.isEmpty ? nil : "How are my projects going?")
        case .dashboards:
            let shown = insights ?? Insights.build(feed, now: now, calendar: calendar)
            own = question(of: .status, in: shown) ?? feed.dashboards.first.flatMap { fit("How's ", $0.title, " looking?") }
        case .calendar:
            own = nextEvent(feed.events, now: now, within: nil).flatMap { fit("Prep me for ", $0.title, "") }
                ?? "What's next on my calendar?"
        }
        guard let own, own.count <= maxCharacters else { return nil }
        return own
    }

    /// A screen's chip row: its own question first, then the general four.
    public static func build(for screen: SuggestionScreen, _ feed: FeedSnapshot, now: Date,
                             calendar: Calendar = .current, insights: [Insight]? = nil) -> [String] {
        let general = build(feed, now: now, calendar: calendar)
        return firstFour([suggestion(for: screen, in: feed, now: now, calendar: calendar, insights: insights)] + general)
    }

    /// `before` + `value` + `after` in 42 characters, the value cut at a word
    /// with an ellipsis when it has to be; nil when too little of it would fit.
    public static func fit(_ before: String, _ value: String, _ after: String) -> String? {
        let v = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !v.isEmpty else { return nil }
        let room = maxCharacters - before.count - after.count
        if v.count <= room { return before + v + after }
        if room < 8 { return nil }
        let chars = Array(v)
        var cut = Array(chars.prefix(room - 1))
        // Back up to the last whole word, unless the cut already fell between two.
        if chars[room - 1] != " ", let space = cut.lastIndex(of: " "), Double(space) >= Double(room - 1) * 0.6 {
            cut = Array(cut[..<space])
        }
        while let last = cut.last, trailing.contains(last) || last.isWhitespace {
            cut.removeLast()
        }
        return before + String(cut) + "…" + after
    }

    // MARK: Pieces

    /// What a cut value may not end on before its ellipsis.
    private static let trailing: Set<Character> = [",", ".", ";", ":", "!", "?", "'", "\"", "“", "”", "‘", "’", "–", "—", "-"]

    /// At most four, none too long, none twice, none skipped.
    static func firstFour(_ candidates: [String?], skip: [String] = []) -> [String] {
        var out: [String] = []
        for case let s? in candidates where !s.isEmpty && s.count <= maxCharacters && !out.contains(s) && !skip.contains(s) {
            out.append(s)
            if out.count == maxSuggestions { break }
        }
        return out
    }

    /// "Why is NVDA up 3.4% today?", or without "today" when that won't fit.
    static func moverQuestion(symbol: String, pct: Double) -> String? {
        let move = "\(symbol) \(pct > 0 ? "up" : "down") \(Insights.pct1(pct))%"
        let full = "Why is \(move) today?"
        if full.count <= maxCharacters { return full }
        let shorter = "Why is \(move)?"
        return shorter.count <= maxCharacters ? shorter : nil
    }

    /// The biggest move worth asking about: 1% or more, on a quote from the last 36 h.
    static func biggestMover(_ quotes: [QuoteSeries], now: Date, calendar: Calendar) -> (symbol: String, pct: Double)? {
        var best: (symbol: String, pct: Double)?
        for series in quotes {
            // Only the move and its age: the usual swing isn't needed here.
            let move = QuoteMove(pct: series.dayChangePct, swing: nil, asOf: series.latest.asOf, now: now)
            guard let pct = move.pct, move.fresh, abs(pct) >= moverMinPct else { continue }
            if let current = best, abs(pct) <= abs(current.pct) { continue }
            best = (series.symbol, pct)
        }
        return best
    }

    /// The next timed event to start after `now`, within `within` when given.
    static func nextEvent(_ events: [CalendarEvent], now: Date, within: TimeInterval?) -> CalendarEvent? {
        events.enumerated()
            .filter { entry in
                let start = entry.element.startsAt
                return !entry.element.allDay && start > now && (within.map { start.timeIntervalSince(now) <= $0 } ?? true)
            }
            .min { ($0.element.startsAt, $0.offset) < ($1.element.startsAt, $1.offset) }?.element
    }

    /// The agent of the latest brief, if it is from the last three hours.
    static func freshBriefAgent(_ feed: FeedSnapshot, now: Date) -> String? {
        guard let brief = Insights.latestBrief(feed.briefs, now: now) else { return nil }
        let age = now.timeIntervalSince(brief.publishedAt)
        guard age < briefFresh, -age < 5 * 60 else { return nil }
        return Insights.nonEmpty(feed.agents.first { $0.id == brief.agentId }?.name)
    }

    /// The question of the first insight of a kind, when it fits on a chip.
    static func question(of kind: Insight.Kind, in insights: [Insight]) -> String? {
        insights.first { $0.kind == kind && $0.question.count <= maxCharacters }?.question
    }
}
