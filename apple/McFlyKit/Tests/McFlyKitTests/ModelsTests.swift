import XCTest
@testable import McFlyKit

final class ModelsTests: XCTestCase {
    func testDemoDataMirrorsTheSeed() throws {
        let demo = try DemoData.load()
        XCTAssertEqual(demo.agents.map(\.slug), ["grok", "market-desk", "daily-pulse", "github-watcher", "ops-metrics", "calendar-sync"])
        XCTAssertEqual(demo.agents.map(\.kind), [.grok, .stocks, .news, .other, .other, .other])
        XCTAssertEqual(demo.agents[0].color, "#7A64E8")
        XCTAssertEqual(demo.agents[0].pushes7d, 48)

        XCTAssertEqual(demo.briefs.count, 3)
        let daily = try XCTUnwrap(demo.briefs.first { $0.externalId == "seed-daily" })
        XCTAssertEqual(daily.kind, .daily)
        XCTAssertTrue(daily.body.contains("- The Fed minutes"))
        XCTAssertNil(daily.expiresAt)

        XCTAssertEqual(demo.quotes.count, 12)
        let apple = try XCTUnwrap(demo.quotes.first { $0.id == 9 })
        XCTAssertEqual(apple.symbol, "AAPL")
        XCTAssertEqual(apple.price, 247.90, accuracy: 0.001)
        XCTAssertEqual(apple.changePct, 1.13)
        XCTAssertEqual(apple.currency, "USD")
        XCTAssertEqual(apple.note, "Services beat; iPhone 18 demand steady.")

        XCTAssertEqual(demo.symbols.map(\.symbol), ["SPY", "AAPL", "NVDA", "TSLA"])
        XCTAssertEqual(demo.devices.count, 2)
        XCTAssertEqual(demo.settings.displayName, "McFly")
        XCTAssertEqual(demo.settings.timezone, "America/Chicago")
        XCTAssertEqual(demo.settings.newsKeepReports, 14)
    }

    func testNewsReportEmbedsAndOrdersItems() throws {
        let demo = try DemoData.load()
        let report = try XCTUnwrap(demo.reports.first { $0.slug == "2026-10-14" })
        XCTAssertEqual(report.reportDate, "2026-10-14")
        XCTAssertEqual(report.displayDate, "Oct 14, 2026")
        XCTAssertEqual(report.items.count, 6)
        XCTAssertEqual(report.hero?.itemKey, "gemini")
        XCTAssertEqual(report.hero?.headline, "Google launches Gemini 4 Argon")
        XCTAssertEqual(report.sections.map(\.name), ["Social", "Paid Ads", "AI Tech"])
        XCTAssertEqual(report.sections[1].items.map(\.itemKey), ["pmax", "meta"])
        XCTAssertEqual(report.headlines.count, 5)
        XCTAssertFalse(report.headlines.contains { $0.itemKey == "gemini" })
        let meta = try XCTUnwrap(report.items.first { $0.itemKey == "meta" })
        XCTAssertEqual(meta.source, "facebook.com")
        XCTAssertEqual(meta.link?.host, "www.facebook.com")
    }

    func testReportWithoutEmbedStillDecodes() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000c0009","agent_id":"00000000-0000-0000-0000-00000000a003","slug":"2026-10-15",
         "report_date":"2026-10-15","display_date":null,"hero_item":null,"published_at":"2026-10-15T12:00:00.123456+00:00","created_at":"2026-10-15T12:00:00+00:00"}
        """
        let report = try JSONDecoder.mcfly.decode(NewsReport.self, from: Data(json.utf8))
        XCTAssertTrue(report.items.isEmpty)
        XCTAssertNil(report.hero)
        XCTAssertEqual(Int(report.publishedAt.timeIntervalSince1970), 1_792_065_600)
    }

    func testUnknownEnumValuesFallBack() throws {
        let agent = """
        {"id":"00000000-0000-0000-0000-00000000a009","name":"X","slug":"x","kind":"weather","color":"#000000","created_at":"2026-10-01T00:00:00Z"}
        """
        XCTAssertEqual(try JSONDecoder.mcfly.decode(Agent.self, from: Data(agent.utf8)).kind, .other)
        let brief = """
        {"id":"00000000-0000-0000-0000-0000000b0009","agent_id":"00000000-0000-0000-0000-00000000a009","title":"T","body":"","kind":"weekly",
         "published_at":"2026-10-01T00:00:00Z","created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-01T00:00:00Z"}
        """
        XCTAssertEqual(try JSONDecoder.mcfly.decode(Brief.self, from: Data(brief.utf8)).kind, .update)
    }

    func testPostgresTimestampsDecode() {
        XCTAssertNotNil(ISO8601Dates.parse("2026-10-14T20:11:07.123456+00:00"))
        XCTAssertNotNil(ISO8601Dates.parse("2026-10-14T20:11:07+00:00"))
        XCTAssertNotNil(ISO8601Dates.parse("2026-10-14T20:11:07Z"))
        XCTAssertNotNil(ISO8601Dates.parse("2026-10-14T20:11:07.5+00"))
        XCTAssertNil(ISO8601Dates.parse("yesterday"))
    }

    func testDeviceOnlineWindow() {
        let now = Date()
        let fresh = Device(id: UUID(), name: "Kitchen", lastSeenAt: now.addingTimeInterval(-14 * 60), createdAt: now)
        let stale = Device(id: UUID(), name: "Office", lastSeenAt: now.addingTimeInterval(-16 * 60), createdAt: now)
        let never = Device(id: UUID(), name: "New", lastSeenAt: nil, createdAt: now)
        XCTAssertTrue(fresh.isOnline(at: now))
        XCTAssertFalse(stale.isOnline(at: now))
        XCTAssertFalse(never.isOnline(at: now))
        XCTAssertEqual(Format.lastSeen(fresh, now: now), "Online")
        XCTAssertEqual(Format.lastSeen(stale, now: now), "Last seen 16 min ago")
        XCTAssertEqual(Format.lastSeen(never, now: now), "Never seen")
    }

    func testRebasingKeepsTheDemoFresh() throws {
        let now = Date()
        let demo = try DemoData.load().rebased(to: now, newestAge: 20 * 60)
        let newest = (demo.briefs.map(\.publishedAt) + demo.quotes.map(\.asOf) + demo.reports.map(\.publishedAt)).max()!
        XCTAssertEqual(now.timeIntervalSince(newest), 20 * 60, accuracy: 1)
        // The briefs keep their distance from the quotes (the seed's 20 minutes).
        XCTAssertEqual(newest.timeIntervalSince(demo.briefs.map(\.publishedAt).max()!), 20 * 60, accuracy: 1)
        // Relative order survives the shift.
        XCTAssertLessThan(demo.quotes.last!.asOf, demo.quotes.first!.asOf)
    }
}
