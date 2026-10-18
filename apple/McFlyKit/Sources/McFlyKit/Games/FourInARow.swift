import Foundation

/// Four in a row for two people at the screen, or one against McFly, the
/// display's (display/qml/games/FourInARow.qml). Tap a column and the disc
/// drops to the lowest free hole; four of a colour in a line, across, down or
/// corner to corner, wins. Easy McFly often plays at random and otherwise
/// looks two discs ahead; Hard up to ten. Who goes first alternates every
/// round, and the score is kept until the game is closed.
public struct FourInARow: Sendable {
    public static let columns = 7
    public static let rows = 6
    /// How many discs ahead Hard McFly looks, at most.
    public static let hardDepth = 10

    /// The holes, bottom row first: index = row * columns + column.
    public private(set) var cells = [Mark?](repeating: nil, count: 42)
    public private(set) var turn = Mark.x
    public private(set) var starter = Mark.x
    public private(set) var winLine: [Int]?
    /// The hole the last disc dropped into.
    public private(set) var lastMove: Int?
    public private(set) var score = Score()
    public private(set) var vsComputer = false
    public private(set) var hard = false

    public init() {}

    public var draw: Bool { winLine == nil && cells.allSatisfy { $0 != nil } }
    public var over: Bool { winLine != nil || draw }
    public var winner: Mark? { winLine.flatMap { cells[$0[0]] } }
    public var computerTurn: Bool { vsComputer && turn == .o && !over }

    public mutating func setMode(vsComputer: Bool, hard: Bool) {
        self.vsComputer = vsComputer
        self.hard = hard
        reset()
    }

    /// The hole a disc dropped in `column` lands in, or nil when it is full.
    public static func landing(_ board: [Mark?], _ column: Int) -> Int? {
        (0..<rows).lazy.map { $0 * columns + column }.first { board[$0] == nil }
    }

    /// The run of four or more through hole `i`, in order, or nil.
    public static func lineThrough(_ board: [Mark?], _ i: Int) -> [Int]? {
        guard let p = board[i] else { return nil }
        let c0 = i % columns, r0 = i / columns
        for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
            var line = [i]
            for s in [1, -1] {
                var c = c0 + dc * s, r = r0 + dr * s
                while c >= 0 && c < columns && r >= 0 && r < rows && board[r * columns + c] == p {
                    if s > 0 { line.append(r * columns + c) } else { line.insert(r * columns + c, at: 0) }
                    c += dc * s
                    r += dr * s
                }
            }
            if line.count >= 4 { return line }
        }
        return nil
    }

    @discardableResult
    public mutating func place(_ column: Int) -> Bool {
        guard !over, (0..<Self.columns).contains(column), let at = Self.landing(cells, column) else { return false }
        cells[at] = turn
        lastMove = at
        winLine = Self.lineThrough(cells, at)
        if over {
            score.count(winner)
        } else {
            turn = turn.other
        }
        return true
    }

    /// A tap on a column: the person whose turn it is.
    @discardableResult
    public mutating func play(_ column: Int) -> Bool {
        guard !computerTurn else { return false }
        return place(column)
    }

    /// The column McFly picks on this board: Easy often at random, else a
    /// look two discs ahead; Hard ten. Pure, so it can run off the main
    /// thread while McFly "thinks"; `place` it after.
    public func computerColumn(using rng: inout some RandomNumberGenerator) -> Int? {
        guard computerTurn else { return nil }
        let open = (0..<Self.columns).filter { Self.landing(cells, $0) != nil }
        guard !open.isEmpty else { return nil }
        if !hard && Double.random(in: 0..<1, using: &rng) < 0.4 { return open.randomElement(using: &rng) }
        var engine = FourInARowEngine()
        return engine.bestMove(cells, for: .o, depth: hard ? Self.hardDepth : 2, using: &rng)
    }

    public mutating func newRound() {
        starter = starter.other
        cells = Array(repeating: nil, count: 42)
        winLine = nil
        lastMove = nil
        turn = starter
    }

    public mutating func reset() {
        score = Score()
        starter = .o
        newRound()
    }

    /// For tests: a position, top row first ("X", "O", anything else empty),
    /// and whose turn it is.
    public mutating func setRack(_ picture: [String], turn: Mark) {
        cells = Array(repeating: nil, count: 42)
        for (r, row) in picture.reversed().enumerated() {
            for (c, ch) in row.enumerated() where c < Self.columns {
                cells[r * Self.columns + c] = Mark(rawValue: String(ch))
            }
        }
        winLine = nil
        lastMove = nil
        self.turn = turn
    }
}

/// McFly's look-ahead in Four in a Row, the display's C++ engine
/// (display/src/games/FourInARowEngine.cpp) in Swift: negamax with
/// alpha-beta on bitboards, the middle columns first. Hard's look of up to
/// ten discs ahead is capped at 600,000 positions a move, keeping the
/// deepest look it finished, so a tangled board stays quick.
public struct FourInARowEngine: Sendable {
    // Bitboards: bit column * 7 + row, row 0 at the bottom. Each column has a
    // spare bit on top, so a line can't run from one column into the next.
    private static let columns = 7
    private static let rows = 6
    private static let stride = rows + 1
    private static let order = [3, 2, 4, 1, 5, 0, 6] // the middle first
    private static let win = 1_000_000
    /// The most positions one move may weigh.
    public static let nodeCap = 600_000

    /// Positions weighed by the last bestMove(), for the tests.
    public private(set) var lastNodes = 0
    private var aborted = false

    public init() {}

    private static func bit(_ column: Int, _ row: Int) -> UInt64 { 1 << UInt64(column * stride + row) }
    private static func bottom(_ column: Int) -> UInt64 { bit(column, 0) }
    private static func top(_ column: Int) -> UInt64 { bit(column, rows - 1) }
    private static func columnMask(_ column: Int) -> UInt64 { ((1 << UInt64(rows)) - 1) << UInt64(column * stride) }
    private static let middle = columnMask(3)
    private static let tops = (0..<columns).map { top($0) }
    private static let bottoms = (0..<columns).map { bottom($0) }
    private static let masks = (0..<columns).map { columnMask($0) }

    private static func fourInARow(_ b: UInt64) -> Bool {
        for shift in [UInt64(1), UInt64(stride), UInt64(stride - 1), UInt64(stride + 1)] { // down, across, both diagonals
            let pairs = b & (b >> shift)
            if pairs & (pairs >> (2 * shift)) != 0 { return true }
        }
        return false
    }

    /// Every line of four holes on the board, as masks.
    private static let windows: [UInt64] = {
        var w: [UInt64] = []
        for c in 0..<columns {
            for r in 0..<rows {
                for (sc, sr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                    let endC = c + 3 * sc, endR = r + 3 * sr
                    guard endC >= 0, endC < columns, endR >= 0, endR < rows else { continue }
                    var mask: UInt64 = 0
                    for k in 0..<4 { mask |= bit(c + k * sc, r + k * sr) }
                    w.append(mask)
                }
            }
        }
        return w
    }()

    /// How good the board looks for `mine`: open threes and twos, and the
    /// middle column, which takes part in the most lines.
    private static func evaluate(_ mine: UInt64, _ theirs: UInt64) -> Int {
        var total = 0
        windows.withUnsafeBufferPointer { list in
            for w in list {
                let a = (mine & w).nonzeroBitCount, b = (theirs & w).nonzeroBitCount
                if b == 0 {
                    total += a == 3 ? 5 : a == 2 ? 2 : 0
                } else if a == 0 {
                    total -= b == 3 ? 4 : b == 2 ? 2 : 0
                }
            }
        }
        return total + 3 * ((mine & middle).nonzeroBitCount - (theirs & middle).nonzeroBitCount)
    }

    /// Negamax with alpha-beta: the value of the board for `mine`, to move.
    private mutating func search(_ mine: UInt64, _ theirs: UInt64, _ left: Int, _ ply: Int, _ alphaIn: Int, _ beta: Int) -> Int {
        if aborted { return 0 }
        lastNodes += 1
        if lastNodes > Self.nodeCap {
            aborted = true
            return 0
        }
        if left == 0 { return Self.evaluate(mine, theirs) }
        let both = mine | theirs
        var alpha = alphaIn
        var best = Int.min
        for c in Self.order {
            if both & Self.tops[c] != 0 { continue }
            let drop = (both &+ Self.bottoms[c]) & Self.masks[c]
            let next = mine | drop
            let v = Self.fourInARow(next) ? Self.win - ply : -search(theirs, next, left - 1, ply + 1, -beta, -alpha)
            if v > best { best = v }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return best == Int.min ? 0 : best // a full board: a draw
    }

    /// The column `player` should drop a disc in, looking up to `depth`
    /// discs ahead: wins soonest, loses latest, and picks at random between
    /// equally good columns so games don't repeat. Nil when the board is full.
    public mutating func bestMove(_ cells: [Mark?], for player: Mark, depth: Int,
                                  using rng: inout some RandomNumberGenerator) -> Int? {
        lastNodes = 0
        var mine: UInt64 = 0, theirs: UInt64 = 0
        for i in 0..<min(cells.count, Self.columns * Self.rows) {
            guard let mark = cells[i] else { continue }
            if mark == player { mine |= Self.bit(i % Self.columns, i / Self.columns) } else { theirs |= Self.bit(i % Self.columns, i / Self.columns) }
        }
        let both = mine | theirs
        let legal = Self.order.filter { both & Self.tops[$0] == 0 }
        guard !legal.isEmpty else { return nil }

        // A disc deeper each time, keeping the last look that finished: a
        // tangled board stops short of `depth` rather than hold the screen.
        var choices = legal
        aborted = false
        for d in 1...max(1, depth) {
            var bestValue = Int.min
            var found: [Int] = []
            for c in legal {
                let next = mine | ((both &+ Self.bottoms[c]) & Self.masks[c])
                var v = Self.win - 1
                if !Self.fourInARow(next) {
                    // A column only has to be shown worse than the best so far;
                    // one as good comes back exact, so ties are found.
                    let alpha = found.isEmpty ? -Self.win - 1 : bestValue - 1
                    v = -search(theirs, next, d - 1, 2, -Self.win - 1, -alpha)
                }
                if aborted { break }
                if v > bestValue {
                    bestValue = v
                    found = [c]
                } else if v == bestValue {
                    found.append(c)
                }
            }
            if aborted { break }
            choices = found
            // A sure win or loss won't change with a deeper look.
            if abs(bestValue) >= Self.win - Self.columns * Self.rows { break }
        }
        return choices.randomElement(using: &rng)
    }

    public mutating func bestMove(_ cells: [Mark?], for player: Mark, depth: Int) -> Int? {
        var rng = SystemRandomNumberGenerator()
        return bestMove(cells, for: player, depth: depth, using: &rng)
    }
}
