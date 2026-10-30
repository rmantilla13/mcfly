import XCTest
@testable import McFlyKit

/// Pairs, as the display's tst_games checks it: every picture twice from
/// different shelves, a pair stays up, a miss turns back, turns and the
/// fewest kept, and McFly's play.
final class PairsTests: XCTestCase {
    func testDealsEveryPictureTwiceFromDifferentShelves() {
        var rng = SeededRandom(5)
        var game = Pairs()
        for size in Pairs.sizes {
            game.setSize(size, using: &rng)
            XCTAssertEqual(game.faces.count, size)
            XCTAssertTrue(game.faces.allSatisfy { f in game.faces.filter { $0 == f }.count == 2 })
            XCTAssertEqual(Set(game.faces.map { ColorByNumber.pictures[$0].category }).count, size / 2)
        }
    }

    func testAloneAPairStaysUpAndAMissTurnsBack() {
        var game = Pairs()
        game.setSize(12)
        game.set(faces: [1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6])
        XCTAssertTrue(game.play(0))
        XCTAssertTrue(game.play(6))
        XCTAssertEqual(game.found[0], .x)
        XCTAssertEqual(game.moves, 1)
        XCTAssertFalse(game.play(0))
        // A miss: both up until the next tap, which turns them back and its card over.
        XCTAssertTrue(game.play(1))
        XCTAssertTrue(game.play(2))
        XCTAssertTrue(game.missed)
        XCTAssertEqual(game.moves, 2)
        XCTAssertTrue(game.play(3))
        XCTAssertEqual(game.up, [3])
        XCTAssertTrue(game.play(9))
        for i in [1, 2, 4, 5] {
            game.play(i)
            game.play(i + 6)
        }
        XCTAssertTrue(game.over)
        XCTAssertEqual(game.moves, 7)
        XCTAssertNil(game.winner)
    }

    func testTwoPlayersTakeTurns() {
        var game = Pairs()
        game.setMode(.two, hard: false)
        XCTAssertEqual(game.turn, .x)
        game.set(faces: [1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6])
        game.play(0)
        game.play(6)
        XCTAssertEqual(game.score.x, 1)
        XCTAssertEqual(game.turn, .x) // a pair goes again
        game.play(1)
        game.play(2)
        game.hideNow()
        XCTAssertEqual(game.turn, .o)
        XCTAssertEqual(game.moves, 0) // turns are counted alone only
        game.deal()
        XCTAssertEqual(game.turn, .o) // the other player starts the next round
    }

    func testMcFlyFindsWhatItHasSeen() {
        var rng = SeededRandom(9)
        var game = Pairs()
        game.setMode(.mcfly, hard: true, using: &rng)
        XCTAssertEqual(game.turn, .x)
        XCTAssertFalse(game.computerTurn)
        let faces = game.faces
        // The partner of the card it just turned, when it has seen it.
        let partner = faces.indices.first { $0 != 0 && faces[$0] == faces[0] }!
        game.set(faces: faces, turn: .o, seen: [partner: faces[partner]], up: [0])
        XCTAssertEqual(game.computerPick(using: &rng), partner)
        // With one card up it hasn't seen the partner of, a card it hasn't seen.
        let other = faces.indices.first { faces[$0] != faces[0] }!
        game.set(faces: faces, turn: .o, seen: [other: faces[other]], up: [0])
        for _ in 0..<20 { XCTAssertNotEqual(game.computerPick(using: &rng), other) }
        // Having seen every card, it clears the board on its turn; you can't play meanwhile.
        game.set(faces: faces, turn: .o, seen: Dictionary(uniqueKeysWithValues: faces.indices.map { ($0, faces[$0]) }))
        XCTAssertFalse(game.play(0))
        while game.computerTurn { game.computerMove(using: &rng) }
        XCTAssertTrue(game.over)
        XCTAssertEqual(game.score.o, faces.count / 2)
        XCTAssertEqual(game.winner, .o)
    }

    func testTheFewestTurnsAreKeptForEachSize() {
        let defaults = UserDefaults(suiteName: "PairsTests")!
        defaults.removePersistentDomain(forName: "PairsTests")
        let progress = GameProgress(defaults: defaults)
        progress.recordPairs(size: 12, moves: 8)
        progress.recordPairs(size: 12, moves: 9)
        progress.recordPairs(size: 20, moves: 14)
        progress.recordPairs(size: 12, moves: 6)
        XCTAssertEqual(progress.pairsBest, [12: 6, 20: 14])
    }
}
