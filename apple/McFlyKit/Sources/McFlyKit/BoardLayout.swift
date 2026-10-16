import Foundation

// A dashboard as a bento grid: the display's `FeedStore::boardLayout`,
// ported. In the agent's order, the first metric is a 2×2 hero once there
// are four columns, a run of two or more statuses is one health strip across
// the board, a chart is wide and tall, a list or a note half a row; then
// first-fit placement and a fill pass that grows tiles into the gaps, so
// there are no holes and nothing is reordered. Pure, so BoardLayoutTests can
// check it at 2, 4 and 6 columns.

/// One tile of a board: which widget(s) it shows and where it sits.
public struct BoardTile: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        /// The board's first metric, 2×2, on four columns or more.
        case hero
        /// A run of two or more statuses, one strip across the board.
        case health
        case metric, status, progress, chart, list, text
    }

    public var id: Int { index }
    /// The widget's position in the dashboard's `widgets` (the first of a health strip's).
    public let index: Int
    /// Every widget the tile shows: a health strip's statuses, else just `index`.
    public let indexes: [Int]
    public let kind: Kind
    public internal(set) var row: Int
    public internal(set) var col: Int
    public internal(set) var rowSpan: Int
    public internal(set) var colSpan: Int
    /// A health strip's statuses per row (it wraps into rows of even length:
    /// 7 on four columns is 4 + 3); 1 for any other tile.
    public let perRow: Int

    public init(index: Int, indexes: [Int], kind: Kind, row: Int, col: Int, rowSpan: Int, colSpan: Int, perRow: Int = 1) {
        self.index = index; self.indexes = indexes; self.kind = kind; self.row = row; self.col = col
        self.rowSpan = rowSpan; self.colSpan = colSpan; self.perRow = perRow
    }
}

/// A health strip's statuses summed up: the worst state and how many of each.
public struct BoardHealth: Hashable, Sendable {
    /// The worst: error (down), then warn, unknown, ok.
    public let state: DashboardWidget.State
    public let down: Int
    public let warn: Int
    public let ok: Int
    public let unknown: Int

    public init(_ widgets: [DashboardWidget]) {
        var worst: DashboardWidget.State?
        var down = 0, warn = 0, ok = 0, unknown = 0
        for widget in widgets {
            guard case .status(_, let state, _) = widget else { continue }
            switch state {
            case .error: down += 1
            case .warn: warn += 1
            case .ok: ok += 1
            case .unknown: unknown += 1
            }
            if worst == nil || Self.rank(state) > Self.rank(worst!) { worst = state }
        }
        state = worst ?? .unknown
        self.down = down; self.warn = warn; self.ok = ok; self.unknown = unknown
    }

    /// "All OK", or "1 down · 1 warning · 2 OK".
    public var summary: String {
        if down + warn + unknown == 0 { return "All OK" }
        var parts: [String] = []
        if down > 0 { parts.append("\(down) down") }
        if warn > 0 { parts.append(warn == 1 ? "1 warning" : "\(warn) warnings") }
        if unknown > 0 { parts.append("\(unknown) unknown") }
        if ok > 0 { parts.append("\(ok) OK") }
        return parts.joined(separator: " · ")
    }

    /// The worst state's colour.
    public var colorHex: String { BoardLayout.colorHex(state) }

    static func rank(_ state: DashboardWidget.State) -> Int {
        switch state {
        case .error: return 3
        case .warn: return 2
        case .unknown: return 1
        case .ok: return 0
        }
    }
}

public enum BoardLayout {
    /// The tiles in reading order (row, then column). A widget type this
    /// version doesn't know is left out, as the display leaves it out, and
    /// breaks a run of statuses; every other widget is in exactly one tile.
    /// Placeholders for the unknown ones, if a view wants them: `unknownIndexes`.
    public static func layout(_ widgets: [Widget], columns: Int) -> [BoardTile] {
        let cols = max(1, columns)
        func isStatus(_ i: Int) -> Bool {
            if case .status = widgets[i] { return true }
            return false
        }

        // Each tile's kind and size, in the board's order.
        var tiles: [BoardTile] = []
        var heroTaken = false
        var i = 0
        while i < widgets.count {
            let widget = widgets[i]
            if case .unknown = widget {
                i += 1
                continue
            }
            var next = i + 1
            if isStatus(i) {
                while next < widgets.count && isStatus(next) { next += 1 }
            }
            var kind: BoardTile.Kind
            var colSpan = 1, rowSpan = 1, perRow = 1
            if next - i >= 2 {
                // A run of statuses: one strip across. A long run wraps (a
                // status a column, three on two columns) into rows of even
                // length: 7 → 4 + 3.
                kind = .health
                colSpan = cols
                let count = next - i
                let most = cols <= 2 ? 3 : cols
                rowSpan = (count + most - 1) / most
                perRow = (count + rowSpan - 1) / rowSpan
            } else {
                switch widget {
                case .metric:
                    kind = .metric
                    if !heroTaken {
                        heroTaken = true
                        if cols >= 4 {
                            kind = .hero
                            colSpan = 2
                            rowSpan = 2
                        }
                    }
                case .status: kind = .status
                case .progress: kind = .progress
                case .chart:
                    kind = .chart
                    colSpan = min(4, cols)
                    rowSpan = 2
                case .list:
                    kind = .list
                    colSpan = min(2, cols)
                case .text:
                    kind = .text
                    colSpan = min(2, cols)
                case .unknown:
                    i += 1
                    continue
                }
            }
            tiles.append(BoardTile(index: i, indexes: Array(i..<next), kind: kind, row: 0, col: 0,
                                   rowSpan: rowSpan, colSpan: colSpan, perRow: perRow))
            i = next
        }

        // First fit: each tile in order at the first place, in reading order, it fits.
        var grid: [[Int]] = [] // [row][col]: the tile there, or -1
        func at(_ r: Int, _ c: Int) -> Int { r < grid.count ? grid[r][c] : -1 }
        func take(_ n: Int, _ r: Int, _ c: Int) {
            while grid.count <= r { grid.append(Array(repeating: -1, count: cols)) }
            grid[r][c] = n
        }
        for n in tiles.indices {
            let t = tiles[n]
            var placed = false
            var r = 0
            while !placed {
                var c = 0
                while c + t.colSpan <= cols && !placed {
                    var free = true
                    for y in r..<(r + t.rowSpan) where free {
                        for x in c..<(c + t.colSpan) where free {
                            free = at(y, x) < 0
                        }
                    }
                    if free {
                        tiles[n].row = r
                        tiles[n].col = c
                        for y in r..<(r + t.rowSpan) {
                            for x in c..<(c + t.colSpan) { take(n, y, x) }
                        }
                        placed = true
                    }
                    c += 1
                }
                r += 1
            }
        }

        // Then no holes: a tile beside or above a gap grows into it (right,
        // down, left, up) when the gap runs its whole edge. Until nothing grows.
        let rows = grid.count
        func empty(_ r0: Int, _ r1: Int, _ c0: Int, _ c1: Int) -> Bool {
            for y in r0..<r1 {
                for x in c0..<c1 where grid[y][x] >= 0 { return false }
            }
            return true
        }
        func fill(_ n: Int) {
            let t = tiles[n]
            for y in t.row..<(t.row + t.rowSpan) {
                for x in t.col..<(t.col + t.colSpan) { grid[y][x] = n }
            }
        }
        var grew = true
        while grew {
            grew = false
            for r in 0..<rows {
                for c in 0..<cols {
                    if grid[r][c] >= 0 { continue }
                    if c > 0, case let n = grid[r][c - 1], n >= 0 {
                        let t = tiles[n]
                        if t.col + t.colSpan == c && empty(t.row, t.row + t.rowSpan, c, c + 1) {
                            tiles[n].colSpan += 1
                            fill(n)
                            grew = true
                            continue
                        }
                    }
                    if r > 0, case let n = grid[r - 1][c], n >= 0 {
                        let t = tiles[n]
                        if t.row + t.rowSpan == r && empty(r, r + 1, t.col, t.col + t.colSpan) {
                            tiles[n].rowSpan += 1
                            fill(n)
                            grew = true
                            continue
                        }
                    }
                    if c + 1 < cols, case let n = grid[r][c + 1], n >= 0 {
                        let t = tiles[n]
                        if t.col == c + 1 && empty(t.row, t.row + t.rowSpan, c, c + 1) {
                            tiles[n].col -= 1
                            tiles[n].colSpan += 1
                            fill(n)
                            grew = true
                            continue
                        }
                    }
                    if r + 1 < rows, case let n = grid[r + 1][c], n >= 0 {
                        let t = tiles[n]
                        if t.row == r + 1 && empty(r, r + 1, t.col, t.col + t.colSpan) {
                            tiles[n].row -= 1
                            tiles[n].rowSpan += 1
                            fill(n)
                            grew = true
                        }
                    }
                }
            }
        }

        return tiles.enumerated()
            .sorted { a, b in
                (a.element.row, a.element.col, a.offset) < (b.element.row, b.element.col, b.offset)
            }
            .map(\.element)
    }

    /// The statuses a health tile (or a lone status tile) shows, summed up.
    public static func health(of tile: BoardTile, in widgets: [Widget]) -> BoardHealth {
        BoardHealth(tile.indexes.filter { widgets.indices.contains($0) }.map { widgets[$0] })
    }

    /// The widgets this version can't draw, by position, so a view can say so.
    public static func unknownIndexes(_ widgets: [Widget]) -> [Int] {
        widgets.indices.filter {
            if case .unknown = widgets[$0] { return true }
            return false
        }
    }

    /// A status's colour on the display: green OK, amber warning, coral down, grey unknown.
    public static func colorHex(_ state: DashboardWidget.State) -> String {
        switch state {
        case .ok: return Insights.goodHex
        case .warn: return Insights.warnHex
        case .error: return Insights.badHex
        case .unknown: return Insights.unknownHex
        }
    }
}

extension Dashboard {
    /// Its widgets as a bento grid of `columns` (`BoardLayout.layout`).
    public func tiles(columns: Int) -> [BoardTile] {
        BoardLayout.layout(widgets, columns: columns)
    }
}
