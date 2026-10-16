import Foundation
import Supabase

// The admin calls behind the dashboard builder (spec §1.7): what a part can
// pull from, a recipe drawn without saving, and saving one. The database
// draws a saved board and keeps it drawn, so the feed then shows it like any
// other.

extension SupabaseAdminService {
    public func dashboardSources() async throws -> DashboardSourceOptions {
        let data = try await client.rpc("admin_dashboard_sources").execute().data
        return try JSONDecoder.mcfly.decode(DashboardSourceOptions.self, from: data)
    }

    public func previewDashboard(_ parts: [DashboardPart]) async throws -> [DashboardWidget] {
        struct Params: Encodable { var sources: [DashboardPart] }
        let data = try await client.rpc("admin_preview_dashboard", params: Params(sources: DashboardPart.normalized(parts))).execute().data
        return try JSONDecoder.mcfly.decode([LenientWidget].self, from: data).map(\.widget)
    }

    public func saveDashboard(id: UUID?, title: String, subtitle: String?, template: String?, parts: [DashboardPart]) async throws -> UUID {
        let data = try await client.rpc("admin_save_dashboard", params: SaveParams(dashboard: id?.lowercased, title: title, sources: DashboardPart.normalized(parts),
                                                                                     subtitle: subtitle, template: template)).execute().data
        return try JSONDecoder.mcfly.decode(UUID.self, from: data)
    }
}

/// `admin_save_dashboard`'s arguments. Every one is sent, nulls included:
/// PostgREST picks the function by the names it's given.
struct SaveParams: Encodable {
    var dashboard: String?
    var title: String
    var sources: [DashboardPart]
    var subtitle: String?
    var template: String?

    enum CodingKeys: String, CodingKey { case dashboard, title, sources, subtitle, template }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dashboard, forKey: .dashboard)
        try c.encode(title, forKey: .title)
        try c.encode(sources, forKey: .sources)
        try c.encode(subtitle, forKey: .subtitle)
        try c.encode(template, forKey: .template)
    }
}

// MARK: Demo

extension DemoAdminService {
    public func dashboardSources() async throws -> DashboardSourceOptions {
        await DemoDashboards.shared.options()
    }

    public func previewDashboard(_ parts: [DashboardPart]) async throws -> [DashboardWidget] {
        let parts = DashboardPart.normalized(parts)
        guard !parts.isEmpty else { throw McFlyError.message("A dashboard needs at least one part.") }
        return await DemoDashboards.shared.draw(parts)
    }

    public func saveDashboard(id: UUID?, title: String, subtitle: String?, template: String?, parts: [DashboardPart]) async throws -> UUID {
        try await DemoDashboards.shared.save(id: id, title: title, subtitle: subtitle, template: template, parts: parts)
    }
}

/// The demo's made boards, kept until the app quits: the builder saves here,
/// and the demo feed (`DemoFeedSource`) lists them after the seed's boards,
/// drawn from its own data.
public actor DemoDashboards {
    public static let shared = DemoDashboards()

    struct Made {
        var id: UUID
        var key: String
        var title: String
        var subtitle: String?
        var template: String?
        var parts: [DashboardPart]
        var updatedAt: Date
    }

    private var made: [Made] = []
    private var data: DemoData?
    /// McFly's own agent, which owns made boards (`mcfly_agent()`).
    public static let agentId = UUID(uuidString: "00000000-0000-0000-0000-0000000000f1")!

    /// The feed's data, or the demo file's when the feed hasn't loaded yet.
    private func feeds() -> DashboardDrawing.Feeds {
        if data == nil { data = try? DemoData.load().rebased() }
        return data.map(DashboardDrawing.Feeds.init) ?? DashboardDrawing.Feeds(Self.empty)
    }

    private static let empty = DemoData(agents: [], briefs: [], quotes: [], symbols: [], reports: [], devices: [],
                                        settings: PlatformSettings(), projects: [], metrics: [], metricSettings: [], dashboards: [], events: [])

    /// Made boards, drawn from `data`, which the feed keeps for the builder.
    public func boards(drawnFrom data: DemoData) -> [Dashboard] {
        self.data = data
        let feeds = DashboardDrawing.Feeds(data)
        return made.enumerated().map { i, m in
            Dashboard(id: m.id, agentId: Self.agentId, key: m.key, title: m.title, subtitle: m.subtitle,
                      widgets: DashboardDrawing.draw(m.parts, from: feeds), sortOrder: 1000 + i, updatedAt: m.updatedAt,
                      template: m.template, sources: m.parts)
        }
    }

    /// Forgets every made board (the tests, between cases).
    func reset() { made = [] }

    func draw(_ parts: [DashboardPart]) -> [DashboardWidget] {
        DashboardDrawing.draw(parts, from: feeds())
    }

    func options() -> DashboardSourceOptions {
        let f = feeds()
        let latestUnit = { (key: String) in f.metrics.filter { $0.key == key }.max { $0.asOf < $1.asOf }?.unit }
        var sections: [DashboardSourceOptions.SectionOption] = []
        for item in f.reports.flatMap(\.items).sorted(by: { ($0.sectionOrder, $0.sectionName) < ($1.sectionOrder, $1.sectionName) })
        where !sections.contains(where: { $0.key == item.sectionKey }) {
            sections.append(.init(key: item.sectionKey, name: item.sectionName))
        }
        return DashboardSourceOptions(
            symbols: f.symbols.sorted { ($0.hidden ? 1 : 0, $0.sortOrder, $0.symbol) < ($1.hidden ? 1 : 0, $1.sortOrder, $1.symbol) }
                .map { s in .init(symbol: s.symbol, name: s.name ?? f.quotes.first { $0.symbol == s.symbol }?.name, hidden: s.hidden) },
            metrics: f.metricSettings.sorted { ($0.hidden ? 1 : 0, $0.sortOrder, $0.key) < ($1.hidden ? 1 : 0, $1.sortOrder, $1.key) }
                .map { m in .init(key: m.key, label: m.label ?? m.key, group: m.groupName, unit: latestUnit(m.key), hidden: m.hidden) },
            projects: f.projects.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
                .map { p in .init(id: p.id.lowercased, name: p.name, status: p.status.rawValue, agentName: f.agents.first { $0.id == p.agentId }?.name) },
            calendars: Array(Set(f.events.map(\.calendar))).sorted(),
            newsSections: sections,
            agents: f.agents.filter { !$0.isRevoked }.sorted { $0.name < $1.name }
                .map { a in .init(id: a.id.lowercased, name: a.name, color: a.color, hasKey: a.keyPrefix != nil) },
            timezone: f.timeZone.identifier)
    }

    func save(id: UUID?, title: String, subtitle: String?, template: String?, parts: [DashboardPart]) throws -> UUID {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty else { throw McFlyError.message("Give the dashboard a title.") }
        let parts = DashboardPart.normalized(parts)
        guard !parts.isEmpty else { throw McFlyError.message("A dashboard needs at least one part.") }
        let subtitle = DashboardPart.words(subtitle, 200)
        if let id {
            guard let i = made.firstIndex(where: { $0.id == id }) else {
                throw McFlyError.message("An agent lays this dashboard out; only a dashboard made here can be edited.")
            }
            made[i].title = title
            made[i].subtitle = subtitle
            made[i].template = template ?? made[i].template
            made[i].parts = parts
            made[i].updatedAt = .now
            return id
        }
        let taken = Set(made.map(\.key) + (data?.dashboards.map(\.key) ?? []))
        let base = String(title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(56))
        var key = base.isEmpty ? "board" : base
        var n = 1
        while taken.contains(key) {
            n += 1
            key = "\(base.isEmpty ? "board" : base)-\(n)"
        }
        let new = Made(id: UUID(), key: key, title: title, subtitle: subtitle, template: template, parts: parts, updatedAt: .now)
        made.append(new)
        return new.id
    }
}
