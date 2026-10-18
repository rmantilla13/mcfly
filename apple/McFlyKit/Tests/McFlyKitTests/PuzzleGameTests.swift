import XCTest
@testable import McFlyKit

/// 2048 and Traffic Jam, as the display's tst_games checks them: 2048's
/// merges and its saved game, and every Traffic Jam level solved at its par.
final class PuzzleGameTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "games-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: 2048

    func testGame2048MergesAndScores() {
        var rng = SeededRandom(1)
        var game = Game2048(using: &rng)
        XCTAssertEqual(game.tiles.count, 2) // a new game

        game = Game2048.seeded(row: [2, 2, 4, 4])
        XCTAssertTrue(game.move(.left, using: &rng))
        XCTAssertEqual(game.score, 12)
        XCTAssertEqual(game.cells[0][0]?.value, 4)
        XCTAssertEqual(game.cells[1][0]?.value, 8)
        XCTAssertEqual(game.availableCells.count, 13) // two merged tiles and a new one
        // The merged tiles say where they came from, for the slide.
        let eight = game.cells[1][0]!
        XCTAssertEqual(eight.mergedFrom?.map(\.value), [4, 4])
        XCTAssertEqual(eight.mergedFrom?.map(\.position), [eight.position, eight.position])
        XCTAssertEqual(eight.mergedFrom?.compactMap(\.previousPosition).map(\.x).sorted(), [2, 3])

        // One merge per tile a move: 2 2 2 2 makes 4 4, not 8.
        game = Game2048.seeded(row: [2, 2, 2, 2])
        game.move(.left, using: &rng)
        XCTAssertEqual(game.cells[0][0]?.value, 4)
        XCTAssertEqual(game.cells[1][0]?.value, 4)
        XCTAssertEqual(game.score, 8)

        // Nothing moves: no new tile.
        game = Game2048.seeded(row: [2, 4, 8, 16])
        XCTAssertFalse(game.move(.left, using: &rng))
        XCTAssertEqual(game.tiles.count, 4)
        XCTAssertTrue(game.move(.right, using: &rng) == false && game.move(.down, using: &rng))
    }

    func testGame2048WinThenKeepGoing() {
        var rng = SeededRandom(2)
        var game = Game2048.seeded(row: [1024, 1024])
        game.move(.left, using: &rng)
        XCTAssertTrue(game.won)
        XCTAssertTrue(game.terminated)
        XCTAssertFalse(game.move(.right, using: &rng)) // not until you choose to keep going
        game.continuePlaying()
        XCTAssertFalse(game.terminated)
        XCTAssertTrue(game.move(.right, using: &rng))
        game.restart(using: &rng)
        XCTAssertEqual(game.score, 0)
        XCTAssertFalse(game.won)
    }

    func testGame2048GameOverAndRemembers() {
        var rng = SeededRandom(3)
        let progress = GameProgress(defaults: defaults)
        var game = Game2048.seeded(row: [2, 2, 4, 4])
        game.move(.left, using: &rng)
        progress.best2048 = max(progress.best2048, game.score)
        progress.game2048 = game.saved

        // Closing saves the game; opening it again carries on.
        let reopened = Game2048(saved: progress.game2048)
        XCTAssertEqual(reopened.score, 12)
        XCTAssertEqual(reopened.cells[1][0]?.value, 8)
        XCTAssertEqual(progress.best2048, 12)

        // One gap and nothing to join: the last slide fills it, and the
        // game is over, and no longer kept.
        let rows = [[0, 8, 16, 8], [16, 32, 64, 32], [8, 64, 32, 64], [16, 128, 256, 128]]
        let cells = (0..<4).map { x in
            (0..<4).map { y in rows[y][x] == 0 ? nil : Game2048.State.SavedTile(position: .init(x: x, y: y), value: rows[y][x]) }
        }
        var stuck = Game2048(saved: Game2048.State(size: 4, cells: cells, score: 40, over: false, won: false, keepPlaying: false))
        XCTAssertTrue(stuck.movesAvailable)
        XCTAssertFalse(stuck.move(.right, using: &rng)) // nowhere to go that way
        XCTAssertTrue(stuck.move(.left, using: &rng))
        XCTAssertTrue(stuck.over)
        XCTAssertTrue(stuck.terminated)
        XCTAssertNil(stuck.saved)
        XCTAssertFalse(stuck.move(.up, using: &rng))
    }

    // MARK: Traffic Jam

    /// The fewest moves that solve a level, breadth first over Board's own
    /// moves (one car or truck any distance). A position is each piece's
    /// place along its lane, three bits apiece.
    private func fewestMoves(_ level: Int) -> Int? {
        let board = try! RushBoard(TrafficJam.levels[level].board) // swiftlint:disable:this force_try
        let pieces = board.pieces
        let n = pieces.count
        XCTAssertLessThanOrEqual(n, 21)
        // Each piece's cells at each place along its lane.
        let lines = pieces.map { $0.stride == 1 ? $0.position / 6 : $0.position % 6 } // its row or column
        let masks: [[UInt64]] = pieces.enumerated().map { i, p in
            (0...(6 - p.size)).map { at in
                var m: UInt64 = 0
                for k in 0..<p.size {
                    let cell = p.stride == 1 ? lines[i] * 6 + at + k : (at + k) * 6 + lines[i]
                    m |= 1 << UInt64(cell)
                }
                return m
            }
        }
        func place(_ state: UInt64, _ i: Int) -> Int { Int((state >> UInt64(3 * i)) & 7) }
        var start: UInt64 = 0
        for (i, p) in pieces.enumerated() {
            let at = p.stride == 1 ? p.position % 6 : p.position / 6
            start |= UInt64(at) << UInt64(3 * i)
        }
        let goal = 6 - pieces[0].size
        if place(start, 0) == goal { return 0 }
        var seen: Set<UInt64> = [start]
        var frontier = [start]
        var depth = 0
        while !frontier.isEmpty {
            depth += 1
            var next: [UInt64] = []
            for state in frontier {
                var occupied: UInt64 = 0
                for i in 0..<n { occupied |= masks[i][place(state, i)] }
                for i in 0..<n {
                    let at = place(state, i)
                    let own = occupied & ~masks[i][at]
                    for dir in [-1, 1] {
                        var to = at + dir
                        while to >= 0 && to < masks[i].count && masks[i][to] & own == 0 {
                            let moved = (state & ~(7 << UInt64(3 * i))) | (UInt64(to) << UInt64(3 * i))
                            if i == 0 && to == goal { return depth }
                            if seen.insert(moved).inserted { next.append(moved) }
                            to += dir
                        }
                    }
                }
            }
            frontier = next
        }
        return nil
    }

    func testTrafficJamLevelsAreRightAndSolvableAtTheirPar() {
        XCTAssertEqual(TrafficJam.levels.count, 40)
        var previous = 0
        for (i, level) in TrafficJam.levels.enumerated() {
            let board = try? RushBoard(level.board)
            XCTAssertNotNil(board, "level \(i + 1)")
            XCTAssertGreaterThanOrEqual(level.par, previous, "levels get harder")
            previous = level.par
            XCTAssertEqual(board?.isSolved, false)
            XCTAssertEqual(board?.primaryRow, 2)
            XCTAssertEqual(board?.pieces.first?.stride, 1) // the red car goes across
            XCTAssertEqual(fewestMoves(i), level.par, "level \(i + 1)")
        }
    }

    func testTrafficJamSlidesUndoesAndSolves() {
        var game = TrafficJam(level: 0)
        XCTAssertFalse(game.slide(0, -99)) // not a legal move
        // Level 1's solution, found by the same search: slide by slide.
        let path = solution(TrafficJam.levels[0].board)
        XCTAssertEqual(path.count, game.par)
        let before = game.board.pieces.map(\.position)
        XCTAssertTrue(game.slide(path[0].piece, path[0].steps))
        game.undo()
        XCTAssertEqual(game.board.pieces.map(\.position), before)
        XCTAssertEqual(game.moves, 0)
        for move in path { XCTAssertTrue(game.slide(move.piece, move.steps)) }
        XCTAssertTrue(game.solved)
        XCTAssertEqual(game.moves, path.count)
        XCTAssertEqual(TrafficJam.stars(moves: game.moves, par: game.par), 3)
        XCTAssertFalse(game.slide(1, 1)) // solved: the board is still
        XCTAssertEqual(TrafficJam.stars(moves: 6, par: 4), 2)
        XCTAssertEqual(TrafficJam.stars(moves: 7, par: 4), 1)
        XCTAssertEqual(TrafficJam.Band(par: 8), .beginner)
        XCTAssertEqual(TrafficJam.Band(par: 26), .expert)

        // Progress is kept: the level, and each level's fewest moves.
        let progress = GameProgress(defaults: defaults)
        progress.recordTraffic(level: 0, moves: 6)
        progress.recordTraffic(level: 0, moves: 4)
        progress.recordTraffic(level: 0, moves: 5)
        progress.trafficLevel = 1
        let again = GameProgress(defaults: defaults)
        XCTAssertEqual(again.trafficBest, [0: 4])
        XCTAssertEqual(again.trafficLevel, 1)
    }

    /// A shortest solution as Board moves, by breadth-first search.
    private func solution(_ desc: String) -> [RushBoard.Move] {
        let start = try! RushBoard(desc) // swiftlint:disable:this force_try
        var parent: [[Int]: ([Int], RushBoard.Move)] = [:]
        var seen: Set<[Int]> = [start.pieces.map(\.position)]
        var frontier = [start]
        while !frontier.isEmpty {
            var next: [RushBoard] = []
            for board in frontier {
                for move in board.moves {
                    var b = board
                    b.doMove(move)
                    let key = b.pieces.map(\.position)
                    guard seen.insert(key).inserted else { continue }
                    parent[key] = (board.pieces.map(\.position), move)
                    if b.isSolved {
                        var path: [RushBoard.Move] = []
                        var k = key
                        while let (from, m) = parent[k] {
                            path.insert(m, at: 0)
                            k = from
                        }
                        return path
                    }
                    next.append(b)
                }
            }
            frontier = next
        }
        return []
    }
}

/// Every game says how to play it and where it comes from; the ports of
/// MIT code carry the notice in full.
final class GameCatalogTests: XCTestCase {
    func testEveryGameHasItsWordsAndCredit() {
        for game in GameID.allCases {
            XCTAssertFalse(game.title.isEmpty)
            XCTAssertFalse(game.howTo.isEmpty)
            XCTAssertFalse(game.credit.isEmpty)
        }
        XCTAssertTrue(GameID.game2048.licence?.contains("Copyright (c) 2014 Gabriele Cirulli") ?? false)
        XCTAssertTrue(GameID.trafficJam.licence?.contains("Copyright (C) 2018 Michael Fogleman") ?? false)
        XCTAssertTrue(GameID.trafficJam.licence?.contains("shall be included in all copies or substantial portions") ?? false)
        XCTAssertNil(GameID.penguinMarch.licence)
        XCTAssertEqual(GameID.allCases.filter(\.timed), [.scoopShop, .penguinMarch])
    }
}
