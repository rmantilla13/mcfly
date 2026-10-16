import Foundation

/// The seed's data, embedded (Resources/demo.json), for previews, the demo
/// mode and the unit tests. Mirrors backend/supabase/seed.sql.
public struct DemoData: Decodable, Sendable {
    public var agents: [Agent]
    public var briefs: [Brief]
    public var quotes: [Quote]
    public var symbols: [Symbol]
    public var reports: [NewsReport]
    public var devices: [Device]
    public var settings: PlatformSettings
    public var projects: [Project]
    public var metrics: [Metric]
    public var metricSettings: [MetricSetting]
    public var dashboards: [Dashboard]
    public var events: [CalendarEvent]

    enum CodingKeys: String, CodingKey {
        case agents, briefs, quotes, symbols, devices, settings, projects, metrics, dashboards, events
        case reports = "news_reports"
        case metricSettings = "metric_settings"
    }

    public static func load() throws -> DemoData {
        guard let url = Bundle.module.url(forResource: "demo", withExtension: "json") else {
            throw McFlyError.message("demo.json is missing from McFlyKit's resources.")
        }
        return try JSONDecoder.mcfly.decode(DemoData.self, from: Data(contentsOf: url))
    }

    /// The same data with every date moved so the newest push is `age` ago:
    /// the demo stays "20 min ago" however old the file gets.
    public func rebased(to now: Date = .now, newestAge: TimeInterval = 20 * 60) -> DemoData {
        let newest = (briefs.map(\.publishedAt) + quotes.map(\.asOf) + reports.map(\.publishedAt)).max() ?? now
        let shift = now.addingTimeInterval(-newestAge).timeIntervalSince(newest)
        guard shift != 0 else { return self }
        var copy = self
        func moved(_ date: Date) -> Date { date.addingTimeInterval(shift) }
        copy.agents = agents.map { a in
            var a = a
            a.createdAt = moved(a.createdAt); a.lastSeenAt = a.lastSeenAt.map(moved); a.keyCreatedAt = a.keyCreatedAt.map(moved)
            return a
        }
        copy.briefs = briefs.map { b in
            var b = b
            b.publishedAt = moved(b.publishedAt); b.createdAt = moved(b.createdAt); b.updatedAt = moved(b.updatedAt)
            b.expiresAt = b.expiresAt.map(moved)
            return b
        }
        copy.quotes = quotes.map { q in
            var q = q
            q.asOf = moved(q.asOf); q.createdAt = moved(q.createdAt)
            // Today's chart is today's session, not one shifted by the push's age.
            let price = q.price
            if let day = q.data?.intraday { q.data?.intraday = day.movedToToday(now: now, price: price) }
            return q
        }
        // A report's date is a day, not a moment, and the seed's are Chicago's:
        // the newest report takes the day the newest push now falls on, here,
        // and the others keep their distance from it.
        let calendar = Calendar.current
        let newestReportDay = reports.max { $0.publishedAt < $1.publishedAt }.flatMap { Self.date($0.reportDate, calendar: calendar) }
        let days = newestReportDay.flatMap {
            calendar.dateComponents([.day], from: $0, to: calendar.startOfDay(for: moved(newest))).day
        } ?? 0
        copy.reports = reports.map { r in
            var r = r
            r.publishedAt = moved(r.publishedAt); r.createdAt = r.createdAt.map(moved)
            r.reportDate = Self.day(r.reportDate, plus: days, calendar: calendar)
            return r
        }
        copy.devices = devices.map { d in
            var d = d
            d.lastSeenAt = d.lastSeenAt.map(moved); d.createdAt = moved(d.createdAt)
            return d
        }
        copy.projects = projects.map { p in
            var p = p
            p.createdAt = moved(p.createdAt); p.updatedAt = moved(p.updatedAt)
            p.updates = p.updates.map { u in
                var u = u
                u.happenedAt = moved(u.happenedAt); u.createdAt = u.createdAt.map(moved)
                return u
            }
            return p
        }
        copy.metrics = metrics.map { m in
            var m = m
            m.asOf = moved(m.asOf); m.createdAt = moved(m.createdAt)
            return m
        }
        copy.events = events.map { e in
            var e = e
            e.startsAt = moved(e.startsAt); e.endsAt = moved(e.endsAt)
            return e
        }
        return copy
    }

    /// "2026-10-14" plus `days`, or the date unchanged if it doesn't parse.
    static func day(_ key: String, plus days: Int, calendar: Calendar) -> String {
        guard days != 0, let date = date(key, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return Timeline.dayKey(shifted, calendar: calendar)
    }

    /// The start of "2026-10-14" in the calendar's time zone.
    static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// Feeds from the demo file. Fails like the network would if the file is missing.
public struct DemoFeedSource: FeedSource {
    private let data: DemoData

    public init(data: DemoData) { self.data = data }

    public init() throws {
        self.init(data: try DemoData.load().rebased())
    }

    public func loadAgents() async throws -> [Agent] { data.agents }
    public func loadBriefs(limit: Int) async throws -> [Brief] { Array(data.briefs.prefix(limit)) }
    public func loadQuotes(limit: Int) async throws -> [Quote] { Array(data.quotes.prefix(limit)) }
    public func loadSymbols() async throws -> [Symbol] { data.symbols }
    public func loadReports(limit: Int) async throws -> [NewsReport] { Array(data.reports.prefix(limit)) }
    public func loadSettings() async throws -> PlatformSettings? { data.settings }
    public func loadProjects(updatesPerProject: Int) async throws -> [Project] {
        data.projects.map { p in
            var p = p
            p.updates = Array(p.updates.prefix(updatesPerProject))
            return p
        }
    }
    public func loadMetrics(limit: Int) async throws -> [Metric] { Array(data.metrics.prefix(limit)) }
    public func loadMetricSettings() async throws -> [MetricSetting] { data.metricSettings }
    public func loadDashboards() async throws -> [Dashboard] { data.dashboards }
    public func loadEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        data.events.filter { $0.endsAt >= from && $0.startsAt <= to }
    }
}

/// Admin calls answered from memory, so the Displays, Agents and Settings
/// screens work in previews. Changes last until the app quits.
public actor DemoAdminService: AdminService {
    private var devices: [Device]
    private var agents: [Agent]
    private var current: PlatformSettings
    private let projects: [Project]

    public init(data: DemoData) {
        devices = data.devices
        agents = data.agents
        current = data.settings
        projects = data.projects
    }

    public init() throws {
        self.init(data: try DemoData.load().rebased())
    }

    public func isPlatformAdmin() async throws -> Bool { true }
    public func listDevices() async throws -> [Device] { devices }

    /// The embedded updates are the whole timeline in the demo.
    public func projectUpdates(_ projectId: UUID, limit: Int) async throws -> [ProjectUpdate] {
        guard let project = projects.first(where: { $0.id == projectId }) else { throw McFlyError.message("Project not found") }
        return Array(project.updates.prefix(limit))
    }

    public func renameDevice(_ id: UUID, name: String) async throws {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { throw McFlyError.message("Device not found") }
        devices[i].name = name
    }

    public func revokeDevice(_ id: UUID) async throws {
        devices.removeAll { $0.id == id }
    }

    public func listAgents() async throws -> [Agent] { agents }

    public func createAgent(name: String, kind: Agent.Kind, color: String) async throws -> CreatedAgent {
        let id = UUID()
        let slug = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        agents.append(Agent(id: id, name: name, slug: slug, kind: kind, color: color, createdAt: .now,
                            keyPrefix: "mcf_demo0000", keyCreatedAt: .now, pushes7d: 0))
        return CreatedAgent(id: id, slug: slug, key: "mcf_demo" + String(repeating: "0", count: 36))
    }

    public func rotateAgentKey(_ id: UUID) async throws -> String {
        guard let i = agents.firstIndex(where: { $0.id == id }) else { throw McFlyError.message("Agent not found") }
        agents[i].revokedAt = nil
        agents[i].keyCreatedAt = .now
        return "mcf_demo" + String(repeating: "1", count: 36)
    }

    public func revokeAgent(_ id: UUID) async throws {
        guard let i = agents.firstIndex(where: { $0.id == id }) else { throw McFlyError.message("Agent not found") }
        agents[i].revokedAt = .now
        agents[i].keyPrefix = nil
    }

    public func deleteAgent(_ id: UUID) async throws {
        agents.removeAll { $0.id == id }
    }

    public func settings() async throws -> PlatformSettings { current }

    public func updateSettings(displayName: String?, timezone: String?, assistantProvider: AssistantProvider?) async throws -> PlatformSettings {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { current.displayName = displayName }
        if let assistantProvider { current.assistantProvider = assistantProvider }
        if let timezone {
            guard TimeZone(identifier: timezone) != nil else { throw McFlyError.message("Timezone \(timezone) is not known") }
            current.timezone = timezone
        }
        current.updatedAt = .now
        return current
    }
}
