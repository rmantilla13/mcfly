import Foundation

// What stands out right now, ranked, as the display's Home and the console's
// Today show it: a blocked project, a board's status that is down, a metric
// far off its usual, a meeting about to start, a big mover, a fresh brief,
// today's Pulse. The display's `FeedStore::rebuildHighlights` and the
// console's admin/lib/insights.ts, ported: the same rules, wording and order,
// and no model call, so it can run on every refresh. Pure, so InsightsTests
// can check it against their cases.

// MARK: Which way is good news

/// Which way a metric should move for the news to be good.
public enum GoodDirection: String, CaseIterable, Hashable, Sendable {
    case up, down
}

/// Whether up or down is good news for a metric. Latency, error rates, cost,
/// churn, queues and the like should fall; everything else should rise. From
/// the unit and the key only, since that is all an agent's push says (the
/// console's `goodDirection`, the display's `upIsGood`). A dashboard widget,
/// which has no key, passes its label.
public func goodDirection(unit: String?, key: String) -> GoodDirection {
    let unit = (unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if GoodNewsWords.downUnits.contains(unit) { return .down }
    for word in GoodNewsWords.words(key.lowercased()) {
        if GoodNewsWords.downWords.contains(word) || GoodNewsWords.isPercentile(word) { return .down }
        if GoodNewsWords.downPrefixes.contains(where: { word.hasPrefix($0) }) { return .down }
    }
    return .up
}

/// The word lists of admin/lib/insights.ts and FeedStore.cpp `upIsGood`.
enum GoodNewsWords {
    static let downPrefixes = [
        "latenc", "error", "fail", "crash", "incident", "outage", "downtime", "churn", "cost", "spend",
        "expens", "refund", "backlog", "queue", "bounce", "ttfb", "cancel", "complaint", "defect", "bug",
    ]
    static let downWords: Set<String> = [
        "lag", "lags", "delay", "delays", "wait", "waits", "debt", "burn", "err", "errs",
        "p50", "p75", "p90", "p95", "p99", "p999",
    ]
    static let downUnits: Set<String> = ["ms", "µs", "us", "ns"]

    /// The runs of a-z and 0-9: `/[^a-z0-9]+/` as the separator, so "é" or
    /// "_" splits a word as it does in the console.
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                out.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { out.append(String(current)) }
        return out
    }

    /// `^p\d{2,3}$`: p50, p95, p999.
    static func isPercentile(_ word: String) -> Bool {
        let scalars = Array(word.unicodeScalars)
        guard (3...4).contains(scalars.count), scalars[0] == "p" else { return false }
        return scalars.dropFirst().allSatisfy { ("0"..."9").contains($0) }
    }
}

// MARK: A metric's move

/// Which way a metric went, whether that is good news, and whether it is far
/// off its usual: the display's per-metric `goodDirection`, `trend`, `good`,
/// `anomaly` and `usualLabel` fields.
public struct MetricTrend: Hashable, Sendable {
    public let goodDirection: GoodDirection
    /// Which way it went: the agent's delta, else its percentage, else the
    /// step from the value before.
    public let trend: Trend
    /// The move is good news, or there was none.
    public let good: Bool
    /// The move `trend` and `good` read.
    public let move: Double
    /// Far off its usual: a robust z of 3 or more over the newest 60 points,
    /// or, with too little history (or none that varies) for a z, a jump of
    /// 10% or more that the agent itself reported.
    public let anomaly: Bool
    /// The anomaly is by z ("unusually high"), not a reported jump ("up 12.5%").
    public let unusual: Bool
    /// Which way the anomaly lies (flat when there is none).
    public let anomalyTrend: Trend
    /// The robust z of the latest value, when there is history enough for one.
    public let z: Double?
    /// The median of the points before the latest: its usual value.
    public let usual: Double?
    /// How strongly it stands out, to rank anomalies (0 when none).
    public let strength: Double

    /// A metric with its history: `points` oldest → newest ending on the
    /// latest value; `delta` and `deltaPct` as the agent sent them on it.
    public init(key: String, unit: String?, points: [Double], delta: Double?, deltaPct: Double?) {
        let direction = McFlyKit.goodDirection(unit: unit, key: key)
        let latest = points.last ?? 0
        let move = delta ?? deltaPct ?? (points.count > 1 ? latest - points[points.count - 2] : 0)
        var anomalyDirection = 0.0
        var strength = 0.0
        var unusual = false
        let z = Series.robustZ(points)
        if let z {
            if abs(z) >= Insights.anomalyZ {
                anomalyDirection = z > 0 ? 1 : -1
                strength = abs(z)
                unusual = true
            }
        } else if let pct = deltaPct, pct.isFinite, abs(pct) >= Insights.shortHistoryPct {
            anomalyDirection = pct > 0 ? 1 : -1
            strength = abs(pct) / Insights.shortHistoryPct * Insights.anomalyZ
        }
        goodDirection = direction
        trend = Trend(move)
        self.move = move.isFinite ? move : 0
        good = !(move.isFinite && move != 0) || (move > 0) == (direction == .up)
        anomaly = anomalyDirection != 0
        self.unusual = unusual
        anomalyTrend = Trend(anomalyDirection)
        self.z = z
        usual = points.count > 1 ? Series.median(Array(points.dropLast())) : nil
        self.strength = strength
    }

    /// Only the direction of a move, for a value without a history (a
    /// dashboard's metric widget): never an anomaly.
    public init(key: String, unit: String?, move: Double) {
        let direction = McFlyKit.goodDirection(unit: unit, key: key)
        goodDirection = direction
        trend = Trend(move)
        self.move = move.isFinite ? move : 0
        good = !(move.isFinite && move != 0) || (move > 0) == (direction == .up)
        anomaly = false
        unusual = false
        anomalyTrend = .flat
        z = nil
        usual = nil
        strength = 0
    }
}

extension MetricSeries {
    /// Its move, whether that is good news, and whether it stands out, read
    /// over the newest 60 points as the display reads them.
    public var trend: MetricTrend {
        MetricTrend(key: key, unit: latest.unit, points: sparkline(), delta: latest.delta, deltaPct: latest.deltaPct)
    }
}

extension DashboardWidget {
    /// A metric widget's move and whether it is good news, the label standing
    /// in for the key (so a falling "Errors" reads as good); nil for the other
    /// kinds. The percentage leads, as on the display's boards.
    public var trend: MetricTrend? {
        guard case .metric(let label, _, let unit, let delta, let deltaPct) = self else { return nil }
        return MetricTrend(key: label, unit: unit, move: deltaPct ?? delta ?? 0)
    }
}

// MARK: A quote's move

/// Today's move of a quote, and whether it is a big mover: 2% or more, or
/// 2.5× its usual daily swing (and 1% at least), on a quote from the last 36 h.
public struct QuoteMove: Hashable, Sendable {
    /// Today's move in percent.
    public let pct: Double?
    /// The usual day-to-day move in percent, today's left out.
    public let swing: Double?
    /// The move against the usual swing (|pct| / swing).
    public let ratio: Double?
    public let trend: Trend
    /// Pushed within the last 36 h: Friday's move isn't "today" on Sunday.
    public let fresh: Bool
    /// A big mover by the rule above.
    public let big: Bool
    /// How big, to rank movers.
    public let strength: Double

    public init(pct: Double?, swing: Double?, asOf: Date?, now: Date) {
        let pct = pct.flatMap { $0.isFinite ? $0 : nil }
        let swing = swing.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let ratio = pct.flatMap { pct in swing.map { abs(pct) / $0 } }
        self.pct = pct
        self.swing = swing
        self.ratio = ratio
        trend = Trend(pct)
        fresh = asOf.map { now.timeIntervalSince($0) <= Insights.quoteFresh } ?? true
        if let pct, pct != 0, fresh {
            let isBig = abs(pct) >= Insights.bigMovePct
            let unusual = (ratio ?? 0) >= Insights.swingRatio && abs(pct) >= Insights.swingFloorPct
            big = isBig || unusual
        } else {
            big = false
        }
        strength = max(abs(pct ?? 0) / Insights.bigMovePct, (ratio ?? 0) / Insights.swingRatio)
    }
}

extension QuoteSeries {
    /// Today's move in percent: the agent's `change_pct`, else its change
    /// over the price before it, else the step from the previous point.
    public var dayChangePct: Double? {
        let quote = latest
        if let pct = quote.changePct, pct.isFinite { return pct }
        if let change = quote.change {
            let base = quote.price - change
            return base != 0 ? change / abs(base) * 100 : nil
        }
        guard history.count > 1, history[1].price != 0 else { return nil }
        return (quote.price - history[1].price) / abs(history[1].price) * 100
    }

    /// Today's move against the usual swing (from daily closes in the
    /// calendar's zone), and whether that makes it a big mover.
    public func dayMove(now: Date = .now, calendar: Calendar = .current) -> QuoteMove {
        QuoteMove(pct: dayChangePct, swing: usualSwing(calendar: calendar), asOf: latest.asOf, now: now)
    }
}

// MARK: Insights

/// One thing that stands out, with where it leads and what to ask about it.
public struct Insight: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case blocked, status, metric, event, mover, brief, pulse
    }

    public enum Tone: String, CaseIterable, Hashable, Sendable {
        case neutral, good, bad, warn
    }

    /// Where a tap leads.
    public enum Target: Hashable, Sendable {
        case project(UUID)
        case dashboard(UUID)
        /// A metric's key (Markets → Metrics).
        case metric(String)
        case event(UUID)
        /// A quote's symbol (Markets).
        case symbol(String)
        case brief(UUID)
        case report(UUID)
    }

    /// Stable across refreshes ("blocked:<project id>", "mover:NVDA"), so a list can key on it.
    public let id: String
    public let kind: Kind
    public let tone: Tone
    /// "Onyx is blocked", "NVDA is up 3.4%".
    public let title: String
    /// What else there is to say: the next step, the value against its usual, the time and place.
    public let detail: String
    /// A question the assistant can answer from what it sees.
    public let question: String
    /// "#rrggbb": the project's, the status's, good or bad, the event's, the agent's.
    public let colorHex: String
    public let target: Target

    public init(id: String, kind: Kind, tone: Tone, title: String, detail: String, question: String,
                colorHex: String, target: Target) {
        self.id = id; self.kind = kind; self.tone = tone; self.title = title; self.detail = detail
        self.question = question; self.colorHex = colorHex; self.target = target
    }

    /// An SF Symbol for the kind (a mover's arrow follows its tone).
    public var systemImage: String {
        switch kind {
        case .blocked: return "exclamationmark.octagon"
        case .status: return "bolt.horizontal.circle"
        case .metric: return "chart.xyaxis.line"
        case .event: return "calendar"
        case .mover: return tone == .bad ? "arrow.down.right" : "arrow.up.right"
        case .brief: return tone == .warn ? "exclamationmark.circle" : "text.alignleft"
        case .pulse: return "newspaper"
        }
    }
}

/// The feeds the insights and the suggestions are built from, shaped as
/// FeedStore keeps them: visible series, projects and dashboards in the
/// console's order, events by start, briefs newest first.
public struct FeedSnapshot: Sendable {
    public var projects: [Project]
    public var dashboards: [Dashboard]
    public var metrics: [MetricSeries]
    public var quotes: [QuoteSeries]
    public var events: [CalendarEvent]
    public var briefs: [Brief]
    public var reports: [NewsReport]
    public var agents: [Agent]

    public init(projects: [Project] = [], dashboards: [Dashboard] = [], metrics: [MetricSeries] = [],
                quotes: [QuoteSeries] = [], events: [CalendarEvent] = [], briefs: [Brief] = [],
                reports: [NewsReport] = [], agents: [Agent] = []) {
        self.projects = projects; self.dashboards = dashboards; self.metrics = metrics; self.quotes = quotes
        self.events = events; self.briefs = briefs; self.reports = reports; self.agents = agents
    }
}

public enum Insights {
    public static let maxInsights = 5
    public static let anomalyZ = 3.0
    /// A metric's own jump that counts when a z can't be had.
    public static let shortHistoryPct = 10.0
    public static let bigMovePct = 2.0
    public static let swingRatio = 2.5
    /// A 0.4% day is never news, however calm the stock.
    public static let swingFloorPct = 1.0
    public static let eventSoon: TimeInterval = 30 * 60
    public static let briefFresh: TimeInterval = 60 * 60
    public static let quoteFresh: TimeInterval = 36 * 60 * 60

    /// The display's colours: good news, bad news, a warning, an agent without one.
    public static let goodHex = "#3DB37A"
    public static let badHex = "#F07F5A"
    public static let warnHex = "#F6B94A"
    public static let unknownHex = "#8F95A1"

    /// At most five, in the display's order: a blocked project, a board's
    /// status that is down (or warns), the two metrics furthest off their
    /// usual, a meeting within 30 minutes (or just started), the two biggest
    /// movers, a brief under an hour old, today's Pulse.
    public static func build(_ feed: FeedSnapshot, now: Date, calendar: Calendar = .current,
                             locale: Locale = .current) -> [Insight] {
        let agents = Dictionary(feed.agents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Insight] = []
        if let blocked = blocked(feed.projects, agents: agents) { out.append(blocked) }
        if let status = status(feed.dashboards) { out.append(status) }
        out += strongest(feed.metrics.compactMap { metric($0) })
        if let event = event(feed.events, agents: agents, now: now, calendar: calendar, locale: locale) { out.append(event) }
        out += strongest(feed.quotes.compactMap { mover($0, now: now, calendar: calendar) })
        if let brief = brief(feed.briefs, agents: agents, now: now) { out.append(brief) }
        if let pulse = pulse(feed.reports, agents: agents, now: now, calendar: calendar) { out.append(pulse) }
        return Array(out.prefix(maxInsights))
    }

    // MARK: Each kind

    /// 1. A blocked project: the one thing only you can unstick.
    static func blocked(_ projects: [Project], agents: [UUID: Agent]) -> Insight? {
        let blocked = projects.filter { $0.status == .blocked }
        guard let project = blocked.first else { return nil }
        let name = project.name
        return Insight(id: "blocked:\(project.id)", kind: .blocked, tone: .warn,
                       title: blocked.count > 1 ? "\(name) and \(blocked.count - 1) more are blocked" : "\(name) is blocked",
                       detail: project.nextStep ?? "", question: "What's blocking \(name)?",
                       colorHex: nonEmpty(project.color) ?? agentColor(project.agentId, agents), target: .project(project.id))
    }

    /// 2. A board's status that is down, else one that warns: the worst first, and how many more.
    static func status(_ dashboards: [Dashboard]) -> Insight? {
        var found: [(board: Dashboard, label: String, state: DashboardWidget.State, detail: String?, order: Int)] = []
        for board in dashboards where !board.hidden {
            for widget in board.widgets {
                guard case .status(let label, let state, let detail) = widget, state == .error || state == .warn else { continue }
                found.append((board, label, state, detail, found.count))
            }
        }
        guard let worst = found.min(by: { a, b in
            let aDown = a.state == .error, bDown = b.state == .error
            return aDown != bDown ? aDown : a.order < b.order
        }) else { return nil }
        let down = worst.state == .error
        var detail: [String] = []
        if let text = nonEmpty(worst.detail) { detail.append(text) }
        detail.append(worst.board.title)
        if found.count > 1 { detail.append("+\(found.count - 1) more") }
        return Insight(id: "status:\(worst.board.id):\(worst.label)", kind: .status, tone: down ? .bad : .warn,
                       title: down ? "\(worst.label) is down" : "\(worst.label) has a warning",
                       detail: detail.joined(separator: " · "),
                       question: down ? "Why is \(worst.label) down?" : "What's wrong with \(worst.label)?",
                       colorHex: down ? badHex : warnHex, target: .dashboard(worst.board.id))
    }

    /// 3. A metric far off its usual.
    static func metric(_ series: MetricSeries) -> (insight: Insight, strength: Double)? {
        let trend = series.trend
        guard trend.anomaly else { return nil }
        let latest = series.latest
        let unit = latest.unit
        let rising = trend.anomalyTrend == .up
        let good = rising == (trend.goodDirection == .up)
        let value = Format.metric(latest.value, unit: unit)
        let title: String
        let detail: String
        if trend.unusual {
            title = "\(series.label) is unusually \(rising ? "high" : "low")"
            detail = trend.usual.map { "\(value), against a usual \(Format.metric($0, unit: unit))" } ?? value
        } else {
            title = "\(series.label) is \(rising ? "up" : "down") \(pct1(latest.deltaPct ?? 0))%"
            detail = value
        }
        return (Insight(id: "metric:\(series.key)", kind: .metric, tone: good ? .good : .bad, title: title, detail: detail,
                        question: "What's behind the \(rising ? "rise" : "drop") in \(series.label)?",
                        colorHex: good ? goodHex : badHex, target: .metric(series.key)),
                trend.strength)
    }

    /// 4. A meeting about to start (or that just did): the soonest timed one
    /// starting within 30 minutes, or under 5 minutes ago.
    static func event(_ events: [CalendarEvent], agents: [UUID: Agent], now: Date, calendar: Calendar,
                      locale: Locale) -> Insight? {
        let soon = events.enumerated()
            .filter { !$0.element.allDay && $0.element.startsAt.timeIntervalSince(now) <= eventSoon
                && now.timeIntervalSince($0.element.startsAt) <= 5 * 60 }
            .min { ($0.element.startsAt, $0.offset) < ($1.element.startsAt, $1.offset) }?.element
        guard let event = soon else { return nil }
        let minutes = Int((event.startsAt.timeIntervalSince(now) / 60).rounded())
        let clock = Timeline.Clock(calendar: calendar, locale: locale)
        let when = "\(clock.label(event.startsAt)) – \(clock.label(event.endsAt))"
        let title: String
        if event.startsAt <= now {
            title = "\(event.title) has started"
        } else if minutes < 1 {
            title = "\(event.title) starts now"
        } else {
            title = "\(event.title) starts in \(minutes) min"
        }
        return Insight(id: "event:\(event.id)", kind: .event, tone: minutes <= 10 ? .warn : .neutral, title: title,
                       detail: nonEmpty(event.location).map { "\(when) · \($0)" } ?? when,
                       question: "What do I need for \(event.title)?",
                       colorHex: nonEmpty(event.color) ?? agentColor(event.agentId, agents), target: .event(event.id))
    }

    /// 5. A big mover.
    static func mover(_ series: QuoteSeries, now: Date, calendar: Calendar) -> (insight: Insight, strength: Double)? {
        mover(symbol: series.symbol, price: Format.price(series.latest.price, currency: series.latest.currency),
              move: series.dayMove(now: now, calendar: calendar))
    }

    static func mover(symbol: String, price: String, move: QuoteMove) -> (insight: Insight, strength: Double)? {
        guard move.big, let pct = move.pct else { return nil }
        let dir = pct > 0 ? "up" : "down"
        var detail = [price]
        if let ratio = move.ratio, ratio >= 1.5 {
            detail.append("\(String(format: "%.1f", ratio))× its usual daily move")
        }
        return (Insight(id: "mover:\(symbol)", kind: .mover, tone: pct > 0 ? .good : .bad,
                        title: "\(symbol) is \(dir) \(pct1(pct))%", detail: detail.joined(separator: " · "),
                        question: "Why is \(symbol) \(dir) \(pct1(pct))% today?",
                        colorHex: pct > 0 ? goodHex : badHex, target: .symbol(symbol)),
                move.strength)
    }

    /// 6. A brief from the last hour.
    static func brief(_ briefs: [Brief], agents: [UUID: Agent], now: Date) -> Insight? {
        guard let brief = latestBrief(briefs, now: now) else { return nil }
        let age = now.timeIntervalSince(brief.publishedAt)
        guard age < briefFresh, -age < 5 * 60 else { return nil }
        let agent = agents[brief.agentId]?.name ?? ""
        let title = clip(brief.title, 60)
        let summary = Timeline.summary(brief.body)
        let ago = agoLabel(brief.publishedAt, now: now)
        return Insight(id: "brief:\(brief.id)", kind: .brief, tone: brief.kind == .alert ? .warn : .neutral,
                       title: agent.isEmpty ? "New brief: “\(title)”" : "\(agent) posted “\(title)”",
                       detail: summary.isEmpty ? ago : "\(ago) · \(clip(summary, 120))",
                       question: agent.isEmpty ? "What's the latest brief?" : "What did \(agent) just say?",
                       colorHex: agentColor(brief.agentId, agents), target: .brief(brief.id))
    }

    /// 7. Today's Pulse, led by its hero story: the newest report today.
    static func pulse(_ reports: [NewsReport], agents: [UUID: Agent], now: Date, calendar: Calendar) -> Insight? {
        guard let lead = todaysLead(reports, now: now, calendar: calendar) else { return nil }
        let name = agents[lead.report.agentId]?.name ?? ""
        let count = lead.report.items.count
        return Insight(id: "pulse:\(lead.report.id)", kind: .pulse, tone: .neutral, title: lead.hero.headline,
                       detail: "\(name.isEmpty ? "Daily Pulse" : name) · \(count == 1 ? "1 story" : "\(count) stories")",
                       question: "Tell me more about “\(clip(lead.hero.headline, 70))”",
                       colorHex: agentColor(lead.report.agentId, agents), target: .report(lead.report.id))
    }

    // MARK: Shared with the suggestions

    /// The newest brief that hasn't expired.
    static func latestBrief(_ briefs: [Brief], now: Date) -> Brief? {
        briefs.enumerated()
            .filter { $0.element.expiresAt.map { $0 > now } ?? true }
            .max { ($0.element.publishedAt, -$0.offset) < ($1.element.publishedAt, -$1.offset) }?.element
    }

    /// Today's newest report with a story, and its hero. Written last night
    /// for today, a report opens the day (the timeline's rule).
    static func todaysLead(_ reports: [NewsReport], now: Date, calendar: Calendar) -> (report: NewsReport, hero: NewsItem)? {
        let today = Timeline.dayKey(now, calendar: calendar)
        let start = calendar.startOfDay(for: now)
        let candidates = reports.enumerated().compactMap { offset, report -> (NewsReport, NewsItem, Date, Int)? in
            guard report.reportDate == today, let hero = report.hero else { return nil }
            let at = calendar.isDate(report.publishedAt, inSameDayAs: now) ? report.publishedAt : start
            return (report, hero, at, offset)
        }
        guard let lead = candidates.max(by: { ($0.2, -$0.3) < ($1.2, -$1.3) }) else { return nil }
        return (lead.0, lead.1)
    }

    // MARK: Labels

    /// The strongest two, strongest first; ties keep their order.
    static func strongest(_ ranked: [(insight: Insight, strength: Double)], count: Int = 2) -> [Insight] {
        ranked.enumerated()
            .sorted { $0.element.strength != $1.element.strength ? $0.element.strength > $1.element.strength : $0.offset < $1.offset }
            .prefix(count)
            .map(\.element.insight)
    }

    /// "3.4": a move's size to one place, as `toFixed(1)` writes it.
    static func pct1(_ value: Double) -> String {
        String(format: "%.1f", abs(value))
    }

    /// "just now", "20 min ago", "3 h ago", "2 d ago".
    static func agoLabel(_ date: Date, now: Date) -> String {
        let minutes = Int((now.timeIntervalSince(date) / 60).rounded())
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = Int((Double(minutes) / 60).rounded())
        return hours < 48 ? "\(hours) h ago" : "\(Int((Double(hours) / 24).rounded())) d ago"
    }

    /// On one line, cut to `max` characters with an ellipsis.
    static func clip(_ text: String, _ max: Int) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > max else { return flat }
        var cut = String(flat.prefix(max - 1))
        while cut.last?.isWhitespace == true { cut.removeLast() }
        return cut + "…"
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static func agentColor(_ id: UUID, _ agents: [UUID: Agent]) -> String {
        nonEmpty(agents[id]?.color) ?? Timeline.defaultColor
    }
}

// MARK: Up next's ring

/// How far along an event is, for Up next's countdown ring (the console's
/// `countdown`): over the last hour before it the ring fills toward the
/// start; once on, it fills through the event.
public struct Countdown: Hashable, Sendable {
    public enum Mode: String, Hashable, Sendable {
        /// More than an hour away: an empty ring.
        case later
        /// Within the hour.
        case soon
        /// Under way.
        case now
    }

    public let mode: Mode
    /// 0…1, the ring's fill.
    public let value: Double
    /// Minutes until the start (later, soon) or the end (now).
    public let minutes: Int

    public init(start: Date, end: Date, now: Date) {
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
        if start <= now {
            let span = end.timeIntervalSince(start)
            mode = .now
            value = span > 0 ? clamp(now.timeIntervalSince(start) / span) : 1
            minutes = max(0, Int((end.timeIntervalSince(now) / 60).rounded()))
            return
        }
        let until = start.timeIntervalSince(now)
        minutes = Int((until / 60).rounded())
        if minutes > 60 {
            mode = .later
            value = 0
        } else {
            mode = .soon
            value = clamp(1 - until / 3600)
        }
    }

    public init(event: CalendarEvent, now: Date) {
        self.init(start: event.startsAt, end: event.endsAt, now: now)
    }
}
