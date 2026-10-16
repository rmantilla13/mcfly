import XCTest
@testable import McFlyKit

/// What stands out: the cases of admin/tests/insights.test.mjs and the
/// display's highlight tests (tst_feedstore.cpp), so the phone ranks and
/// words them as the console and the wall display do.
final class InsightsTests: XCTestCase {
    private static var chicago: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    private let calendar = InsightsTests.chicago
    private let locale = Locale(identifier: "en_US")

    /// 10 AM in Chicago on Oct 14, 2026.
    private let now = InsightsTests.iso("2026-10-14T15:00:00Z")
    private static func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private func minutes(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }

    private let grok = Agent(id: UUID(), name: "Grok", slug: "grok", kind: .grok, color: "#7A64E8", createdAt: .distantPast)
    private let pulseAgent = Agent(id: UUID(), name: "Daily Pulse", slug: "pulse", kind: .news, color: "#E2725B", createdAt: .distantPast)
    private let github = Agent(id: UUID(), name: "GitHub", slug: "gh", kind: .other, color: "#5B7CF5", createdAt: .distantPast)
    private let calendarAgent = Agent(id: UUID(), name: "Calendar", slug: "cal", kind: .other, color: "#14C2C2", createdAt: .distantPast)
    private let onyxId = UUID()
    private let reportId = UUID()
    private let usualP95: [Double] = [240, 238, 243, 241, 239, 244, 240, 242, 237, 241, 240, 239]

    // MARK: Builders

    /// A metric's history, oldest first, an hour apart and ending now; the
    /// agent's delta and percentage on the newest row only.
    private func metric(_ key: String, _ label: String, unit: String?, _ points: [Double],
                        delta: Double? = nil, deltaPct: Double? = nil) -> MetricSeries {
        let rows = points.enumerated().map { i, value in
            let newest = i == points.count - 1
            return Metric(id: Int64(i), agentId: grok.id, key: key, label: label, value: value, unit: unit,
                          delta: newest ? delta : nil, deltaPct: newest ? deltaPct : nil,
                          asOf: now.addingTimeInterval(-3600 * Double(points.count - 1 - i)), createdAt: now)
        }
        return MetricSeries(key: key, label: label, group: nil, history: rows.reversed(), sortOrder: 0)
    }

    /// One quote with today's move, pushed `age` minutes ago.
    private func ticker(_ symbol: String, pct: Double, price: Double = 100, age: Double = 20) -> QuoteSeries {
        let quote = Quote(id: 1, agentId: grok.id, symbol: symbol, price: price, changePct: pct, asOf: minutes(-age), createdAt: minutes(-age))
        return QuoteSeries(symbol: symbol, name: nil, history: [quote], sortOrder: 0)
    }

    private func event(_ title: String, in offset: Double, length: Double = 15, location: String? = nil,
                       allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: UUID(), agentId: calendarAgent.id, externalId: title, title: title, location: location,
                      startsAt: minutes(offset), endsAt: minutes(offset + length), allDay: allDay, color: "#5B7CF5")
    }

    private func brief(_ title: String, _ body: String, _ kind: Brief.Kind = .hourly, minutesAgo: Double, agent: Agent? = nil) -> Brief {
        let at = minutes(-minutesAgo)
        return Brief(id: UUID(), agentId: (agent ?? grok).id, title: title, body: body, kind: kind, publishedAt: at,
                     createdAt: at, updatedAt: at)
    }

    private func report(_ headline: String, stories: Int, date: String = "2026-10-14") -> NewsReport {
        let items = (0..<stories).map { i in
            NewsItem(id: UUID(), reportId: reportId, sectionKey: "ai", sectionName: "AI", sectionOrder: 0, itemKey: "k\(i)",
                     position: i, headline: i == 0 ? headline : "Story \(i)", takeaway: "", url: "https://example.com/\(i)")
        }
        return NewsReport(id: reportId, agentId: pulseAgent.id, slug: date, reportDate: date, heroItem: "k0",
                          publishedAt: Self.iso("2026-10-14T12:00:00Z"), items: items)
    }

    private func onyx(color: String? = "#E2604A") -> Project {
        Project(id: onyxId, agentId: github.id, key: "onyx", name: "Onyx", status: .blocked, progress: 80,
                nextStep: "App Review answer", color: color, createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func everything() -> FeedSnapshot {
        FeedSnapshot(
            projects: [onyx()],
            metrics: [metric("api.p95", "API p95", unit: "ms", usualP95 + [212], deltaPct: -7.8),
                      metric("sales.today", "Sales today", unit: "USD", [3900, 3700, 4100, 3850, 4000, 3950, 3800, 4050, 3900, 4280],
                             deltaPct: 12.5)],
            quotes: [ticker("TSLA", pct: 4.1, price: 402.10), ticker("SPY", pct: 0.3, price: 668.42)],
            events: [event("Standup", in: 18, location: "Zoom"), event("Later", in: 180, length: 60)],
            briefs: [brief("Hourly check-in", "Quiet hour.", minutesAgo: 20)],
            reports: [report("Google launches Gemini 4 Argon", stories: 6)],
            agents: [grok, pulseAgent, github, calendarAgent])
    }

    private func build(_ feed: FeedSnapshot, at moment: Date? = nil) -> [Insight] {
        Insights.build(feed, now: moment ?? now, calendar: calendar, locale: locale)
    }

    // MARK: Ranking

    func testRankedBlockedMetricEventMoverBriefPulseAtMostFive() {
        let all = build(everything())
        XCTAssertEqual(all.count, Insights.maxInsights)
        XCTAssertEqual(all.map(\.kind), [.blocked, .metric, .event, .mover, .brief])
        var calmer = everything()
        calmer.events = []
        calmer.quotes = []
        XCTAssertEqual(build(calmer).map(\.kind), [.blocked, .metric, .brief, .pulse])
        XCTAssertEqual(build(FeedSnapshot()), [])
    }

    func testABoardsStatusComesRightAfterABlockedProject() throws {
        var feed = everything()
        feed.dashboards = [Dashboard(id: UUID(), agentId: grok.id, key: "ops", title: "Ops",
                                     widgets: [.status(label: "Search", state: .error, detail: nil)])]
        XCTAssertEqual(build(feed).map(\.kind), [.blocked, .status, .metric, .event, .mover])
    }

    func testEachCarriesAStableIdATargetAndAQuestion() throws {
        var feed = everything()
        feed.events = []
        XCTAssertEqual(build(feed).map(\.id), build(feed, at: minutes(1)).map(\.id))
        feed.metrics = []
        let by = Dictionary(build(feed).map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        let blocked = try XCTUnwrap(by[.blocked])
        XCTAssertEqual(blocked.id, "blocked:\(onyxId)")
        XCTAssertEqual(blocked.target, .project(onyxId))
        XCTAssertEqual(blocked.title, "Onyx is blocked")
        XCTAssertEqual(blocked.detail, "App Review answer")
        XCTAssertEqual(blocked.question, "What's blocking Onyx?")
        XCTAssertEqual(blocked.tone, .warn)
        XCTAssertEqual(blocked.colorHex, "#E2604A")
        XCTAssertEqual(by[.mover]?.question, "Why is TSLA up 4.1% today?")
        XCTAssertEqual(by[.mover]?.target, .symbol("TSLA"))
        XCTAssertEqual(by[.mover]?.id, "mover:TSLA")
        XCTAssertEqual(by[.brief]?.question, "What did Grok just say?")

        let pulse = try XCTUnwrap(build(FeedSnapshot(reports: [report("Google launches Gemini 4 Argon", stories: 6)],
                                                     agents: [pulseAgent])).first)
        XCTAssertEqual(pulse.id, "pulse:\(reportId)")
        XCTAssertEqual(pulse.target, .report(reportId))
        XCTAssertEqual(pulse.title, "Google launches Gemini 4 Argon")
        XCTAssertEqual(pulse.detail, "Daily Pulse · 6 stories")
        XCTAssertEqual(pulse.question, "Tell me more about “Google launches Gemini 4 Argon”")
        XCTAssertEqual(pulse.colorHex, "#E2725B")
        let one = build(FeedSnapshot(reports: [report("Solo", stories: 1)]))
        XCTAssertEqual(one.first?.detail, "Daily Pulse · 1 story", "an unknown source is the Daily Pulse")
        XCTAssertEqual(build(FeedSnapshot(reports: [report("Old", stories: 2, date: "2026-10-13")])), [], "only today's")
    }

    func testMoreThanOneBlockedProjectAndTheAgentsColourWhenTheProjectHasNone() throws {
        let second = Project(id: UUID(), agentId: github.id, key: "b", name: "Homestead", status: .blocked,
                             createdAt: .distantPast, updatedAt: .distantPast)
        let blocked = try XCTUnwrap(build(FeedSnapshot(projects: [onyx(color: nil), second], agents: [github])).first)
        XCTAssertEqual(blocked.title, "Onyx and 1 more are blocked")
        XCTAssertEqual(blocked.colorHex, "#5B7CF5")
        XCTAssertEqual(blocked.systemImage, "exclamationmark.octagon")
    }

    // MARK: Board statuses

    func testTheWorstStatusFirstWithHowManyMore() throws {
        let ops = UUID(), launch = UUID()
        let feed = FeedSnapshot(dashboards: [
            Dashboard(id: ops, agentId: grok.id, key: "ops", title: "Ops", widgets: [
                .status(label: "API", state: .warn, detail: "slow"),
                .status(label: "Search", state: .error, detail: "Index rebuilding since 3:10"),
                .status(label: "DB", state: .ok, detail: nil),
            ]),
            Dashboard(id: launch, agentId: grok.id, key: "launch", title: "Launch", widgets: [.status(label: "Web", state: .warn, detail: nil)]),
        ])
        let status = try XCTUnwrap(build(feed).first)
        XCTAssertEqual(status.kind, .status)
        XCTAssertEqual(status.id, "status:\(ops):Search")
        XCTAssertEqual(status.title, "Search is down")
        XCTAssertEqual(status.detail, "Index rebuilding since 3:10 · Ops · +2 more")
        XCTAssertEqual(status.question, "Why is Search down?")
        XCTAssertEqual(status.tone, .bad)
        XCTAssertEqual(status.colorHex, Insights.badHex)
        XCTAssertEqual(status.target, .dashboard(ops))

        // Only warnings: the first in board order.
        let warn = FeedSnapshot(dashboards: [
            Dashboard(id: ops, agentId: grok.id, key: "ops", title: "Ops", widgets: [.status(label: "API", state: .warn, detail: "slow")]),
        ])
        let warning = try XCTUnwrap(build(warn).first)
        XCTAssertEqual(warning.title, "API has a warning")
        XCTAssertEqual(warning.detail, "slow · Ops")
        XCTAssertEqual(warning.question, "What's wrong with API?")
        XCTAssertEqual(warning.tone, .warn)
        XCTAssertEqual(warning.colorHex, Insights.warnHex)

        let fine = FeedSnapshot(dashboards: [
            Dashboard(id: ops, agentId: grok.id, key: "ops", title: "Ops",
                      widgets: [.status(label: "API", state: .ok, detail: nil), .status(label: "?", state: .unknown, detail: nil)]),
        ])
        XCTAssertEqual(build(fine), [])
    }

    // MARK: Metrics

    func testAMetricAnomalyByRobustZWithGoodNewsByDirection() throws {
        let m = try XCTUnwrap(build(FeedSnapshot(metrics: everything().metrics)).first)
        XCTAssertEqual(m.id, "metric:api.p95")
        XCTAssertEqual(m.target, .metric("api.p95"))
        XCTAssertEqual(m.title, "API p95 is unusually low")
        XCTAssertEqual(m.tone, .good, "latency falling is good news")
        XCTAssertEqual(m.colorHex, Insights.goodHex)
        XCTAssertEqual(m.detail, "212 ms, against a usual 240 ms")
        XCTAssertEqual(m.question, "What's behind the drop in API p95?")
        // Sales +12.5% sits inside its usual spread: long history wins over the jump.
        XCTAssertEqual(build(FeedSnapshot(metrics: [everything().metrics[1]])), [])
        // Uptime that should rise, unusually low: bad news.
        let uptime = metric("site.uptime", "Uptime", unit: "%", [99.9, 99.95, 99.9, 99.92, 99.94, 99.9, 99.93, 99.91, 99.92, 97], deltaPct: -2)
        XCTAssertEqual(build(FeedSnapshot(metrics: [uptime])).first?.tone, .bad)
    }

    func testAMetricJumpCountsWhenTheHistoryIsTooShortOrFlatForAZ() throws {
        let short = try XCTUnwrap(build(FeedSnapshot(metrics: [metric("sales.today", "Sales today", unit: "USD", [3804, 4280], deltaPct: 12.5)])).first)
        XCTAssertEqual(short.title, "Sales today is up 12.5%")
        XCTAssertEqual(short.tone, .good)
        XCTAssertEqual(short.detail, Format.metric(4280, unit: "USD"))
        let flat = try XCTUnwrap(build(FeedSnapshot(metrics: [metric("queue.depth", "Queue", unit: nil, [10, 10, 10, 10, 10, 10, 10, 10, 10, 14], deltaPct: 40)])).first)
        XCTAssertEqual(flat.title, "Queue is up 40.0%")
        XCTAssertEqual(flat.tone, .bad, "a growing queue is bad news")
        // Only the agent's own percentage counts, not one worked out from the values.
        XCTAssertEqual(build(FeedSnapshot(metrics: [metric("sales.today", "Sales today", unit: "USD", [3000, 4280], delta: 1280)])), [])
        // Under 10% is no jump.
        XCTAssertEqual(build(FeedSnapshot(metrics: [metric("steps", "Steps", unit: nil, [7010, 6420], deltaPct: -8)])), [])
    }

    func testTheStrongestTwoMetricsFirst() {
        // The display's case: a latency spike (z ≈ 54) outranks a 15% jump; a
        // varied series whose 15% is within its usual isn't news.
        let feed = FeedSnapshot(metrics: [
            metric("signups", "Signups", unit: nil, [10, 30, 12, 28, 15, 25, 11, 29, 14, 24], deltaPct: 15),
            metric("orders.open", "Open orders", unit: nil, [20, 20, 20, 20, 20, 20, 20, 20, 20, 23], deltaPct: 15),
            metric("api.latency", "API latency", unit: "ms", [100, 102, 99, 101, 100, 98, 103, 100, 101, 180]),
        ])
        let metrics = build(feed)
        XCTAssertEqual(metrics.map(\.title), ["API latency is unusually high", "Open orders is up 15.0%"])
        XCTAssertEqual(metrics[0].detail, "180 ms, against a usual 100 ms")
        XCTAssertEqual(metrics[0].tone, .bad)
        XCTAssertEqual(metrics[0].question, "What's behind the rise in API latency?")
        XCTAssertEqual(metrics[1].detail, "23")
        XCTAssertEqual(metrics[1].tone, .good)
    }

    func testAMetricsTrendGoodNewsAndUsual() throws {
        let latency = metric("api.latency", "API latency", unit: "ms", [100, 102, 99, 101, 100, 98, 103, 100, 101, 180]).trend
        XCTAssertEqual(latency.goodDirection, .down)
        XCTAssertEqual(latency.trend, .up)
        XCTAssertFalse(latency.good)
        XCTAssertTrue(latency.anomaly)
        XCTAssertTrue(latency.unusual)
        XCTAssertEqual(latency.anomalyTrend, .up)
        XCTAssertEqual(latency.usual, 100)
        XCTAssertGreaterThan(try XCTUnwrap(latency.z), 3)

        // The agent's delta leads, then its percentage, then the step from the value before.
        let p95 = metric("api.p95", "API p95", unit: "ms", [230, 212], delta: -18).trend
        XCTAssertEqual(p95.trend, .down)
        XCTAssertTrue(p95.good)
        XCTAssertFalse(p95.anomaly)
        XCTAssertNil(p95.z)
        XCTAssertEqual(p95.usual, 230)
        let steps = metric("steps", "Steps", unit: nil, [7010, 6420], deltaPct: -8).trend
        XCTAssertEqual(steps.trend, .down)
        XCTAssertFalse(steps.good)
        let derived = metric("sales.today", "Sales today", unit: "USD", [3800, 4280]).trend
        XCTAssertEqual(derived.move, 480)
        XCTAssertTrue(derived.good)
        let alone = metric("site.uptime", "Uptime", unit: "%", [99.98]).trend
        XCTAssertEqual(alone.trend, .flat)
        XCTAssertTrue(alone.good, "no move is no bad news")
        XCTAssertNil(alone.usual)
    }

    func testADashboardMetricKnowsGoodNewsByItsLabel() throws {
        let errors = try XCTUnwrap(DashboardWidget.metric(label: "Errors", value: 0.12, unit: "%", delta: nil, deltaPct: -30).trend)
        XCTAssertEqual(errors.trend, .down)
        XCTAssertTrue(errors.good)
        XCTAssertFalse(errors.anomaly, "a widget has no history to be unusual against")
        let signups = try XCTUnwrap(DashboardWidget.metric(label: "Signups", value: 812, unit: nil, delta: 46, deltaPct: nil).trend)
        XCTAssertEqual(signups.trend, .up)
        XCTAssertTrue(signups.good)
        let latency = try XCTUnwrap(DashboardWidget.metric(label: "p95", value: 212, unit: "ms", delta: 12, deltaPct: nil).trend)
        XCTAssertFalse(latency.good)
        XCTAssertNil(DashboardWidget.text(title: nil, body: "x").trend)
    }

    // MARK: Movers

    private func mover(_ pct: Double, swing: Double? = nil, asOf: Date? = nil, symbol: String = "NVDA", price: String = "$191.25") -> Insight? {
        Insights.mover(symbol: symbol, price: price, move: QuoteMove(pct: pct, swing: swing, asOf: asOf, now: now))?.insight
    }

    func testBigMoversTwoPercentOrTwoAndAHalfTimesTheUsualSwing() throws {
        XCTAssertEqual(mover(2)?.title, "NVDA is up 2.0%")
        XCTAssertEqual(mover(-1.5, swing: 0.5, symbol: "SPY")?.title, "SPY is down 1.5%")
        XCTAssertNil(mover(0.8, swing: 0.2), "under 1% is never news")
        XCTAssertNil(mover(1.9, swing: 2))
        XCTAssertNil(mover(3, asOf: minutes(-40 * 60)), "Friday's move isn't today's")
        XCTAssertNotNil(mover(3, asOf: minutes(-35 * 60)))
        XCTAssertNil(mover(0))

        let detail = try XCTUnwrap(mover(3.4, swing: 1.6))
        XCTAssertEqual(detail.detail, "$191.25 · 2.1× its usual daily move")
        XCTAssertEqual(detail.tone, .good)
        XCTAssertEqual(detail.colorHex, Insights.goodHex)
        XCTAssertEqual(detail.question, "Why is NVDA up 3.4% today?")
        XCTAssertEqual(mover(-2.5, swing: 2)?.detail, "$191.25", "under 1.5× the usual says nothing more")
        XCTAssertEqual(mover(-2.5)?.tone, .bad)
        XCTAssertEqual(mover(-2.5)?.systemImage, "arrow.down.right")

        let two = build(FeedSnapshot(quotes: [ticker("A", pct: 2.1), ticker("B", pct: -6), ticker("C", pct: 3)]))
        XCTAssertEqual(two.map(\.title), ["B is down 6.0%", "C is up 3.0%"], "the two biggest")
    }

    func testAMoveAgainstTheUsualSwingFromTheQuotesOwnHistory() throws {
        // A calm stock (about 0.2% a day for a week) up 1.2% today: news.
        let closes: [Double] = [100, 100.2, 100, 100.2, 100, 100.2]
        var rows = closes.enumerated().map { day, price in
            Quote(id: Int64(day), agentId: grok.id, symbol: "SPY", price: price,
                  asOf: now.addingTimeInterval(-86_400 * Double(closes.count - day)), createdAt: now)
        }
        rows.append(Quote(id: 99, agentId: grok.id, symbol: "SPY", price: 101.4, changePct: 1.2, asOf: minutes(-20), createdAt: now))
        let series = try XCTUnwrap(QuoteSeries.group(rows, symbols: []).first)
        let move = series.dayMove(now: now, calendar: calendar)
        XCTAssertEqual(move.pct, 1.2)
        XCTAssertLessThan(try XCTUnwrap(move.swing), 0.3)
        XCTAssertGreaterThan(try XCTUnwrap(move.ratio), Insights.swingRatio)
        XCTAssertTrue(move.big)
        let insight = try XCTUnwrap(build(FeedSnapshot(quotes: [series])).first)
        XCTAssertEqual(insight.title, "SPY is up 1.2%")
        XCTAssertTrue(insight.detail.hasSuffix("× its usual daily move"), insight.detail)
    }

    func testTodaysMoveInPercentFromWhatTheAgentSent() throws {
        func series(_ quotes: [Quote]) throws -> QuoteSeries { try XCTUnwrap(QuoteSeries.group(quotes, symbols: []).first) }
        let pct = Quote(id: 2, agentId: grok.id, symbol: "X", price: 110, change: 10, changePct: 9.5, asOf: now, createdAt: now)
        XCTAssertEqual(try series([pct]).dayChangePct, 9.5, "the agent's own percentage")
        let change = Quote(id: 2, agentId: grok.id, symbol: "X", price: 110, change: 10, asOf: now, createdAt: now)
        XCTAssertEqual(try series([change]).dayChangePct, 10, "its change over the price before it")
        let before = Quote(id: 1, agentId: grok.id, symbol: "X", price: 200, asOf: minutes(-60), createdAt: now)
        let bare = Quote(id: 2, agentId: grok.id, symbol: "X", price: 210, asOf: now, createdAt: now)
        XCTAssertEqual(try series([before, bare]).dayChangePct, 5, "the step from the price before")
        XCTAssertNil(try series([bare]).dayChangePct)
    }

    // MARK: Events

    func testEventsWithinThirtyMinutesOrJustStartedNeverAllDay() throws {
        func one(_ e: CalendarEvent) -> Insight? { build(FeedSnapshot(events: [e])).first }
        XCTAssertEqual(one(event("Standup", in: 18))?.title, "Standup starts in 18 min")
        XCTAssertEqual(one(event("Standup", in: 18))?.tone, .neutral)
        XCTAssertEqual(one(event("Standup", in: 8))?.tone, .warn)
        XCTAssertEqual(one(event("Standup", in: 18, location: "Zoom"))?.detail, "10:18 am – 10:33 am · Zoom")
        XCTAssertEqual(one(event("Standup", in: 18))?.detail, "10:18 am – 10:33 am")
        XCTAssertEqual(one(event("Standup", in: 18))?.question, "What do I need for Standup?")
        XCTAssertEqual(one(event("Standup", in: 0.3))?.title, "Standup starts now")
        XCTAssertEqual(one(event("Standup", in: -3))?.title, "Standup has started")
        XCTAssertEqual(one(event("Standup", in: 30))?.title, "Standup starts in 30 min")
        XCTAssertNil(one(event("Standup", in: 45)))
        XCTAssertNil(one(event("Standup", in: -20)))
        XCTAssertNil(one(event("Holiday", in: 10, allDay: true)))
        // The soonest of two.
        let both = build(FeedSnapshot(events: [event("Later", in: 25), event("Sooner", in: 5)]))
        XCTAssertEqual(both.map(\.title), ["Sooner starts in 5 min"])
        let e = event("Standup", in: 18)
        XCTAssertEqual(one(e)?.id, "event:\(e.id)")
        XCTAssertEqual(one(e)?.target, .event(e.id))
        XCTAssertEqual(one(e)?.colorHex, "#5B7CF5")
    }

    // MARK: Briefs

    func testBriefsUnderAnHourOldAlertsWarn() throws {
        func b(_ minutesAgo: Double, _ kind: Brief.Kind = .hourly, agents: [Agent]? = nil) -> [Insight] {
            build(FeedSnapshot(briefs: [brief("Hourly check-in", "Quiet hour.\n\nMore.", kind, minutesAgo: minutesAgo)],
                               agents: agents ?? [grok]))
        }
        XCTAssertEqual(b(20).first?.title, "Grok posted “Hourly check-in”")
        XCTAssertEqual(b(20).first?.detail, "20 min ago · Quiet hour.")
        XCTAssertEqual(b(20).first?.colorHex, "#7A64E8")
        XCTAssertEqual(b(20).first?.tone, .neutral)
        XCTAssertEqual(b(20, .alert).first?.tone, .warn)
        XCTAssertEqual(b(0.2).first?.detail, "just now · Quiet hour.")
        XCTAssertEqual(b(90), [])
        let anonymous = try XCTUnwrap(b(20, agents: []).first)
        XCTAssertEqual(anonymous.title, "New brief: “Hourly check-in”")
        XCTAssertEqual(anonymous.question, "What's the latest brief?")
        // An expired brief isn't the latest.
        var expired = brief("Gone", "", minutesAgo: 5)
        expired.expiresAt = minutes(-1)
        XCTAssertEqual(build(FeedSnapshot(briefs: [expired, brief("Hourly check-in", "", minutesAgo: 30)], agents: [grok])).first?.title,
                       "Grok posted “Hourly check-in”")
    }

    func testLabels() {
        XCTAssertEqual(Insights.agoLabel(minutes(-0.4), now: now), "just now")
        XCTAssertEqual(Insights.agoLabel(minutes(-59), now: now), "59 min ago")
        XCTAssertEqual(Insights.agoLabel(minutes(-150), now: now), "3 h ago")
        XCTAssertEqual(Insights.agoLabel(minutes(-60 * 50), now: now), "2 d ago")
        XCTAssertEqual(Insights.clip("  a  b\nc ", 10), "a b c")
        XCTAssertEqual(Insights.clip("Hourly check-in with more", 10), "Hourly ch…")
        XCTAssertEqual(Insights.clip("Hourly check", 8), "Hourly…")
        XCTAssertEqual(Insights.pct1(-3.449), "3.4")
        XCTAssertEqual(Insights.pct1(12.5), "12.5")
    }

    // MARK: Which way is good news

    func testWhichWayIsGoodNews() {
        let down: [(String?, String)] = [
            ("ms", "api.p95"), (nil, "api.p95"), (nil, "checkout.latency"), ("%", "errors.rate"), (nil, "error_rate"),
            ("USD", "cloud.cost"), ("USD", "ads.spend"), (nil, "churn"), (nil, "queue.depth"), (nil, "jobs.backlog"),
            ("ms", "anything"), (nil, "crashes"),
            // The task's and the boards': labels stand in for keys.
            ("%", "Error rate"), (nil, "Latency"), (nil, "p95"), (nil, "P99 latency"), (" µs ", "render"), ("NS", "x"),
            (nil, "build.wait"), (nil, "deploy-fail-count"), (nil, "TTFB"),
            // Split on anything but a-z and 0-9, as the console's regex does.
            (nil, "caféerror"),
        ]
        let up: [(String?, String)] = [
            ("USD", "sales.today"), ("%", "site.uptime"), (nil, "steps"), (nil, "orders.open"), (nil, "signups"),
            ("%", "conversion"), (nil, "Sales"), ("%", "Uptime"), (nil, "p9"), (nil, "p1000"), (nil, "errand"),
            (nil, ""), ("s", "build.time"),
        ]
        for (unit, key) in down { XCTAssertEqual(goodDirection(unit: unit, key: key), .down, "\(key) (\(unit ?? "nil"))") }
        for (unit, key) in up { XCTAssertEqual(goodDirection(unit: unit, key: key), .up, "\(key) (\(unit ?? "nil"))") }
    }

    // MARK: Up next's ring

    func testCountdownFillsOverTheLastHourThenThroughTheEvent() {
        let later = Countdown(start: minutes(90), end: minutes(120), now: now)
        XCTAssertEqual(later.mode, .later)
        XCTAssertEqual(later.value, 0)
        XCTAssertEqual(later.minutes, 90)
        let soon = Countdown(start: minutes(15), end: minutes(45), now: now)
        XCTAssertEqual(soon.mode, .soon)
        XCTAssertEqual(soon.value, 0.75, accuracy: 1e-9)
        XCTAssertEqual(soon.minutes, 15)
        XCTAssertEqual(Countdown(start: minutes(60), end: minutes(90), now: now).mode, .soon)
        let on = Countdown(start: minutes(-15), end: minutes(45), now: now)
        XCTAssertEqual(on.mode, .now)
        XCTAssertEqual(on.value, 0.25, accuracy: 1e-9)
        XCTAssertEqual(on.minutes, 45)
        XCTAssertEqual(Countdown(start: minutes(-1), end: minutes(-1), now: now).value, 1)
        XCTAssertEqual(Countdown(start: minutes(-90), end: minutes(-30), now: now).minutes, 0)
    }

    // MARK: The demo

    /// The demo file as it is (Oct 14, 2026), shaped as FeedStore shapes it.
    static func demoSnapshot() throws -> (DemoData, FeedSnapshot) {
        let demo = try DemoData.load()
        let feed = FeedSnapshot(
            projects: demo.projects.sorted { ($0.status == .done ? 1 : 0, $0.sortOrder, $0.name) < ($1.status == .done ? 1 : 0, $1.sortOrder, $1.name) },
            dashboards: demo.dashboards.filter { !$0.hidden }.sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) },
            metrics: MetricSeries.group(demo.metrics, settings: demo.metricSettings),
            quotes: QuoteSeries.group(demo.quotes, symbols: demo.symbols),
            events: demo.events.sorted { ($0.startsAt, $0.title) < ($1.startsAt, $1.title) },
            briefs: demo.briefs.sorted { $0.publishedAt > $1.publishedAt },
            reports: demo.reports.sorted { ($0.reportDate, $0.publishedAt) > ($1.reportDate, $1.publishedAt) },
            agents: demo.agents)
        return (demo, feed)
    }

    func testTheDemoAtTwentyPastThree() throws {
        let (demo, feed) = try Self.demoSnapshot()
        // 3:20 pm in Chicago: the 3:30 Pulse review is ten minutes out, the
        // hourly check-in forty minutes old.
        let insights = Insights.build(feed, now: Self.iso("2026-10-14T20:20:00Z"), calendar: calendar, locale: locale)
        let onyx = try XCTUnwrap(demo.projects.first { $0.key == "onyx" })
        let ops = try XCTUnwrap(demo.dashboards.first { $0.key == "ops" })
        let review = try XCTUnwrap(demo.events.first { $0.title == "Pulse review with the team" })
        let hourly = try XCTUnwrap(demo.briefs.first { $0.title == "Hourly check-in" })
        XCTAssertEqual(insights.map(\.id), ["blocked:\(onyx.id)", "status:\(ops.id):Workers", "metric:sales.today",
                                            "event:\(review.id)", "brief:\(hourly.id)"])
        XCTAssertEqual(insights.map(\.title), ["Onyx is blocked", "Workers has a warning", "Sales today is up 12.5%",
                                               "Pulse review with the team starts in 10 min", "Grok posted “Hourly check-in”"])
        XCTAssertEqual(insights.map(\.tone), [.warn, .warn, .good, .warn, .neutral])
        XCTAssertEqual(insights[0].detail, "App Review answer on the FSKit entitlement")
        XCTAssertEqual(insights[0].colorHex, "#5B7CF5", "the GitHub watcher's colour: the project has none")
        XCTAssertEqual(insights[1].detail, "1 of 4 behind · Ops")
        XCTAssertEqual(insights[1].question, "What's wrong with Workers?")
        XCTAssertEqual(insights[2].question, "What's behind the rise in Sales today?")
        XCTAssertEqual(insights[3].detail, "3:30 pm – 4:00 pm · Zoom")
        XCTAssertTrue(insights[4].detail.hasPrefix("40 min ago · Quiet hour. NVDA is leading the Nasdaq"), insights[4].detail)
        // No mover: the biggest move is 1.5%, and three days of closes give no usual swing.
        XCTAssertFalse(insights.contains { $0.kind == .mover })
    }

    func testTheDemoLaterInTheAfternoon() throws {
        let (_, feed) = try Self.demoSnapshot()
        // 4:30 pm: the meeting started an hour ago, the brief is two hours old: the Pulse gets in.
        let insights = Insights.build(feed, now: Self.iso("2026-10-14T21:30:00Z"), calendar: calendar, locale: locale)
        XCTAssertEqual(insights.map(\.kind), [.blocked, .status, .metric, .pulse])
        XCTAssertEqual(insights.last?.title, "Google launches Gemini 4 Argon")
        XCTAssertEqual(insights.last?.detail, "Daily Pulse · 6 stories")
        XCTAssertEqual(insights.last?.colorHex, "#E2725B")
    }

    @MainActor
    func testTheStoreBuildsThemFromItsFeeds() async throws {
        // The demo rebased so its newest push was 20 minutes before 3:20 pm today.
        let afternoon = try XCTUnwrap(Calendar.current.date(bySettingHour: 15, minute: 20, second: 0, of: .now))
        let store = FeedStore(source: DemoFeedSource(data: try DemoData.load().rebased(to: afternoon)))
        await store.refresh()
        XCTAssertNil(store.errorMessage)
        let insights = store.insights(now: afternoon)
        XCTAssertEqual(insights.map(\.kind), [.blocked, .status, .metric, .event, .brief])
        XCTAssertEqual(insights.map(\.id), store.insights(now: afternoon).map(\.id), "the same feeds, the same ids")
        XCTAssertEqual(store.suggestions(now: afternoon), [
            "What's blocking Onyx?", "Why is NVDA up 1.5% today?", "What do I need for Pulse review with the…?",
            "More on Google launches Gemini 4 Argon",
        ])
        XCTAssertEqual(store.suggestion(for: .dashboards, now: afternoon), "What's wrong with Workers?")
        XCTAssertEqual(store.suggestions(for: .calendar, now: afternoon).first, "Prep me for Pulse review with the team")

        // Given the insights on show, the screens ask from those, not from a second build.
        for screen in SuggestionScreen.allCases {
            XCTAssertEqual(store.suggestion(for: screen, now: afternoon, insights: insights),
                           store.suggestion(for: screen, now: afternoon), "\(screen)")
            XCTAssertEqual(store.suggestions(for: screen, now: afternoon, insights: insights),
                           store.suggestions(for: screen, now: afternoon), "\(screen)")
        }
        XCTAssertEqual(store.suggestion(for: .metrics, now: afternoon, insights: insights),
                       "What's behind the rise in Sales today?")
        XCTAssertEqual(store.suggestion(for: .metrics, now: afternoon, insights: []), "How are my metrics looking?")
        XCTAssertEqual(store.suggestions(for: .dashboards, now: afternoon, insights: []).first, "How's Ops looking?")
    }
}
