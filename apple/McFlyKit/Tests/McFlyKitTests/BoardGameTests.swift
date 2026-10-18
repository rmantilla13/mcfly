import XCTest
@testable import McFlyKit

/// A repeatable generator for the games' random choices (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Tic-tac-toe and Four in a Row, as the display's tst_games checks them:
/// wins, draws, whose turn, and McFly's play.
final class BoardGameTests: XCTestCase {
    // MARK: Tic-tac-toe

    func testTicTacToeTwoPlayers() {
        var game = TicTacToe()
        // X: 0 1 2 across the top; O: 3 4.
        for cell in [0, 3, 1, 4, 2] { XCTAssertTrue(game.play(cell)) }
        XCTAssertEqual(game.winner, .x)
        XCTAssertEqual(game.winLine, [0, 1, 2])
        XCTAssertEqual(game.score.x, 1)
        XCTAssertFalse(game.play(5)) // the round is over

        // O starts the next round. A full board with no line is a draw.
        game.newRound()
        XCTAssertEqual(game.turn, .o)
        for cell in [1, 0, 4, 2, 5, 3, 6, 7, 8] { XCTAssertTrue(game.play(cell)) }
        XCTAssertTrue(game.draw)
        XCTAssertEqual(game.score.draws, 1)
    }

    /// Every game X can play against Hard McFly: X never gets three in a row.
    private func explore(_ board: [Mark?], xToMove: Bool, games: inout Int, rng: inout SeededRandom) {
        let won = TicTacToe.findLine(board).flatMap { board[$0[0]] }
        XCTAssertNotEqual(won, .x, "\(board)")
        if won != nil || !board.contains(nil) {
            games += 1
            return
        }
        if xToMove {
            for i in 0..<9 where board[i] == nil {
                var next = board
                next[i] = .x
                explore(next, xToMove: false, games: &games, rng: &rng)
            }
            return
        }
        let i = TicTacToe.bestMove(board, for: .o, using: &rng)
        XCTAssertNil(board[i])
        var next = board
        next[i] = .o
        explore(next, xToMove: true, games: &games, rng: &rng)
    }

    func testTicTacToeHardNeverLoses() {
        var rng = SeededRandom(1)
        var games = 0
        explore(Array(repeating: nil, count: 9), xToMove: true, games: &games, rng: &rng)   // X first
        explore(Array(repeating: nil, count: 9), xToMove: false, games: &games, rng: &rng)  // McFly first
        XCTAssertGreaterThan(games, 100)

        // Easy McFly answers a move.
        var game = TicTacToe()
        game.setMode(vsComputer: true, hard: false)
        XCTAssertEqual(game.turn, .x) // you start, then McFly the next round
        XCTAssertTrue(game.play(4))
        XCTAssertTrue(game.computerTurn)
        XCTAssertFalse(game.play(0)) // not while it's McFly's turn
        game.computerMove(using: &rng)
        XCTAssertEqual(game.turn, .x)
        XCTAssertEqual(game.cells.filter { $0 == .o }.count, 1)
        game.newRound()
        XCTAssertTrue(game.computerTurn)
    }

    // MARK: Four in a Row

    func testFourInARowTwoPlayers() {
        var game = FourInARow()
        XCTAssertEqual(game.turn, .x) // X starts, then each round the other
        // Discs stack; X takes column 0 straight up.
        for column in [0, 1, 0, 1, 0, 1] { XCTAssertTrue(game.play(column)) }
        XCTAssertEqual(game.cells[7], .x)
        XCTAssertEqual(game.cells[8], .o)
        XCTAssertNil(game.winner)
        XCTAssertTrue(game.play(0))
        XCTAssertEqual(game.winner, .x)
        XCTAssertEqual(game.winLine?.sorted(), [0, 7, 14, 21])
        XCTAssertEqual(game.score.x, 1)
        XCTAssertFalse(game.play(2)) // the round is over

        // O starts the next round, and takes the bottom row.
        game.newRound()
        XCTAssertEqual(game.turn, .o)
        for column in [0, 0, 1, 1, 2, 2, 3] { XCTAssertTrue(game.play(column)) }
        XCTAssertEqual(game.winner, .o)
        XCTAssertEqual(game.winLine?.sorted(), [0, 1, 2, 3])
        XCTAssertEqual(game.score.o, 1)

        // A full column takes no more.
        game.newRound()
        for _ in 0..<6 { XCTAssertTrue(game.play(6)) }
        let turn = game.turn
        XCTAssertFalse(game.play(6))
        XCTAssertEqual(game.turn, turn)

        // Corner to corner, both ways.
        game.setRack([".......", ".......", ".......", "..XO...", ".XOO...", "XOOX..."], turn: .x)
        XCTAssertTrue(game.play(3))
        XCTAssertEqual(game.winLine?.sorted(), [0, 8, 16, 24])
        game.setRack([".......", ".......", ".......", "OX.....", "OOX....", "XOOX..."], turn: .x)
        XCTAssertTrue(game.play(0))
        XCTAssertEqual(game.winLine?.sorted(), [3, 9, 15, 21])

        // A full board with no line is a draw.
        game.setRack(["OXOXOX.", "OXOXOXO", "OXOXOXO", "XOXOXOX", "XOXOXOX", "XOXOXOX"], turn: .o)
        let draws = game.score.draws
        XCTAssertTrue(game.play(6))
        XCTAssertTrue(game.draw)
        XCTAssertTrue(game.over)
        XCTAssertEqual(game.score.draws, draws + 1)
    }

    private func hardMove(_ rack: [String], _ rng: inout SeededRandom) -> Int? {
        var game = FourInARow()
        game.setRack(rack, turn: .o)
        var engine = FourInARowEngine()
        return engine.bestMove(game.cells, for: .o, depth: FourInARow.hardDepth, using: &rng)
    }

    func testFourInARowHardTakesAWinAndBlocks() {
        var rng = SeededRandom(2)
        // Takes a win when it has one.
        XCTAssertEqual(hardMove([".......", ".......", ".......", ".......", "XX.....", "OOO.XX."], &rng), 3)
        // Blocks yours.
        XCTAssertEqual(hardMove([".......", ".......", ".......", ".......", "O.....O", "XXX...O"], &rng), 3)
        // Won't drop a disc that lets you win on top of it.
        for _ in 0..<5 {
            XCTAssertNotEqual(hardMove([".......", ".......", ".......", ".......", "XXX...O", "OOX...O"], &rng), 3)
        }
    }

    /// The display's C++ engine weighs exactly these many positions on these
    /// boards (display/src/games/FourInARowEngine.cpp, run on the same
    /// boards): the same move order and the same cuts, so the same play.
    func testFourInARowSearchesAsTheDisplayDoes() {
        let cases: [(rack: [String], player: Mark, depth: Int, nodes: Int, moves: Set<Int>)] = [
            (Array(repeating: ".......", count: 6), .o, 10, 111_856, [3]),
            (Array(repeating: ".......", count: 6), .o, 42, 600_001, [3]),
            ([".......", ".......", "...O...", "..XX...", "..OXO..", ".XOXO.."], .o, 10, 187_130, [4]),
            ([".......", ".......", ".......", ".......", "XX.....", "OOO.XX."], .o, 10, 6, [3]),
            ([".......", ".......", ".......", ".......", "O.....O", "XXX...O"], .o, 10, 223_452, [3]),
            ([".......", ".......", ".......", ".......", "XXX...O", "OOX...O"], .o, 10, 600_001, [2]),
            ([".......", ".......", ".......", ".......", ".......", "...X..."], .o, 2, 27, [3]),
            ([".......", ".......", ".......", ".......", ".......", "...X..."], .o, 6, 2971, [3]),
            ([".......", ".......", ".......", "..X....", "..OX...", ".XOOX.O"], .x, 8, 28119, [2, 3]),
        ]
        var rng = SeededRandom(3)
        for (i, c) in cases.enumerated() {
            var game = FourInARow()
            game.setRack(c.rack, turn: c.player)
            var engine = FourInARowEngine()
            var seen = Set<Int>()
            for _ in 0..<4 {
                if let move = engine.bestMove(game.cells, for: c.player, depth: c.depth, using: &rng) { seen.insert(move) }
                XCTAssertEqual(engine.lastNodes, c.nodes, "board \(i)")
            }
            XCTAssertTrue(seen.isSubset(of: c.moves), "board \(i): \(seen)")
        }
    }

    /// Hard never loses to someone dropping discs at random.
    func testFourInARowHardBeatsRandomPlay() {
        var rng = SeededRandom(4)
        var wins = 0
        let matches = 12
        for i in 0..<matches {
            var board = [Mark?](repeating: nil, count: 42)
            var turn: Mark = i % 2 == 0 ? .x : .o
            var engine = FourInARowEngine()
            var result: Mark?
            while true {
                let open = (0..<7).filter { FourInARow.landing(board, $0) != nil }
                if open.isEmpty { break }
                let column = turn == .o ? engine.bestMove(board, for: .o, depth: FourInARow.hardDepth, using: &rng)!
                                        : open.randomElement(using: &rng)!
                let at = FourInARow.landing(board, column)!
                board[at] = turn
                if FourInARow.lineThrough(board, at) != nil {
                    result = turn
                    break
                }
                turn = turn.other
            }
            XCTAssertNotEqual(result, .x, "random play beat Hard")
            if result == .o { wins += 1 }
        }
        XCTAssertGreaterThanOrEqual(wins, matches - 1)
    }

    func testFourInARowEasyMcFlyAnswers() {
        var rng = SeededRandom(5)
        var game = FourInARow()
        game.setMode(vsComputer: true, hard: false)
        XCTAssertEqual(game.turn, .x)
        XCTAssertNil(game.computerColumn(using: &rng)) // not McFly's turn
        XCTAssertTrue(game.play(3))
        XCTAssertFalse(game.play(3)) // McFly's turn now
        let column = game.computerColumn(using: &rng)
        XCTAssertNotNil(column)
        XCTAssertTrue(game.place(column!))
        XCTAssertEqual(game.turn, .x)
        XCTAssertEqual(game.cells.filter { $0 == .o }.count, 1)
    }
}
