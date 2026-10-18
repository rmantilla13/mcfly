import Foundation

/// X or O: a square's mark in tic-tac-toe, a disc's colour in Four in a Row.
public enum Mark: String, Sendable, Codable {
    case x = "X", o = "O"

    public var other: Mark { self == .x ? .o : .x }
}

/// Wins for each side and draws, kept until the game is closed.
public struct Score: Sendable, Equatable {
    public var x = 0, o = 0, draws = 0

    public init() {}

    public subscript(_ mark: Mark) -> Int { mark == .x ? x : o }

    mutating func count(_ winner: Mark?) {
        switch winner {
        case .x: x += 1
        case .o: o += 1
        case nil: draws += 1
        }
    }
}

/// Tic-tac-toe for two people at the screen, or one against McFly, the
/// display's (display/qml/games/TicTacToe.qml). Easy McFly often plays at
/// random; Hard looks ahead to the end (minimax) and never loses. Who goes
/// first alternates every round, and the score is kept until the game is
/// closed.
public struct TicTacToe: Sendable {
    public static let lines = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

    public private(set) var cells = [Mark?](repeating: nil, count: 9)
    public private(set) var turn = Mark.x
    public private(set) var starter = Mark.x
    public private(set) var winLine: [Int]?
    public private(set) var score = Score()
    public private(set) var vsComputer = false
    public private(set) var hard = false

    public init() {}

    public var draw: Bool { winLine == nil && cells.allSatisfy { $0 != nil } }
    public var over: Bool { winLine != nil || draw }
    public var winner: Mark? { winLine.flatMap { cells[$0[0]] } }
    public var computerTurn: Bool { vsComputer && turn == .o && !over }

    /// Who plays and how hard: the score starts over, and McFly starts.
    public mutating func setMode(vsComputer: Bool, hard: Bool) {
        self.vsComputer = vsComputer
        self.hard = hard
        reset()
    }

    public static func findLine(_ board: [Mark?]) -> [Int]? {
        lines.first { l in board[l[0]] != nil && board[l[0]] == board[l[1]] && board[l[0]] == board[l[2]] }
    }

    /// The best square for `player`: wins soonest, loses latest, and picks at
    /// random between equally good squares so games don't repeat.
    public static func bestMove(_ board: [Mark?], for player: Mark, using rng: inout some RandomNumberGenerator) -> Int {
        var board = board
        let empty = board.indices.filter { board[$0] == nil }
        if empty.count == 9 { return [0, 2, 4, 6, 8].randomElement(using: &rng)! } // every opening draws
        func value(_ turnNow: Mark, _ depth: Int) -> Int {
            if let line = findLine(board) { return board[line[0]] == player ? 10 - depth : depth - 10 }
            if board.allSatisfy({ $0 != nil }) { return 0 }
            var best = turnNow == player ? -100 : 100
            for i in 0..<9 where board[i] == nil {
                board[i] = turnNow
                let v = value(turnNow.other, depth + 1)
                board[i] = nil
                best = turnNow == player ? max(best, v) : min(best, v)
            }
            return best
        }
        var top = -1000
        var choices: [Int] = []
        for i in empty {
            board[i] = player
            let v = value(player.other, 1)
            board[i] = nil
            if v > top {
                top = v
                choices = [i]
            } else if v == top {
                choices.append(i)
            }
        }
        return choices.randomElement(using: &rng)!
    }

    @discardableResult
    mutating func place(_ cell: Int) -> Bool {
        guard !over, cells.indices.contains(cell), cells[cell] == nil else { return false }
        cells[cell] = turn
        winLine = Self.findLine(cells)
        if over {
            score.count(winner)
        } else {
            turn = turn.other
        }
        return true
    }

    /// A tap on the board: the person whose turn it is.
    @discardableResult
    public mutating func play(_ cell: Int) -> Bool {
        guard !computerTurn else { return false }
        return place(cell)
    }

    /// McFly's move, when it's McFly's turn.
    public mutating func computerMove(using rng: inout some RandomNumberGenerator) {
        guard computerTurn else { return }
        let empty = cells.indices.filter { cells[$0] == nil }
        let random = !hard && Double.random(in: 0..<1, using: &rng) < 0.55
        place(random ? empty.randomElement(using: &rng)! : Self.bestMove(cells, for: .o, using: &rng))
    }

    public mutating func computerMove() {
        var rng = SystemRandomNumberGenerator()
        computerMove(using: &rng)
    }

    public mutating func newRound() {
        starter = starter.other
        cells = Array(repeating: nil, count: 9)
        winLine = nil
        turn = starter
    }

    public mutating func reset() {
        score = Score()
        starter = .o
        newRound()
    }
}
