import XCTest
@testable import McFlyKit

/// Scoop Shop's orders and scoring, as the display's tst_games checks them,
/// and its generator against scoops.js's own output.
final class ScoopShopTests: XCTestCase {
    private func order(_ base: ScoopBase, _ scoops: [ScoopFlavour], _ toppings: [ScoopTopping] = []) -> ScoopOrder {
        ScoopOrder(base: base, scoops: scoops, toppings: toppings)
    }

    /// The same numbers and orders as scoops.js (as of display f8fc4d6, before
    /// the menu grew to seven and seven), run under node with the same
    /// seeds: a shift can be replayed on either.
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
            (3, 42, [order(.cup, [.chocolate, .mint], [.sprinkles]), order(.cone, [.strawberry], [.cherry]),
                     order(.cup, [.strawberry, .chocolate])], 0.6866120179183781),
            (5, 1234, [order(.cone, [.strawberry, .mint], [.sprinkles, .cherry]), order(.cup, [.chocolate, .vanilla, .strawberry]),
                       order(.cup, [.chocolate, .chocolate, .chocolate])], 0.8682829476892948),
            (7, 99999, [order(.cup, [.strawberry, .strawberry, .strawberry], [.sprinkles]), order(.cup, [.vanilla, .mint, .chocolate], [.wafer]),
                        order(.cone, [.mint, .strawberry, .strawberry], [.sprinkles, .wafer])], 0.06572708999738097),
            (10, 4_294_967_295, [order(.cone, [.vanilla, .strawberry, .mint], [.cherry, .wafer]), order(.cup, [.mint, .mint], [.cherry]),
                                 order(.cone, [.mint, .mint], [.sprinkles])], 0.9202409950084984),
            (10, 23767, [order(.cup, [.mint, .vanilla, .vanilla], [.sprinkles, .cherry]), order(.cup, [.chocolate, .strawberry], [.sprinkles, .cherry]),
                         order(.cone, [.strawberry, .strawberry], [.cherry])], 0.8146749250590801),
            (4, 2026, [order(.cone, [.chocolate, .strawberry], [.sprinkles]), order(.cup, [.mint, .chocolate, .vanilla]),
                       order(.cone, [.vanilla, .vanilla])], 0.9208663781173527),
        ]
        for c in cases {
            var rand = Scoops.Random(seed: c.seed)
            let orders = (0..<3).map { _ in Scoops.makeOrder(c.level, &rand) }
            XCTAssertEqual(orders, c.orders, "level \(c.level) seed \(c.seed)")
            XCTAssertEqual(rand(), c.after, accuracy: 1e-15)
        }
    }

    func testOrdersFollowTheLevel() {
        // Every order is a cone or a cup, with scoops and toppings from the
        // menu, as many as its level allows; level 10 asks for the most.
        var biggest = 0
        for lv in 1...10 {
            let r = Scoops.rules(lv)
            for s in 1...300 {
                var rand = Scoops.Random(seed: UInt32(s * 7919 + lv))
                let o = Scoops.makeOrder(lv, &rand)
                XCTAssertNotNil(o.base)
                XCTAssertTrue((r.minScoops...r.maxScoops).contains(o.scoops.count), "level \(lv): \(o)")
                XCTAssertTrue((r.minToppings...r.maxToppings).contains(o.toppings.count), "level \(lv): \(o)")
                XCTAssertEqual(Set(o.toppings).count, o.toppings.count)
                if lv == 10 { biggest = max(biggest, o.scoops.count + o.toppings.count) }
            }
        }
        XCTAssertEqual(biggest, 5)

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
        // The pace (display f8fc4d6): a cone of one scoop waits 27 s at level 1,
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
