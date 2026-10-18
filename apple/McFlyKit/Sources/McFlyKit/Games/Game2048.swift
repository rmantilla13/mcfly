// 2048 by Gabriele Cirulli, https://github.com/gabrielecirulli/2048
// The rules of js/tile.js, js/grid.js and js/game_manager.js at commit
// 478b6ec3 (display/games/2048/game.js), in Swift.
//
// The MIT License (MIT)
//
// Copyright (c) 2014 Gabriele Cirulli
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

/// The game manager: a 4 × 4 grid of tiles, moved by direction. What the
/// web page's actuator and storage did is the app's: `tiles` says how to
/// draw the last move, `saved`/`init(saved:)` keep a game in progress.
public struct Game2048: Sendable {
    /// 0 up, 1 right, 2 down, 3 left (game_manager.js).
    public enum Direction: Int, Sendable, CaseIterable {
        case up, right, down, left

        var vector: (x: Int, y: Int) {
            switch self {
            case .up: return (0, -1)
            case .right: return (1, 0)
            case .down: return (0, 1)
            case .left: return (-1, 0)
            }
        }
    }

    public struct Position: Sendable, Codable, Equatable, Hashable {
        public var x: Int, y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public struct Tile: Sendable, Equatable, Identifiable {
        /// Stays with a tile while it slides; a merge is a new tile.
        public var id: Int
        public var x: Int, y: Int
        public var value: Int
        public var previousPosition: Position?
        /// The two tiles that slid together into this one.
        public var mergedFrom: [Tile]?

        public var position: Position { Position(x: x, y: y) }
    }

    /// A game in progress, as local_storage_manager.js keeps it.
    public struct State: Codable, Sendable, Equatable {
        public struct SavedTile: Codable, Sendable, Equatable {
            public var position: Position
            public var value: Int
        }
        public var size: Int
        /// cells[x][y].
        public var cells: [[SavedTile?]]
        public var score: Int
        public var over: Bool
        public var won: Bool
        public var keepPlaying: Bool
    }

    public let size: Int
    /// cells[x][y], as grid.js has them.
    public private(set) var cells: [[Tile?]]
    public private(set) var score = 0
    public private(set) var over = false
    public private(set) var won = false
    public private(set) var keepPlaying = false
    private var nextId = 1
    let startTiles = 2

    /// A new game, or the saved one carried on.
    public init(size: Int = 4, saved: State? = nil, using rng: inout some RandomNumberGenerator) {
        self.size = size
        cells = Array(repeating: Array(repeating: nil, count: size), count: size)
        setup(saved, using: &rng)
    }

    public init(size: Int = 4, saved: State? = nil) {
        var rng = SystemRandomNumberGenerator()
        self.init(size: size, saved: saved, using: &rng)
    }

    /// True if the game is lost, or has won and the player hasn't kept playing.
    public var terminated: Bool { over || (won && !keepPlaying) }

    /// What to keep: nil once the game is over (game over only, not a win).
    public var saved: State? {
        guard !over else { return nil }
        return State(size: size, cells: cells.map { column in
            column.map { tile in tile.map { State.SavedTile(position: $0.position, value: $0.value) } }
        }, score: score, over: over, won: won, keepPlaying: keepPlaying)
    }

    /// Tiles to draw after the last move, mergers' sources included (under
    /// the tile they made).
    public var tiles: [Tile] {
        var list: [Tile] = []
        for column in cells {
            for case let tile? in column {
                list.append(tile)
                if let from = tile.mergedFrom { list.append(contentsOf: from) }
            }
        }
        return list
    }

    public mutating func restart(using rng: inout some RandomNumberGenerator) {
        setup(nil, using: &rng)
    }

    public mutating func restart() {
        var rng = SystemRandomNumberGenerator()
        restart(using: &rng)
    }

    /// Keep playing after winning (allows going over 2048).
    public mutating func continuePlaying() { keepPlaying = true }

    private mutating func setup(_ previous: State?, using rng: inout some RandomNumberGenerator) {
        cells = Array(repeating: Array(repeating: nil, count: size), count: size)
        if let previous, previous.size == size, previous.cells.count == size {
            for x in 0..<size {
                for y in 0..<min(size, previous.cells[x].count) {
                    if let t = previous.cells[x][y] { cells[x][y] = newTile(Position(x: x, y: y), t.value) }
                }
            }
            score = previous.score
            over = previous.over
            won = previous.won
            keepPlaying = previous.keepPlaying
        } else {
            score = 0
            over = false
            won = false
            keepPlaying = false
            for _ in 0..<startTiles { addRandomTile(using: &rng) }
        }
    }

    private mutating func newTile(_ position: Position, _ value: Int) -> Tile {
        defer { nextId += 1 }
        return Tile(id: nextId, x: position.x, y: position.y, value: value)
    }

    // MARK: Grid

    public var availableCells: [Position] {
        var list: [Position] = []
        for x in 0..<size {
            for y in 0..<size where cells[x][y] == nil { list.append(Position(x: x, y: y)) }
        }
        return list
    }

    func withinBounds(_ p: Position) -> Bool { p.x >= 0 && p.x < size && p.y >= 0 && p.y < size }

    func cellContent(_ p: Position) -> Tile? { withinBounds(p) ? cells[p.x][p.y] : nil }

    private mutating func addRandomTile(using rng: inout some RandomNumberGenerator) {
        let available = availableCells
        guard !available.isEmpty else { return }
        let value = Double.random(in: 0..<1, using: &rng) < 0.9 ? 2 : 4
        let cell = available[Int(Double.random(in: 0..<1, using: &rng) * Double(available.count))]
        cells[cell.x][cell.y] = newTile(cell, value)
    }

    // MARK: Moving

    /// Moves every tile one way; returns whether anything moved (and so a
    /// tile was added).
    @discardableResult
    public mutating func move(_ direction: Direction, using rng: inout some RandomNumberGenerator) -> Bool {
        if terminated { return false } // Don't do anything if the game's over
        let vector = direction.vector
        var moved = false

        // Save the current tile positions and remove merger information
        for x in 0..<size {
            for y in 0..<size where cells[x][y] != nil {
                cells[x][y]!.mergedFrom = nil
                cells[x][y]!.previousPosition = cells[x][y]!.position
            }
        }

        // Traverse the grid in the right direction and move tiles
        var xs = Array(0..<size), ys = Array(0..<size)
        if vector.x == 1 { xs.reverse() }
        if vector.y == 1 { ys.reverse() }
        for x in xs {
            for y in ys {
                let cell = Position(x: x, y: y)
                guard var tile = cellContent(cell) else { continue }
                let (farthest, next) = findFarthestPosition(cell, vector)
                if let other = cellContent(next), other.value == tile.value, other.mergedFrom == nil {
                    // Converge the two tiles' positions
                    tile.x = next.x
                    tile.y = next.y
                    var merged = newTile(next, tile.value * 2)
                    merged.mergedFrom = [tile, other]
                    cells[next.x][next.y] = merged
                    cells[cell.x][cell.y] = nil
                    // Update the score
                    score += merged.value
                    // The mighty 2048 tile
                    if merged.value == 2048 { won = true }
                } else {
                    cells[cell.x][cell.y] = nil
                    tile.x = farthest.x
                    tile.y = farthest.y
                    cells[farthest.x][farthest.y] = tile
                }
                if cell != tile.position { moved = true } // The tile moved from its original cell!
            }
        }

        if moved {
            addRandomTile(using: &rng)
            if !movesAvailable { over = true } // Game over!
        }
        return moved
    }

    @discardableResult
    public mutating func move(_ direction: Direction) -> Bool {
        var rng = SystemRandomNumberGenerator()
        return move(direction, using: &rng)
    }

    private func findFarthestPosition(_ start: Position, _ vector: (x: Int, y: Int)) -> (farthest: Position, next: Position) {
        var previous: Position
        var cell = start
        // Progress towards the vector direction until an obstacle is found
        repeat {
            previous = cell
            cell = Position(x: previous.x + vector.x, y: previous.y + vector.y)
        } while withinBounds(cell) && cellContent(cell) == nil
        return (previous, cell)
    }

    public var movesAvailable: Bool { !availableCells.isEmpty || tileMatchesAvailable }

    /// Check for available matches between tiles (more expensive check)
    private var tileMatchesAvailable: Bool {
        for x in 0..<size {
            for y in 0..<size {
                guard let tile = cells[x][y] else { continue }
                for direction in Direction.allCases {
                    let v = direction.vector
                    if let other = cellContent(Position(x: x + v.x, y: y + v.y)), other.value == tile.value {
                        return true // These two tiles can be merged
                    }
                }
            }
        }
        return false
    }

    /// For tests: one row of tiles (left to right, 0 for none), the rest empty.
    public static func seeded(row: [Int]) -> Game2048 {
        let cells = (0..<4).map { x -> [State.SavedTile?] in
            [x < row.count && row[x] != 0 ? State.SavedTile(position: Position(x: x, y: 0), value: row[x]) : nil, nil, nil, nil]
        }
        return Game2048(saved: State(size: 4, cells: cells, score: 0, over: false, won: false, keepPlaying: false))
    }
}
