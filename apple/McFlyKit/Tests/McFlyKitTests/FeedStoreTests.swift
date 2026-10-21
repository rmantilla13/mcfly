import XCTest
@testable import McFlyKit

/// A source the tests control: the demo data, with an expired brief added
/// and a failure switch.
private struct TestSource: FeedSource {
    var data: DemoData
    var fails = false
    var dismissals: [Dismissal] = []

    func loadAgents() async throws -> [Agent] { try check(); return data.agents }
    func loadBriefs(limit: Int) async throws -> [Brief] {
        try check()
        var expired = data.briefs[0]
        expired = Brief(id: UUID(), agentId: expired.agentId, title: "Old alert", body: "", kind: .alert,
                        publishedAt: .now, expiresAt: Date().addingTimeInterval(-60), createdAt: .now, updatedAt: .now)
        return data.briefs + [expired]
    }
    func loadQuotes(limit: Int) async throws -> [Quote] { try check(); return data.quotes }
    func loadSymbols() async throws -> [Symbol] { try check(); return data.symbols }
    func loadReports(limit: Int) async throws -> [NewsReport] { try check(); return data.reports.reversed() }
    func loadSettings() async throws -> PlatformSettings? { try check(); return data.settings }
    func loadProjects(updatesPerProject: Int) async throws -> [Project] { try check(); return data.projects.reversed() }
    func loadMetrics(limit: Int) async throws -> [Metric] { try check(); return data.metrics }
    func loadMetricSettings() async throws -> [MetricSetting] {
        try check()
        // One hidden metric, to be left out.
        return data.metricSettings + [MetricSetting(key: "orders.open", groupName: "Store", sortOrder: 1, hidden: true)].filter { _ in false }
            + [MetricSetting(key: "secret", groupName: "Ops", sortOrder: 9, hidden: true)]
    }
    func loadDashboards() async throws -> [Dashboard] {
        try check()
        let hidden = Dashboard(id: UUID(), agentId: data.agents[0].id, key: "hidden", title: "Hidden", widgets: [.text(title: nil, body: "x")],
                               sortOrder: 0, hidden: true, updatedAt: .now)
        return data.dashboards.reversed() + [hidden]
    }
    func loadEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        try check()
        return data.events.filter { $0.endsAt >= from && $0.startsAt <= to }.reversed()
    }

    func loadDismissals() async throws -> [Dismissal] { try check(); return dismissals }

    private func check() throws {
        if fails { throw URLError(.notConnectedToInternet) }
    }
}

@MainActor
final class FeedStoreTests: XCTestCase {
    func testRefreshFillsAndDerives() async throws {
        // The seed's newest push at 3 pm today, so its briefs fall on today and
        // yesterday wherever the clock is: rebased to now, a late-evening run
        // (CI's 22:50 UTC) put all three on one day.
        let afternoon = try XCTUnwrap(Calendar.current.date(bySettingHour: 15, minute: 20, second: 0, of: .now))
        let demo = try DemoData.load().rebased(to: afternoon)
        let store = FeedStore(source: TestSource(data: demo))
        XCTAssertFalse(store.hasLoaded)
        await store.refresh()
        XCTAssertTrue(store.hasLoaded)
        XCTAssertNil(store.errorMessage)
        // Expired briefs are dropped; the rest are newest first.
        XCTAssertEqual(store.briefs.map(\.externalId), ["seed-hourly", "seed-daily", "seed-yesterday"])
        XCTAssertEqual(store.latestBrief?.title, "Hourly check-in")
        XCTAssertEqual(store.briefsByDay().count, 2)
        XCTAssertEqual(store.briefsByDay()[0].briefs.count, 2)
        // Reports come back newest first however the source ordered them.
        XCTAssertEqual(store.latestReport?.slug, "2026-10-14")
        XCTAssertEqual(store.series.map(\.symbol), ["SPY", "AAPL", "NVDA", "TSLA"])
        XCTAssertEqual(store.series(for: "AAPL")?.history.count, 3)
        XCTAssertEqual(store.agent(demo.agents[0].id)?.name, "Grok")
        XCTAssertEqual(store.displayName, "McFly")
        // The productivity feeds come through the same refresh, ordered however the source sent them.
        XCTAssertEqual(store.projects.map(\.key), ["mcfly", "onyx", "homestead"])
        XCTAssertEqual(store.dashboards.map(\.key), ["ops", "launch"])
        XCTAssertEqual(store.metricSeries.count, 5)
        XCTAssertEqual(store.events.first?.title, "Standup")
        XCTAssertEqual(store.settings?.assistantProvider, .claude)
    }

    func testDismissedCalloutsStayHidden() async throws {
        let demo = try DemoData.load()
        let onyx = try XCTUnwrap(demo.projects.first { $0.key == "onyx" })
        var source = TestSource(data: demo)
        // Onyx's callout until it changes, and a mover's that has run out.
        source.dismissals = [Dismissal(key: "blocked:\(onyx.id.uuidString.lowercased())"),
                             Dismissal(key: "mover:aapl", hideUntil: Date().addingTimeInterval(-60))]
        let store = FeedStore(source: source)
        await store.refresh()
        // Still blocked on the Projects screen, but no longer called out.
        XCTAssertEqual(store.blockedProjects.map(\.key), ["onyx"])
        XCTAssertTrue(store.needsYou.isEmpty)
        XCTAssertFalse(store.insights().contains { $0.kind == .blocked })
        // Any case (Swift writes a UUID in capitals); a run-out one hides nothing.
        XCTAssertTrue(store.isDismissed("BLOCKED:\(onyx.id.uuidString)"))
        XCTAssertFalse(store.isDismissed("mover:AAPL"))
    }

    func testAFailedRefreshKeepsWhatWasLoaded() async throws {
        let demo = try DemoData.load()
        let store = FeedStore(source: TestSource(data: demo, fails: true))
        await store.refresh()
        XCTAssertFalse(store.hasLoaded)
        XCTAssertEqual(store.errorMessage, "McFly couldn't be reached. Check your connection and try again.")
        XCTAssertEqual(store.displayName, "McFly")
    }

    func testDemoAdminServiceRoundTrips() async throws {
        let admin = try DemoAdminService()
        let isAdmin = try await admin.isPlatformAdmin()
        XCTAssertTrue(isAdmin)
        let created = try await admin.createAgent(name: "Weather bot", kind: .other, color: "#5B7CF5")
        XCTAssertTrue(created.key.hasPrefix("mcf_"))
        XCTAssertEqual(created.slug, "weather-bot")
        let rotated = try await admin.rotateAgentKey(created.id)
        XCTAssertNotEqual(rotated, created.key)
        try await admin.revokeAgent(created.id)
        let revoked = try await admin.listAgents().first { $0.id == created.id }
        XCTAssertTrue(revoked?.isRevoked ?? false)
        try await admin.deleteAgent(created.id)
        let remaining = try await admin.listAgents()
        XCTAssertEqual(remaining.count, 6)   // the seed's six agents
        let devices = try await admin.listDevices()
        try await admin.renameDevice(devices[0].id, name: "Hall")
        let renamed = try await admin.listDevices()
        XCTAssertEqual(renamed[0].name, "Hall")
        let settings = try await admin.updateSettings(displayName: "Doc", timezone: "Europe/Paris", assistantProvider: .grok)
        XCTAssertEqual(settings.displayName, "Doc")
        XCTAssertEqual(settings.assistantProvider, .grok)
        do {
            _ = try await admin.updateSettings(displayName: nil, timezone: "Mars/Olympus", assistantProvider: nil)
            XCTFail("an unknown timezone must be refused")
        } catch {}
    }
}
