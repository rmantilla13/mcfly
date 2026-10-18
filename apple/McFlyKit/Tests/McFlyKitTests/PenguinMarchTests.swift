import XCTest
@testable import McFlyKit

/// Penguin March's rules on small made-up levels, every real level won by
/// replaying its recorded solution, and both matching the display: the
/// display's tests (display/tests/tst_penguins.cpp) in Swift, plus the
/// display's own terrain and replays, cell for cell and tick for tick.
final class PenguinMarchTests: XCTestCase {
    /// A floor with its top at row 90 (a penguin on it stands at y = 89), one
    /// penguin dropping in at x = 20 and no igloo.
    private func flat(_ w: Int = 240, _ h: Int = 120) -> PenguinLevel {
        var l = PenguinLevel(name: "flat", hint: "", total: 1, need: 1)
        l.width = w
        l.height = h
        l.rate = 30
        l.entrance = PenguinPoint(20, 70)
        l.exit = PenguinPoint(-1000, -1000)
        l.skills = Array(repeating: 5, count: PenguinSkill.allCases.count)
        l.shapes = [.rect(0, 90, w, h - 90)]
        return l
    }

    /// Runs until penguin `id` is out and on its feet.
    private func untilWalking(_ sim: inout PenguinSim, _ id: Int = 0, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<400 {
            if sim.released > id && sim.penguins[id].state == .walking { return }
            sim.step()
        }
        XCTFail("never walked", file: file, line: line)
    }

    /// Runs until penguin `id` is at x (walking), then gives it `skill`.
    private func assignAt(_ sim: inout PenguinSim, _ id: Int, _ skill: PenguinSkill, _ x: Int) -> Bool {
        for _ in 0..<2000 {
            if sim.released > id {
                let p = sim.penguins[id]
                if p.x == x && p.state == .walking { return sim.assign(skill, to: id) }
            }
            sim.step()
        }
        return false
    }

    func testWalksStepsUpAndTurnsAtAWall() {
        var l = flat()
        l.shapes += [.rect(80, 86, 30, 4), .rect(150, 40, 10, 50)] // a step 4 high, climbed; a wall, turned at
        var sim = PenguinSim(l)
        untilWalking(&sim)
        XCTAssertEqual(sim.penguins[0].y, 89)
        XCTAssertEqual(sim.penguins[0].dir, 1)
        var maxX = 0
        var yOnStep = -1
        for _ in 0..<200 {
            sim.step()
            let p = sim.penguins[0]
            maxX = max(maxX, p.x)
            if p.x == 95 { yOnStep = p.y }
            XCTAssertEqual(p.state, .walking)
        }
        XCTAssertEqual(yOnStep, 85)              // on top of the step
        XCTAssertEqual(maxX, 149)                // up to the wall, never into it
        XCTAssertEqual(sim.penguins[0].dir, -1)  // and back
        XCTAssertLessThan(sim.penguins[0].x, 149)
        // The side of the world is a wall too.
        sim.run(400)
        XCTAssertGreaterThanOrEqual(sim.penguins[0].x, 0)
    }

    func testALongFallKills() {
        var l = flat()
        l.entrance = PenguinPoint(20, 89 - Penguins.lethalFall) // just survivable
        var safe = PenguinSim(l)
        untilWalking(&safe)
        XCTAssertEqual(safe.penguins[0].y, 89)

        l.entrance = PenguinPoint(20, 89 - Penguins.lethalFall - 3)
        var fatal = PenguinSim(l)
        fatal.run(200)
        XCTAssertEqual(fatal.penguins[0].state, .lost)
        XCTAssertEqual(fatal.lost, 1)
        XCTAssertTrue(fatal.finished)
        XCTAssertFalse(fatal.won)

        // Walking off a high ledge is a fall like any other.
        var ledge = flat(240, 200)
        ledge.shapes = [.rect(0, 90, 100, 10), .rect(0, 190, 240, 10)]
        var off = PenguinSim(ledge)
        off.run(400)
        XCTAssertEqual(off.penguins[0].state, .lost)
    }

    func testAFloaterSurvivesTheFall() {
        var l = flat(240, 200)
        l.shapes = [.rect(0, 190, 240, 10)]
        l.entrance = PenguinPoint(20, 10) // 179 px down
        var sim = PenguinSim(l)
        sim.run(Penguins.openTicks + 1)
        XCTAssertEqual(sim.penguins[0].state, .falling)
        sim.run(5)
        XCTAssertTrue(sim.assign(.float, to: 0))  // while it falls
        XCTAssertFalse(sim.assign(.float, to: 0)) // only one umbrella
        var floated = false
        for _ in 0..<400 where sim.penguins[0].state != .walking {
            sim.step()
            floated = floated || sim.penguins[0].state == .floating
        }
        XCTAssertTrue(floated)
        XCTAssertEqual(sim.penguins[0].state, .walking)
        XCTAssertEqual(sim.penguins[0].y, 189)
        XCTAssertEqual(sim.left(.float), 4)
    }

    func testABlockerTurnsTheOthers() {
        var l = flat()
        l.total = 2
        l.need = 1
        var sim = PenguinSim(l)
        XCTAssertTrue(assignAt(&sim, 0, .block, 100))
        XCTAssertEqual(sim.penguins[0].state, .blocking)
        var maxX = 0, turns = 0, lastDir = 1
        for _ in 0..<800 {
            sim.step()
            guard sim.released >= 2 else { continue }
            let p = sim.penguins[1]
            guard p.state == .walking else { continue }
            maxX = max(maxX, p.x)
            if p.dir != lastDir && p.x > 50 { turns += 1 }
            lastDir = p.dir
        }
        XCTAssertEqual(maxX, 100 - Penguins.blockReach) // turned in front of the blocker
        XCTAssertGreaterThanOrEqual(turns, 2)           // every time it came back
        XCTAssertEqual(sim.penguins[0].x, 100)          // the blocker never moved

        // A blocker stays, so once the rest are home the level is over.
        var home = flat()
        home.total = 2
        home.need = 1
        home.exit = PenguinPoint(100, 89)
        home.entrance = PenguinPoint(60, 70)
        home.entranceDir = -1
        var done = PenguinSim(home)
        XCTAssertTrue(assignAt(&done, 0, .block, 50))
        done.run(400)
        XCTAssertTrue(done.finished)
        XCTAssertTrue(done.won)
        XCTAssertEqual(done.saved, 1)
    }

    func testADiggerDigsThrough() {
        var l = flat(240, 160)
        l.shapes = [.rect(0, 90, 240, 20), .rect(0, 140, 240, 20)]
        var sim = PenguinSim(l)
        XCTAssertTrue(assignAt(&sim, 0, .dig, 60))
        XCTAssertEqual(sim.cell(60, 100), .ground)
        for _ in 0..<300 where sim.penguins[0].y < 139 { sim.step() }
        untilWalking(&sim)
        XCTAssertEqual(sim.penguins[0].y, 139) // through the upper floor, onto the lower
        for y in 90..<110 {
            XCTAssertEqual(sim.cell(60 - Penguins.digHalf, y), .air)
            XCTAssertEqual(sim.cell(60 + Penguins.digHalf, y), .air)
            XCTAssertEqual(sim.cell(60 + Penguins.digHalf + 1, y), .ground)
        }
        XCTAssertFalse(sim.edits.isEmpty)

        // Steel stops it.
        l.shapes.append(.rect(40, 100, 40, 10, .steel))
        var steel = PenguinSim(l)
        XCTAssertTrue(assignAt(&steel, 0, .dig, 60))
        steel.run(60)
        XCTAssertEqual(steel.penguins[0].state, .walking)
        XCTAssertLessThan(steel.penguins[0].y, 100)
        XCTAssertEqual(steel.cell(60, 100), .steel)
    }

    func testABasherTunnels() {
        var l = flat()
        l.shapes.append(.rect(100, 40, 30, 50))
        var sim = PenguinSim(l)
        XCTAssertTrue(assignAt(&sim, 0, .bash, 95))
        var maxX = 0
        for _ in 0..<300 {
            sim.step()
            maxX = max(maxX, sim.penguins[0].x)
        }
        XCTAssertGreaterThan(maxX, 140)                  // through the wall
        XCTAssertEqual(sim.penguins[0].state, .walking)  // and walking on
        XCTAssertEqual(sim.cell(115, 89), .air)          // the tunnel
        XCTAssertEqual(sim.cell(115, 89 - Penguins.bashHeight + 1), .air)
        XCTAssertEqual(sim.cell(115, 89 - Penguins.bashHeight - 1), .ground) // its roof

        // Steel stops it.
        var rock = flat()
        rock.shapes.append(.rect(100, 40, 30, 50, .steel))
        var stop = PenguinSim(rock)
        XCTAssertTrue(assignAt(&stop, 0, .bash, 90))
        maxX = 0
        for _ in 0..<300 {
            stop.step()
            maxX = max(maxX, stop.penguins[0].x)
        }
        XCTAssertLessThan(maxX, 100)
        XCTAssertEqual(stop.penguins[0].state, .walking)
        XCTAssertEqual(stop.penguins[0].dir, -1)

        // Nothing to bash: it goes back to walking (and the skill is spent).
        var open = PenguinSim(flat())
        XCTAssertTrue(assignAt(&open, 0, .bash, 40))
        open.run(5)
        XCTAssertEqual(open.penguins[0].state, .walking)
        XCTAssertEqual(open.left(.bash), 4)
    }

    func testABridgeCanBeWalked() {
        // Two floors with a pit between them, out of the bottom of the world.
        var l = flat()
        l.total = 2
        l.need = 2
        l.rate = 60
        l.shapes = [.rect(0, 90, 100, 30), .rect(140, 90, 100, 30)]
        l.exit = PenguinPoint(200, 89)
        var sim = PenguinSim(l)
        XCTAssertTrue(assignAt(&sim, 0, .build, 96))
        XCTAssertEqual(sim.penguins[0].bricks, Penguins.bricks)
        for _ in 0..<2000 where !sim.finished { sim.step() }
        XCTAssertTrue(sim.finished)
        XCTAssertEqual(sim.saved, 2) // both over the bridge and home
        XCTAssertTrue(sim.won)
        // The bridge: bricks over the pit, rising as they go.
        XCTAssertEqual(sim.cell(110, 84), .brick)
        XCTAssertEqual(sim.cell(130, 74), .brick)
        XCTAssertEqual(sim.edits.filter { $0.kind == .brick }.count, Penguins.bricks)

        // A wall in the way ends the bridge early; the builder walks on.
        var wall = flat()
        wall.shapes.append(.rect(120, 20, 10, 70))
        var short = PenguinSim(wall)
        XCTAssertTrue(assignAt(&short, 0, .build, 100))
        short.run(120)
        XCTAssertNotEqual(short.penguins[0].state, .building)
        XCTAssertLessThan(short.penguins[0].x, 120)
    }

    func testTouchPicksTheNearestThatCanTakeIt() {
        var l = flat(240, 200)
        l.shapes = [.rect(0, 190, 240, 10)]
        l.entrance = PenguinPoint(20, 10)
        l.total = 3
        l.rate = 40
        var sim = PenguinSim(l)
        // 0 and 1 on the ground, 2 still falling.
        for _ in 0..<2000 {
            if sim.released == 3 && sim.penguins[2].y > 60 { break }
            sim.step()
        }
        let falling = sim.penguins[2]
        XCTAssertEqual(falling.state, .falling)
        XCTAssertEqual(sim.pick(.float, x: Double(falling.x + 10), y: Double(falling.y - 8), radius: 20), 2)
        XCTAssertNil(sim.pick(.dig, x: Double(falling.x + 10), y: Double(falling.y - 8), radius: 20)) // not in the air
        XCTAssertNil(sim.pick(.float, x: Double(falling.x + 40), y: Double(falling.y - 8), radius: 20)) // out of reach

        var two = flat()
        two.total = 2
        two.rate = 20
        var walkers = PenguinSim(two)
        walkers.run(Penguins.openTicks + 20 + 40)
        let a = walkers.penguins[0], b = walkers.penguins[1]
        XCTAssertGreaterThan(a.x, b.x + 10)
        let mid = Double(a.x + b.x) / 2
        XCTAssertEqual(walkers.pick(.dig, x: mid + 2, y: 81, radius: 40), 0)
        XCTAssertEqual(walkers.pick(.dig, x: mid - 2, y: 81, radius: 40), 1)
    }

    func testLevelsAreSound() {
        let all = PenguinLevel.all
        XCTAssertEqual(all.count, 16)
        XCTAssertEqual(Set(all.map(\.name)).count, all.count)
        for l in all {
            XCTAssertFalse(l.hint.isEmpty, l.name)
            XCTAssertTrue(l.need >= 1 && l.need <= l.total, l.name)
            XCTAssertEqual(l.width, 400)
            XCTAssertEqual(l.height, 184)
            XCTAssertTrue(PenguinRect(0, 0, l.width, l.height).contains(l.entrance.x, l.entrance.y), l.name)
            let sim = PenguinSim(l)
            // The igloo stands on the ground.
            XCTAssertTrue(sim.solid(l.exit.x, l.exit.y + 1), l.name)
            XCTAssertFalse(sim.solid(l.exit.x, l.exit.y), l.name)
            XCTAssertFalse(l.solution.isEmpty, l.name)
        }
    }

    /// Each level's recorded solution wins it, with every step taken as
    /// written, and doing nothing doesn't.
    func testEveryLevelCanBeWon() {
        for (i, l) in PenguinLevel.all.enumerated() {
            var sim = PenguinSim(l)
            let applied = sim.replay(l.solution)
            XCTAssertEqual(applied, l.solution.count, "level \(i + 1) \(l.name)")
            XCTAssertTrue(sim.finished, "level \(i + 1) ends")
            XCTAssertTrue(sim.won, "level \(i + 1) \(l.name): saved \(sim.saved) of \(l.total), needed \(l.need)")
            for skill in PenguinSkill.allCases {
                XCTAssertLessThanOrEqual(l.solution.filter { $0.skill == skill }.count, l.count(skill))
            }
            var idle = PenguinSim(l)
            XCTAssertEqual(idle.replay([]), 0)
            XCTAssertFalse(idle.won, "level \(i + 1): it takes skills to win")
        }
    }

    private func fnv(_ h: inout UInt64, _ v: UInt64, bytes: Int = 8) {
        for i in 0..<bytes {
            h ^= (v >> (UInt64(i) * 8)) & 0xFF
            h = h &* 1_099_511_628_211
        }
    }

    private func stateIndex(_ s: PenguinState) -> UInt64 {
        switch s {
        case .falling: return 0
        case .floating: return 1
        case .walking: return 2
        case .blocking: return 3
        case .digging: return 4
        case .bashing: return 5
        case .building: return 6
        case .exiting: return 7
        case .splatting: return 8
        case .drowning: return 9
        case .saved: return 10
        case .lost: return 11
        }
    }

    /// The display's own numbers, from its C++ (Sim::rasterize and replay)
    /// run on the same levels: each level's terrain, hashed cell by cell,
    /// and its solution's replay: the tick it ends, saved, lost, terrain
    /// edits, and a hash of every penguin's x, y and state at every tick.
    func testPlaysExactlyAsTheDisplay() {
        let display: [(terrain: UInt64, tick: Int, saved: Int, lost: Int, edits: Int, trace: UInt64)] = [
            (8_453_130_579_093_200_951, 671, 10, 0, 10, 3_896_425_353_208_327_144),
            (15_998_935_941_247_730_375, 630, 6, 0, 0, 6_935_780_198_033_125_007),
            (5_942_874_558_606_725_363, 589, 9, 0, 0, 13_357_745_913_926_150_385),
            (816_415_877_709_107_715, 704, 10, 0, 12, 8_913_339_406_848_999_844),
            (4_249_049_087_581_013_703, 677, 10, 0, 19, 12_581_755_069_919_776_971),
            (18_135_939_376_383_288_723, 707, 10, 0, 23, 12_051_862_613_100_256_375),
            (16_516_132_695_828_197_255, 544, 9, 0, 12, 12_819_787_500_908_043_949),
            (16_956_069_894_363_266_403, 724, 10, 0, 26, 17_043_550_477_884_265_242),
            (3_300_600_993_236_793_387, 681, 10, 0, 29, 17_909_088_365_630_919_289),
            (14_454_785_471_396_001_954, 690, 8, 0, 12, 6_371_215_446_323_173_986),
            (8_764_442_168_503_997_663, 734, 10, 0, 24, 4_072_628_355_553_566_233),
            (13_854_505_852_369_736_211, 685, 8, 0, 14, 18_277_560_716_528_526_017),
            (9_229_744_369_187_401_295, 741, 10, 0, 34, 14_629_886_610_376_370_499),
            (16_086_590_554_849_719_057, 730, 9, 0, 27, 5_070_953_448_453_655_114),
            (6_170_295_253_987_239_367, 671, 8, 0, 24, 8_713_040_166_136_414_913),
            (123_628_298_388_268_621, 1070, 11, 0, 31, 16_314_673_437_726_851_113),
        ]
        XCTAssertEqual(display.count, PenguinLevel.all.count)
        for (i, l) in PenguinLevel.all.enumerated() {
            var terrain: UInt64 = 1_469_598_103_934_665_603
            for cell in PenguinSim.rasterize(l) { fnv(&terrain, UInt64(cell), bytes: 1) }
            XCTAssertEqual(terrain, display[i].terrain, "level \(i + 1) \(l.name): the terrain")

            var sim = PenguinSim(l)
            var replayer = PenguinReplayer(l.solution)
            var trace: UInt64 = 1_469_598_103_934_665_603
            while !sim.finished && sim.tick < 12000 {
                replayer.apply(&sim)
                sim.step()
                for p in sim.penguins {
                    fnv(&trace, UInt64(UInt32(bitPattern: Int32(p.x))))
                    fnv(&trace, UInt64(UInt32(bitPattern: Int32(p.y))))
                    fnv(&trace, stateIndex(p.state))
                }
            }
            XCTAssertEqual(sim.tick, display[i].tick, "level \(i + 1)")
            XCTAssertEqual(sim.saved, display[i].saved, "level \(i + 1)")
            XCTAssertEqual(sim.lost, display[i].lost, "level \(i + 1)")
            XCTAssertEqual(sim.edits.count, display[i].edits, "level \(i + 1)")
            XCTAssertEqual(trace, display[i].trace, "level \(i + 1) \(l.name): the replay")
        }
    }

    func testProgressKeepsWinsOnly() {
        let suite = "penguin-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = GameProgress(defaults: defaults)
        progress.recordPenguins(level: 2, saved: 7, need: 8) // not a win
        progress.recordPenguins(level: 2, saved: 9, need: 8)
        progress.recordPenguins(level: 2, saved: 8, need: 8) // fewer: kept the most
        progress.penguinLevel = 3
        let again = GameProgress(defaults: defaults)
        XCTAssertEqual(again.penguinBest, [2: 9])
        XCTAssertEqual(again.penguinLevel, 3)
    }
}
