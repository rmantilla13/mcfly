import XCTest
@testable import McFlyKit

/// What a market agent adds to a quote, as the display shows it
/// (display/tests/tst_feedstore.cpp: shapesHoldingsAndSignals and
/// aHoldingCountsWhileInTheNewestPush).
final class HoldingsTests: XCTestCase {
    private let agent = UUID()
    private let pushed = Date(timeIntervalSince1970: 1_800_000_000)

    private func quote(_ id: Int64, _ symbol: String, _ price: Double, change: Double?, created: Date? = nil,
                       asOf: Date? = nil, data: QuoteData? = nil) -> Quote {
        Quote(id: id, agentId: agent, symbol: symbol, price: price, change: change,
              asOf: asOf ?? created ?? pushed, createdAt: created ?? pushed, data: data)
    }

    private func decode(_ json: String) throws -> QuoteData {
        try JSONDecoder.mcfly.decode(QuoteData.self, from: Data(json.utf8))
    }

    func testDecodesNumbersAsStringsAndSignalsAsStrings() throws {
        let data = try decode("""
        {"position": {"shares": "1.5", "value": "$1,150", "day_change": -3, "avg_cost": true},
         "signals": [{"text": "RSI 71", "tone": "up"}, "Earnings in 3 days", {"text": "Odd", "tone": "sideways"}],
         "stats": {"open": "49", "market_cap": 3.7e12, "earnings": "Oct 30, after close", "pe": "n/a"}}
        """)
        XCTAssertEqual(data.position?.shares, 1.5)
        XCTAssertEqual(data.position?.value, 1150)
        XCTAssertEqual(data.position?.dayChange, -3)
        XCTAssertNil(data.position?.avgCost) // not a number
        XCTAssertEqual(data.signals.map(\.tone), [.up, .watch, .watch])
        XCTAssertEqual(data.signals[1].text, "Earnings in 3 days")
        XCTAssertEqual(data.stats?.open, 49)
        XCTAssertNil(data.stats?.pe)
        XCTAssertEqual(data.stats?.earnings, "Oct 30, after close")
        // Nothing usable is an empty object, not an error.
        XCTAssertEqual(try decode("{}"), QuoteData())
    }

    func testHoldingsSignalsStatsAndTheTotal() throws {
        let aaa = QuoteData(
            position: .init(shares: 4, avgCost: 40),
            signals: [.init(text: "RSI 71, near the overbought line", tone: .up), .init(text: "Earnings in 3 days"), .init(text: "  ", tone: .down)],
            stats: .init(open: 49, high: 51, low: 48.5, prevClose: 49, volume: 52_300_000, avgVolume: 41_000_000,
                         marketCap: 3.7e12, pe: 37.24, low52w: 30, high52w: 60, earnings: "Oct 30, after close"))
        let bbb = QuoteData(position: .init(shares: 1.5, value: 150, dayChange: -3))
        let series = QuoteSeries.group([quote(1, "AAA", 50, change: 1, data: aaa), quote(2, "BBB", 100, change: -2, data: bbb)], symbols: [])
        let (insights, portfolio) = Holdings.build(series: series, latest: [])

        let a = try XCTUnwrap(insights["AAA"]?.holding)
        XCTAssertEqual(a.value, 200)        // 4 × $50
        XCTAssertEqual(a.dayChange, 4)      // 4 × $1
        XCTAssertEqual(a.totalChange, 40)   // $200 − 4 × $40
        XCTAssertEqual(a.totalChangePct, 25)
        XCTAssertEqual(try XCTUnwrap(a.weightPct), 200.0 / 350 * 100, accuracy: 1e-9)
        XCTAssertEqual(insights["AAA"]?.signals.map(\.text), ["RSI 71, near the overbought line", "Earnings in 3 days"])
        XCTAssertEqual(insights["AAA"]?.stats.map(\.label), ["Open", "Prev close", "Volume", "Market cap", "P/E", "Earnings"])
        XCTAssertEqual(insights["AAA"]?.stats.first { $0.label == "Volume" }?.value, "52.3M · 1.3× avg")
        XCTAssertEqual(insights["AAA"]?.stats.first { $0.label == "Market cap" }?.value, "$3.7T")
        XCTAssertEqual(insights["AAA"]?.ranges.map(\.label), ["Today", "52 weeks"])
        XCTAssertEqual(try XCTUnwrap(insights["AAA"]?.ranges.first?.position), 0.6, accuracy: 1e-9) // (50 − 48.5) / 2.5

        let b = try XCTUnwrap(insights["BBB"]?.holding)
        XCTAssertEqual(b.value, 150)        // given, not worked out
        XCTAssertNil(b.totalChange)         // no cost

        // $350; +$1 on the $349 before today; +$40 on the $160 the gain is known for.
        XCTAssertEqual(portfolio.count, 2)
        XCTAssertEqual(portfolio.value, 350)
        XCTAssertEqual(portfolio.dayChange, 1)
        XCTAssertEqual(try XCTUnwrap(portfolio.dayChangePct), 1.0 / 349 * 100, accuracy: 1e-9)
        XCTAssertEqual(portfolio.totalChange, 40)
        XCTAssertEqual(portfolio.totalChangePct, 25)
    }

    func testAHoldingCountsWhileInTheNewestPush() {
        let held = QuoteData(position: .init(shares: 2), signals: [.init(text: "Stale")])
        let earlier = pushed.addingTimeInterval(-900)
        let quotes = [
            // One push, its quotes stamped hours apart (a close and a live price): both current.
            quote(3, "BTC-USD", 100, change: 1, created: pushed, data: held),
            quote(2, "AAA", 50, change: 1, created: pushed, asOf: pushed.addingTimeInterval(-3 * 3600), data: held),
            // Only in an earlier push: its price stays, its holding goes.
            quote(1, "OLD", 9, change: 0, created: earlier, data: held),
        ]
        let (insights, portfolio) = Holdings.build(series: QuoteSeries.group(quotes, symbols: []), latest: [])
        XCTAssertNotNil(insights["BTC-USD"]?.holding)
        XCTAssertNotNil(insights["AAA"]?.holding)
        XCTAssertNil(insights["OLD"]?.holding)
        XCTAssertNil(insights["OLD"]?.signals.first)
        XCTAssertEqual(portfolio.count, 2)
    }

    func testLiveDataComesFromTheLatestRow() {
        // The live history carries no data; quotes_latest does, for the row with the same as_of.
        let quotes = [quote(2, "AAA", 50, change: 1), quote(1, "AAA", 49, change: 0, created: pushed.addingTimeInterval(-86_400))]
        let latest = [QuoteLatest(symbol: "AAA", asOf: pushed, data: QuoteData(position: .init(shares: 3))),
                      QuoteLatest(symbol: "ZZZ", asOf: pushed, data: QuoteData(position: .init(shares: 1)))]
        let (insights, portfolio) = Holdings.build(series: QuoteSeries.group(quotes, symbols: []), latest: latest)
        XCTAssertEqual(insights["AAA"]?.holding?.value, 150)
        XCTAssertNil(insights["ZZZ"])
        XCTAssertEqual(portfolio.count, 1)
        // A latest row from another moment (a newer push not yet in the history) is not used.
        let stale = [QuoteLatest(symbol: "AAA", asOf: pushed.addingTimeInterval(60), data: QuoteData(position: .init(shares: 3)))]
        XCTAssertNil(Holdings.build(series: QuoteSeries.group(quotes, symbols: []), latest: stale).insights["AAA"])
    }

    func testIntradayBarsOnTheSession() throws {
        let data = try decode("""
        {"intraday": {"interval": "10minute", "open": 1800000000, "close": 1800023400,
                      "points": [[1800011700, 108], [1800000000, 102], [1800030000, 1], [1800000600]]}}
        """)
        XCTAssertEqual(data.intraday?.points.count, 3) // the one without a price is dropped
        let series = QuoteSeries.group([quote(1, "AAA", 104, change: 4, data: data)], symbols: [])
        let insight = try XCTUnwrap(Holdings.build(series: series, latest: []).insights["AAA"])
        let day = try XCTUnwrap(insight.intraday)
        XCTAssertEqual(day.points.map(\.price), [102, 108]) // in time order; the bar past the close is out
        XCTAssertEqual(day.open, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(insight.prevClose, 100)
        // Fewer than two bars is no chart; a missing close is no intraday at all.
        let one = try decode(#"{"intraday": {"open": 1800000000, "close": 1800023400, "points": [[1800000000, 9]]}}"#)
        XCTAssertNil(Holdings.session(one.intraday))
        XCTAssertNil(try decode(#"{"intraday": {"open": 1800000000, "points": []}}"#).intraday)
    }

    func testFormats() {
        XCTAssertEqual(Format.shares(40), "40 shares")
        XCTAssertEqual(Format.shares(1), "1 share")
        XCTAssertEqual(Format.shares(0.186358), "0.1864 shares")
        XCTAssertEqual(Format.signedPrice(-48), "−$48.00")
        XCTAssertEqual(Format.compact(312_000_000), "312M")
        XCTAssertEqual(Format.compact(4.66e12), "4.7T")
    }

    @MainActor
    func testTheDemoHoldsThreeSymbols() async throws {
        let store = FeedStore(source: DemoFeedSource(data: try DemoData.load()))
        await store.refresh()
        let (insights, portfolio) = store.markets
        XCTAssertEqual(portfolio.count, 3) // SPY, AAPL, NVDA; TSLA only has a signal
        XCTAssertNotNil(insights["TSLA"]?.signals.first)
        XCTAssertNil(insights["TSLA"]?.holding)
        XCTAssertEqual(insights["AAPL"]?.holding?.shares, 40)
    }
}
