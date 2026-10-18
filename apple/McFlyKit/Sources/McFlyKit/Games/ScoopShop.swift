import Foundation

// Scoop Shop: an ice cream counter against the clock, the display's game
// (display/qml/games/ScoopShop.qml, its rules in scoops.js) in Swift. The
// player picks who works the shift, Pip the penguin or Lotl the axolotl.
// Customers come to the counter with a ticket: a cone or a cup, the scoops
// from the bottom up, and toppings. Build it, then hand it over before
// their patience runs out. A right order scores, more the quicker it is; a
// wrong one, or a customer who gives up, costs one of three hearts. Every
// five served it gets busier: more seats, bigger orders, less time, and
// new flavours and toppings join the menu.

public enum ScoopBase: String, Sendable, CaseIterable, Codable { case cone, cup }
/// In the order they join the menu (scoops.js FLAVOURS): the first four from
/// the start, the rest from level `Scoops.newFlavours`. Orders are drawn
/// from this order, so it is the generator's too.
public enum ScoopFlavour: String, Sendable, CaseIterable, Codable {
    case vanilla, chocolate, strawberry, mint, mango, blueberry, cookies
}
/// In the order they join the menu (scoops.js TOPPINGS): the first three from
/// the start, the rest from level `Scoops.newToppings`.
public enum ScoopTopping: String, Sendable, CaseIterable, Codable {
    case sprinkles, cherry, wafer, syrup, crunch, rings, cream
}

/// A treat: a ticket's order, or the one being built.
public struct ScoopOrder: Sendable, Equatable, Codable {
    public var base: ScoopBase?
    /// Bottom to top.
    public var scoops: [ScoopFlavour]
    public var toppings: [ScoopTopping]

    public init(base: ScoopBase? = nil, scoops: [ScoopFlavour] = [], toppings: [ScoopTopping] = []) {
        self.base = base
        self.scoops = scoops
        self.toppings = toppings
    }

    /// The base, each scoop and each topping.
    public var items: Int { (base == nil ? 0 : 1) + scoops.count + toppings.count }
}

/// Scoop Shop's rules (scoops.js): what each customer orders, how long they
/// wait, what a delivery scores, and how the shop gets busier.
public enum Scoops {
    public static let maxScoops = 3
    public static let maxLevel = 10
    /// Customers served to reach the next level.
    public static let perLevel = 5
    public static let hearts = 3
    /// Seats at the counter, at most.
    public static let maxSeats = 4
    /// The levels the last three flavours and the last four toppings join at.
    public static let newFlavours = 3
    public static let newToppings = 4
    /// The share of their patience left when a customer flips out.
    public static let furious = 0.2
    /// The shop's pace: every wait and every gap between customers is this
    /// share of the times in `rules`. 0.9 gives a tenth less time.
    public static let pace = 0.9

    /// A small seeded generator (mulberry32), so a test can replay a shift:
    /// next() steps its state, unit() turns a state into a number in [0, 1).
    public static func next(_ state: UInt32) -> UInt32 { state &+ 0x6D2B79F5 }

    public static func unit(_ state: UInt32) -> Double {
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    /// The generator as scoops.js's random(seed): a function to call.
    public struct Random: Sendable {
        public var state: UInt32
        public init(seed: UInt32) { state = seed }
        public mutating func callAsFunction() -> Double {
            state = Scoops.next(state)
            return Scoops.unit(state)
        }
    }

    public static func level(served: Int) -> Int { min(maxLevel, 1 + served / perLevel) }

    /// What a level asks for. Times are in milliseconds.
    public struct Rules: Sendable, Equatable {
        public var seats: Int
        public var minScoops: Int, maxScoops: Int
        public var minToppings: Int, maxToppings: Int
        /// What orders are made of at this level.
        public var flavours: [ScoopFlavour], toppings: [ScoopTopping]
        /// How long a customer waits: a little for being there, more for
        /// each thing on the order, both shorter as the shop gets busy.
        public var wait: Int, perItem: Int
        /// Time between customers arriving.
        public var arrival: Int
    }

    public static func rules(_ level: Int) -> Rules {
        let lv = max(1, min(maxLevel, level))
        return Rules(seats: lv < 3 ? 2 : lv < 5 ? 3 : 4,
                     minScoops: lv < 5 ? 1 : 2,
                     maxScoops: lv < 2 ? 1 : lv < 4 ? 2 : 3,
                     minToppings: lv < 7 ? 0 : 1,
                     maxToppings: lv < 2 ? 0 : lv < 4 ? 1 : 2,
                     flavours: Array(ScoopFlavour.allCases.prefix(lv < newFlavours ? 4 : ScoopFlavour.allCases.count)),
                     toppings: Array(ScoopTopping.allCases.prefix(lv < newToppings ? 3 : ScoopTopping.allCases.count)),
                     wait: paced(max(10000, 24000 - 1600 * (lv - 1))),
                     perItem: paced(max(1600, 3000 - 200 * (lv - 1))),
                     arrival: paced(max(2500, 7000 - 500 * (lv - 1))))
    }

    /// A time at the shop's pace, rounded to the millisecond as Math.round does.
    private static func paced(_ ms: Int) -> Int { Int((pace * Double(ms)).rounded(.toNearestOrAwayFromZero)) }

    static func pick<T>(_ rand: inout Random, _ list: [T]) -> T { list[Int(rand() * Double(list.count))] }
    static func between(_ rand: inout Random, _ lo: Int, _ hi: Int) -> Int { lo + Int(rand() * Double(hi - lo + 1)) }

    /// An order for this level, with the generator's draws in scoops.js's order.
    public static func makeOrder(_ level: Int, _ rand: inout Random) -> ScoopOrder {
        let r = rules(level)
        var scoops: [ScoopFlavour] = []
        let n = between(&rand, r.minScoops, r.maxScoops)
        for _ in 0..<n { scoops.append(pick(&rand, r.flavours)) }
        var left = r.toppings
        var toppings: [ScoopTopping] = []
        let t = between(&rand, r.minToppings, r.maxToppings)
        for _ in 0..<t { toppings.append(left.remove(at: Int(rand() * Double(left.count)))) }
        // Toppings in the menu's order: they all go on top, so it doesn't matter.
        toppings.sort { ScoopTopping.allCases.firstIndex(of: $0)! < ScoopTopping.allCases.firstIndex(of: $1)! }
        return ScoopOrder(base: pick(&rand, ScoopBase.allCases), scoops: scoops, toppings: toppings)
    }

    public static func patience(_ order: ScoopOrder, level: Int) -> Int {
        let r = rules(level)
        return r.wait + r.perItem * order.items
    }

    /// Right when the base matches, the scoops match in order from the bottom
    /// up, and the toppings match in any order.
    public static func matches(_ order: ScoopOrder, _ build: ScoopOrder) -> Bool {
        order.base == build.base && order.scoops == build.scoops && order.toppings.count == build.toppings.count
            && order.toppings.allSatisfy(build.toppings.contains)
    }

    /// Ten a thing on the order, and up to as much again for speed: `left` is
    /// the share of the customer's patience still left, 0 to 1.
    public static func points(_ order: ScoopOrder, left: Double) -> Int {
        let n = order.items
        return 10 * n + Int((10 * Double(n) * max(0, min(1, left))).rounded(.toNearestOrAwayFromZero))
    }

    /// How a customer looks: by how it went, or by the patience they have
    /// `left`. In the last fifth they flip out.
    public enum Face: Sendable, Equatable { case smile, flat, frown, furious, happy, cross }

    public static func face(left: Double, gone: ScoopCustomer.Gone) -> Face {
        switch gone {
        case .right: return .happy
        case .wrong, .late: return .cross
        case .waiting: return left > 0.5 ? .smile : left > 0.3 ? .flat : left > furious ? .frown : .furious
        }
    }
}

/// A customer at the counter.
public struct ScoopCustomer: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable { case bear, bunny, cat, frog, chick }
    /// How they left: "" while they wait.
    public enum Gone: Sendable, Equatable { case waiting, right, wrong, late }

    public var id: Int
    public var order: ScoopOrder
    public var kind: Kind
    /// Shift time they sat down, ms.
    public var arrived: Double
    /// How long they'll wait, ms.
    public var patience: Int
    public var gone = Gone.waiting
    public var goneAt: Double = 0
    public var points = 0

    /// Patience left at `now`, 1 down to 0.
    public func patienceLeft(at now: Double) -> Double {
        gone == .waiting ? max(0, 1 - (now - arrived) / Double(patience)) : 0
    }

    public func face(at now: Double) -> Scoops.Face { Scoops.face(left: patienceLeft(at: now), gone: gone) }
}

public enum ScoopKeeper: String, Sendable, CaseIterable { case pip, lotl }

/// One shift at the counter: the clock, the seats, the treat being built.
public struct ScoopShift: Sendable {
    public enum Phase: Sendable { case ready, playing, over }
    /// What a press on a counter button did, for the view's hint.
    public enum Nudge: String, Sendable, Error {
        case baseFirst = "Cone or cup first"
        case threeAtMost = "Three scoops at most"
        case scoopFirst = "A scoop first"
        case makeFirst = "Make their order first"
    }
    public enum Delivery: Sendable { case right, wrong }

    public static let leaveMs: Double = 700

    public private(set) var phase = Phase.ready
    public var paused = false
    public private(set) var worker = ScoopKeeper.pip
    public private(set) var score = 0
    public private(set) var best: Int
    public private(set) var newBest = false
    public private(set) var hearts = Scoops.hearts
    public private(set) var served = 0
    /// Shift time in ms; it runs only while playing.
    public private(set) var now: Double = 0
    private var nextArrival: Double = 0
    public private(set) var seats = [ScoopCustomer?](repeating: nil, count: Scoops.maxSeats)
    private var nextId = 1
    /// The treat being made.
    public private(set) var build = ScoopOrder()
    /// A repeatable shift for tests: the generator starts here (0: anywhere).
    public var seed: UInt32 = 0
    private var dice: UInt32 = 1

    public init(best: Int = 0, worker: ScoopKeeper = .pip) {
        self.best = best
        self.worker = worker
    }

    public var level: Int { Scoops.level(served: served) }
    public var rules: Scoops.Rules { Scoops.rules(level) }
    public var playing: Bool { phase == .playing && !paused }
    /// Someone at the counter is about to give up: the shopkeeper panics.
    public var alarm: Bool {
        phase == .playing && seats.contains { c in
            guard let c, c.gone == .waiting else { return false }
            return 1 - (now - c.arrived) / Double(c.patience) <= Scoops.furious
        }
    }

    private mutating func random() -> Double {
        dice = Scoops.next(dice)
        return Scoops.unit(dice)
    }

    public mutating func start(_ who: ScoopKeeper? = nil) {
        if let who { worker = who }
        score = 0
        served = 0
        hearts = Scoops.hearts
        newBest = false
        now = 0
        nextArrival = 1000
        nextId = 1
        seats = Array(repeating: nil, count: Scoops.maxSeats)
        build = ScoopOrder()
        dice = seed > 0 ? seed : UInt32.random(in: 1...UInt32.max)
        paused = false
        phase = .playing
    }

    public mutating func pause() { if phase == .playing { paused = true } }
    public mutating func resume() { paused = false }

    /// Moves the shift on by `ms`, a tenth of a second at a time. Returns the
    /// hearts lost to customers who gave up.
    @discardableResult
    public mutating func advance(_ ms: Double) -> Int {
        var ms = ms
        var late = 0
        while ms > 0 && playing {
            let step = min(100, ms)
            ms -= step
            now += step
            late += tick()
        }
        return late
    }

    private mutating func customer(_ order: ScoopOrder) -> ScoopCustomer {
        defer { nextId += 1 }
        let kind = ScoopCustomer.Kind.allCases[Int(random() * Double(ScoopCustomer.Kind.allCases.count))]
        return ScoopCustomer(id: nextId, order: order, kind: kind, arrived: now, patience: Scoops.patience(order, level: level))
    }

    private func leaving(_ c: ScoopCustomer, _ how: ScoopCustomer.Gone, _ points: Int) -> ScoopCustomer {
        var c = c
        c.gone = how
        c.goneAt = now
        c.points = points
        return c
    }

    private mutating func tick() -> Int {
        var next = seats
        var late = 0
        for i in next.indices {
            guard let c = next[i] else { continue }
            if c.gone != .waiting && now - c.goneAt >= Self.leaveMs {
                next[i] = nil
            } else if c.gone == .waiting && now - c.arrived >= Double(c.patience) {
                next[i] = leaving(c, .late, 0)
                late += 1
            }
        }
        // Nobody waiting: the next one comes in soon.
        if !next.contains(where: { $0 != nil && $0!.gone == .waiting }) { nextArrival = min(nextArrival, now + 1200) }
        if now >= nextArrival {
            let free = (0..<rules.seats).filter { next[$0] == nil }
            if !free.isEmpty {
                // As scoops.js draws them: the seat, then the order, then who.
                let seat = free[Int(random() * Double(free.count))]
                var rand = Scoops.Random(seed: dice)
                let order = Scoops.makeOrder(level, &rand)
                dice = rand.state
                next[seat] = customer(order)
                nextArrival = now + Double(rules.arrival)
            } else {
                nextArrival = now + 400 // someone's at the door
            }
        }
        seats = next
        if late > 0 { loseHearts(late) }
        return late
    }

    /// For tests: a customer with this order in seat `index`. Returns how
    /// long they will wait.
    @discardableResult
    public mutating func seat(_ index: Int, _ order: ScoopOrder) -> Int {
        guard phase == .playing else { return 0 }
        seats[index] = customer(order)
        return seats[index]!.patience
    }

    // MARK: Making the treat

    @discardableResult
    public mutating func pickBase(_ base: ScoopBase) -> Bool {
        guard playing else { return false }
        build.base = base
        return true
    }

    /// Adds a scoop, or says why not.
    public mutating func addScoop(_ flavour: ScoopFlavour) -> Result<Void, Nudge>? {
        guard playing else { return nil }
        if build.base == nil { return .failure(.baseFirst) }
        if build.scoops.count >= Scoops.maxScoops { return .failure(.threeAtMost) }
        build.scoops.append(flavour)
        return .success(())
    }

    /// Adds a topping (once each), or says why not.
    public mutating func addTopping(_ topping: ScoopTopping) -> Result<Void, Nudge>? {
        guard playing else { return nil }
        if build.scoops.isEmpty { return .failure(.scoopFirst) }
        if build.toppings.contains(topping) { return nil }
        build.toppings.append(topping)
        return .success(())
    }

    /// Takes off what's on top: a topping, else a scoop, else the cone or cup.
    @discardableResult
    public mutating func undo() -> Bool {
        guard playing else { return false }
        if !build.toppings.isEmpty {
            build.toppings.removeLast()
        } else if !build.scoops.isEmpty {
            build.scoops.removeLast()
        } else if build.base != nil {
            build = ScoopOrder()
        } else {
            return false
        }
        return true
    }

    /// Hands the treat to the customer in seat `index`: right, wrong, or nil
    /// when nothing changed hands (with why, if it was the treat).
    public mutating func deliver(_ index: Int) -> Result<Delivery, Nudge>? {
        guard playing, let c = seats[index], c.gone == .waiting else { return nil }
        guard build.base != nil else { return .failure(.makeFirst) }
        let right = Scoops.matches(c.order, build)
        if right {
            let points = Scoops.points(c.order, left: 1 - (now - c.arrived) / Double(c.patience))
            score += points
            served += 1
            seats[index] = leaving(c, .right, points)
        } else {
            seats[index] = leaving(c, .wrong, 0)
        }
        build = ScoopOrder()
        if !right { loseHearts(1) }
        return .success(right ? .right : .wrong)
    }

    private mutating func loseHearts(_ n: Int) {
        hearts = max(0, hearts - n)
        if hearts == 0 { endShift() }
    }

    public mutating func endShift() {
        guard phase == .playing else { return }
        phase = .over
        paused = false
        if score > best {
            best = score
            newBest = true
        }
    }
}
