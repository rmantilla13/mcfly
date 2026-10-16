import Foundation
import Observation

/// Where the feeds come from: PostgREST with the signed-in person's JWT, or
/// the demo file for previews and screenshots.
public protocol FeedSource: Sendable {
    func loadAgents() async throws -> [Agent]
    func loadBriefs(limit: Int) async throws -> [Brief]
    func loadQuotes(limit: Int) async throws -> [Quote]
    /// The newest row's `data` per symbol (`quotes_latest`).
    func loadLatestQuoteData() async throws -> [QuoteLatest]
    func loadSymbols() async throws -> [Symbol]
    func loadReports(limit: Int) async throws -> [NewsReport]
    func loadSettings() async throws -> PlatformSettings?
    /// Projects with their newest updates embedded.
    func loadProjects(updatesPerProject: Int) async throws -> [Project]
    func loadMetrics(limit: Int) async throws -> [Metric]
    func loadMetricSettings() async throws -> [MetricSetting]
    func loadDashboards() async throws -> [Dashboard]
    /// Events overlapping the window.
    func loadEvents(from: Date, to: Date) async throws -> [CalendarEvent]
}

extension FeedSource {
    /// A source whose quote rows carry their own `data` (the demo) needs none.
    public func loadLatestQuoteData() async throws -> [QuoteLatest] { [] }
}

/// Everything the feed screens read. One refresh loads every feed at once,
/// as the Pi display does, so the screens never disagree with each other.
@MainActor
@Observable
public final class FeedStore {
    public private(set) var agents: [Agent] = []
    /// Newest first, unexpired.
    public private(set) var briefs: [Brief] = []
    /// Raw history, newest first.
    public private(set) var quotes: [Quote] = []
    /// The newest row's `data` per symbol (live; the demo's rows carry their own).
    public private(set) var quoteData: [QuoteLatest] = []
    public private(set) var symbols: [Symbol] = []
    /// Newest first, items embedded.
    public private(set) var reports: [NewsReport] = []
    public private(set) var settings: PlatformSettings?
    /// In the console's order, done last.
    public private(set) var projects: [Project] = []
    /// Raw history, newest first.
    public private(set) var metrics: [Metric] = []
    public private(set) var metricSettings: [MetricSetting] = []
    /// Visible, in the console's order.
    public private(set) var dashboards: [Dashboard] = []
    /// From yesterday to about two months out, by start.
    public private(set) var events: [CalendarEvent] = []
    public private(set) var isLoading = false
    public private(set) var loadedAt: Date?
    public var errorMessage: String?

    /// How much history is read. The sync matches the display's (spec §3).
    public static let briefLimit = 100
    public static let quoteLimit = 2000
    public static let reportLimit = 14
    public static let metricLimit = 2000
    public static let updatesPerProject = 5
    public static let eventsDaysBack = 1
    public static let eventsDaysAhead = 60

    private let source: FeedSource

    public init(source: FeedSource) {
        self.source = source
    }

    public var hasLoaded: Bool { loadedAt != nil }

    public func refresh() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let eventsFrom = calendar.date(byAdding: .day, value: -Self.eventsDaysBack, to: today) ?? today
        let eventsTo = calendar.date(byAdding: .day, value: Self.eventsDaysAhead, to: today) ?? today
        do {
            async let agents = source.loadAgents()
            async let briefs = source.loadBriefs(limit: Self.briefLimit)
            async let quotes = source.loadQuotes(limit: Self.quoteLimit)
            async let quoteData = source.loadLatestQuoteData()
            async let symbols = source.loadSymbols()
            async let reports = source.loadReports(limit: Self.reportLimit)
            async let settings = source.loadSettings()
            async let projects = source.loadProjects(updatesPerProject: Self.updatesPerProject)
            async let metrics = source.loadMetrics(limit: Self.metricLimit)
            async let metricSettings = source.loadMetricSettings()
            async let dashboards = source.loadDashboards()
            async let events = source.loadEvents(from: eventsFrom, to: eventsTo)
            self.agents = try await agents
            self.briefs = try await briefs
                .filter { $0.expiresAt.map { $0 > now } ?? true }
                .sorted { $0.publishedAt > $1.publishedAt }
            self.quotes = try await quotes
            // Extras: without them the prices still show.
            self.quoteData = (try? await quoteData) ?? []
            self.symbols = try await symbols
            self.reports = try await reports.sorted { ($0.reportDate, $0.publishedAt) > ($1.reportDate, $1.publishedAt) }
            self.settings = try await settings
            self.projects = try await projects.sorted {
                ($0.status == .done ? 1 : 0, $0.sortOrder, $0.name) < ($1.status == .done ? 1 : 0, $1.sortOrder, $1.name)
            }
            self.metrics = try await metrics
            self.metricSettings = try await metricSettings
            self.dashboards = try await dashboards.filter { !$0.hidden }.sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
            self.events = try await events.sorted { ($0.startsAt, $0.title) < ($1.startsAt, $1.title) }
            loadedAt = now
            errorMessage = nil
        } catch is CancellationError {
            // Pull-to-refresh let go early, or the screen closed.
        } catch {
            errorMessage = McFlyError.describe(error)
        }
    }

    // MARK: Derived

    /// Today in time order: today's Pulse reports, briefs, project updates and events (`Timeline`).
    public func timeline(now: Date = .now, calendar: Calendar = .current) -> [TimelineItem] {
        Timeline.build(briefs: briefs, reports: reports, projects: projects, events: events, agents: agents,
                       now: now, calendar: calendar)
    }

    /// Tomorrow's events as rows: Home's preview under today's last row (`Timeline.tomorrow`).
    public func tomorrow(now: Date = .now, calendar: Calendar = .current) -> [TimelineItem] {
        Timeline.tomorrow(events: events, agents: agents, now: now, calendar: calendar)
    }

    /// Blocked projects, in the console's order.
    public var blockedProjects: [Project] { projects.filter { $0.status == .blocked } }

    /// Today's newest report, if one has come in.
    public func todaysReport(now: Date = .now, calendar: Calendar = .current) -> NewsReport? {
        let today = Timeline.dayKey(now, calendar: calendar)
        return reports.first { $0.reportDate == today }
    }

    public var latestBrief: Brief? { briefs.first }

    /// Briefs grouped by the day they were published, newest day first.
    public func briefsByDay(calendar: Calendar = .current) -> [(day: Date, briefs: [Brief])] {
        var days: [Date] = []
        var grouped: [Date: [Brief]] = [:]
        for brief in briefs {
            let day = calendar.startOfDay(for: brief.publishedAt)
            if grouped[day] == nil { days.append(day) }
            grouped[day, default: []].append(brief)
        }
        return days.map { ($0, grouped[$0] ?? []) }
    }

    /// Visible symbols with their history, in the console's order.
    public var series: [QuoteSeries] { QuoteSeries.group(quotes, symbols: symbols) }

    public func series(for symbol: String) -> QuoteSeries? { series.first { $0.symbol == symbol } }

    /// Each shown symbol's holding, signals and numbers, and the holdings summed (`Holdings`).
    public var markets: (insights: [String: QuoteInsight], portfolio: Portfolio) {
        Holdings.build(series: series, latest: quoteData)
    }

    public var latestReport: NewsReport? { reports.first }

    public func report(_ id: UUID?) -> NewsReport? { reports.first { $0.id == id } }

    public func agent(_ id: UUID) -> Agent? { agents.first { $0.id == id } }

    /// The display's name, for titles and the assistant.
    public var displayName: String { settings?.displayName ?? "McFly" }

    /// Projects by how much they need a look: blocked first, then active, paused, done.
    public var projectsByAttention: [Project] {
        projects.sorted { ($0.status.attention, $0.sortOrder, $0.name) < ($1.status.attention, $1.sortOrder, $1.name) }
    }

    public func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    /// Visible metrics with their history, in the console's order.
    public var metricSeries: [MetricSeries] { MetricSeries.group(metrics, settings: metricSettings) }

    /// The same, grouped by `metric_settings.group_name`.
    public var metricGroups: [MetricGroup] { MetricSeries.grouped(metricSeries) }

    public func metricSeries(for key: String) -> MetricSeries? { metricSeries.first { $0.key == key } }

    public func dashboard(_ id: UUID?) -> Dashboard? { dashboards.first { $0.id == id } }

    /// Events still to come (or under way), soonest first.
    public func upcomingEvents(limit: Int, now: Date = .now) -> [CalendarEvent] {
        Array(events.filter { $0.endsAt > now }.prefix(limit))
    }

    /// Events grouped by the day they start, today onward, as an agenda.
    public func eventsByDay(from start: Date = .now, calendar: Calendar = .current) -> [(day: Date, events: [CalendarEvent])] {
        let today = calendar.startOfDay(for: start)
        var days: [Date] = []
        var grouped: [Date: [CalendarEvent]] = [:]
        for event in events where event.endsAt > today {
            let day = max(calendar.startOfDay(for: event.startsAt), today)
            if grouped[day] == nil { days.append(day) }
            grouped[day, default: []].append(event)
        }
        return days.sorted().map { ($0, grouped[$0] ?? []) }
    }

    public func events(on day: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        events.filter { $0.occurs(on: day, calendar: calendar) }
    }
}

/// One symbol's quotes, newest first, with the console's name and order.
public struct QuoteSeries: Identifiable, Hashable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public var name: String?
    /// Newest first.
    public var history: [Quote]
    public var sortOrder: Int

    public var latest: Quote { history[0] }
    /// Oldest to newest, for a sparkline.
    public var prices: [Double] { history.reversed().map(\.price) }
    public var displayName: String { name ?? latest.name ?? symbol }

    /// Groups the raw history by symbol, newest first within each, and orders
    /// the series as the display does: visible symbols by `sort_order`, then
    /// symbol. A symbol without a `symbols` row (one the console hasn't seen
    /// yet) sorts as a new one would, at 1000.
    public static func group(_ quotes: [Quote], symbols: [Symbol]) -> [QuoteSeries] {
        let known = Dictionary(symbols.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })
        var bySymbol: [String: [Quote]] = [:]
        for quote in quotes { bySymbol[quote.symbol, default: []].append(quote) }
        return bySymbol.compactMap { symbol, rows -> QuoteSeries? in
            if let row = known[symbol], row.hidden { return nil }
            let history = rows.sorted { ($0.asOf, $0.id) > ($1.asOf, $1.id) }
            guard !history.isEmpty else { return nil }
            return QuoteSeries(symbol: symbol, name: known[symbol]?.name ?? history[0].name,
                               history: history, sortOrder: known[symbol]?.sortOrder ?? 1000)
        }
        .sorted { ($0.sortOrder, $0.symbol) < ($1.sortOrder, $1.symbol) }
    }
}
