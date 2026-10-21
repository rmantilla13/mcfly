import XCTest
@testable import McFlyKit

final class ProductivityTests: XCTestCase {
    func testProjectsDecodeWithTheirUpdatesNewestFirst() throws {
        let demo = try DemoData.load()
        XCTAssertEqual(demo.projects.map(\.key), ["mcfly", "onyx", "homestead"])
        let mcfly = demo.projects[0]
        XCTAssertEqual(mcfly.kind, .code)
        XCTAssertEqual(mcfly.status, .active)
        XCTAssertEqual(mcfly.progress, 62)
        XCTAssertEqual(mcfly.nextStep, "Ship the dashboards screen")
        XCTAssertEqual(mcfly.url?.host, "github.com")
        // Whatever order the file lists them in, the decoder puts the newest first.
        XCTAssertEqual(mcfly.updates.count, 2)
        XCTAssertEqual(mcfly.updates.map(\.happenedAt), mcfly.updates.map(\.happenedAt).sorted(by: >))
        XCTAssertEqual(mcfly.lastUpdate?.kind, .ci)
        XCTAssertEqual(mcfly.updates.first { $0.kind == .pr }?.link?.host, "github.com")
        let onyx = demo.projects[1]
        XCTAssertEqual(onyx.status, .blocked)
        XCTAssertEqual(onyx.updates.first?.kind, .alert)
        XCTAssertTrue(demo.projects[2].updates.isEmpty)
        XCTAssertEqual(Project.Status.blocked.attention, 0)
        XCTAssertLessThan(Project.Status.active.attention, Project.Status.done.attention)
        // The seed's stages, and when each project reached its own.
        XCTAssertEqual(mcfly.stages, ["Plan", "Build", "Review", "Ship"])
        XCTAssertEqual(mcfly.stage, "Build")
        XCTAssertEqual(onyx.stageTrack?.headline, "Blocked in App Review")
        XCTAssertEqual(demo.projects[2].stageTrack?.headline, "Paused in Launch")
        let since = try XCTUnwrap(onyx.stageSince)
        // Rebased, the demo keeps it five days before the newest push.
        let now = Date()
        let rebased = demo.rebased(to: now)
        XCTAssertEqual(rebased.projects[1].timeInStage(now: now), "5 days")
        XCTAssertEqual(try XCTUnwrap(rebased.projects[1].stageSince).timeIntervalSince(rebased.projects[1].updatedAt),
                       since.timeIntervalSince(onyx.updatedAt), accuracy: 0.001)
    }

    func testProjectRowWithoutEmbedAndUnknownEnums() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-00000000f009","agent_id":"00000000-0000-0000-0000-00000000a004","key":"x","name":"X",
         "kind":"research","status":"shipped","created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-01T00:00:00Z"}
        """
        let project = try JSONDecoder.mcfly.decode(Project.self, from: Data(json.utf8))
        XCTAssertEqual(project.kind, .other)
        XCTAssertEqual(project.status, .active)
        XCTAssertEqual(project.summary, "")
        XCTAssertEqual(project.sortOrder, 1000)
        XCTAssertTrue(project.updates.isEmpty)
        // A database from before stages: none, so no track.
        XCTAssertEqual(project.stages, [])
        XCTAssertNil(project.stage)
        XCTAssertNil(project.stageSince)
        XCTAssertNil(project.stageTrack)
        // Postgres writes microseconds; a null stage list reads as none too.
        let staged = """
        {"id":"00000000-0000-0000-0000-00000000f00a","agent_id":"00000000-0000-0000-0000-00000000a004","key":"y","name":"Y",
         "status":"active","stages":["Plan","Build"],"stage":"Build","stage_since":"2026-10-18T14:03:11.123456+00:00",
         "created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-01T00:00:00Z"}
        """
        let y = try JSONDecoder.mcfly.decode(Project.self, from: Data(staged.utf8))
        XCTAssertEqual(y.stageTrack?.position, "2 of 2")
        XCTAssertNotNil(y.stageSince)
        let unset = """
        {"id":"00000000-0000-0000-0000-00000000f00b","agent_id":"00000000-0000-0000-0000-00000000a004","key":"z","name":"Z",
         "stages":null,"stage":null,"stage_since":null,"created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-01T00:00:00Z"}
        """
        XCTAssertEqual(try JSONDecoder.mcfly.decode(Project.self, from: Data(unset.utf8)).stages, [])
        // And it round-trips, as the feed's cache writes it.
        let again = try JSONDecoder.mcfly.decode(Project.self, from: JSONEncoder.mcfly.encode(y))
        XCTAssertEqual(again.stages, y.stages)
        XCTAssertEqual(again.stage, "Build")
        let update = """
        {"id":9,"kind":"release","text":"v2","happened_at":"2026-10-01T00:00:00Z"}
        """
        XCTAssertEqual(try JSONDecoder.mcfly.decode(ProjectUpdate.self, from: Data(update.utf8)).kind, .note)
    }

    func testMetricsGroupLikeQuotes() throws {
        let demo = try DemoData.load()
        XCTAssertEqual(demo.metrics.count, 8)
        let series = MetricSeries.group(demo.metrics, settings: demo.metricSettings)
        // The console's order: visible settings by sort_order, then key.
        let expectedOrder = demo.metricSettings.filter { !$0.hidden }.sorted { ($0.sortOrder, $0.key) < ($1.sortOrder, $1.key) }.map(\.key)
        XCTAssertEqual(series.map(\.key), expectedOrder)
        XCTAssertEqual(Set(series.map(\.key)), ["sales.today", "orders.open", "site.uptime", "api.p95", "steps"])
        let sales = try XCTUnwrap(series.first { $0.key == "sales.today" })
        XCTAssertEqual(sales.label, "Sales today")
        XCTAssertEqual(sales.group, "Store")
        XCTAssertEqual(sales.history.map(\.asOf), sales.history.map(\.asOf).sorted(by: >))
        XCTAssertEqual(sales.values, [3800, 4280])
        XCTAssertEqual(sales.latest.unit, "USD")
        XCTAssertEqual(sales.latest.deltaPct, 12.5)
        XCTAssertEqual(series.first { $0.key == "api.p95" }?.latest.note, "After the cache change.")
        // Groups follow the first series of each, so they come out in the console's order too.
        let groups = MetricSeries.grouped(series)
        var seen: [String?] = []
        for s in series where !seen.contains(s.group) { seen.append(s.group) }
        XCTAssertEqual(groups.map(\.name), seen)
        XCTAssertEqual(groups.first { $0.name == "Store" }?.series.map(\.key).sorted(), ["orders.open", "sales.today"])
    }

    func testHiddenMetricsLeaveAndUnknownOnesSortLastUnderOther() throws {
        let demo = try DemoData.load()
        var settings = demo.metricSettings
        settings[0].hidden = true
        let stray = Metric(id: 99, agentId: demo.agents[0].id, key: "cpu", value: 0.5, asOf: .now, createdAt: .now)
        let series = MetricSeries.group(demo.metrics + [stray], settings: settings)
        XCTAssertFalse(series.contains { $0.key == "sales.today" })
        XCTAssertEqual(series.last?.key, "cpu")
        XCTAssertEqual(series.last?.label, "cpu")
        XCTAssertNil(MetricSeries.grouped(series).last?.name)
    }

    func testDashboardWidgetsDecodeByType() throws {
        let demo = try DemoData.load()
        XCTAssertEqual(demo.dashboards.map(\.key), ["ops", "launch"])
        let ops = demo.dashboards[0]
        XCTAssertEqual(ops.subtitle, "Production, last 24 h")
        XCTAssertEqual(ops.widgets.map(\.typeName), ["status", "status", "metric", "metric", "progress", "chart", "list", "text"])
        XCTAssertEqual(ops.widgets[0], .status(label: "API", state: .ok, detail: "All checks passing"))
        XCTAssertEqual(ops.widgets[1], .status(label: "Workers", state: .warn, detail: "1 of 4 behind"))
        // An empty unit is no unit.
        XCTAssertEqual(ops.widgets[2], .metric(label: "Requests", value: 1_240_000, unit: nil, delta: nil, deltaPct: 4.2))
        XCTAssertEqual(ops.widgets[3], .metric(label: "Errors", value: 0.12, unit: "%", delta: nil, deltaPct: -30))
        XCTAssertEqual(ops.widgets[4], .progress(label: "Storage", value: 68, max: 100, unit: "%"))
        XCTAssertEqual(ops.widgets[5], .chart(label: "Requests per hour", points: [40, 42, 38, 51, 60, 58, 64, 70, 66, 72, 75, 71], unit: "k"))
        XCTAssertEqual(ops.widgets[6], .list(title: "On call", items: ["Ricky (primary)", "Pager: quiet since Mon"]))
        XCTAssertEqual(ops.widgets[7], .text(title: "Note", body: "Deploy window tonight 9–10 PM CT."))
        let launch = demo.dashboards[1]
        XCTAssertEqual(launch.widgets[0], .progress(label: "Checklist", value: 14, max: 20, unit: nil))
        XCTAssertEqual(launch.widgets[2], .metric(label: "Waitlist", value: 812, unit: nil, delta: 46, deltaPct: nil))
    }

    func testUnknownOrBrokenWidgetsDontSinkTheDashboard() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-00000000d109","agent_id":"00000000-0000-0000-0000-00000000a005","key":"k","title":"T",
         "sort_order":0,"hidden":false,"updated_at":"2026-10-14T19:00:00Z",
         "widgets":[{"type":"gauge","label":"Temp","value":70},{"type":"metric","label":"No value"},
                    {"type":"status","label":"Queue","state":"meltdown"},{"type":"metric","label":"Text number","value":"1,234"},
                    {"type":"text","body":"ok"}]}
        """
        let dashboard = try JSONDecoder.mcfly.decode(Dashboard.self, from: Data(json.utf8))
        XCTAssertEqual(dashboard.widgets.count, 5)
        XCTAssertEqual(dashboard.widgets[0], .unknown(type: "gauge"))
        // A known type with a missing or odd value still shows, as best it can.
        XCTAssertEqual(dashboard.widgets[1], .metric(label: "No value", value: 0, unit: nil, delta: nil, deltaPct: nil))
        XCTAssertEqual(dashboard.widgets[2], .status(label: "Queue", state: .unknown, detail: nil))
        XCTAssertEqual(dashboard.widgets[3], .metric(label: "Text number", value: 1234, unit: nil, delta: nil, deltaPct: nil))
        XCTAssertEqual(dashboard.widgets[4], .text(title: nil, body: "ok"))
    }

    func testEventsDecodeAndFallOnDays() throws {
        let demo = try DemoData.load()
        XCTAssertEqual(demo.events.count, 6)
        let launch = try XCTUnwrap(demo.events.first { $0.externalId == "ev-6" })
        XCTAssertTrue(launch.allDay)
        XCTAssertEqual(launch.calendar, "Home")
        XCTAssertEqual(launch.color, "#F6B94A")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let oct20 = try XCTUnwrap(ISO8601Dates.parse("2026-10-20T12:00:00Z"))
        let oct19 = try XCTUnwrap(ISO8601Dates.parse("2026-10-19T12:00:00Z"))
        XCTAssertTrue(launch.occurs(on: oct20, calendar: utc))
        XCTAssertFalse(launch.occurs(on: oct19, calendar: utc))
        let review = try XCTUnwrap(demo.events.first { $0.externalId == "ev-2" })
        XCTAssertEqual(review.location, "Zoom")
        XCTAssertEqual(review.link?.host, "zoom.us")
        XCTAssertTrue(review.isOngoing(at: review.startsAt.addingTimeInterval(60)))
        XCTAssertFalse(review.isOngoing(at: review.endsAt))
    }

    func testSettingsDecodeWithAndWithoutTheNewColumns() throws {
        let old = """
        {"display_name":"McFly","timezone":"America/Chicago","briefs_keep_days":30,"quotes_keep_days":90,"news_keep_reports":14}
        """
        let legacy = try JSONDecoder.mcfly.decode(PlatformSettings.self, from: Data(old.utf8))
        XCTAssertEqual(legacy.assistantProvider, .claude)
        XCTAssertEqual(legacy.metricsKeepDays, 90)
        XCTAssertEqual(legacy.eventsKeepDays, 60)
        let new = """
        {"display_name":"Doc","timezone":"UTC","briefs_keep_days":1,"quotes_keep_days":2,"news_keep_reports":3,
         "assistant_provider":"grok","metrics_keep_days":4,"events_keep_days":5}
        """
        let current = try JSONDecoder.mcfly.decode(PlatformSettings.self, from: Data(new.utf8))
        XCTAssertEqual(current.assistantProvider, .grok)
        XCTAssertEqual(current.metricsKeepDays, 4)
        XCTAssertEqual(current.eventsKeepDays, 5)
        let odd = Data("\"llama\"".utf8)
        XCTAssertEqual(try JSONDecoder.mcfly.decode(AssistantProvider.self, from: odd), .claude)
    }
}
