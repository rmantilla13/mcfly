import XCTest
@testable import McFlyKit

/// A day's conflicts, back-to-back runs and busiest stretch, as the
/// calendar colours them.
final class DayLoadTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()
    private lazy var day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 22 + dayOffset, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: UUID(), agentId: UUID(), externalId: title, title: title, startsAt: start, endsAt: end, allDay: allDay)
    }

    func testOverlapsAreConflicts() {
        let a = event("A", at(9), at(10))
        let b = event("B", at(9, 30), at(10, 30))
        let c = event("C", at(14), at(15))
        let load = DayLoad(events: [a, b, c], day: day, calendar: calendar)
        XCTAssertEqual(load.conflicts, [DayLoad.Span(start: at(9, 30), end: at(10))])
        XCTAssertEqual(load.kind(of: a), .conflict)
        XCTAssertEqual(load.kind(of: b), .conflict)
        XCTAssertEqual(load.kind(of: c), .clear)
        XCTAssertEqual(load.conflictCount, 1)
    }

    func testAnEventInsideAnotherConflictsAndOverlapsJoin() {
        let long = event("Long", at(9), at(12))
        let inside = event("Inside", at(10), at(10, 30))
        let late = event("Late", at(11), at(12, 30))
        let load = DayLoad(events: [long, inside, late], day: day, calendar: calendar)
        // 10–10:30 and 11–12 are separate stretches.
        XCTAssertEqual(load.conflicts.map(\.start), [at(10), at(11)])
        XCTAssertEqual(load.conflicts.map(\.end), [at(10, 30), at(12)])
        XCTAssertEqual([long, inside, late].map(load.kind(of:)), [.conflict, .conflict, .conflict])
    }

    func testBackToBackIsFiveMinutesOrLess() {
        let a = event("A", at(9), at(10))
        let b = event("B", at(10), at(10, 30)) // the same minute
        let c = event("C", at(10, 35), at(11)) // five minutes later
        let d = event("D", at(11, 6), at(12)) // six: not back to back
        let load = DayLoad(events: [a, b, c, d], day: day, calendar: calendar)
        XCTAssertEqual([a, b, c, d].map(load.kind(of:)), [.backToBack, .backToBack, .backToBack, .clear])
        XCTAssertEqual(load.backToBackCount, 2)
        XCTAssertTrue(load.conflicts.isEmpty)
    }

    func testAConflictOutranksBackToBack() {
        let a = event("A", at(9), at(10))
        let b = event("B", at(10), at(11))
        let c = event("C", at(10, 30), at(11, 30))
        let load = DayLoad(events: [a, b, c], day: day, calendar: calendar)
        XCTAssertEqual(load.kind(of: a), .backToBack)
        XCTAssertEqual(load.kind(of: b), .conflict)
        XCTAssertEqual(load.kind(of: c), .conflict)
    }

    func testAllDayTakesNoTimeAndMultiDayCountsOnlyItsPartOfTheDay() {
        let holiday = event("Holiday", day, at(0, dayOffset: 1), allDay: true)
        let overnight = event("Overnight", at(22, dayOffset: -1), at(1))
        let early = event("Early", at(0, 30), at(2))
        let load = DayLoad(events: [holiday, overnight, early], day: day, calendar: calendar)
        XCTAssertEqual(load.kind(of: holiday), .clear)
        XCTAssertEqual(load.conflicts, [DayLoad.Span(start: at(0, 30), end: at(1))])
        // Another day's stretch of the overnight event isn't today's.
        let yesterday = DayLoad(events: [overnight, early], day: at(12, dayOffset: -1), calendar: calendar)
        XCTAssertTrue(yesterday.conflicts.isEmpty)
    }

    func testTheBusiestStretchNeedsAnHourBooked() {
        // 10–12:30 is packed (15 minutes free before lunch still joins it);
        // the afternoon has one short call.
        let load = DayLoad(events: [
            event("Standup", at(9), at(9, 15)),
            event("Review", at(10), at(11)),
            event("Pipeline", at(11), at(11, 30)),
            event("Lunch", at(11, 45), at(12, 30)),
            event("Call", at(15), at(15, 30)),
        ], day: day, calendar: calendar)
        XCTAssertEqual(load.busiest, DayLoad.Span(start: at(10), end: at(12, 30)))
        // Heat peaks in the busy stretch, and is nothing at night.
        let slot = { (h: Int, m: Int) in (h * 60 + m) / 15 }
        XCTAssertGreaterThan(load.heat[slot(11, 0)], load.heat[slot(15, 0)])
        XCTAssertEqual(load.heat[slot(3, 0)], 0)
        XCTAssertTrue(load.heat.allSatisfy { $0 >= 0 && $0 <= 1 })
        // Two half-hour calls aren't a busy stretch.
        let light = DayLoad(events: [event("A", at(9), at(9, 30)), event("B", at(14), at(14, 30))], day: day, calendar: calendar)
        XCTAssertNil(light.busiest)
        // Nor is one long dinner on its own, beside a packed hour of two.
        let dinner = DayLoad(events: [
            event("Dinner", at(18), at(21)), event("Sync", at(9), at(9, 40)), event("Prep", at(9, 45), at(10, 15)),
        ], day: day, calendar: calendar)
        XCTAssertEqual(dinner.busiest, DayLoad.Span(start: at(9), end: at(10, 15)))
        XCTAssertNil(DayLoad(events: [event("Offsite", at(9), at(17))], day: day, calendar: calendar).busiest)
    }

    func testOverlapsCountOnceTowardBusy() {
        // Three events on the same hour book an hour, not three.
        let same = (0..<3).map { event("S\($0)", at(9), at(10)) }
        let load = DayLoad(events: same, day: day, calendar: calendar)
        XCTAssertEqual(load.busiest, DayLoad.Span(start: at(9), end: at(10)))
        XCTAssertEqual(load.heat[9 * 4 + 2], 0.5, accuracy: 1e-9) // 9:30: one booked hour of the two around it
    }

    func testAnEmptyDay() {
        let load = DayLoad(events: [], day: day, calendar: calendar)
        XCTAssertTrue(load.conflicts.isEmpty)
        XCTAssertEqual(load.backToBackCount, 0)
        XCTAssertNil(load.busiest)
        XCTAssertEqual(load.heat.count, 96)
    }
}
