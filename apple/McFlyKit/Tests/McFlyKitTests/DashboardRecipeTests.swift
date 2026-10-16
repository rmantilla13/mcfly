import XCTest
@testable import McFlyKit

/// Made dashboards: the templates, reading a part, the shape the database
/// takes (the console's tests/dashboard-sources.test.mjs, same cases), and
/// the demo's drawing. The database's own drawing is checked in
/// backend/tests/dashboards_test.sql.
final class DashboardRecipeTests: XCTestCase {
    private func json(_ part: DashboardPart) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(part)) as! [String: Any]
    }

    private func read(_ json: String) throws -> DashboardPart? {
        try JSONDecoder().decode(DashboardPart.self, from: Data(json.utf8)).normalized()
    }

    func testTemplatesMatchTheConsole() throws {
        XCTAssertEqual(DashboardTemplate.all.map(\.id), ["today", "markets", "numbers", "projects", "week", "health", "reading", "blank"])
        for t in DashboardTemplate.all {
            XCTAssertTrue((1...20).contains(t.parts.count), t.id)
            XCTAssertNotNil(t.id.range(of: "^[a-z0-9][a-z0-9-]{0,39}$", options: .regularExpression), t.id)
            // A template needs no cleaning: it reads back as itself.
            let encoded = try t.parts.map(json)
            let cleaned = try DashboardPart.normalized(t.parts).map(json)
            XCTAssertEqual(encoded as NSArray, cleaned as NSArray, t.id)
        }
        XCTAssertEqual(DashboardTemplate.find("markets")?.label, "Markets")
        XCTAssertNil(DashboardTemplate.find("nope"))
        // Each call is a fresh copy.
        var today = try XCTUnwrap(DashboardTemplate.find("today")).parts
        today[0].days = 31
        XCTAssertEqual(DashboardTemplate.find("today")?.parts[0].days, 1)
    }

    func testTheWireShapeIsTheConsoles() throws {
        let markets = try XCTUnwrap(DashboardTemplate.find("markets")).parts
        XCTAssertEqual(try json(markets[0]) as NSDictionary, ["from": "quotes", "symbols": [String](), "show": "chart", "limit": 1] as NSDictionary)
        let week = try XCTUnwrap(DashboardTemplate.find("week")).parts
        XCTAssertEqual(try json(week[0]) as NSDictionary, ["from": "calendar", "calendars": [String](), "days": 7, "limit": 12] as NSDictionary)
        XCTAssertEqual(try json(week[2]) as NSDictionary, ["from": "todos", "kind": "reminder", "limit": 6] as NSDictionary)
        var brief = DashboardPart(.brief)
        brief.briefKind = .daily
        brief.title = "Morning"
        XCTAssertEqual(try json(brief) as NSDictionary, ["from": "brief", "kind": "daily", "title": "Morning"] as NSDictionary)
        XCTAssertEqual(try json(DashboardPart(.agents)) as NSDictionary, ["from": "agents", "agents": [String](), "hours": 24] as NSDictionary)
        // What the save sends: every argument, nulls included.
        let params = SaveParams(dashboard: nil, title: "T", sources: [], subtitle: nil, template: "markets")
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as! [String: Any]
        XCTAssertEqual(Set(sent.keys), ["dashboard", "title", "sources", "subtitle", "template"])
        XCTAssertTrue(sent["dashboard"] is NSNull)
    }

    func testReadingAPartCleansWhatItCan() throws {
        let quotes = try XCTUnwrap(read(#"{"from": "quotes", "symbols": [" aapl ", "AAPL", "bad symbol!", 4], "show": "candles", "limit": "40"}"#))
        XCTAssertEqual(quotes.symbols, ["AAPL"])
        XCTAssertEqual(quotes.show, .tiles)
        XCTAssertEqual(quotes.limit, 12)
        let metrics = try XCTUnwrap(read(#"{"from": "metrics", "keys": ["API.P95"], "group": "  ", "show": "chart", "title": " Speed "}"#))
        XCTAssertEqual(metrics.keys, ["api.p95"])
        XCTAssertNil(metrics.group)
        XCTAssertEqual(metrics.title, "Speed")
        XCTAssertEqual(try read(#"{"from": "calendar", "days": 6}"#)?.days, 7, "days snap to a choice")
        XCTAssertEqual(try read(#"{"from": "calendar", "days": 5}"#)?.days, 3, "a tie goes to the smaller")
        XCTAssertEqual(try read(#"{"from": "todos", "kind": "chores"}"#)?.todos, .all)
        let brief = try XCTUnwrap(read(#"{"from": "brief", "kind": "weekly", "agent": "not-an-id"}"#))
        XCTAssertNil(brief.briefKind)
        XCTAssertNil(brief.agent)
        XCTAssertEqual(try read(#"{"from": "projects", "projects": ["00000000-0000-0000-0000-00000000A004", "x"]}"#)?.projects,
                       ["00000000-0000-0000-0000-00000000a004"])
        XCTAssertEqual(try read(#"{"from": "agents", "hours": 30}"#)?.hours, 24)
        XCTAssertNil(try read(#"{"from": "note", "body": "   "}"#), "a note needs words")
        XCTAssertThrowsError(try read(#"{"from": "weather"}"#))
        XCTAssertEqual(DashboardPart.normalized(Array(repeating: DashboardPart(.todos), count: 30)).count, 20)
    }

    func testAStoredRecipeSkipsWhatItCantRead() throws {
        let row = #"""
        {"id": "11111111-1111-1111-1111-111111111111", "agent_id": "00000000-0000-0000-0000-0000000000f1", "key": "mine", "title": "Mine",
         "widgets": [{"type": "text", "body": "x"}], "template": "markets",
         "sources": [{"from": "quotes", "symbols": ["AAPL"]}, {"from": "weather"}, "nonsense"]}
        """#
        let board = try JSONDecoder.mcfly.decode(Dashboard.self, from: Data(row.utf8))
        XCTAssertTrue(board.isMade)
        XCTAssertEqual(board.template, "markets")
        XCTAssertEqual(board.sources?.map(\.from), [.quotes])
        XCTAssertEqual(board, try JSONDecoder.mcfly.decode(Dashboard.self, from: Data(row.utf8)), "two reads of one board are equal")
        let agents = try JSONDecoder.mcfly.decode(Dashboard.self, from: Data(#"{"id": "11111111-1111-1111-1111-111111111111", "agent_id": "00000000-0000-0000-0000-0000000000f1", "key": "ops", "title": "Ops", "widgets": [], "sources": null}"#.utf8))
        XCTAssertFalse(agents.isMade)
    }

    func testAPartSaysWhereItPullsFrom() {
        var options = DashboardSourceOptions()
        options.metrics = [.init(key: "api.p95", label: "API p95", group: "Ops", unit: "ms", hidden: false)]
        options.projects = [.init(id: "p1", name: "McFly", status: "active", agentName: "GitHub")]
        options.newsSections = [.init(key: "tech", name: "Tech")]
        options.agents = [.init(id: "a1", name: "Grok", color: "#7A64E8", hasKey: true)]
        var p = DashboardPart(.quotes)
        p.symbols = ["AAPL", "NVDA"]
        XCTAssertEqual(p.describe(), "AAPL, NVDA as tiles")
        p.symbols = ["A", "B", "C", "D", "E"]; p.show = .chart; p.limit = 2
        XCTAssertEqual(p.describe(), "A, B, C and 2 more as charts, up to 2")
        var m = DashboardPart(.metrics)
        m.keys = ["api.p95"]
        XCTAssertEqual(m.describe(options), "API p95 as tiles")
        m.keys = []; m.group = "Ops"; m.show = .chart
        XCTAssertEqual(m.describe(), "Every Ops metric as charts")
        var pr = DashboardPart(.projects)
        pr.projects = ["p1"]; pr.show = .list
        XCTAssertEqual(pr.describe(options), "McFly, as a list")
        var c = DashboardPart(.calendar)
        c.days = 1
        XCTAssertEqual(c.describe(), "Every calendar, today")
        c.calendars = ["Work"]; c.days = 7
        XCTAssertEqual(c.describe(), "Work, the next 7 days")
        var t = DashboardPart(.todos)
        t.todos = .reminder
        XCTAssertEqual(t.describe(), "Reminders")
        var n = DashboardPart(.news)
        n.section = "tech"; n.limit = 3
        XCTAssertEqual(n.describe(options), "Tech headlines, up to 3")
        var b = DashboardPart(.brief)
        b.briefKind = .daily; b.agent = "a1"
        XCTAssertEqual(b.describe(options), "The newest daily brief from Grok")
        var a = DashboardPart(.agents)
        a.hours = 72
        XCTAssertEqual(a.describe(), "Every agent with a key, quiet after 3 days")
    }

    // MARK: The demo's drawing

    func testTimesReadTheWayTheDatabaseWritesThem() {
        let chicago = TimeZone(identifier: "America/Chicago")!
        let now = Date(timeIntervalSince1970: 1_792_162_800) // 2026-10-16 15:00 UTC, 10 AM in Chicago
        XCTAssertEqual(DashboardDrawing.when(now.addingTimeInterval(5.5 * 3600), allDay: false, in: chicago, now: now), "Today 3:30 PM")
        XCTAssertEqual(DashboardDrawing.when(now.addingTimeInterval(24 * 3600), allDay: false, in: chicago, now: now), "Tomorrow 10:00 AM")
        XCTAssertEqual(DashboardDrawing.when(now.addingTimeInterval(-24 * 3600), allDay: true, in: chicago, now: now), "Yesterday")
        XCTAssertEqual(DashboardDrawing.when(now.addingTimeInterval(96 * 3600), allDay: false, in: TimeZone(identifier: "UTC")!, now: now), "Tue Oct 20 3:00 PM")
    }

    func testEveryTemplateDrawsFromTheDemo() throws {
        let feeds = DashboardDrawing.Feeds(try DemoData.load().rebased())
        for t in DashboardTemplate.all {
            let widgets = DashboardDrawing.draw(t.parts, from: feeds)
            XCTAssertTrue((1...40).contains(widgets.count), t.id)
            XCTAssertFalse(widgets.contains { if case .unknown = $0 { return true } else { return false } }, t.id)
        }
        XCTAssertEqual(DashboardDrawing.draw([], from: feeds), [.text(title: nil, body: "Nothing to show yet.")])
    }

    func testTheDemoDrawsQuotesMetricsAndEmptyParts() throws {
        let data = try DemoData.load().rebased()
        let feeds = DashboardDrawing.Feeds(data)
        var quotes = DashboardPart(.quotes)
        quotes.symbols = ["AAPL"]
        guard case let .metric(label, value, unit, _, _) = DashboardDrawing.draw([quotes], from: feeds).first else { return XCTFail("a quote tile") }
        let latest = try XCTUnwrap(data.quotes.filter { $0.symbol == "AAPL" }.max { ($0.asOf, $0.id) < ($1.asOf, $1.id) })
        XCTAssertEqual(label, "AAPL")
        XCTAssertEqual(value, latest.price)
        XCTAssertEqual(unit, "USD")
        // Every visible symbol, in the display's order.
        let all = DashboardDrawing.draw([DashboardPart(.quotes)], from: feeds).compactMap { w -> String? in
            if case let .metric(label, _, _, _, _) = w { return label } else { return nil }
        }
        let order = data.symbols.filter { !$0.hidden }.sorted { ($0.sortOrder, $0.symbol) < ($1.sortOrder, $1.symbol) }.map(\.symbol)
        XCTAssertEqual(all, Array(order.filter { s in data.quotes.contains { $0.symbol == s } }.prefix(8)))
        quotes.symbols = ["ZZZZ"]
        XCTAssertEqual(DashboardDrawing.draw([quotes], from: feeds), [.text(title: "Markets", body: "No quotes yet for ZZZZ.")])
        var metrics = DashboardPart(.metrics)
        metrics.keys = ["nope"]
        metrics.title = "Shop"
        XCTAssertEqual(DashboardDrawing.draw([metrics], from: feeds), [.text(title: "Shop", body: "No numbers yet.")])
        XCTAssertEqual(DashboardDrawing.draw([DashboardPart(.todos)], from: feeds), [.text(title: "To do", body: "Nothing open.")])
    }

    @MainActor
    func testTheDemoKeepsMadeBoards() async throws {
        // The demo keeps made boards for the whole process; other tests count the demo's boards.
        await DemoDashboards.shared.reset()
        addTeardownBlock { await DemoDashboards.shared.reset() }
        let admin = DemoAdminService(data: try DemoData.load().rebased())
        let options = try await admin.dashboardSources()
        XCTAssertFalse(options.symbols.isEmpty)
        let markets = try XCTUnwrap(DashboardTemplate.find("markets"))
        let id = try await admin.saveDashboard(id: nil, title: "My Markets!", subtitle: nil, template: markets.id, parts: markets.parts)
        let store = FeedStore(source: DemoFeedSource(data: try DemoData.load().rebased()))
        await store.refresh()
        let board = try XCTUnwrap(store.dashboard(id))
        XCTAssertTrue(board.isMade)
        XCTAssertEqual(board.template, "markets")
        XCTAssertTrue(board.key.hasPrefix("my-markets"))
        XCTAssertFalse(board.widgets.isEmpty)
        var note = DashboardPart(.note)
        note.body = "Edited"
        _ = try await admin.saveDashboard(id: id, title: "Holdings", subtitle: nil, template: nil, parts: [note])
        await store.refresh()
        XCTAssertEqual(store.dashboard(id)?.title, "Holdings")
        XCTAssertEqual(store.dashboard(id)?.widgets, [.text(title: nil, body: "Edited")])
        do {
            _ = try await admin.saveDashboard(id: UUID(), title: "x", subtitle: nil, template: nil, parts: [note])
            XCTFail("an agent's board isn't edited here")
        } catch {}
    }
}
