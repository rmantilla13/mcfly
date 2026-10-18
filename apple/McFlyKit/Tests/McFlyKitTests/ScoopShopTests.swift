import XCTest
@testable import McFlyKit

/// Scoop Shop's orders and scoring, as the display's tst_games checks them,
/// and its generator against scoops.js's own output.
final class ScoopShopTests: XCTestCase {
    private func order(_ base: ScoopBase, _ scoops: [ScoopFlavour], _ toppings: [ScoopTopping] = []) -> ScoopOrder {
        ScoopOrder(base: base, scoops: scoops, toppings: toppings)
    }

    /// The same numbers and orders as scoops.js, run under node with the same
    /// seeds: a shift can be replayed on either. Levels 1 and 2 keep to the
    /// first four flavours, level 3 adds the rest, level 4 the new toppings.
    func testTheGeneratorIsScoopsJs() {
        var state: UInt32 = 7
        let units = (0..<5).map { _ -> Double in
            state = Scoops.next(state)
            return Scoops.unit(state)
        }
        let expected = [0.011704753153026104, 0.06195825757458806, 0.97690763277933, 0.6990287057124078, 0.5214452685322613]
        for (a, b) in zip(units, expected) { XCTAssertEqual(a, b, accuracy: 1e-15) }

        let cases: [(level: Int, seed: UInt32, orders: [ScoopOrder], after: Double)] = [
            (1, 1, [order(.cup, [.vanilla]), order(.cup, [.chocolate]), order(.cone, [.mint])], 0.13893358339555562),
            (2, 7, [order(.cup, [.vanilla], [.wafer]), order(.cup, [.chocolate]), order(.cone, [.chocolate, .vanilla], [.cherry])],
             0.3679585934150964),
            (3, 42, [order(.cup, [.mint, .blueberry], [.sprinkles]), order(.cone, [.mango], [.cherry]),
                     order(.cup, [.blueberry, .strawberry])], 0.6866120179183781),
            (5, 1234, [order(.cone, [.mango, .cookies], [.sprinkles, .cherry]), order(.cup, [.strawberry, .vanilla, .mint]),
                       order(.cup, [.chocolate, .strawberry, .mint])], 0.8682829476892948),
            (7, 99999, [order(.cup, [.mint, .mango, .mango], [.sprinkles]), order(.cup, [.chocolate, .cookies, .strawberry], [.rings]),
                        order(.cone, [.cookies, .mint, .mango], [.wafer, .cream])], 0.06572708999738097),
            (10, 4_294_967_295, [order(.cone, [.chocolate, .blueberry, .cookies], [.syrup, .rings]), order(.cup, [.cookies, .cookies], [.wafer]),
                                 order(.cone, [.blueberry, .cookies], [.cherry])], 0.9202409950084984),
            (10, 23767, [order(.cup, [.cookies, .vanilla, .vanilla], [.cherry, .syrup]), order(.cup, [.strawberry, .mint], [.wafer, .syrup]),
                         order(.cone, [.mango, .mint], [.syrup])], 0.8146749250590801),
            (4, 2026, [order(.cone, [.strawberry, .mango], [.cherry]), order(.cup, [.blueberry, .strawberry, .vanilla]),
                       order(.cone, [.vanilla, .chocolate])], 0.9208663781173527),
            (3, 5, [order(.cup, [.blueberry, .chocolate], [.sprinkles]), order(.cup, [.mint, .cookies]), order(.cone, [.mango, .vanilla])],
             0.8965497829485685),
            (4, 77, [order(.cup, [.vanilla, .mango], [.sprinkles]), order(.cup, [.blueberry, .vanilla, .chocolate], [.wafer, .crunch]),
                     order(.cone, [.vanilla, .vanilla])], 0.5065870243124664),
            (10, 8, [order(.cup, [.mango, .strawberry], [.wafer, .crunch]), order(.cone, [.mint, .vanilla], [.sprinkles, .crunch]),
                     order(.cone, [.cookies, .mango], [.sprinkles])], 0.5559864083770663),
        ]
        for c in cases {
            var rand = Scoops.Random(seed: c.seed)
            let orders = (0..<3).map { _ in Scoops.makeOrder(c.level, &rand) }
            XCTAssertEqual(orders, c.orders, "level \(c.level) seed \(c.seed)")
            XCTAssertEqual(rand(), c.after, accuracy: 1e-15)
        }
    }

    func testOrdersFollowTheLevel() {
        // Every order is a cone or a cup, with scoops and toppings from what
        // its level offers, as many as it allows. Levels 1 and 2 keep to the
        // first four flavours and level 3 the first three toppings; by
        // level 10 every flavour and topping turns up, and the biggest orders.
        var biggest = 0
        var seenFlavours = Set<ScoopFlavour>(), seenToppings = Set<ScoopTopping>()
        for lv in 1...10 {
            let r = Scoops.rules(lv)
            for s in 1...300 {
                var rand = Scoops.Random(seed: UInt32(s * 7919 + lv))
                let o = Scoops.makeOrder(lv, &rand)
                XCTAssertNotNil(o.base)
                XCTAssertTrue((r.minScoops...r.maxScoops).contains(o.scoops.count), "level \(lv): \(o)")
                XCTAssertTrue((r.minToppings...r.maxToppings).contains(o.toppings.count), "level \(lv): \(o)")
                XCTAssertTrue(o.scoops.allSatisfy(r.flavours.contains), "level \(lv): \(o)")
                XCTAssertTrue(o.toppings.allSatisfy(r.toppings.contains), "level \(lv): \(o)")
                XCTAssertEqual(Set(o.toppings).count, o.toppings.count)
                if lv == 10 {
                    biggest = max(biggest, o.scoops.count + o.toppings.count)
                    seenFlavours.formUnion(o.scoops)
                    seenToppings.formUnion(o.toppings)
                }
            }
        }
        XCTAssertEqual(biggest, 5)
        XCTAssertEqual([Scoops.rules(2).flavours.count, Scoops.rules(3).flavours.count], [4, 7])
        XCTAssertEqual([Scoops.rules(3).toppings.count, Scoops.rules(4).toppings.count], [3, 7])
        XCTAssertEqual(Scoops.rules(1).flavours, [.vanilla, .chocolate, .strawberry, .mint])
        XCTAssertEqual(Scoops.rules(1).toppings, [.sprinkles, .cherry, .wafer])
        XCTAssertEqual(seenFlavours.count, 7)
        XCTAssertEqual(seenToppings.count, 7)

        // It gets busier: more seats, bigger orders, less time, sooner.
        for lv in 1..<10 {
            let a = Scoops.rules(lv), b = Scoops.rules(lv + 1)
            XCTAssertTrue(b.seats >= a.seats && b.maxScoops >= a.maxScoops && b.maxToppings >= a.maxToppings && b.minScoops >= a.minScoops)
            XCTAssertTrue(b.wait <= a.wait && b.perItem <= a.perItem && b.arrival <= a.arrival)
        }
        let one = Scoops.rules(1), ten = Scoops.rules(10)
        XCTAssertEqual([one.seats, one.maxScoops, one.maxToppings, ten.seats], [2, 1, 0, 4])
        let big = order(.cup, [.mint, .mint, .vanilla], [.cherry, .wafer])
        XCTAssertLessThan(Scoops.patience(big, level: 10), Scoops.patience(big, level: 5))
        XCTAssertLessThan(Scoops.patience(big, level: 5), Scoops.patience(big, level: 1))
        // At the busiest, a full counter of the biggest orders can still be
        // served: four customers, seven taps each, two taps a second.
        XCTAssertGreaterThanOrEqual(Scoops.patience(big, level: 10), 4 * 7 * 500)
        // The pace: a cone of one scoop waits 27 s at level 1,
        // a tenth under the first tuning's 30 s, and customers come every 6.3 s.
        XCTAssertEqual(Scoops.patience(order(.cone, [.mint]), level: 1), 27000)
        XCTAssertEqual(Scoops.rules(1).arrival, 6300)
        XCTAssertEqual(Scoops.rules(10).arrival, 2250)
        XCTAssertEqual(Scoops.patience(big, level: 10), 17640)
        // Quick scores more than slow, and right scores at least ten a thing.
        XCTAssertEqual(Scoops.points(order(.cone, [.mint]), left: 1), 40)
        XCTAssertEqual(Scoops.points(order(.cone, [.mint]), left: 0), 20)
        XCTAssertEqual(Scoops.points(order(.cone, [.mint]), left: 0.5), 30)
    }

    private func shift() -> ScoopShift {
        var s = ScoopShift()
        s.seed = 7
        return s
    }

    func testARightOrderScores() {
        var s = shift()
        s.start(.lotl)
        XCTAssertEqual(s.phase, .playing)
        XCTAssertEqual(s.worker, .lotl)
        XCTAssertEqual(s.seats.compactMap { $0 }.count, 0)
        s.advance(1000) // the first customer, a second in
        XCTAssertEqual(s.seats.compactMap { $0 }.count, 1)
        let at = s.seats.firstIndex { $0 != nil }!

        // Make their ticket at the counter, and hand it over.
        s.advance(2000)
        let o = s.seats[at]!.order
        s.pickBase(o.base!)
        for f in o.scoops { XCTAssertNotNil(try? s.addScoop(f)?.get()) }
        for t in o.toppings { XCTAssertNotNil(try? s.addTopping(t)?.get()) }
        let c = s.seats[at]!
        let expected = Scoops.points(c.order, left: 1 - (s.now - c.arrived) / Double(c.patience))
        XCTAssertGreaterThan(expected, 0)
        XCTAssertEqual(try? s.deliver(at)?.get(), .right)
        XCTAssertEqual(s.score, expected)
        XCTAssertEqual(s.served, 1)
        XCTAssertEqual(s.hearts, 3)
        XCTAssertEqual(s.seats[at]?.gone, .right)
        XCTAssertNil(s.build.base) // a fresh start
        // They're gone once they've walked off; handing them more does nothing.
        XCTAssertNil(s.deliver(at))
        s.advance(700)
        XCTAssertNil(s.seats[at])
    }

    func testAWrongOrderCostsAHeart() {
        var s = shift()
        s.start(.pip)
        let o = order(.cone, [.vanilla, .chocolate], [.cherry, .sprinkles])

        // The same scoops the other way up is the wrong order.
        s.seat(0, o)
        s.pickBase(.cone)
        _ = s.addScoop(.chocolate)
        _ = s.addScoop(.vanilla)
        _ = s.addTopping(.cherry)
        _ = s.addTopping(.sprinkles)
        XCTAssertEqual(try? s.deliver(0)?.get(), .wrong)
        XCTAssertEqual(s.hearts, 2)
        XCTAssertEqual(s.score, 0)
        XCTAssertEqual(s.seats[0]?.gone, .wrong)
        XCTAssertTrue(s.build.scoops.isEmpty)

        // Toppings go on in any order.
        s.seat(1, o)
        s.pickBase(.cone)
        _ = s.addScoop(.vanilla)
        _ = s.addScoop(.chocolate)
        _ = s.addTopping(.sprinkles)
        _ = s.addTopping(.cherry)
        XCTAssertEqual(try? s.deliver(1)?.get(), .right)
        XCTAssertEqual(s.hearts, 2)

        // A cup for a cone is wrong too; nothing made hands nothing over.
        s.seat(2, order(.cone, [.mint]))
        if case .failure(let why)? = s.deliver(2) { XCTAssertEqual(why, .makeFirst) } else { XCTFail("handed over nothing") }
        s.pickBase(.cup)
        _ = s.addScoop(.mint)
        XCTAssertEqual(try? s.deliver(2)?.get(), .wrong)
        XCTAssertEqual(s.hearts, 1)

        // The counter's own rules: a cone or cup before scoops, three at
        // most, toppings on a scoop, once each; undo takes off the top.
        if case .failure(let why)? = s.addScoop(.mint) { XCTAssertEqual(why, .baseFirst) } else { XCTFail("a scoop with no cone") }
        XCTAssertTrue(s.pickBase(.cup))
        if case .failure(let why)? = s.addTopping(.cherry) { XCTAssertEqual(why, .scoopFirst) } else { XCTFail("a topping on nothing") }
        for f in [ScoopFlavour.mint, .vanilla, .mint] { XCTAssertNotNil(try? s.addScoop(f)?.get()) }
        if case .failure(let why)? = s.addScoop(.chocolate) { XCTAssertEqual(why, .threeAtMost) } else { XCTFail("a fourth scoop") }
        XCTAssertNotNil(try? s.addTopping(.wafer)?.get())
        XCTAssertNil(s.addTopping(.wafer)) // once each
        XCTAssertTrue(s.pickBase(.cone)) // a cone instead, scoops and all
        XCTAssertEqual(s.build, order(.cone, [.mint, .vanilla, .mint], [.wafer]))
        XCTAssertTrue(s.undo() && s.undo())
        XCTAssertEqual(s.build, order(.cone, [.mint, .vanilla]))
        XCTAssertTrue(s.undo() && s.undo() && s.undo())
        XCTAssertFalse(s.undo())
        XCTAssertNil(s.build.base)
    }

    func testACustomerGivesUp() {
        var s = shift()
        s.start(.pip)
        let wait = s.seat(0, order(.cup, [.mint]))
        XCTAssertEqual(wait, Scoops.patience(order(.cup, [.mint]), level: 1))
        XCTAssertGreaterThanOrEqual(wait, 20000)
        s.advance(Double(wait - 100))
        XCTAssertEqual(s.seats[0]?.gone, .waiting)
        XCTAssertEqual(s.hearts, 3)
        XCTAssertEqual(s.advance(200), 1)
        XCTAssertEqual(s.seats[0]?.gone, .late)
        XCTAssertEqual(s.hearts, 2)
        XCTAssertEqual(s.served, 0)
    }

    func testCustomersFlipOut() {
        var s = shift()
        s.start(.pip)
        let wait = s.seat(0, order(.cone, [.mango]))
        func face() -> Scoops.Face { s.seats[0]!.face(at: s.now) }
        XCTAssertEqual(face(), .smile)
        XCTAssertFalse(s.alarm)
        s.advance(Double(wait * 6 / 10))
        XCTAssertEqual(face(), .flat)
        s.advance(Double(wait * 15 / 100))
        XCTAssertEqual(face(), .frown)
        XCTAssertFalse(s.alarm)
        // The last fifth: they flip out, and the shopkeeper panics.
        s.advance(Double(wait * 1 / 10))
        XCTAssertEqual(face(), .furious)
        XCTAssertTrue(s.alarm)
        // Served in time, they're happy; the panic stays only while someone
        // else is that close.
        s.pickBase(.cone)
        XCTAssertNotNil(try? s.addScoop(.mango)?.get())
        XCTAssertEqual(try? s.deliver(0)?.get(), .right)
        XCTAssertEqual(face(), .happy)
        let others = s.seats.indices.contains { i in
            i != 0 && s.seats[i].map { $0.gone == .waiting && $0.patienceLeft(at: s.now) <= Scoops.furious } == true
        }
        XCTAssertEqual(s.alarm, others)
        // The faces' edges: flat to frown at 0.3, frown to furious at 0.2.
        XCTAssertEqual(Scoops.face(left: 0.2, gone: .waiting), .furious)
        XCTAssertEqual(Scoops.face(left: 0.21, gone: .waiting), .frown)
        XCTAssertEqual(Scoops.face(left: 0.3, gone: .waiting), .frown)
        XCTAssertEqual(Scoops.face(left: 0.31, gone: .waiting), .flat)
        XCTAssertEqual(Scoops.face(left: 0, gone: .late), .cross)
        // Once the shop has closed, nobody is flipping out.
        s.endShift()
        XCTAssertFalse(s.alarm)
    }

    func testTheShopClosesAfterThreeHeartsAndKeepsTheBest() {
        var s = shift()
        s.start(.pip)
        // Nobody served: the customers give up, one after another.
        s.advance(600_000)
        XCTAssertEqual(s.phase, .over)
        XCTAssertEqual(s.hearts, 0)
        // The shop is shut: time stands still and taps do nothing.
        let now = s.now
        s.advance(5000)
        XCTAssertEqual(s.now, now)
        XCTAssertFalse(s.pickBase(.cone))
        XCTAssertNil(s.deliver(0))
        // The next shift starts fresh.
        s.start(.lotl)
        XCTAssertEqual(s.phase, .playing)
        XCTAssertEqual(s.hearts, 3)
        XCTAssertEqual(s.score, 0)
        XCTAssertEqual(s.seats.compactMap { $0 }.count, 0)

        // Serve until the score passes the best so far, then close up.
        let before = s.best
        for _ in 0..<100 where s.score <= before {
            s.seat(0, order(.cone, [.vanilla]))
            s.pickBase(.cone)
            _ = s.addScoop(.vanilla)
            XCTAssertEqual(try? s.deliver(0)?.get(), .right)
            s.advance(700)
        }
        XCTAssertGreaterThan(s.score, before)
        s.endShift()
        XCTAssertTrue(s.newBest)
        XCTAssertEqual(s.best, s.score)
        // A worse shift leaves it.
        let best = s.best
        s.start(.pip)
        s.advance(600_000)
        XCTAssertFalse(s.newBest)
        XCTAssertEqual(s.best, best)
    }

    func testPausedTheClockStops() {
        var s = shift()
        s.start(.pip)
        s.advance(1000)
        s.pause()
        XCTAssertFalse(s.playing)
        let now = s.now
        s.advance(10000)
        XCTAssertEqual(s.now, now)
        XCTAssertFalse(s.pickBase(.cone))
        s.resume()
        s.advance(100)
        XCTAssertEqual(s.now, now + 100)
    }
}
