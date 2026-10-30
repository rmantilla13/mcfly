import XCTest
@testable import McFlyKit

/// Dots and Boxes, as the display's tst_games checks it: the fourth side
/// claims a box and goes again, the most boxes wins, and Hard McFly's play,
/// down to the same chain of two given away in the same position.
final class DotsAndBoxesTests: XCTestCase {
    func testTheFourthSideClaimsTheBox() {
        var game = DotsAndBoxes()
        game.setMode(vsComputer: false, hard: false, size: 3)
        XCTAssertEqual(game.lineCount, 24)
        XCTAssertEqual(game.boxes.count, 9)
        XCTAssertEqual(game.turn, .x)
        let s = game.sides(of: 0)
        for l in s.prefix(3) { XCTAssertTrue(game.play(l)) }
        XCTAssertEqual(game.turn, .o)
        XCTAssertTrue(game.play(s[3]))
        XCTAssertEqual(game.boxes[0], .o)
        XCTAssertEqual(game.turn, .o)
        XCTAssertFalse(game.play(s[0]))
        // The line between two boxes closes both.
        for l in game.sides(of: 4) + game.sides(of: 5) where l != game.downLine(1, 2) { game.place(l) }
        let closer = game.turn
        XCTAssertTrue(game.place(game.downLine(1, 2)))
        XCTAssertEqual(game.boxes[4], closer)
        XCTAssertEqual(game.boxes[5], closer)
        XCTAssertEqual(game.turn, closer)
        for l in 0..<game.lineCount { game.place(l) }
        XCTAssertTrue(game.over)
        XCTAssertEqual(game.xBoxes + game.oBoxes, 9)
        XCTAssertNotNil(game.winner)
        XCTAssertEqual(game.score[game.winner!], 1)
        // The next round, the other player starts.
        let starter = game.starter
        game.newRound()
        XCTAssertEqual(game.starter, starter.other)
        XCTAssertEqual(game.turn, game.starter)
        XCTAssertTrue(game.lines.allSatisfy { $0 == nil })
    }

    /// Thirty games against random lines: McFly takes a box whenever there's
    /// a safe line too, never draws a third side while a safe line is left,
    /// and wins nearly all of them (about 99 in 100 on the display).
    func testHardMcFlyPlaysSafeAndWins() {
        var rng = SeededRandom(11)
        var game = DotsAndBoxes()
        game.setMode(vsComputer: true, hard: true, size: 3)
        var won = 0
        for _ in 0..<30 {
            game.newRound()
            while !game.over {
                if game.turn == .o {
                    let sorted = game.sortLines(game.lines)
                    let l = game.bestLine(using: &rng)!
                    if !sorted.closing.isEmpty && !sorted.safe.isEmpty { XCTAssertTrue(sorted.closing.contains(l)) }
                    if sorted.closing.isEmpty && !sorted.safe.isEmpty { XCTAssertTrue(sorted.safe.contains(l)) }
                    game.place(l)
                } else {
                    game.place(game.lines.indices.filter { game.lines[$0] == nil }.randomElement(using: &rng)!)
                }
            }
            if game.winner == .o { won += 1 }
        }
        XCTAssertGreaterThanOrEqual(won, 24)
    }

    /// Box 0 closes into box 1 (the rest of box 1 open to the edge), and the
    /// six other open boxes make one long chain; box 4 is taken. McFly gives
    /// the two away to keep the six, as on the display.
    func testHardMcFlyKeepsControl() {
        var rng = SeededRandom(3)
        var game = DotsAndBoxes()
        game.setMode(vsComputer: true, hard: true, size: 3)
        var lines = [Mark?](repeating: nil, count: 24)
        for l in [game.acrossLine(0, 0), game.downLine(0, 0), game.acrossLine(1, 0), game.acrossLine(1, 1), game.downLine(0, 2),
                  game.downLine(0, 3), game.downLine(1, 1), game.downLine(1, 2), game.acrossLine(2, 1), game.downLine(1, 3),
                  game.downLine(2, 0), game.acrossLine(3, 0), game.acrossLine(3, 1), game.downLine(2, 3), game.acrossLine(3, 2)] {
            lines[l] = .x
        }
        var boxes = [Mark?](repeating: nil, count: 9)
        boxes[4] = .x
        game.set(lines: lines, boxes: boxes, turn: .x)
        let sorted = game.sortLines(game.lines)
        XCTAssertTrue(sorted.safe.isEmpty)
        XCTAssertEqual(sorted.closing.count, 1)
        XCTAssertEqual(game.bestLine(using: &rng), game.acrossLine(0, 1))
        // With nothing left after them, it takes the two.
        for l in lines.indices where lines[l] == nil && l != game.downLine(0, 1) && l != game.acrossLine(0, 1) { lines[l] = .x }
        game.set(lines: lines, boxes: boxes.indices.map { $0 < 2 ? nil : .x }, turn: .x)
        XCTAssertEqual(game.bestLine(using: &rng), game.downLine(0, 1))
    }
}
