import Foundation
import Supabase

/// Reads the feeds through PostgREST with the signed-in person's JWT. RLS
/// lets an admin read every feed table; anyone else gets empty lists, which
/// the sign-in flow catches first with `is_platform_admin`.
public struct SupabaseFeedSource: FeedSource {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func loadAgents() async throws -> [Agent] {
        try decode(await client.from("agents").select().order("created_at").execute().data)
    }

    public func loadBriefs(limit: Int) async throws -> [Brief] {
        let now = ISO8601DateFormatter().string(from: .now)
        return try decode(await client.from("briefs").select()
            .or("expires_at.is.null,expires_at.gt.\(now)")
            .order("published_at", ascending: false)
            .limit(limit)
            .execute().data)
    }

    /// The history without `data`, which only the newest row needs.
    public func loadQuotes(limit: Int) async throws -> [Quote] {
        try decode(await client.from("quotes")
            .select("id,agent_id,symbol,name,price,change,change_pct,currency,note,as_of,created_at")
            .order("as_of", ascending: false)
            .order("id", ascending: false)
            .limit(limit)
            .execute().data)
    }

    public func loadLatestQuoteData() async throws -> [QuoteLatest] {
        try decode(await client.from("quotes_latest").select("symbol,as_of,data").execute().data)
    }

    public func loadSymbols() async throws -> [Symbol] {
        try decode(await client.from("symbols").select().order("sort_order").order("symbol").execute().data)
    }

    /// Reports with their items embedded through the report_id foreign key.
    public func loadReports(limit: Int) async throws -> [NewsReport] {
        try decode(await client.from("news_reports").select("*, news_items(*)")
            .order("report_date", ascending: false)
            .order("published_at", ascending: false)
            .limit(limit)
            .execute().data)
    }

    public func loadSettings() async throws -> PlatformSettings? {
        let rows: [PlatformSettings] = try decode(await client.from("platform_settings").select().limit(1).execute().data)
        return rows.first
    }

    /// Projects with their newest updates embedded through the project_id foreign key.
    public func loadProjects(updatesPerProject: Int) async throws -> [Project] {
        try decode(await client.from("projects").select("*, project_updates(*)")
            .order("sort_order").order("name")
            .order("happened_at", ascending: false, referencedTable: "project_updates")
            .limit(updatesPerProject, referencedTable: "project_updates")
            .execute().data)
    }

    public func loadDismissals() async throws -> [Dismissal] {
        try decode(await client.from("dismissals").select("key,hide_until").execute().data)
    }

    public func loadMetrics(limit: Int) async throws -> [Metric] {
        try decode(await client.from("metrics").select()
            .order("as_of", ascending: false)
            .order("id", ascending: false)
            .limit(limit)
            .execute().data)
    }

    public func loadMetricSettings() async throws -> [MetricSetting] {
        try decode(await client.from("metric_settings").select().order("sort_order").order("key").execute().data)
    }

    public func loadDashboards() async throws -> [Dashboard] {
        try decode(await client.from("dashboards").select().eq("hidden", value: false)
            .order("sort_order").order("title").execute().data)
    }

    /// Events overlapping the window: ending after `from`, starting before `to`.
    public func loadEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        let iso = ISO8601DateFormatter()
        return try decode(await client.from("events").select()
            .gte("ends_at", value: iso.string(from: from))
            .lte("starts_at", value: iso.string(from: to))
            .order("starts_at").order("id")
            .limit(1000)
            .execute().data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder.mcfly.decode(T.self, from: data)
    }
}
