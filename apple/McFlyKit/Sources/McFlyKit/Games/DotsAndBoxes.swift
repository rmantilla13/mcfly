import Foundation

/// Dots and boxes for two people at the screen, or one against McFly, the
/// display's (display/qml/games/DotsAndBoxes.qml). Take turns drawing a line
/// between two dots; the line that closes a box claims it, and the same
/// player goes again. Most boxes wins.
///
/// Easy McFly often draws at random. Hard takes every box it can, never
/// gives a box its third side while it has a choice, then hands over the
/// smallest chain it can and, with longer chains still to come, leaves the
/// last two boxes of a chain to keep the next one for itself. Who goes first
/// alternates every round, and the score is kept until the game is closed.
///
/// The lines: the across ones row by row ((size + 1) × size), then the down
/// ones (size × (size + 1)). Boxes row by row.
public struct DotsAndBoxes: Sendable {
    /// Boxes across and down.
    public static let sizes = [3, 4, 5]

    public private(set) var size = 4
    public private(set) var vsComputer = false
    public private(set) var hard = false
    /// Who drew each line, nil while undrawn.
    public private(set) var lines: [Mark?]
    /// Who closed each box.
    public private(set) var boxes: [Mark?]
    public private(set) var turn = Mark.x
    public private(set) var starter = Mark.x
    public private(set) var score = Score()
    /// The line drawn last, so a move made across the room is easy to find.
    public private(set) var lastLine: Int?

    public init() {
        lines = Array(repeating: nil, count: 2 * size * (size + 1))
        boxes = Array(repeating: nil, count: size * size)
    }

    public var rows: Int { size }
    public var columns: Int { size }
    public var across: Int { (rows + 1) * columns }
    public var lineCount: Int { lines.count }
    public var xBoxes: Int { boxes.filter { $0 == .x }.count }
    public var oBoxes: Int { boxes.filter { $0 == .o }.count }
    public var over: Bool { boxes.allSatisfy { $0 != nil } }
    /// The winner once it's over; nil for a draw.
    public var winner: Mark? { over && xBoxes != oBoxes ? (xBoxes > oBoxes ? .x : .o) : nil }
    public var computerTurn: Bool { vsComputer && turn == .o && !over }

    public func acrossLine(_ r: Int, _ c: Int) -> Int { r * columns + c }
    public func downLine(_ r: Int, _ c: Int) -> Int { across + r * (columns + 1) + c }

    /// The four lines around box `b`: top, bottom, left, right.
    public func sides(of b: Int) -> [Int] {
        let r = b / columns, c = b % columns
        return [acrossLine(r, c), acrossLine(r + 1, c), downLine(r, c), downLine(r, c + 1)]
    }

    /// The one or two boxes beside line `l`.
    public func boxes(beside l: Int) -> [Int] {
        var out: [Int] = []
        if l < across {
            let r = l / columns, c = l % columns
            if r > 0 { out.append((r - 1) * columns + c) }
            if r < rows { out.append(r * columns + c) }
        } else {
            let i = l - across, r = i / (columns + 1), c = i % (columns + 1)
            if c > 0 { out.append(r * columns + c - 1) }
            if c < columns { out.append(r * columns + c) }
        }
        return out
    }

    private func drawn(around b: Int, _ lines: [Mark?]) -> Int {
        sides(of: b).filter { lines[$0] != nil }.count
    }

    /// Draws line `l` for `player` on plain arrays; returns how many boxes it closed.
    private func draw(_ l: Int, by player: Mark, lines: inout [Mark?], boxes: inout [Mark?]) -> Int {
        lines[l] = player
        var closed = 0
        for b in self.boxes(beside: l) where drawn(around: b, lines) == 4 {
            boxes[b] = player
            closed += 1
        }
        return closed
    }

    @discardableResult
    public mutating func place(_ l: Int) -> Bool {
        guard !over, lines.indices.contains(l), lines[l] == nil else { return false }
        let closed = draw(l, by: turn, lines: &lines, boxes: &boxes)
        lastLine = l
        if over {
            score.count(winner)
        } else if closed == 0 {
            turn = turn.other
        }
        return true
    }

    /// A tap on the board: the person whose turn it is.
    @discardableResult
    public mutating func play(_ l: Int) -> Bool {
        guard !computerTurn else { return false }
        return place(l)
    }

    public mutating func newRound() {
        starter = starter.other
        lines = Array(repeating: nil, count: 2 * size * (size + 1))
        boxes = Array(repeating: nil, count: size * size)
        lastLine = nil
        turn = starter
    }

    public mutating func reset() {
        score = Score()
        starter = .o
        newRound()
    }

    /// Who plays, how hard and how big: the score starts over, you first.
    public mutating func setMode(vsComputer: Bool, hard: Bool, size: Int) {
        self.vsComputer = vsComputer
        self.hard = hard
        if Self.sizes.contains(size) { self.size = size }
        reset()
    }

    // MARK: McFly

    /// The undrawn lines that close a box, that give no box its third side,
    /// and the rest.
    public func sortLines(_ lines: [Mark?]) -> (closing: [Int], safe: [Int], giving: [Int]) {
        var closing: [Int] = [], safe: [Int] = [], giving: [Int] = []
        for l in lines.indices where lines[l] == nil {
            let counts = boxes(beside: l).map { drawn(around: $0, lines) }
            if counts.contains(3) {
                closing.append(l)
            } else if counts.allSatisfy({ $0 < 2 }) {
                safe.append(l)
            } else {
                giving.append(l)
            }
        }
        return (closing, safe, giving)
    }

    /// How many boxes the other player takes, greedily, after line `l`.
    private func handedOver(_ l: Int) -> Int {
        var d = lines, o = boxes
        d[l] = .o
        var taken = 0
        while let next = sortLines(d).closing.first {
            taken += draw(next, by: .x, lines: &d, boxes: &o)
        }
        return taken
    }

    /// The open boxes reachable from `b` through undrawn lines between boxes.
    private func chain(of b: Int) -> Set<Int> {
        var reached: Set<Int> = [b], todo = [b]
        while let at = todo.popLast() {
            for l in sides(of: at) where lines[l] == nil {
                for next in boxes(beside: l) where boxes[next] == nil && reached.insert(next).inserted {
                    todo.append(next)
                }
            }
        }
        return reached
    }

    /// The line McFly draws.
    public func bestLine(using rng: inout some RandomNumberGenerator) -> Int? {
        let sorted = sortLines(lines)
        if !hard {
            if !sorted.closing.isEmpty, Double.random(in: 0..<1, using: &rng) < 0.75 {
                return sorted.closing.randomElement(using: &rng)
            }
            if !sorted.safe.isEmpty, Double.random(in: 0..<1, using: &rng) < 0.6 {
                return sorted.safe.randomElement(using: &rng)
            }
            return (sorted.closing + sorted.safe + sorted.giving).randomElement(using: &rng)
        }
        if !sorted.closing.isEmpty {
            // Keep control: with no safe line left after this chain, and a
            // chain of two closing, give those two away when a longer chain
            // waits (the other player has to open it after).
            if sorted.safe.isEmpty, sorted.closing.count == 1,
               let b = boxes(beside: sorted.closing[0]).first(where: { drawn(around: $0, lines) == 3 }) {
                let here = chain(of: b)
                if here.count == 2 {
                    var longest = 0, counted = Set<Int>()
                    for i in boxes.indices where boxes[i] == nil && !here.contains(i) && !counted.contains(i) {
                        let c = chain(of: i)
                        counted.formUnion(c)
                        longest = max(longest, c.count)
                    }
                    if longest >= 3, let other = here.first(where: { $0 != b }),
                       // The far side of the second box, not the line between them.
                       let far = sides(of: other).first(where: { lines[$0] == nil && !boxes(beside: $0).contains(b) }) {
                        return far
                    }
                }
            }
            return sorted.closing.randomElement(using: &rng)
        }
        if !sorted.safe.isEmpty { return sorted.safe.randomElement(using: &rng) }
        // Only lines that give boxes away: the fewest, and between equals one
        // between two boxes, so a chain of two can't be split to keep control.
        var fewest = Int.max, choices: [Int] = []
        for l in sorted.giving {
            let n = handedOver(l) * 2 + (boxes(beside: l).count == 2 ? 0 : 1)
            if n < fewest {
                fewest = n
                choices = [l]
            } else if n == fewest {
                choices.append(l)
            }
        }
        return choices.randomElement(using: &rng)
    }

    /// McFly's line, when it's McFly's turn.
    public mutating func computerMove(using rng: inout some RandomNumberGenerator) {
        guard computerTurn, let l = bestLine(using: &rng) else { return }
        place(l)
    }

    public mutating func computerMove() {
        var rng = SystemRandomNumberGenerator()
        computerMove(using: &rng)
    }

    // MARK: Testing

    /// Lays out a board (the tests'): who drew each line and owns each box.
    mutating func set(lines: [Mark?], boxes: [Mark?], turn: Mark) {
        self.lines = lines
        self.boxes = boxes
        self.turn = turn
    }
}
