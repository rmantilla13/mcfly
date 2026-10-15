import XCTest
@testable import McFlyKit

final class QuoteSeriesTests: XCTestCase {
    private func quote(_ id: Int64, _ symbol: String, _ price: Double, daysAgo: Double) -> Quote {
        Quote(id: id, agentId: UUID(), symbol: symbol, price: price,
              asOf: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400), createdAt: .now)
    }

    func testGroupsNewestFirstInConsoleOrder() {
        let quotes = [
            quote(1, "AAPL", 243.7, daysAgo: 2), quote(5, "AAPL", 245.1, daysAgo: 1), quote(9, "AAPL", 247.9, daysAgo: 0),
            quote(2, "NVDA", 191.5, daysAgo: 2), quote(10, "NVDA", 191.25, daysAgo: 0),
            quote(12, "SPY", 668.4, daysAgo: 0),
        ]
        let symbols = [Symbol(symbol: "SPY", sortOrder: 0), Symbol(symbol: "AAPL", name: "Apple", sortOrder: 1), Symbol(symbol: "NVDA", sortOrder: 2)]
        let series = QuoteSeries.group(quotes, symbols: symbols)
        XCTAssertEqual(series.map(\.symbol), ["SPY", "AAPL", "NVDA"])
        let apple = series[1]
        XCTAssertEqual(apple.history.map(\.id), [9, 5, 1])
        XCTAssertEqual(apple.latest.price, 247.9)
        XCTAssertEqual(apple.prices, [243.7, 245.1, 247.9])
        XCTAssertEqual(apple.displayName, "Apple")
    }

    func testHiddenSymbolsAreLeftOutAndUnknownOnesSortLast() {
        let quotes = [quote(1, "ZZZ", 1, daysAgo: 0), quote(2, "AAPL", 2, daysAgo: 0), quote(3, "HID", 3, daysAgo: 0)]
        let symbols = [Symbol(symbol: "AAPL", sortOrder: 5), Symbol(symbol: "HID", sortOrder: 0, hidden: true)]
        let series = QuoteSeries.group(quotes, symbols: symbols)
        XCTAssertEqual(series.map(\.symbol), ["AAPL", "ZZZ"])
        XCTAssertEqual(series[1].sortOrder, 1000)
    }

    func testSameInstantBreaksTiesByRowId() {
        let quotes = [quote(7, "SPY", 1, daysAgo: 0), quote(8, "SPY", 2, daysAgo: 0)]
        XCTAssertEqual(QuoteSeries.group(quotes, symbols: []).first?.latest.id, 8)
    }

    func testDemoSeriesMatchTheSeedOrder() throws {
        let demo = try DemoData.load()
        let series = QuoteSeries.group(demo.quotes, symbols: demo.symbols)
        XCTAssertEqual(series.map(\.symbol), ["SPY", "AAPL", "NVDA", "TSLA"])
        XCTAssertEqual(series[1].history.count, 3)
        XCTAssertEqual(series[1].latest.note, "Services beat; iPhone 18 demand steady.")
    }
}
