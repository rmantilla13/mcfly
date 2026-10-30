import Foundation

/// Solitaire (Klondike, the traditional patience), the display's
/// (display/qml/games/Solitaire.qml): build each suit up from the ace on the
/// four home piles, moving cards between the seven columns in descending
/// runs of alternating colour, a king (or a run under one) to an empty
/// column. The deck turns one card over, or three, and turns the waste back
/// over when it runs out.
///
/// No dragging: a tap moves a card, and every card on it, to the best place
/// it can go (home first for one card, then a column with cards in it, then
/// an empty one), and a tap on a run that can't move tries the column's other
/// cards. Undo takes back a move at a time; once every card is face up, the
/// rest go home on their own (`finishStep`), which isn't a move.
///
/// A card is 0–51: suit × 13 + rank − 1, the suits spades, hearts, diamonds,
/// clubs. The game in progress is kept (`GameProgress.solitaire`), Undo's
/// history isn't.
public struct Solitaire: Sendable, Codable, Equatable {
    /// Where cards are: the waste, a home pile (by suit) or a column.
    public enum Pile: Sendable, Equatable, Hashable {
        case waste, home(Int), column(Int)
    }

    /// Each pile's cards, bottom first.
    public private(set) var stock: [Int] = []
    public private(set) var waste: [Int] = []
    public private(set) var foundations: [[Int]] = Array(repeating: [], count: 4)
    public private(set) var tableau: [[Int]] = Array(repeating: [], count: 7)
    /// How many cards at the bottom of each column are face down.
    public private(set) var hidden: [Int] = Array(repeating: 0, count: 7)
    public private(set) var moves = 0
    public private(set) var drawThree = false
    /// The cards that moved last, drawn over the rest while they glide.
    public private(set) var lastMoved: [Int] = []
    private var history: [Position] = []

    private struct Position: Sendable, Equatable {
        var stock: [Int], waste: [Int], foundations: [[Int]], tableau: [[Int]], hidden: [Int], moves: Int
    }

    private enum CodingKeys: String, CodingKey {
        case stock, waste, foundations, tableau, hidden, moves, drawThree
    }

    public init(seed: UInt32? = nil, drawThree: Bool = false) {
        self.drawThree = drawThree
        deal(seed: seed)
    }

    public static func suit(of card: Int) -> Int { card / 13 }
    public static func rank(of card: Int) -> Int { card % 13 + 1 }
    public static func isRed(_ card: Int) -> Bool { suit(of: card) == 1 || suit(of: card) == 2 }

    public var home: Int { foundations.reduce(0) { $0 + $1.count } }
    public var won: Bool { home == 52 }
    /// Every card face up and the deck gone: the rest go home on their own.
    public var finishing: Bool { !won && stock.isEmpty && waste.isEmpty && hidden.allSatisfy { $0 == 0 } }
    public var canUndo: Bool { !history.isEmpty && !won && !finishing }

    /// Every card once, each pile the right shape: a saved game worth loading.
    public var isValid: Bool {
        guard foundations.count == 4, tableau.count == 7, hidden.count == 7 else { return false }
        var all = stock + waste
        for pile in foundations + tableau { all += pile }
        guard all.count == 52, Set(all) == Set(0..<52) else { return false }
        return tableau.indices.allSatisfy { c in
            hidden[c] >= 0 && (tableau[c].isEmpty ? hidden[c] == 0 : hidden[c] < tableau[c].count)
        }
    }

    // MARK: Dealing

    /// The display's shuffle for a seed (a linear congruential generator), so
    /// a seed deals the same game on both.
    public static func deck(seed: UInt32) -> [Int] {
        var deck = Array(0..<52)
        var s = seed
        for i in stride(from: 51, to: 0, by: -1) {
            s = s &* 1_664_525 &+ 1_013_904_223
            let j = Int(Double(s) / 4_294_967_296 * Double(i + 1))
            deck.swapAt(i, j)
        }
        return deck
    }

    public mutating func deal(seed: UInt32? = nil) {
        var deck: [Int]
        if let seed {
            deck = Self.deck(seed: seed)
        } else {
            var rng = SystemRandomNumberGenerator()
            deck = Array(0..<52).shuffled(using: &rng)
        }
        tableau = (0..<7).map { c in
            let column = Array(deck.prefix(c + 1))
            deck.removeFirst(c + 1)
            return column
        }
        hidden = Array(0..<7)
        stock = deck
        waste = []
        foundations = Array(repeating: [], count: 4)
        moves = 0
        history = []
        lastMoved = []
    }

    /// One card at a time or three: a new game.
    public mutating func setDrawThree(_ three: Bool, seed: UInt32? = nil) {
        drawThree = three
        deal(seed: seed)
    }

    // MARK: Rules

    public func fitsHome(_ card: Int) -> Bool {
        foundations[Self.suit(of: card)].count == Self.rank(of: card) - 1
    }

    public func fitsColumn(_ card: Int, _ column: Int) -> Bool {
        guard let top = tableau[column].last else { return Self.rank(of: card) == 13 }
        return Self.rank(of: top) == Self.rank(of: card) + 1 && Self.isRed(top) != Self.isRed(card)
    }

    public func cards(_ pile: Pile) -> [Int] {
        switch pile {
        case .waste: return waste
        case .home(let s): return foundations[s]
        case .column(let c): return tableau[c]
        }
    }

    /// Where the top `count` cards of `from` go best, or nil.
    public func destination(from: Pile, count: Int) -> Pile? {
        let source = cards(from)
        guard count >= 1, count <= source.count else { return nil }
        let card = source[source.count - count]
        var fromHome = false, fromColumn: Int?
        switch from {
        case .home: fromHome = true
        case .column(let c): fromColumn = c
        case .waste: break
        }
        if count == 1, !fromHome, fitsHome(card) { return .home(Self.suit(of: card)) }
        var empty: Pile?
        for c in 0..<7 {
            if c == fromColumn || !fitsColumn(card, c) { continue }
            if !tableau[c].isEmpty { return .column(c) }
            if empty == nil { empty = .column(c) }
        }
        // A king to an empty column, unless it's the whole of one already.
        if let empty, !(fromColumn != nil && source.count == count) { return empty }
        return nil
    }

    // MARK: Moves

    private var position: Position {
        Position(stock: stock, waste: waste, foundations: foundations, tableau: tableau, hidden: hidden, moves: moves)
    }

    private mutating func remember() {
        history.append(position)
        if history.count > 300 { history.removeFirst(history.count - 300) }
    }

    private mutating func take(_ count: Int, from pile: Pile) -> [Int] {
        switch pile {
        case .waste:
            defer { waste.removeLast(count) }
            return Array(waste.suffix(count))
        case .home(let s):
            defer { foundations[s].removeLast(count) }
            return Array(foundations[s].suffix(count))
        case .column(let c):
            defer {
                tableau[c].removeLast(count)
                // Turn the column's new top card face up.
                if hidden[c] >= tableau[c].count { hidden[c] = max(0, tableau[c].count - 1) }
            }
            return Array(tableau[c].suffix(count))
        }
    }

    private mutating func put(_ cards: [Int], on pile: Pile) {
        switch pile {
        case .waste: waste += cards
        case .home(let s): foundations[s] += cards
        case .column(let c): tableau[c] += cards
        }
    }

    @discardableResult
    mutating func moveRun(from: Pile, count: Int, to: Pile) -> Bool {
        remember()
        let cards = take(count, from: from)
        put(cards, on: to)
        moves += 1
        lastMoved = cards
        return true
    }

    /// The deck: turn one card (or three) onto the waste, or, when it's
    /// empty, turn the waste back over.
    @discardableResult
    public mutating func draw() -> Bool {
        guard !won, !finishing else { return false }
        if !stock.isEmpty {
            remember()
            var turned: [Int] = []
            for _ in 0..<min(drawThree ? 3 : 1, stock.count) {
                turned.append(stock.removeLast())
            }
            waste += turned
            lastMoved = turned
        } else if !waste.isEmpty {
            remember()
            stock = waste.reversed()
            waste = []
            lastMoved = []
        } else {
            return false
        }
        moves += 1
        return true
    }

    @discardableResult
    public mutating func tapWaste() -> Bool {
        guard !won, !waste.isEmpty, let to = destination(from: .waste, count: 1) else { return false }
        return moveRun(from: .waste, count: 1, to: to)
    }

    @discardableResult
    public mutating func tapHome(_ suit: Int) -> Bool {
        guard !won, !foundations[suit].isEmpty, let to = destination(from: .home(suit), count: 1) else { return false }
        return moveRun(from: .home(suit), count: 1, to: to)
    }

    /// A tap on column `column` at its card `index`: that card and the ones
    /// on it if they can go somewhere, else the top card, else any other run
    /// in the column, the longest first.
    @discardableResult
    public mutating func tapColumn(_ column: Int, at index: Int) -> Bool {
        let t = tableau[column]
        guard !won, !t.isEmpty else { return false }
        let top = t.count - 1, first = hidden[column]
        var tried = Set<Int>()
        for i in [max(first, min(top, index)), top] + Array(first...top) where tried.insert(i).inserted {
            if let to = destination(from: .column(column), count: t.count - i) {
                return moveRun(from: .column(column), count: t.count - i, to: to)
            }
        }
        return false
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard canUndo, let last = history.popLast() else { return false }
        stock = last.stock
        waste = last.waste
        foundations = last.foundations
        tableau = last.tableau
        hidden = last.hidden
        moves = last.moves
        lastMoved = []
        return true
    }

    /// With every card face up, the lowest card that fits goes home.
    @discardableResult
    public mutating func finishStep() -> Bool {
        guard finishing else { return false }
        var pick: Int?
        for c in 0..<7 {
            guard let card = tableau[c].last, fitsHome(card) else { continue }
            if let p = pick, let other = tableau[p].last, Self.rank(of: other) <= Self.rank(of: card) { continue }
            pick = c
        }
        guard let pick, let card = tableau[pick].popLast() else { return false }
        foundations[Self.suit(of: card)].append(card)
        lastMoved = [card]
        return true
    }

    // MARK: Testing

    /// Lays out a position (the tests' and screenshots'), with no history.
    mutating func set(stock: [Int], waste: [Int], foundations: [[Int]], tableau: [[Int]], hidden: [Int], moves: Int = 0) {
        self.stock = stock
        self.waste = waste
        self.foundations = foundations
        self.tableau = tableau
        self.hidden = hidden
        self.moves = moves
        history = []
        lastMoved = []
    }
}
