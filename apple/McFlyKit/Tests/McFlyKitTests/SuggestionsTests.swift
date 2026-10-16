import XCTest
@testable import McFlyKit

/// The Ask bar's questions: the cases of admin/tests/suggestions.test.mjs
/// and the display's `suggestionsFor` (tst_assistant.cpp), so the chips read
/// the same on every surface.
final class SuggestionsTests: XCTestCase {
    private static var chicago: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    private let calendar = SuggestionsTests.chicago

    /// 10 AM in Chicago on Oct 14, 2026.
    private let now = SuggestionsTests.iso("2026-10-14T15:00:00Z")
    private static func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private func minutes(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }

    private let grok = Agent(id: UUID(), name: "Grok", slug: "grok", kind: .grok, color: "#7A64E8", createdAt: .distantPast)

    private func project(_ name: String, _ status: Project.Status) -> Project {
        Project(id: UUID(), agentId: grok.id, key: name, name: name, status: status, createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func ticker(_ symbol: String, _ pct: Double, age: Double = 20) -> QuoteSeries {
        QuoteSeries(symbol: symbol, name: nil, history: [Quote(id: 1, agentId: grok.id, symbol: symbol, price: 100, changePct: pct,
                                                               asOf: minutes(-age), createdAt: minutes(-age))], sortOrder: 0)
    }

    private func event(_ title: String, in offset: Double, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: UUID(), agentId: grok.id, externalId: title, title: title, startsAt: minutes(offset),
                      endsAt: minutes(offset + (allDay ? 24 * 60 : 30)), allDay: allDay)
    }

    private func report(_ headline: String) -> NewsReport {
        let id = UUID()
        return NewsReport(id: id, agentId: grok.id, slug: "2026-10-14", reportDate: "2026-10-14", publishedAt: Self.iso("2026-10-14T12:00:00Z"),
                          items: [NewsItem(id: UUID(), reportId: id, sectionKey: "ai", sectionName: "AI", sectionOrder: 0, itemKey: "a",
                                           position: 0, headline: headline, takeaway: "", url: "https://example.com")])
    }

    private func brief(minutesAgo: Double) -> Brief {
        let at = minutes(-minutesAgo)
        return Brief(id: UUID(), agentId: grok.id, title: "Hourly check-in", body: "", kind: .hourly, publishedAt: at, createdAt: at, updatedAt: at)
    }

    private var aMetric: MetricSeries {
        MetricSeries(key: "steps", label: "Steps", group: nil,
                     history: [Metric(id: 1, agentId: grok.id, key: "steps", value: 6420, asOf: now, createdAt: now)], sortOrder: 0)
    }

    private func page() -> FeedSnapshot {
        FeedSnapshot(projects: [project("Onyx", .blocked)], metrics: [aMetric],
                     quotes: [ticker("SPY", 0.3), ticker("TSLA", -4.12), ticker("NVDA", 1.5)],
                     events: [event("All hands", in: 30, allDay: true), event("Standup", in: 40)],
                     briefs: [brief(minutesAgo: 20)], reports: [report("Google launches Gemini 4 Argon")], agents: [grok])
    }

    private func build(_ feed: FeedSnapshot, at moment: Date? = nil, skip: [String] = []) -> [String] {
        Suggestions.build(feed, now: moment ?? now, calendar: calendar, skip: skip)
    }

    func testFromThePageInOrderBlockedMoverNextMeetingThePulse() {
        XCTAssertEqual(build(page()), [
            "What's blocking Onyx?",
            "Why is TSLA down 4.1% today?",
            "What do I need for Standup?",
            "More on Google launches Gemini 4 Argon",
        ])
    }

    func testTheRestFromAFreshBriefThenQuestionsThatFitAnyDay() {
        var p = page()
        p.projects = []
        p.reports = []
        p.events = []
        XCTAssertEqual(build(p), ["Why is TSLA down 4.1% today?", "What did Grok just say?", "Summarize my day", "How are the markets doing?"])
        XCTAssertEqual(build(FeedSnapshot()), ["Summarize my day", "Anything I should know?"])
        XCTAssertEqual(build(FeedSnapshot(metrics: [aMetric], events: page().events)), [
            "What do I need for Standup?",
            "Summarize my day",
            "What's next on my calendar?",
            "How are my metrics looking?",
        ])
    }

    func testAQuestionTheSurfaceOffersItsOwnWayIsSkippedBeforeTheFourArePicked() {
        var p = page()
        p.projects = []
        p.reports = []
        p.events = []
        XCTAssertEqual(build(p, skip: [Suggestions.summarizeDay]), [
            "Why is TSLA down 4.1% today?",
            "What did Grok just say?",
            "How are the markets doing?",
            "How are my metrics looking?",
        ])
        XCTAssertEqual(build(FeedSnapshot(), skip: [Suggestions.summarizeDay]), ["Anything I should know?"])
    }

    func testOnlyRealMoversMeetingsInTheNextThreeHoursBriefsUnderThreeHours() {
        let calm = build(FeedSnapshot(quotes: [ticker("SPY", 0.9)]))
        XCTAssertFalse(calm.contains { $0.hasPrefix("Why is") }, "under 1% isn't asked about")
        XCTAssertTrue(build(FeedSnapshot(quotes: [ticker("SPY", 1)])).contains("Why is SPY up 1.0% today?"), "1% is")
        let stale = build(FeedSnapshot(quotes: [ticker("NVDA", 3, age: 40 * 60)]))
        XCTAssertFalse(stale.contains { $0.hasPrefix("Why is") })
        var late = page()
        late.events = [event("Dinner", in: 4 * 60)]
        XCTAssertFalse(build(late).contains { $0.contains("Dinner") })
        var soonEnough = page()
        soonEnough.events = [event("Dinner", in: 3 * 60)]
        XCTAssertTrue(build(soonEnough).contains("What do I need for Dinner?"), "three hours exactly")
        var past = page()
        past.events = [event("Standup", in: -5)]
        XCTAssertFalse(build(past).contains { $0.contains("Standup") })
        let old = build(FeedSnapshot(briefs: [brief(minutesAgo: 4 * 60)], agents: [grok]))
        XCTAssertFalse(old.contains { $0.contains("Grok") })
    }

    func testThePagesClockNotTheMachines() {
        let later = minutes(3 * 60)
        XCTAssertFalse(build(page(), at: later).contains { $0.contains("Standup") }, "Standup is over by then")
        XCTAssertFalse(build(page(), at: later).contains { $0.contains("Grok") }, "and the brief is over 3 hours old")
    }

    func testLongNamesAreCutAtAWordToFitWithAnEllipsis() {
        let p = FeedSnapshot(projects: [project("The very long project name that keeps going", .blocked)],
                             events: [event("Pulse review with the whole team and the agency", in: 60)],
                             reports: [report("Google adds channel-level reporting to Performance Max")])
        let out = build(p)
        XCTAssertEqual(Array(out.prefix(3)), [
            "What's blocking The very long project…?",
            "What do I need for Pulse review with the…?",
            "More on Google adds channel-level…",
        ])
        for s in out { XCTAssertLessThanOrEqual(s.count, Suggestions.maxCharacters, "\(s) (\(s.count))") }
    }

    func testFitAtTheBoundaries() {
        // Exactly 42 fits whole; one more is cut.
        let exact = String(repeating: "a", count: 42 - "More on ".count)
        XCTAssertEqual(Suggestions.fit("More on ", exact, ""), "More on " + exact)
        XCTAssertEqual(Suggestions.fit("More on ", exact, "")?.count, 42)
        let over = Suggestions.fit("More on ", exact + "b", "")
        XCTAssertEqual(over?.count, 42)
        XCTAssertEqual(over?.hasSuffix("…"), true)
        // A cut that lands between two words keeps the word before it.
        XCTAssertEqual(Suggestions.fit("What do I need for ", "Pulse review with the team", "?"), "What do I need for Pulse review with the…?")
        XCTAssertEqual(Suggestions.fit("What do I need for ", "Pulse review with the team", "?")?.count, 42)
        // Trailing punctuation goes before the ellipsis.
        XCTAssertEqual(Suggestions.fit("More on ", "Markets, rates, the dollar, everything else", ""), "More on Markets, rates, the dollar…")
        // Whitespace is one space; nothing is nothing; too little room is nil.
        XCTAssertEqual(Suggestions.fit("More on ", "  a \n b ", ""), "More on a b")
        XCTAssertNil(Suggestions.fit("More on ", "   ", ""))
        XCTAssertNil(Suggestions.fit(String(repeating: "x", count: 35), "a long value", ""))
    }

    func testAMoverQuestionDropsTodayToFit() {
        XCTAssertEqual(Suggestions.moverQuestion(symbol: "NVDA", pct: 3.44), "Why is NVDA up 3.4% today?")
        let long = String(repeating: "X", count: 20)
        XCTAssertEqual(Suggestions.moverQuestion(symbol: long, pct: -12.3), "Why is \(long) down 12.3%?")
        XCTAssertNil(Suggestions.moverQuestion(symbol: String(repeating: "X", count: 30), pct: 1))
    }

    func testNeverMoreThanFourNeverTwiceTheSameNeverTooLong() {
        var p = page()
        p.briefs = [brief(minutesAgo: 0)]
        let out = build(p)
        XCTAssertEqual(out.count, Suggestions.maxSuggestions)
        XCTAssertEqual(Set(out).count, out.count)
        XCTAssertEqual(Suggestions.firstFour(["a", "a", nil, "", String(repeating: "x", count: 43), "b", "c", "d", "e"]), ["a", "b", "c", "d"])
    }

    // MARK: Each screen's own

    func testEachScreenLeadsWithItsOwnQuestion() {
        let p = page()
        func own(_ screen: SuggestionScreen, _ feed: FeedSnapshot? = nil) -> String? {
            Suggestions.suggestion(for: screen, in: feed ?? p, now: now, calendar: calendar)
        }
        XCTAssertEqual(own(.home), "Summarize my day")
        XCTAssertEqual(own(.briefs), "What did Grok just say?")
        XCTAssertEqual(own(.markets), "Why is TSLA down 4.1% today?")
        XCTAssertEqual(own(.news), "More on Google launches Gemini 4 Argon")
        XCTAssertEqual(own(.projects), "What's blocking Onyx?")
        XCTAssertEqual(own(.calendar), "Prep me for Standup", "the next timed one, however far")
        XCTAssertEqual(own(.metrics), "How are my metrics looking?", "nothing unusual: the general question")
        XCTAssertNil(own(.dashboards), "no boards, nothing to ask")

        // Without the feed's own subject, the general one; with no feed at all, none.
        var quiet = p
        quiet.briefs = [brief(minutesAgo: 4 * 60)]
        quiet.quotes = [ticker("SPY", 0.3)]
        quiet.reports = [NewsReport(id: UUID(), agentId: grok.id, slug: "x", reportDate: "2026-10-13", publishedAt: minutes(-24 * 60),
                                    items: report("Yesterday's").items)]
        quiet.projects = [project("Homestead", .paused), project("McFly", .active)]
        quiet.events = []
        XCTAssertEqual(own(.briefs, quiet), "What's the latest brief?")
        XCTAssertEqual(own(.markets, quiet), "How are the markets doing?")
        XCTAssertEqual(own(.news, quiet), "What's in the news today?")
        XCTAssertEqual(own(.projects, quiet), "What's next for McFly?")
        XCTAssertEqual(own(.calendar, quiet), "What's next on my calendar?")
        quiet.projects = [project("Homestead", .paused)]
        XCTAssertEqual(own(.projects, quiet), "How are my projects going?")
        let empty = FeedSnapshot()
        for screen in [SuggestionScreen.briefs, .markets, .metrics, .news, .projects, .dashboards] {
            XCTAssertNil(own(screen, empty), screen.rawValue)
        }
        XCTAssertEqual(own(.calendar, empty), "What's next on my calendar?")
    }

    func testTheBlockedProjectLeadsProjectsWhereverItSorts() {
        let p = FeedSnapshot(projects: [project("McFly", .active), project("Onyx", .blocked)])
        XCTAssertEqual(Suggestions.suggestion(for: .projects, in: p, now: now, calendar: calendar), "What's blocking Onyx?")
    }

    func testMetricsAndBoardsAskAboutWhatStandsOut() {
        let ops = Dashboard(id: UUID(), agentId: grok.id, key: "ops", title: "Ops",
                            widgets: [.status(label: "Search", state: .error, detail: nil)])
        let fine = Dashboard(id: UUID(), agentId: grok.id, key: "launch", title: "Launch week",
                             widgets: [.status(label: "Web", state: .ok, detail: nil)])
        XCTAssertEqual(Suggestions.suggestion(for: .dashboards, in: FeedSnapshot(dashboards: [ops]), now: now, calendar: calendar),
                       "Why is Search down?")
        XCTAssertEqual(Suggestions.suggestion(for: .dashboards, in: FeedSnapshot(dashboards: [fine]), now: now, calendar: calendar),
                       "How's Launch week looking?")
        let jump = MetricSeries(key: "sales.today", label: "Sales today", group: nil,
                                history: [Metric(id: 1, agentId: grok.id, key: "sales.today", value: 4280, unit: "USD", deltaPct: 12.5,
                                                 asOf: now, createdAt: now)], sortOrder: 0)
        XCTAssertEqual(Suggestions.suggestion(for: .metrics, in: FeedSnapshot(metrics: [jump]), now: now, calendar: calendar),
                       "What's behind the rise in Sales today?")
        // An insight's question too long for a chip isn't offered.
        let long = Dashboard(id: UUID(), agentId: grok.id, key: "x", title: "X",
                             widgets: [.status(label: "The payments reconciliation worker", state: .error, detail: nil)])
        XCTAssertEqual(Suggestions.suggestion(for: .dashboards, in: FeedSnapshot(dashboards: [long]), now: now, calendar: calendar),
                       "How's X looking?")
    }

    func testAScreensRowIsItsOwnThenTheGeneralFour() {
        let row = Suggestions.build(for: .markets, page(), now: now, calendar: calendar)
        XCTAssertEqual(row, ["Why is TSLA down 4.1% today?", "What's blocking Onyx?", "What do I need for Standup?",
                             "More on Google launches Gemini 4 Argon"])
        XCTAssertEqual(Suggestions.build(for: .home, FeedSnapshot(), now: now, calendar: calendar), ["Summarize my day", "Anything I should know?"])
    }

    // MARK: The demo

    func testTheDemoAtTwentyPastThree() throws {
        let (_, feed) = try InsightsTests.demoSnapshot()
        let at = Self.iso("2026-10-14T20:20:00Z")
        let out = Suggestions.build(feed, now: at, calendar: calendar)
        XCTAssertEqual(out, [
            "What's blocking Onyx?",
            "Why is NVDA up 1.5% today?",
            "What do I need for Pulse review with the…?",
            "More on Google launches Gemini 4 Argon",
        ])
        XCTAssertEqual(out[2].count, 42, "cut to the cap exactly")
        func own(_ screen: SuggestionScreen) -> String? { Suggestions.suggestion(for: screen, in: feed, now: at, calendar: calendar) }
        XCTAssertEqual(own(.briefs), "What did Grok just say?")
        XCTAssertEqual(own(.markets), "Why is NVDA up 1.5% today?")
        XCTAssertEqual(own(.metrics), "What's behind the rise in Sales today?")
        XCTAssertEqual(own(.projects), "What's blocking Onyx?")
        XCTAssertEqual(own(.dashboards), "What's wrong with Workers?")
        XCTAssertEqual(own(.calendar), "Prep me for Pulse review with the team")
        for screen in SuggestionScreen.allCases {
            let row = Suggestions.build(for: screen, feed, now: at, calendar: calendar)
            XCTAssertLessThanOrEqual(row.count, Suggestions.maxSuggestions)
            for s in row { XCTAssertLessThanOrEqual(s.count, Suggestions.maxCharacters, s) }
        }
    }
}
