import XCTest
@testable import McFlyKit

/// Series shaping: the cases of admin/tests/series.test.mjs, so the phone,
/// the console and the display read a history the same way.
final class SeriesTests: XCTestCase {
    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testMedian() {
        XCTAssertEqual(Series.median([3, 1, 2]), 2)
        XCTAssertEqual(Series.median([4, 1, 3, 2]), 2.5)
        XCTAssertNil(Series.median([]))
    }

    func testRobustZFlagsTheLastValueAgainstTheOnesBefore() throws {
        let usual: [Double] = [240, 238, 243, 241, 239, 244, 240, 242, 237, 241]
        XCTAssertLessThanOrEqual(try XCTUnwrap(Series.robustZ(usual + [212])), -3)
        XCTAssertLessThan(abs(try XCTUnwrap(Series.robustZ(usual + [241]))), 1)
        // One old spike doesn't hide the next unusual value.
        let spiked = Array(usual[0..<4]) + [900] + Array(usual[4...]) + [300]
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(Series.robustZ(spiked)), 3)
    }

    func testRobustZWithTooLittleOrNoSpreadIsNilNeverInfinite() throws {
        XCTAssertNil(Series.robustZ([1, 2, 3, 4, 5, 6, 7, 8]), "7 earlier points is too few")
        XCTAssertNotNil(Series.robustZ([1, 2, 3, 4, 5, 6, 7, 8, 9]), "8 is enough")
        XCTAssertNil(Series.robustZ([5, 5, 5, 5, 5, 5, 5, 5, 5, 9]), "no spread at all")
        XCTAssertNil(Series.robustZ([]))
        XCTAssertNil(Series.robustZ([4], minHistory: 0))
        // Mostly one value (the MAD is 0): the mean deviation stands in.
        let z = try XCTUnwrap(Series.robustZ([20, 20, 20, 20, 20, 21, 20, 20, 19, 20, 30]))
        XCTAssertTrue(z.isFinite && z >= 3)
    }

    func testUsualSwingLeavesTodaysMoveOut() throws {
        let closes: [Double] = [100, 101, 100, 101, 100, 101, 100]
        let calm = try XCTUnwrap(Series.usualSwing(closes))
        XCTAssertTrue(calm > 0.9 && calm < 1.1, "about 1%: \(calm)")
        XCTAssertEqual(Series.usualSwing(Array(closes.dropLast()) + [130]), calm, "a big last day doesn't change the usual")
        XCTAssertNil(Series.usualSwing([100, 101, 102, 103]), "too few days")
        XCTAssertNil(Series.usualSwing([100, 100, 100, 100, 100, 100, 100]), "no movement at all")
        XCTAssertNil(Series.usualSwing([100]))
        XCTAssertNil(Series.usualSwing([]))
    }

    func testRangeAndWhereTheLatestValueSits() {
        XCTAssertEqual(Series.range([10, 30, 20]), SeriesRange(low: 10, high: 30, last: 20, position: 0.5))
        XCTAssertEqual(Series.range([10, 30, 30])?.position, 1)
        XCTAssertEqual(Series.range([10, 30, 10])?.position, 0)
        XCTAssertEqual(Series.range([7, 7, 7])?.position, 0.5)
        XCTAssertNil(Series.range([]))
    }

    func testDailyClosesInTheZone() {
        let points: [(date: Date, value: Double)] = [
            (Self.iso("2026-10-13T15:00:00Z"), 1), // Oct 13, 10 am
            (Self.iso("2026-10-14T04:30:00Z"), 2), // Oct 13, 11:30 pm: the 13th's close
            (Self.iso("2026-10-14T05:30:00Z"), 3), // Oct 14, 12:30 am
            (Self.iso("2026-10-14T20:00:00Z"), 4),
        ]
        XCTAssertEqual(Series.dailyCloses(points, calendar: Self.calendar("America/Chicago")), [2, 4])
        XCTAssertEqual(Series.dailyCloses(points, calendar: Self.calendar("UTC")), [1, 4])
    }

    func testDailyClosesAcrossADSTChangeAndNoneFromNothing() {
        // Chicago falls back on 2026-11-01: that day is 25 hours long.
        let points: [(date: Date, value: Double)] = [
            (Self.iso("2026-11-01T05:30:00Z"), 1), // 00:30 CDT, Nov 1
            (Self.iso("2026-11-01T06:30:00Z"), 2), // 01:30 CDT
            (Self.iso("2026-11-01T07:30:00Z"), 3), // 01:30 CST, the hour again
            (Self.iso("2026-11-02T05:30:00Z"), 4), // 23:30 CST, still Nov 1
            (Self.iso("2026-11-02T06:30:00Z"), 5), // 00:30 CST, Nov 2
        ]
        XCTAssertEqual(Series.dailyCloses(points, calendar: Self.calendar("America/Chicago")), [4, 5])
        XCTAssertEqual(Series.dailyCloses([], calendar: Self.calendar("UTC")), [])
    }

    func testDownsampleKeepsTheEndsTheCountAndTheSpikes() {
        let flat = (0..<100).map { i in i == 57 ? 100.0 : 10 + Double(i % 3) }
        let out = Series.downsample(flat, to: 10)
        XCTAssertEqual(out.count, 10)
        XCTAssertEqual(out.first, 10)
        XCTAssertEqual(out.last, flat[99])
        XCTAssertTrue(out.contains(100), "the spike survives")
    }

    func testDownsampleWithFewPointsOrATinyN() {
        let values: [Double] = [1, 2, 3]
        XCTAssertEqual(Series.downsample(values, to: 30), values)
        XCTAssertEqual(Series.downsample(values, to: 2), [1, 3])
        XCTAssertEqual(Series.downsample(values, to: 1), [3])
        XCTAssertEqual(Series.downsample(values, to: 0), [])
        XCTAssertEqual(Series.downsample([], to: 5), [])
        XCTAssertEqual(Series.downsample([1, 5, 2, 8, 3], to: 4).count, 4)
    }

    func testTrendFollowsTheSign() {
        XCTAssertEqual(Trend(2), .up)
        XCTAssertEqual(Trend(-0.1), .down)
        XCTAssertEqual(Trend(0), .flat)
        XCTAssertEqual(Trend(nil), .flat)
        XCTAssertEqual(Trend(.nan), .flat)
    }

    // MARK: The feeds' histories

    private func quote(_ id: Int64, _ price: Double, _ asOf: String, changePct: Double? = nil) -> Quote {
        Quote(id: id, agentId: UUID(), symbol: "SPY", price: price, changePct: changePct, asOf: Self.iso(asOf), createdAt: Self.iso(asOf))
    }

    func testAQuotesDailyClosesAndUsualSwingComeFromItsWholeHistory() throws {
        // Two pushes a day for a week, the evening one each day's close.
        var quotes: [Quote] = []
        let closes: [Double] = [100, 101, 100, 101, 100, 101, 100]
        for (day, close) in closes.enumerated() {
            let date = String(format: "2026-10-%02d", 5 + day)
            quotes.append(quote(Int64(day * 2), 50, "\(date)T15:00:00Z"))
            quotes.append(quote(Int64(day * 2 + 1), close, "\(date)T20:00:00Z"))
        }
        let series = try XCTUnwrap(QuoteSeries.group(quotes.shuffled(), symbols: []).first)
        let chicago = Self.calendar("America/Chicago")
        XCTAssertEqual(series.dailyCloses(calendar: chicago), closes)
        XCTAssertEqual(series.usualSwing(calendar: chicago), Series.usualSwing(closes))
        XCTAssertEqual(series.sparkline(), series.prices)
        XCTAssertEqual(series.sparkline(limit: 3), [101, 50, 100])
        XCTAssertEqual(series.historyRange?.low, 50)
        XCTAssertEqual(series.historyRange?.high, 101)
    }

    func testTheSparklineAndRangeAreTheNewestSixtyPoints() throws {
        let metrics = (0..<80).map { i in
            Metric(id: Int64(i), agentId: UUID(), key: "steps", value: Double(i), asOf: Date(timeIntervalSince1970: Double(i) * 3600),
                   createdAt: .distantPast)
        }
        let series = try XCTUnwrap(MetricSeries.group(metrics, settings: []).first)
        XCTAssertEqual(series.values.count, 80)
        XCTAssertEqual(series.sparkline().count, Series.sparklinePoints)
        XCTAssertEqual(series.sparkline().first, 20)
        XCTAssertEqual(series.sparkline().last, 79)
        XCTAssertEqual(series.historyRange, SeriesRange(low: 20, high: 79, last: 79, position: 1))
    }
}
