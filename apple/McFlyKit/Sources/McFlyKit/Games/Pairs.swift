import Foundation

/// Pairs, the display's (display/qml/games/Pairs.qml): the cards lie face
/// down, two of every picture. Turn two over; a pair stays up and the same
/// player goes again, two that don't match turn back. Alone it counts the
/// turns (the fewest for each size of board are kept); two people at the
/// screen, or one against McFly, take turns and count pairs. Easy McFly
/// remembers about a third of what it sees, Hard all of it.
///
/// The pictures are Color by Number's, painted in, each from a different
/// shelf so no two pairs look alike.
public struct Pairs: Sendable {
    public enum Mode: String, Sendable, CaseIterable {
        case solo, two, mcfly
    }

    /// How many cards a board can have.
    public static let sizes = [12, 16, 20]

    public private(set) var mode = Mode.solo
    public private(set) var hard = false
    public private(set) var size = 16
    /// Per card: its picture (a `ColorByNumber.pictures` index).
    public private(set) var faces: [Int] = []
    /// Per card: who found it (X alone), nil while it's still down.
    public private(set) var found: [Mark?] = []
    /// The cards turned up this turn and not yet a pair: none, one or two.
    public private(set) var up: [Int] = []
    public private(set) var turn = Mark.x
    public private(set) var starter = Mark.x
    public private(set) var score = Score()
    /// Turns taken alone (a turn is two cards).
    public private(set) var moves = 0
    /// What McFly has seen: card → picture.
    public private(set) var seen: [Int: Int] = [:]

    public init() {
        var rng = SystemRandomNumberGenerator()
        deal(using: &rng)
    }

    public var solo: Bool { mode == .solo }
    public var vsComputer: Bool { mode == .mcfly }
    public var pairsLeft: Int { faces.count / 2 - found.compactMap { $0 }.count / 2 }
    public var over: Bool { !faces.isEmpty && pairsLeft == 0 }
    /// Two cards up that don't match, waiting to turn back.
    public var missed: Bool { up.count == 2 }
    public var computerTurn: Bool { vsComputer && turn == .o && !over }
    /// Who won once it's over (not alone): nil for a draw.
    public var winner: Mark? {
        guard over, !solo, score.x != score.o else { return nil }
        return score.x > score.o ? .x : .o
    }

    /// A new board: one picture from each of `size / 2` shelves, twice over.
    /// Who goes first alternates every round.
    public mutating func deal(using rng: inout some RandomNumberGenerator) {
        let shelves = ColorByNumber.categories.map(\.id).shuffled(using: &rng).prefix(size / 2)
        let pictures = shelves.compactMap { ColorByNumber.pictures(in: $0).randomElement(using: &rng) }
        faces = (pictures + pictures).shuffled(using: &rng)
        found = Array(repeating: nil, count: faces.count)
        up = []
        seen = [:]
        moves = 0
        score = Score()
        starter = starter.other
        turn = solo ? .x : starter
    }

    public mutating func deal() {
        var rng = SystemRandomNumberGenerator()
        deal(using: &rng)
    }

    /// Who plays and how hard: a new board, you first.
    public mutating func setMode(_ mode: Mode, hard: Bool, using rng: inout some RandomNumberGenerator) {
        let changed = mode != self.mode
        self.mode = mode
        self.hard = hard
        if changed { starter = .o }
        deal(using: &rng)
    }

    public mutating func setMode(_ mode: Mode, hard: Bool) {
        var rng = SystemRandomNumberGenerator()
        setMode(mode, hard: hard, using: &rng)
    }

    public mutating func setSize(_ size: Int, using rng: inout some RandomNumberGenerator) {
        guard Self.sizes.contains(size) else { return }
        self.size = size
        deal(using: &rng)
    }

    public mutating func setSize(_ size: Int) {
        var rng = SystemRandomNumberGenerator()
        setSize(size, using: &rng)
    }

    /// McFly sees every card turned up; Easy keeps about a third of them.
    private mutating func remember(_ i: Int, using rng: inout some RandomNumberGenerator) {
        guard vsComputer, hard || Double.random(in: 0..<1, using: &rng) < 0.35 else { return }
        seen[i] = faces[i]
    }

    /// Turns card `i` up for whoever's turn it is.
    @discardableResult
    public mutating func flip(_ i: Int, using rng: inout some RandomNumberGenerator) -> Bool {
        guard !over, faces.indices.contains(i), found[i] == nil, !up.contains(i) else { return false }
        if missed { hideNow() }
        up.append(i)
        remember(i, using: &rng)
        guard up.count == 2 else { return true }
        if solo { moves += 1 }
        let a = up[0], b = up[1]
        if faces[a] == faces[b] {
            found[a] = turn
            found[b] = turn
            up = []
            if !solo { score.add(turn) }
        }
        return true
    }

    /// A tap on a card: the person whose turn it is. A tap while a missed
    /// pair is up turns it back at once.
    @discardableResult
    public mutating func play(_ i: Int) -> Bool {
        if computerTurn && !missed { return false }
        if missed {
            hideNow()
            if computerTurn { return false }
        }
        var rng = SystemRandomNumberGenerator()
        return flip(i, using: &rng)
    }

    /// A missed pair turns back, and the turn passes.
    public mutating func hideNow() {
        guard missed else { return }
        up = []
        if !solo { turn = turn.other }
    }

    /// The card McFly turns next: half of a pair it remembers, the other half
    /// of the card it just turned if it has seen it, or one it hasn't seen.
    public func computerPick(using rng: inout some RandomNumberGenerator) -> Int? {
        let open = faces.indices.filter { found[$0] == nil && !up.contains($0) }
        let known = open.filter { seen[$0] != nil }
        if up.count == 1 {
            if let partner = known.first(where: { seen[$0] == faces[up[0]] }) { return partner }
        } else if let i = known.first(where: { i in known.contains { $0 != i && seen[$0] == seen[i] } }) {
            return i
        }
        let fresh = open.filter { seen[$0] == nil }
        return (fresh.isEmpty ? open : fresh).randomElement(using: &rng)
    }

    /// McFly turns a card, when it's McFly's turn.
    public mutating func computerMove(using rng: inout some RandomNumberGenerator) {
        guard computerTurn, !missed, let i = computerPick(using: &rng) else { return }
        flip(i, using: &rng)
    }

    public mutating func computerMove() {
        var rng = SystemRandomNumberGenerator()
        computerMove(using: &rng)
    }

    // MARK: Testing

    /// Lays out a board (the tests' and screenshots').
    mutating func set(faces: [Int], found: [Mark?]? = nil, turn: Mark = .x, seen: [Int: Int] = [:], up: [Int] = []) {
        self.faces = faces
        self.found = found ?? Array(repeating: nil, count: faces.count)
        self.turn = turn
        self.seen = seen
        self.up = up
    }
}

extension Score {
    mutating func add(_ mark: Mark) {
        if mark == .x { x += 1 } else { o += 1 }
    }
}
