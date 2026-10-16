import XCTest
@testable import McFlyKit

/// Dashboards as bento grids: the display's boardLayout cases
/// (tst_feedstore.cpp), on the app's demo boards and the display's own
/// shapes, at 2, 4 and 6 columns.
final class BoardLayoutTests: XCTestCase {
    /// Every cell from the top to the last row covered exactly once, every
    /// widget this version knows in exactly one tile, nothing out of bounds,
    /// and the tiles in reading order.
    private func assertPacked(_ tiles: [BoardTile], columns: Int, widgets: [Widget],
                              file: StaticString = #filePath, line: UInt = #line) {
        let rows = tiles.map { $0.row + $0.rowSpan }.max() ?? 0
        var cover = Array(repeating: 0, count: rows * columns)
        var seen = Array(repeating: 0, count: widgets.count)
        for tile in tiles {
            XCTAssertTrue(tile.colSpan >= 1 && tile.rowSpan >= 1 && tile.col >= 0 && tile.row >= 0 && tile.col + tile.colSpan <= columns,
                          "\(tile) out of bounds at \(columns) columns", file: file, line: line)
            XCTAssertEqual(tile.index, tile.indexes.first, file: file, line: line)
            XCTAssertEqual(tile.id, tile.index, file: file, line: line)
            for y in tile.row..<(tile.row + tile.rowSpan) {
                for x in tile.col..<(tile.col + tile.colSpan) where y * columns + x < cover.count { cover[y * columns + x] += 1 }
            }
            for i in tile.indexes { seen[i] += 1 }
        }
        for (i, count) in cover.enumerated() {
            XCTAssertEqual(count, 1, "cell \(i / columns),\(i % columns) covered \(count) times at \(columns) columns", file: file, line: line)
        }
        for (i, widget) in widgets.enumerated() {
            let known: Bool
            if case .unknown = widget { known = false } else { known = true }
            XCTAssertEqual(seen[i], known ? 1 : 0, "widget \(i) at \(columns) columns", file: file, line: line)
        }
        let order = tiles.map { [$0.row, $0.col] }
        XCTAssertEqual(order, order.sorted { $0.lexicographicallyPrecedes($1) }, "reading order", file: file, line: line)
    }

    /// Where each tile sits: "kind(index)@row,col colSpan×rowSpan".
    private func describe(_ tiles: [BoardTile]) -> [String] {
        tiles.map { "\($0.kind.rawValue)(\($0.index))@\($0.row),\($0.col) \($0.colSpan)×\($0.rowSpan)" }
    }

    private func demoBoards() throws -> [Dashboard] {
        try DemoData.load().dashboards.filter { !$0.hidden }.sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
    }

    func testTheDemoBoardsPackWithoutHoles() throws {
        let boards = try demoBoards()
        XCTAssertEqual(boards.map(\.key), ["ops", "launch"])
        for board in boards {
            for columns in [1, 2, 3, 4, 5, 6] {
                assertPacked(board.tiles(columns: columns), columns: columns, widgets: board.widgets)
            }
        }
    }

    func testOpsOnSixFourAndTwoColumns() throws {
        let ops = try XCTUnwrap(demoBoards().first)
        // Six: the two statuses as one strip, the first metric a 2×2 hero, the chart 4×2.
        XCTAssertEqual(describe(ops.tiles(columns: 6)), [
            "health(0)@0,0 6×1", "hero(2)@1,0 2×2", "metric(3)@1,2 1×1", "progress(4)@1,3 1×1", "list(6)@1,4 2×1",
            "chart(5)@2,2 4×2", "text(7)@3,0 2×1",
        ])
        // Four: the chart goes full width, the note grows into the last row.
        XCTAssertEqual(describe(ops.tiles(columns: 4)), [
            "health(0)@0,0 4×1", "hero(2)@1,0 2×2", "metric(3)@1,2 1×1", "progress(4)@1,3 1×1", "list(6)@2,2 2×1",
            "chart(5)@3,0 4×2", "text(7)@5,0 4×1",
        ])
        // Two: no hero (the first metric is still the one that would be), the progress grows into the gap.
        XCTAssertEqual(describe(ops.tiles(columns: 2)), [
            "health(0)@0,0 2×1", "metric(2)@1,0 1×1", "metric(3)@1,1 1×1", "progress(4)@2,0 2×1", "chart(5)@3,0 2×2",
            "list(6)@5,0 2×1", "text(7)@6,0 2×1",
        ])
        let health = try XCTUnwrap(ops.tiles(columns: 6).first)
        XCTAssertEqual(health.indexes, [0, 1])
        XCTAssertEqual(health.perRow, 2)
        let summary = BoardLayout.health(of: health, in: ops.widgets)
        XCTAssertEqual(summary.state, .warn)
        XCTAssertEqual(summary.summary, "1 warning · 1 OK")
        XCTAssertEqual(summary.colorHex, Insights.warnHex)
    }

    func testLaunchWeekGrowsIntoTheRoomItLeaves() throws {
        let launch = try XCTUnwrap(demoBoards().last)
        XCTAssertEqual(describe(launch.tiles(columns: 6)), ["progress(0)@0,0 1×2", "list(1)@0,1 2×2", "hero(2)@0,3 3×2"])
        XCTAssertEqual(describe(launch.tiles(columns: 4)), ["progress(0)@0,0 1×1", "list(1)@0,1 3×1", "hero(2)@1,0 4×2"])
        XCTAssertEqual(describe(launch.tiles(columns: 2)), ["progress(0)@0,0 1×1", "metric(2)@0,1 1×1", "list(1)@1,0 2×1"])
    }

    func testTheDisplaysOpsBoard() {
        // The display's demo Ops: three statuses (one down), three metrics, a
        // progress, a chart, a list and a note.
        let widgets: [Widget] = [
            .status(label: "API", state: .ok, detail: nil), .status(label: "Workers", state: .warn, detail: nil),
            .status(label: "Search", state: .error, detail: "Index rebuilding"),
            .metric(label: "Requests", value: 1_240_000, unit: nil, delta: nil, deltaPct: 4.2),
            .metric(label: "Error rate", value: 0.12, unit: "%", delta: nil, deltaPct: -30),
            .metric(label: "Signups", value: 812, unit: nil, delta: 46, deltaPct: nil),
            .progress(label: "Storage", value: 68, max: 100, unit: "%"),
            .chart(label: "Requests per hour", points: [1, 2, 3], unit: nil),
            .list(title: "On call", items: ["Ricky"]), .text(title: "Note", body: "Deploy tonight"),
        ]
        for columns in [2, 4, 6] { assertPacked(BoardLayout.layout(widgets, columns: columns), columns: columns, widgets: widgets) }
        // As the display lays it out on six (the figure in its handoff).
        XCTAssertEqual(describe(BoardLayout.layout(widgets, columns: 6)), [
            "health(0)@0,0 6×1", "hero(3)@1,0 2×2", "metric(4)@1,2 1×1", "metric(5)@1,3 1×1", "progress(6)@1,4 2×1",
            "chart(7)@2,2 4×2", "list(8)@3,0 2×1", "text(9)@4,0 6×1",
        ])
        XCTAssertEqual(BoardLayout.layout(widgets, columns: 6)[0].perRow, 3)
        let health = BoardLayout.health(of: BoardLayout.layout(widgets, columns: 6)[0], in: widgets)
        XCTAssertEqual(health.state, .error)
        XCTAssertEqual(health.colorHex, Insights.badHex)
        XCTAssertEqual(health.summary, "1 down · 1 warning · 1 OK")
    }

    func testUnknownWidgetsAreSkippedAndBreakAStatusRun() {
        let widgets: [Widget] = [
            .metric(label: "Requests", value: 1, unit: nil, delta: nil, deltaPct: nil),
            .unknown(type: "gauge"),
            .status(label: "API", state: .ok, detail: nil), .status(label: "DB", state: .ok, detail: nil),
            .list(title: "On call", items: ["Ricky"]),
        ]
        for columns in [2, 4, 6] {
            let tiles = BoardLayout.layout(widgets, columns: columns)
            assertPacked(tiles, columns: columns, widgets: widgets)
            XCTAssertFalse(tiles.contains { $0.indexes.contains(1) })
        }
        // On six: the hero, the list grown into the room beside it, the statuses' strip under both.
        XCTAssertEqual(describe(BoardLayout.layout(widgets, columns: 6)), ["hero(0)@0,0 2×2", "list(4)@0,2 4×2", "health(2)@2,0 6×1"])
        let health = BoardLayout.layout(widgets, columns: 6)[2]
        XCTAssertEqual(health.indexes, [2, 3])
        XCTAssertEqual(BoardLayout.health(of: health, in: widgets).summary, "All OK")
        XCTAssertEqual(BoardLayout.health(of: health, in: widgets).state, .ok)
        XCTAssertEqual(BoardLayout.unknownIndexes(widgets), [1])

        // A status, an unknown, a status: two lone statuses, not a strip.
        let split: [Widget] = [.status(label: "A", state: .ok, detail: nil), .unknown(type: ""), .status(label: "B", state: .warn, detail: nil)]
        XCTAssertEqual(BoardLayout.layout(split, columns: 4).map(\.kind), [.status, .status])
        XCTAssertEqual(BoardLayout.layout([.unknown(type: "gauge")], columns: 4), [])
        XCTAssertEqual(BoardLayout.layout([], columns: 4), [])
    }

    func testALongHealthStripWrapsIntoEvenRows() {
        var widgets: [Widget] = [.metric(label: "Requests", value: 1, unit: nil, delta: nil, deltaPct: nil)]
        for name in ["API", "Web", "DB", "Cache", "Queue", "Search", "Mail"] {
            widgets.append(.status(label: name, state: .ok, detail: nil))
        }
        widgets.append(.list(title: "On call", items: ["Ricky"]))
        // columns → rows of the strip, statuses in each row
        for (columns, lines, perRow) in [(2, 3, 3), (4, 2, 4), (6, 2, 4)] {
            let tiles = BoardLayout.layout(widgets, columns: columns)
            assertPacked(tiles, columns: columns, widgets: widgets)
            let health = tiles.first { $0.kind == .health }
            XCTAssertEqual(health?.indexes.count, 7)
            XCTAssertEqual(health?.colSpan, columns)
            XCTAssertEqual(health?.rowSpan, lines, "\(columns) columns")
            XCTAssertEqual(health?.perRow, perRow, "\(columns) columns")
        }
        // The demo's two fit one row at any width.
        for columns in [2, 4, 6] {
            let health = BoardLayout.layout([.status(label: "A", state: .ok, detail: nil), .status(label: "B", state: .warn, detail: nil)],
                                            columns: columns).first
            XCTAssertEqual(health?.rowSpan, 1)
            XCTAssertEqual(health?.perRow, 2)
        }
    }

    func testOneColumnAndALoneStatus() {
        let widgets: [Widget] = [
            .chart(label: nil, points: [1, 2], unit: nil), .status(label: "API", state: .warn, detail: nil),
            .metric(label: "Requests", value: 1, unit: nil, delta: nil, deltaPct: nil), .text(title: nil, body: "x"),
        ]
        XCTAssertEqual(describe(BoardLayout.layout(widgets, columns: 1)),
                       ["chart(0)@0,0 1×2", "status(1)@2,0 1×1", "metric(2)@3,0 1×1", "text(3)@4,0 1×1"])
        XCTAssertEqual(BoardLayout.layout(widgets, columns: 0).count, 4, "fewer than one column is one")
        XCTAssertEqual(BoardLayout.health(of: BoardLayout.layout(widgets, columns: 1)[1], in: widgets).summary, "1 warning")
    }

    func testStatusColours() {
        XCTAssertEqual(BoardLayout.colorHex(.ok), "#3DB37A")
        XCTAssertEqual(BoardLayout.colorHex(.warn), "#F6B94A")
        XCTAssertEqual(BoardLayout.colorHex(.error), "#F07F5A")
        XCTAssertEqual(BoardLayout.colorHex(.unknown), "#8F95A1")
        XCTAssertEqual(BoardHealth([]).summary, "All OK")
        XCTAssertEqual(BoardHealth([.status(label: "a", state: .unknown, detail: nil), .status(label: "b", state: .warn, detail: nil),
                                    .status(label: "c", state: .warn, detail: nil)]).summary, "2 warnings · 1 unknown")
    }
}
