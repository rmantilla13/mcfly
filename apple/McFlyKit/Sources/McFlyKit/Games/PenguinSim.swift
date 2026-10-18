import Foundation

// Penguin March's rules, the display's (display/src/games/PenguinSim.cpp)
// in Swift: penguins drop from a hatch, walk, turn at walls and fall; a fall
// that is too long is the end of one. Each can be given a skill. A level is
// won by getting enough of them into the igloo.
//
// The world is a grid of world pixels (a penguin is 16 tall) and runs on a
// fixed tick of `Penguins.tickMs`. Everything is whole numbers and nothing is
// random, so a level plays the same way every time from the same
// assignments, and the same way as on the display: a level's recorded
// solution replays exactly (PenguinMarchTests).
//
// A penguin's position is its foot: the lowest row of its body. The ground
// it stands on is the row below (y + 1).
public enum Penguins {
    public static let tickMs = 50          // 20 ticks a second
    public static let height = 16          // a penguin, foot to crown
    static let stepUp = 4                  // the highest step a walker climbs
    static let stepDown = 4                // the deepest step it walks down; more is a fall
    static let fallSpeed = 3               // px a tick
    public static let lethalFall = 72      // more than this, without an umbrella, is fatal
    static let floatOpen = 12              // px of falling before the umbrella opens
    public static let blockReach = 7       // a walker this close to a blocker turns
    public static let digPeriod = 3        // ticks a stroke
    public static let digHalf = 5          // a hole 11 wide
    public static let bashPeriod = 3
    static let bashReach = 8               // cleared ahead of the foot each stroke
    public static let bashHeight = 16      // the tunnel: a penguin tall
    static let bashLook = 16               // nothing to bash this far ahead: stop
    public static let buildPeriod = 6
    public static let bricks = 12          // a bridge: 12 steps, 2 up and 4 along each
    static let brickLength = 8
    public static let exitTicks = 10
    public static let splatTicks = 14
    public static let drownTicks = 16
    public static let openTicks = 20       // the hatch opening, before the first penguin
}

public enum PenguinCell: UInt8, Sendable {
    case air, ground, steel, brick
}

public enum PenguinSkill: Int, CaseIterable, Sendable, Identifiable {
    case block, dig, bash, build, float

    public var id: Self { self }

    /// "block", "dig", "bash", "build", "float": the display's names.
    public var key: String {
        switch self {
        case .block: return "block"
        case .dig: return "dig"
        case .bash: return "bash"
        case .build: return "build"
        case .float: return "float"
        }
    }

    public var name: String { key.prefix(1).uppercased() + key.dropFirst() }
}

public enum PenguinState: Sendable, Equatable {
    case falling, floating, walking, blocking, digging, bashing, building
    case exiting, splatting, drowning, saved, lost
}

public struct Penguin: Sendable, Equatable {
    public var id = 0
    public var x = 0, y = 0
    /// Where it was a tick ago, for drawing in between.
    public var px = 0, py = 0
    /// 1 right, -1 left.
    public var dir = 1
    public var state = PenguinState.falling
    /// Ticks in this state.
    public var timer = 0
    /// Px fallen so far in this fall.
    public var fall = 0
    /// Bricks left to lay.
    public var bricks = 0
    /// Has an umbrella.
    public var floater = false

    public var gone: Bool { state == .saved || state == .lost }
    /// Still on its way somewhere: everything but a blocker, the gone and the going.
    public var moving: Bool { !gone && state != .blocking }
}

/// A point in world pixels.
public struct PenguinPoint: Sendable, Equatable {
    public var x: Int, y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

/// A rectangle of world pixels, as Qt's QRect: `x ..< x + width` across.
public struct PenguinRect: Sendable, Equatable {
    public var x: Int, y: Int, width: Int, height: Int
    public init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    public func contains(_ px: Int, _ py: Int) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }

    public func intersection(_ other: PenguinRect) -> PenguinRect {
        let l = max(x, other.x), t = max(y, other.y)
        let r = min(maxX, other.maxX), b = min(maxY, other.maxY)
        return r > l && b > t ? PenguinRect(l, t, r - l, b - t) : PenguinRect(0, 0, 0, 0)
    }
}

/// A level's terrain is drawn from shapes, in order: ground (diggable snow
/// and ice), steel (rock nothing digs) and cuts (back to air).
public struct PenguinShape: Sendable {
    public enum Kind: Sendable { case ground, steel, cut }
    public var kind: Kind
    /// A rectangle is a four-point polygon.
    public var points: [PenguinPoint]
    /// The polygon's bounding box as an ellipse.
    public var ellipse = false

    public var bounds: PenguinRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        let x = xs.min() ?? 0, y = ys.min() ?? 0
        // Qt's QPolygon::boundingRect: the far corner is inside.
        return PenguinRect(x, y, (xs.max() ?? 0) - x + 1, (ys.max() ?? 0) - y + 1)
    }

    public static func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ kind: Kind = .ground) -> PenguinShape {
        PenguinShape(kind: kind, points: [PenguinPoint(x, y), PenguinPoint(x + w, y), PenguinPoint(x + w, y + h), PenguinPoint(x, y + h)])
    }

    public static func poly(_ points: [(Int, Int)], _ kind: Kind = .ground) -> PenguinShape {
        PenguinShape(kind: kind, points: points.map { PenguinPoint($0.0, $0.1) })
    }

    public static func ellipse(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ kind: Kind = .ground) -> PenguinShape {
        var shape = rect(x, y, w, h, kind)
        shape.ellipse = true
        return shape
    }
}

/// One assignment of a recorded solution: give `skill` to penguin `id` the
/// first tick it can take it at x == atX (any x if nil) and, if atY is set,
/// at y >= atY; or at tick atTick if that is set instead. A penguin's steps
/// are taken in the order they're listed.
public struct PenguinStep: Sendable {
    public var id: Int
    public var skill: PenguinSkill
    public var atX: Int?
    public var atY: Int?
    public var atTick: Int?

    public init(id: Int, skill: PenguinSkill, atX: Int? = nil, atY: Int? = nil, atTick: Int? = nil) {
        self.id = id
        self.skill = skill
        self.atX = atX
        self.atY = atY
        self.atTick = atTick
    }
}

public struct PenguinLevel: Sendable {
    public var name: String
    /// What's new in it, a sentence.
    public var hint: String
    public var width = 400
    public var height = 184
    /// Penguins.
    public var total = 10
    /// To win.
    public var need = 10
    /// Ticks between penguins.
    public var rate = 40
    /// Where they drop in (a foot point).
    public var entrance = PenguinPoint(0, 0)
    public var entranceDir = 1
    /// A foot point in the doorway.
    public var exit = PenguinPoint(0, 0)
    /// Each skill's count, in `PenguinSkill` order.
    public var skills = [Int](repeating: 0, count: PenguinSkill.allCases.count)
    public var shapes: [PenguinShape] = []
    public var water: [PenguinRect] = []
    public var solution: [PenguinStep] = []

    public init(name: String, hint: String, total: Int = 10, need: Int = 10) {
        self.name = name
        self.hint = hint
        self.total = total
        self.need = need
    }

    public func count(_ skill: PenguinSkill) -> Int { skills[skill.rawValue] }
}

/// A change to the terrain since the level started, for the view to draw:
/// a hole cut (dig, bash) or a brick laid.
public struct PenguinEdit: Sendable, Equatable {
    public enum Kind: Sendable { case cut, brick }
    public var kind: Kind
    public var rect: PenguinRect
}

public struct PenguinSim: Sendable {
    public private(set) var level: PenguinLevel
    public private(set) var width = 0
    public private(set) var height = 0
    private var cells: [UInt8] = []
    public private(set) var penguins: [Penguin] = []
    private var left: [Int] = []
    /// Every change to the terrain so far, in order; it grows by append only,
    /// so a view can keep its place in it.
    public private(set) var edits: [PenguinEdit] = []
    public private(set) var tick = 0
    private var nextSpawn = 0
    public private(set) var saved = 0
    public private(set) var lost = 0
    public private(set) var finished = false
    /// Bumped by load(): the view starts its terrain over.
    public private(set) var generation = 0

    public init(_ level: PenguinLevel) {
        self.level = level
        load(level)
    }

    public mutating func load(_ level: PenguinLevel) {
        self.level = level
        width = level.width
        height = level.height
        cells = Self.rasterize(level)
        penguins = []
        left = level.skills
        edits = []
        tick = 0
        nextSpawn = Penguins.openTicks
        saved = 0
        lost = 0
        finished = false
        generation += 1
    }

    public mutating func restart() { load(level) }

    public var released: Int { penguins.count }
    /// In the level now: released, not saved or lost.
    public var out: Int { penguins.filter { !$0.gone }.count }
    public func left(_ skill: PenguinSkill) -> Int { left[skill.rawValue] }
    public var won: Bool { finished && saved >= level.need }
    /// The hatch: 0 shut .. 1 open.
    public var hatchOpen: Double { min(1, Double(tick) / Double(Penguins.openTicks)) }

    public func cell(_ x: Int, _ y: Int) -> PenguinCell {
        if x < 0 || x >= width { return .steel } // the sides of the world are walls
        if y < 0 || y >= height { return .air }  // open above, and below: falling out of it
        return PenguinCell(rawValue: cells[y * width + x]) ?? .air
    }

    public func solid(_ x: Int, _ y: Int) -> Bool { cell(x, y) != .air }

    private func inWater(_ x: Int, _ y: Int) -> Bool {
        level.water.contains { $0.contains(x, y) }
    }

    // MARK: Running

    /// One tick. Nothing happens once the level is over.
    public mutating func step() {
        if finished { return }
        for i in penguins.indices {
            penguins[i].px = penguins[i].x
            penguins[i].py = penguins[i].y
        }
        if released < level.total && tick >= nextSpawn {
            spawn()
            nextSpawn = tick + level.rate
        }
        // Each penguin is taken out, moved and put back, so its own move can
        // look at the others (a walker at the blockers) without holding the array.
        for i in penguins.indices {
            var p = penguins[i]
            update(&p)
            penguins[i] = p
        }
        tick += 1
        checkFinished()
    }

    public mutating func run(_ ticks: Int) {
        var i = 0
        while i < ticks && !finished {
            step()
            i += 1
        }
    }

    private mutating func spawn() {
        var p = Penguin()
        p.id = penguins.count
        p.x = level.entrance.x
        p.px = p.x
        p.y = level.entrance.y
        p.py = p.y
        p.dir = level.entranceDir < 0 ? -1 : 1
        p.state = .falling
        penguins.append(p)
    }

    private func set(_ p: inout Penguin, _ state: PenguinState) {
        p.state = state
        p.timer = 0
    }

    private mutating func update(_ p: inout Penguin) {
        p.timer += 1
        switch p.state {
        case .falling:
            fallStep(&p, Penguins.fallSpeed)
        case .floating:
            fallStep(&p, p.timer % 2 != 0 ? 2 : 1)
        case .walking:
            walk(&p)
        case .blocking:
            if !groundBelow(p) { startFalling(&p) }
        case .digging:
            dig(&p)
        case .bashing:
            bash(&p)
        case .building:
            build(&p)
        case .exiting:
            if p.timer >= Penguins.exitTicks {
                set(&p, .saved)
                saved += 1
            }
        case .splatting, .drowning:
            if p.timer >= (p.state == .splatting ? Penguins.splatTicks : Penguins.drownTicks) {
                set(&p, .lost)
                lost += 1
            }
        case .saved, .lost:
            break
        }
    }

    private func groundBelow(_ p: Penguin) -> Bool { solid(p.x, p.y + 1) }

    private func startFalling(_ p: inout Penguin) {
        set(&p, .falling)
        p.fall = 0
    }

    /// After a move: the igloo, the water, the bottom of the world.
    @discardableResult
    private mutating func arrived(_ p: inout Penguin) -> Bool {
        if p.y >= height + Penguins.height {
            set(&p, .lost)
            lost += 1
            return true
        }
        if inWater(p.x, p.y) {
            set(&p, .drowning)
            return true
        }
        let door = level.exit
        if abs(p.x - door.x) <= 3 && p.y >= door.y - 4 && p.y <= door.y + 2 {
            set(&p, .exiting)
            return true
        }
        return false
    }

    private mutating func fallStep(_ p: inout Penguin, _ px: Int) {
        for _ in 0..<px {
            if groundBelow(p) { break }
            p.y += 1
            p.fall += 1
            if arrived(&p) { return }
            if p.state == .falling && p.floater && p.fall >= Penguins.floatOpen {
                set(&p, .floating)
                return
            }
        }
        if !groundBelow(p) { return }
        // Landed. A long fall is fatal without an umbrella open.
        let fatal = p.state == .falling && p.fall > Penguins.lethalFall
        set(&p, fatal ? .splatting : .walking)
        p.fall = 0
    }

    private mutating func walk(_ p: inout Penguin) {
        for b in penguins where b.state == .blocking && b.id != p.id {
            let ahead = (b.x - p.x) * p.dir
            if ahead > 0 && ahead <= Penguins.blockReach && abs(b.y - p.y) <= Penguins.height / 2 + 2 {
                p.dir = -p.dir
                return
            }
        }
        let nx = p.x + p.dir
        if !solid(nx, p.y) {
            // Level or downhill: follow the ground down a step, or fall.
            p.x = nx
            var down = 0
            while down < Penguins.stepDown && !groundBelow(p) {
                p.y += 1
                down += 1
            }
            if arrived(&p) { return }
            if !groundBelow(p) {
                startFalling(&p)
                p.fall = down
            }
            return
        }
        // Uphill: the lowest free row within a step, or it's a wall.
        for up in 1...Penguins.stepUp where !solid(nx, p.y - up) {
            p.x = nx
            p.y -= up
            arrived(&p)
            return
        }
        p.dir = -p.dir
    }

    private mutating func dig(_ p: inout Penguin) {
        if (p.timer - 1) % Penguins.digPeriod != 0 { return }
        for x in (p.x - 1)...(p.x + 1) {
            for y in (p.y + 1)...(p.y + 2) where cell(x, y) == .steel {
                set(&p, .walking)
                return
            }
        }
        cut(PenguinRect(p.x - Penguins.digHalf, p.y + 1, 2 * Penguins.digHalf + 1, 2))
        for _ in 0..<2 {
            if groundBelow(p) { break }
            p.y += 1
            if arrived(&p) { return }
        }
        if !groundBelow(p) { startFalling(&p) }
    }

    private mutating func bash(_ p: inout Penguin) {
        if (p.timer - 1) % Penguins.bashPeriod != 0 { return }
        // Rock right in front stops it; so does nothing left to bash.
        for c in 1...4 {
            for y in (p.y - 12)...p.y where cell(p.x + p.dir * c, y) == .steel {
                set(&p, .walking)
                return
            }
        }
        var any = false
        var c = 1
        while c <= Penguins.bashLook && !any {
            var y = p.y - Penguins.bashHeight + 1
            while y < p.y && !any {
                let k = cell(p.x + p.dir * c, y)
                any = k == .ground || k == .brick
                y += 1
            }
            c += 1
        }
        if !any {
            set(&p, .walking)
            return
        }
        let left = p.dir > 0 ? p.x + 1 : p.x - Penguins.bashReach
        cut(PenguinRect(left, p.y - Penguins.bashHeight + 1, Penguins.bashReach, Penguins.bashHeight))
        for _ in 0..<2 {
            if solid(p.x + p.dir, p.y) { break }
            p.x += p.dir
            var down = 0
            while down < Penguins.stepDown && !groundBelow(p) {
                p.y += 1
                down += 1
            }
            if arrived(&p) { return }
            if !groundBelow(p) {
                startFalling(&p)
                p.fall = down
                return
            }
        }
    }

    private mutating func build(_ p: inout Penguin) {
        if (p.timer - 1) % Penguins.buildPeriod != 0 { return }
        let left = p.dir > 0 ? p.x + 1 : p.x - Penguins.brickLength
        brick(PenguinRect(left, p.y - 1, Penguins.brickLength, 2))
        p.bricks -= 1
        // Step up onto it, unless something is in the way: then it walks (and
        // the walk climbs onto a ledge or turns at a wall).
        for c in 1...4 {
            for y in (p.y - 10)...(p.y - 2) where solid(p.x + p.dir * c, y) {
                set(&p, .walking)
                return
            }
        }
        p.y -= 2
        p.x += 4 * p.dir
        if arrived(&p) { return }
        if p.bricks <= 0 { set(&p, .walking) }
    }

    /// Clears ground and bricks (never steel) in `rect`.
    private mutating func cut(_ rect: PenguinRect) {
        let r = rect.intersection(PenguinRect(0, 0, width, height))
        guard !r.isEmpty else { return }
        var any = false
        for y in r.y..<r.maxY {
            for x in r.x..<r.maxX {
                let i = y * width + x
                if cells[i] == PenguinCell.ground.rawValue || cells[i] == PenguinCell.brick.rawValue {
                    cells[i] = PenguinCell.air.rawValue
                    any = true
                }
            }
        }
        if any { edits.append(PenguinEdit(kind: .cut, rect: r)) }
    }

    private mutating func brick(_ rect: PenguinRect) {
        let r = rect.intersection(PenguinRect(0, 0, width, height))
        guard !r.isEmpty else { return }
        var any = false
        for y in r.y..<r.maxY {
            for x in r.x..<r.maxX where cells[y * width + x] == PenguinCell.air.rawValue {
                cells[y * width + x] = PenguinCell.brick.rawValue
                any = true
            }
        }
        if any { edits.append(PenguinEdit(kind: .brick, rect: r)) }
    }

    // MARK: Skills

    public func canTake(_ p: Penguin, _ skill: PenguinSkill) -> Bool {
        if finished || p.gone || p.state == .exiting || p.state == .splatting || p.state == .drowning { return false }
        let grounded = p.state == .walking || p.state == .digging || p.state == .bashing || p.state == .building
        switch skill {
        case .float: return !p.floater
        case .block: return grounded
        case .dig: return grounded && p.state != .digging
        case .bash: return grounded && p.state != .bashing
        case .build: return grounded // again while building: a longer bridge
        }
    }

    /// Gives `skill` to penguin `id` if it can take it now and any are left.
    @discardableResult
    public mutating func assign(_ skill: PenguinSkill, to id: Int) -> Bool {
        guard id >= 0, id < released, left[skill.rawValue] > 0 else { return false }
        var p = penguins[id]
        guard canTake(p, skill) else { return false }
        left[skill.rawValue] -= 1
        switch skill {
        case .float:
            p.floater = true
        case .block:
            set(&p, .blocking)
        case .dig:
            set(&p, .digging)
        case .bash:
            set(&p, .bashing)
        case .build:
            set(&p, .building)
            p.bricks = Penguins.bricks
        }
        penguins[id] = p
        return true
    }

    /// The penguin nearest (x, y) that can take `skill`, within `radius`
    /// (world px, measured to the middle of its body), or nil.
    public func pick(_ skill: PenguinSkill, x: Double, y: Double, radius: Double) -> Int? {
        var best: Int?
        var bestDistance = radius
        for p in penguins where canTake(p, skill) {
            let d = hypot(Double(p.x) - x, Double(p.y) - Double(Penguins.height) / 2 - y)
            if d <= bestDistance && (best == nil || d < bestDistance) {
                best = p.id
                bestDistance = d
            }
        }
        return best
    }

    /// Ends the level now (the Finish button once enough are home): the ones
    /// still out don't count.
    public mutating func finish() { finished = true }

    private mutating func checkFinished() {
        if released < level.total { return }
        if penguins.contains(where: \.moving) { return }
        finished = true
    }

    // MARK: Terrain

    /// The terrain as it starts, a byte a cell: each shape filled where a
    /// cell's centre is inside it, in order, as the display's QPainter does
    /// without antialiasing (`Sim::rasterize`). A four-point rectangle
    /// (x, y, x + w, y + h) covers w × h cells.
    public static func rasterize(_ level: PenguinLevel) -> [UInt8] {
        let w = level.width, h = level.height
        var cells = [UInt8](repeating: 0, count: w * h)
        for shape in level.shapes {
            let value: PenguinCell = shape.kind == .ground ? .ground : shape.kind == .steel ? .steel : .air
            let fill = { (y: Int, x0: Int, x1: Int) in
                guard y >= 0, y < h else { return }
                for x in max(0, x0)..<min(w, x1) { cells[y * w + x] = value.rawValue }
            }
            if shape.ellipse {
                fillEllipse(shape.bounds, fill)
            } else {
                fillPolygon(shape.points, fill)
            }
        }
        return cells
    }

    /// Scanline fill, odd-even, sampling each cell at its centre: a row's
    /// spans as (row, first cell, past the last). A centre right on a
    /// slanted edge goes the way Qt's fixed-point edges send it: they step
    /// a slope rounded toward zero, so an edge leaning right as it goes down
    /// runs a hair left of true, and one leaning left a hair right.
    static func fillPolygon(_ points: [PenguinPoint], _ fill: (Int, Int, Int) -> Void) {
        guard points.count >= 3 else { return }
        let top = points.map(\.y).min() ?? 0, bottom = points.map(\.y).max() ?? 0
        for y in top..<bottom {
            // Twice the sample's height, so the arithmetic stays whole.
            let sy2 = 2 * y + 1
            var xs: [Double] = []
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                let ay2 = 2 * a.y, by2 = 2 * b.y
                guard (ay2 <= sy2 && sy2 < by2) || (by2 <= sy2 && sy2 < ay2) else { continue }
                let dx = b.x - a.x, dy = b.y - a.y
                // Exact: a tie lands on x.5 with no rounding.
                let x = Double(2 * a.x * dy + (sy2 - ay2) * dx) / Double(2 * dy)
                let lean = (dx > 0) == (dy > 0) ? 1.0 : -1.0
                xs.append(dx == 0 ? x : x - lean * 1e-6)
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                // Cells whose centre (x + 0.5) is in [left, right).
                let first = Int((xs[i] - 0.5).rounded(.up))
                let past = Int((xs[i + 1] - 0.5).rounded(.up))
                if past > first { fill(y, first, past) }
                i += 2
            }
        }
    }

    /// The bumps of snow the levels use, as the display draws them: Qt's
    /// aliased ellipse (a midpoint algorithm, not a centre test) for an
    /// ellipse(x, y, w, h) covers rows y + 1 ..< y + h, each row in from both
    /// sides by these many cells, top row first to the middle one; the rows
    /// under the middle mirror them. Read off the display's own terrain,
    /// and checked against it for every level by PenguinMarchTests.
    static let bumps: [String: [Int]] = [
        "40x12": [12, 6, 3, 1, 0, 0],
        "40x14": [12, 7, 4, 2, 1, 0, 0],
        "40x16": [13, 8, 5, 3, 2, 1, 0, 0],
        "50x12": [15, 8, 4, 2, 0, 0],
        "50x16": [16, 10, 6, 4, 2, 1, 0, 0],
        "60x20": [20, 14, 10, 7, 4, 3, 1, 1, 0, 0],
        "70x20": [24, 16, 11, 8, 5, 3, 2, 1, 0, 0],
    ]

    /// The ellipse whose box is `bounds` (its far corner inside, so one
    /// wider and taller than the shape asked for).
    static func fillEllipse(_ bounds: PenguinRect, _ fill: (Int, Int, Int) -> Void) {
        let x = bounds.x, y = bounds.y, w = bounds.width - 1, h = bounds.height - 1
        guard w > 0, h > 1 else { return }
        if let half = bumps["\(w)x\(h)"] {
            let rows = (0..<(h - 1)).map { $0 < half.count ? half[$0] : half[h - 2 - $0] }
            for (i, inset) in rows.enumerated() { fill(y + 1 + i, x + inset, x + w - inset) }
            return
        }
        // Any other size: the same box, cells whose centre is inside.
        let rx = Double(w) / 2, ry = Double(h - 1) / 2
        let cx = Double(x) + rx, cy = Double(y + 1) + ry
        for row in (y + 1)..<(y + h) {
            let dy = (Double(row) + 0.5 - cy) / ry
            guard dy * dy <= 1 else { continue }
            let span = rx * (1 - dy * dy).squareRoot()
            let first = Int((cx - span - 0.5).rounded(.up))
            let last = Int((cx + span - 0.5).rounded(.down))
            if last >= first { fill(row, first, last + 1) }
        }
    }
}

/// Plays recorded steps into a running level: each is applied the first tick
/// its penguin can take it.
public struct PenguinReplayer: Sendable {
    private let steps: [PenguinStep]
    private var done: [Bool]
    public private(set) var applied = 0

    public init(_ steps: [PenguinStep] = []) {
        self.steps = steps
        done = Array(repeating: false, count: steps.count)
    }

    public var active: Bool { !steps.isEmpty }

    /// Applies the steps that are due now (call before each step()).
    public mutating func apply(_ sim: inout PenguinSim) {
        for i in steps.indices {
            let s = steps[i]
            if done[i] || s.id >= sim.released { continue }
            // A penguin's steps go in order: this one waits for its earlier ones.
            if (0..<i).contains(where: { !done[$0] && steps[$0].id == s.id }) { continue }
            let p = sim.penguins[s.id]
            let due: Bool
            if let atTick = s.atTick {
                due = sim.tick >= atTick
            } else {
                due = (s.atX == nil || p.x == s.atX) && (s.atY == nil || p.y >= s.atY!)
            }
            if due && sim.assign(s.skill, to: s.id) {
                done[i] = true
                applied += 1
            }
        }
    }
}

extension PenguinSim {
    /// Replays steps from the start of the level to its end (or `maxTicks`).
    /// Returns how many were applied; the sim is left where the level ended.
    @discardableResult
    public mutating func replay(_ steps: [PenguinStep], maxTicks: Int = 20 * 60 * 10) -> Int {
        restart()
        var replayer = PenguinReplayer(steps)
        while !finished && tick < maxTicks {
            replayer.apply(&self)
            step()
        }
        return replayer.applied
    }
}
