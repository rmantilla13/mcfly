import XCTest
@testable import McFlyKit

/// The Home timeline: the cases of admin/tests/today.test.mjs, so the phone,
/// the web and the display agree on what today holds and where "now" is.
final class TimelineTests: XCTestCase {
    private static var chicago: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    private let calendar = TimelineTests.chicago
    private let locale = Locale(identifier: "en_US")

    /// 10 AM in Chicago on Oct 14, 2026.
    private let now = TimelineTests.iso("2026-10-14T15:00:00Z")

    private static func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    /// A Chicago hour on Oct 14 (hours past 24 run into the next days).
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        return base.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private let grok = Agent(id: UUID(), name: "Grok", slug: "grok", kind: .grok, color: "#7A64E8", createdAt: .distantPast)
    private let desk = Agent(id: UUID(), name: "Desk", slug: "desk", kind: .stocks, color: "#2E9E6A", createdAt: .distantPast)
    private let pulse = Agent(id: UUID(), name: "Daily Pulse", slug: "pulse", kind: .news, color: "#5B7CF5", createdAt: .distantPast)
    private let calendarAgent = Agent(id: UUID(), name: "Calendar", slug: "cal", kind: .other, color: "#14C2C2", createdAt: .distantPast)
    private let reportId = UUID()
    private let projectId = UUID()

    private func brief(_ title: String, _ body: String, _ kind: Brief.Kind, _ at: Date, agent: Agent) -> Brief {
        Brief(id: UUID(), agentId: agent.id, title: title, body: body, kind: kind, publishedAt: at, createdAt: at, updatedAt: at)
    }

    private func item(_ key: String, _ headline: String, section: Int, position: Int, image: String? = nil) -> NewsItem {
        NewsItem(id: UUID(), reportId: reportId, sectionKey: "s\(section)", sectionName: "S\(section)", sectionOrder: section,
                 itemKey: key, position: position, headline: headline, takeaway: "", url: "https://example.com/\(key)", imageURL: image)
    }

    private func event(_ title: String, _ calendarName: String, location: String? = nil, _ start: Date, _ end: Date,
                       allDay: Bool = false, color: String? = nil) -> CalendarEvent {
        CalendarEvent(id: UUID(), agentId: calendarAgent.id, calendar: calendarName, externalId: title, title: title,
                      location: location, startsAt: start, endsAt: end, allDay: allDay, color: color)
    }

    private var events: [CalendarEvent] {
        [event("Standup", "Work", location: "Zoom", at(9, 30), at(10, 15)),
         event("Pulse review", "Work", at(15, 30), at(16), color: "#E2725B"),
         event("Holiday", "Home", at(0), at(24), allDay: true),
         event("Tomorrow", "Work", at(33), at(34))]
    }

    private func build(at moment: Date? = nil) -> [TimelineItem] {
        let reports = [
            NewsReport(id: reportId, agentId: pulse.id, slug: "2026-10-14", reportDate: "2026-10-14", heroItem: "b",
                       publishedAt: Self.iso("2026-10-14T04:00:00Z"),
                       items: [item("a", "A", section: 0, position: 0), item("b", "B", section: 1, position: 0, image: "https://img/b.jpg"),
                               item("c", "C", section: 1, position: 1), item("d", "D", section: 2, position: 0)]),
            NewsReport(id: UUID(), agentId: pulse.id, slug: "2026-10-13", reportDate: "2026-10-13",
                       publishedAt: Self.iso("2026-10-13T12:00:00Z"), items: [item("x", "Old", section: 0, position: 0)]),
        ]
        let briefs = [
            brief("Morning briefing", "Three things.\n\nMore.", .daily, at(8, 30), agent: grok),
            brief("Yesterday", "", .hourly, Self.iso("2026-10-13T20:00:00Z"), agent: grok),
            brief("TSLA up", "", .alert, at(9, 5), agent: desk),
        ]
        let projects = [
            Project(id: projectId, agentId: grok.id, key: "mcfly", name: "McFly", status: .active, progress: 62,
                    createdAt: .distantPast, updatedAt: .distantPast,
                    updates: [ProjectUpdate(id: 3, kind: .ci, text: "CI green", happenedAt: at(9, 25)),
                              ProjectUpdate(id: 2, kind: .note, text: "Old", happenedAt: Self.iso("2026-10-12T12:00:00Z"))]),
        ]
        return Timeline.build(briefs: briefs, reports: reports, projects: projects, events: events,
                              agents: [grok, desk, pulse, calendarAgent], now: moment ?? now, calendar: calendar, locale: locale)
    }

    func testOnlyTodaysRowsAllDayFirstThenInTimeOrder() {
        let rows = build()
        XCTAssertEqual(rows.map(\.title), ["Holiday", "B", "Morning briefing", "TSLA up", "CI green", "Standup", "Pulse review"])
        XCTAssertEqual(rows[0].time, "All day")
        XCTAssertEqual(rows[0].ampm, "")
    }

    func testAnOvernightReportOpensTheDayWithItsHeroAndTheRest() throws {
        let news = try XCTUnwrap(build().first { $0.kind == .news })
        XCTAssertEqual(news.time, "12:00")
        XCTAssertEqual(news.ampm, "am")
        XCTAssertEqual(news.title, "B")
        XCTAssertEqual(news.detail, "A · C · 1 more")
        XCTAssertEqual(news.label, "Daily Pulse · 4 stories")
        XCTAssertEqual(news.target, .report(reportId))
        XCTAssertEqual(news.imageURL, URL(string: "https://img/b.jpg"))
    }

    func testRowsCarryTheirKindTimeAndTarget() throws {
        let rows = build()
        let alert = try XCTUnwrap(rows.first { $0.title == "TSLA up" })
        XCTAssertEqual(alert.kind, .alert)
        XCTAssertEqual("\(alert.time) \(alert.ampm)", "9:05 am")
        XCTAssertEqual(alert.label, "Desk · Alert")
        let ci = try XCTUnwrap(rows.first { $0.kind == .project })
        XCTAssertEqual(ci.detail, "62% done")
        XCTAssertEqual(ci.target, .project(projectId))
        XCTAssertEqual(ci.color, "#3DB37A")
        XCTAssertEqual(ci.systemImage, ProjectUpdate.Kind.ci.systemImage)
        let standup = try XCTUnwrap(rows.first { $0.title == "Standup" })
        XCTAssertEqual(standup.detail, "9:30 am – 10:15 am · Zoom")
        XCTAssertEqual(standup.color, "#14C2C2", "an event without a colour takes its agent's")
        XCTAssertEqual(rows.first { $0.title == "Morning briefing" }?.detail, "Three things.")
        XCTAssertEqual(rows.first { $0.title == "Morning briefing" }?.label, "Grok · Daily")
        XCTAssertEqual(rows.first { $0.title == "Holiday" }?.detail, "Home")
    }

    func testPastNowAndNextFollowTheClock() throws {
        let rows = build()
        let standup = try XCTUnwrap(rows.firstIndex { $0.title == "Standup" })
        let review = try XCTUnwrap(rows.firstIndex { $0.title == "Pulse review" })
        XCTAssertEqual(Timeline.state(at: standup, in: rows, now: now), .now)
        XCTAssertEqual(Timeline.state(at: review, in: rows, now: now), .next)
        XCTAssertEqual(Timeline.state(at: 1, in: rows, now: now), TimelineItem.RowState.none, "only events have a state")
        XCTAssertEqual(Timeline.nextIndex(rows, now: now), review)
        XCTAssertEqual(Timeline.focusIndex(rows, now: now), standup)
        XCTAssertEqual(Timeline.state(at: standup, in: rows, now: at(11)), .past)
        XCTAssertEqual(Timeline.focusIndex(rows, now: at(17)), rows.count - 1)
        XCTAssertNil(Timeline.focusIndex([], now: now))
    }

    func testUpNextSkipsAllDayAndFinishedEvents() {
        XCTAssertEqual(Timeline.upNext(events, now: now)?.title, "Standup")
        XCTAssertEqual(Timeline.upNext(events, now: at(11))?.title, "Pulse review")
        XCTAssertNil(Timeline.upNext(events, now: at(36)))
    }

    func testLabels() {
        XCTAssertEqual(Timeline.untilLabel(now.addingTimeInterval(18 * 60), now: now), "in 18 min")
        XCTAssertEqual(Timeline.untilLabel(now.addingTimeInterval(18 * 60), now: now, long: true), "in 18 minutes")
        XCTAssertEqual(Timeline.untilLabel(now.addingTimeInterval(125 * 60), now: now), "in 2 h 5 min")
        XCTAssertEqual(Timeline.untilLabel(now.addingTimeInterval(120 * 60), now: now), "in 2 h")
        XCTAssertEqual(Timeline.untilLabel(now.addingTimeInterval(-1), now: now), "now")
        XCTAssertEqual(Timeline.greeting(now: now, calendar: calendar), "Good morning")
        XCTAssertEqual(Timeline.greeting(now: now, calendar: calendar, name: "Ricky"), "Good morning, Ricky")
        XCTAssertEqual(Timeline.greeting(now: now, calendar: calendar, name: "McFly"), "Good morning")
        XCTAssertEqual(Timeline.greeting(now: at(19), calendar: calendar), "Good evening")
        XCTAssertEqual(Timeline.greeting(now: at(3), calendar: calendar), "Good night")
    }

    func testA24HourClockHasNoPeriod() {
        let clock = Timeline.Clock(calendar: calendar, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(clock.parts(at(15, 30)).time, "15:30")
        XCTAssertEqual(clock.parts(at(15, 30)).ampm, "")
        XCTAssertEqual(clock.label(at(9, 5)), "09:05")
    }

    func testTheMoodFollowsTheDisplaysHours() {
        let moods = [(6, 29, Mood.night), (6, 30, .morning), (10, 59, .morning), (11, 0, .day), (16, 59, .day),
                     (17, 0, .evening), (21, 29, .evening), (21, 30, .night), (0, 0, .night)]
        for (hour, minute, mood) in moods {
            XCTAssertEqual(Mood(date: at(hour, minute), calendar: calendar), mood, "\(hour):\(minute)")
        }
        XCTAssertEqual(Mood.nextChange(after: at(10), calendar: calendar), at(11))
        XCTAssertEqual(Mood.nextChange(after: at(11), calendar: calendar), at(17))
        XCTAssertEqual(Mood.nextChange(after: at(21, 45), calendar: calendar), at(30, 30), "tomorrow's 6:30")
        XCTAssertEqual(Mood.nextChange(after: at(3), calendar: calendar), at(6, 30))
    }

    func testTheDemosNewestReportIsAlwaysTodays() throws {
        for hoursAhead in [0, 30, 24 * 9 + 5] {
            let moment = Date().addingTimeInterval(TimeInterval(hoursAhead * 3600))
            let demo = try DemoData.load().rebased(to: moment)
            let newest = try XCTUnwrap(demo.reports.max { $0.publishedAt < $1.publishedAt })
            // The newest push lands 20 minutes ago, and its day is today.
            XCTAssertEqual(newest.reportDate, Timeline.dayKey(moment.addingTimeInterval(-20 * 60)), "\(hoursAhead) h ahead")
        }
        XCTAssertEqual(DemoData.day("2026-10-31", plus: 1, calendar: calendar), "2026-11-01")
        XCTAssertEqual(DemoData.day("not a date", plus: 1, calendar: calendar), "not a date")
    }
}
