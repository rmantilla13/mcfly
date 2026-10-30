import XCTest
@testable import McFlyKit

/// Solitaire, as the display's tst_games checks it: the deal (seed 7 deals
/// the display's game, card for card), the deck, the rules a tap moves by,
/// Undo, the cards going home on their own, and what's kept.
final class SolitaireTests: XCTestCase {
    func testDealsTheDisplaysGame() {
        let game = Solitaire(seed: 7)
        XCTAssertEqual(game.tableau, [[39], [0, 51], [8, 32, 15], [33, 19, 6, 5], [49, 25, 7, 43, 17], [26, 1, 13, 31, 20, 27],
                                      [37, 10, 29, 24, 4, 9, 23]]) // tst_games' solitaireDealsAndPlays
        XCTAssertEqual(game.hidden, [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(game.stock.count, 24)
        XCTAssertTrue(game.waste.isEmpty)
        XCTAssertTrue(game.isValid)
        XCTAssertEqual(Solitaire(seed: 7), game)
        XCTAssertNotEqual(Solitaire(seed: 8).tableau, game.tableau)
    }

    func testTheDeck() {
        var game = Solitaire(seed: 7)
        XCTAssertTrue(game.draw())
        XCTAssertEqual(game.waste.count, 1)
        XCTAssertEqual(game.stock.count, 23)
        XCTAssertEqual(game.moves, 1)
        while !game.stock.isEmpty { game.draw() }
        let first = game.waste[0]
        // Empty, a tap turns the waste back over: the first card turned is on top.
        XCTAssertTrue(game.draw())
        XCTAssertEqual(game.stock.count, 24)
        XCTAssertTrue(game.waste.isEmpty)
        XCTAssertEqual(game.stock.last, first)
        // Three at a time is a new game.
        game.setDrawThree(true)
        XCTAssertEqual(game.moves, 0)
        XCTAssertTrue(game.draw())
        XCTAssertEqual(game.waste.count, 3)
        XCTAssertEqual(game.stock.count, 21)
    }

    func testTapsMoveByTheRules() {
        var game = Solitaire(seed: 1)
        // The ace of spades on the waste; the king of spades alone in the
        // first column; the queen of hearts on a face-down card in the
        // second; the king of hearts on one in the fourth.
        game.set(stock: [40, 41], waste: [0], foundations: [[], [], [], []],
                 tableau: [[12], [5, 24], [], [7, 25], [], [], []], hidden: [0, 1, 0, 1, 0, 0, 0])
        XCTAssertTrue(game.tapWaste())
        XCTAssertEqual(game.foundations[0], [0])
        XCTAssertTrue(game.tapColumn(1, at: 1))
        XCTAssertEqual(game.tableau[0], [12, 24])
        XCTAssertEqual(game.tableau[1], [5])
        XCTAssertEqual(game.hidden[1], 0)
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.tableau[0], [12])
        XCTAssertEqual(game.tableau[1], [5, 24])
        XCTAssertEqual(game.hidden[1], 1)
        XCTAssertEqual(game.moves, 1)
        // A tap on a face-down card moves the face-up one on it.
        XCTAssertTrue(game.tapColumn(1, at: 0))
        XCTAssertEqual(game.tableau[0], [12, 24])
        XCTAssertTrue(game.undo())
        // A king to an empty column, from on a face-down card; not when it's
        // the whole of a column already.
        XCTAssertTrue(game.tapColumn(3, at: 1))
        XCTAssertEqual(game.tableau[2], [25])
        XCTAssertEqual(game.tableau[3], [7])
        XCTAssertEqual(game.hidden[3], 0)
        XCTAssertFalse(game.tapColumn(2, at: 0))
        // Red on red, a rank too low, the same colour: no.
        XCTAssertFalse(game.fitsColumn(24, 2) || game.fitsColumn(23, 0) || game.fitsColumn(11, 0))
        XCTAssertTrue(game.fitsColumn(24, 0) && game.fitsColumn(37, 0))
        // A home card comes back down onto a column.
        game.set(stock: [], waste: [], foundations: [[], [13, 14], [], []], tableau: [[2], [], [], [], [], [], []],
                 hidden: [0, 0, 0, 0, 0, 0, 0])
        XCTAssertTrue(game.tapHome(1))
        XCTAssertEqual(game.tableau[0], [2, 14])
        XCTAssertEqual(game.foundations[1], [13])
    }

    func testTheRestGoHomeAndAWinIsKept() {
        var game = Solitaire(seed: 1)
        game.set(stock: [], waste: [], foundations: [[], [], [], []],
                 tableau: (0..<4).map { s in (0..<13).map { s * 13 + 12 - $0 } } + [[], [], []],
                 hidden: [0, 0, 0, 0, 0, 0, 0], moves: 40)
        XCTAssertTrue(game.finishing)
        XCTAssertFalse(game.draw())
        var steps = 0
        while game.finishStep() { steps += 1 }
        XCTAssertEqual(steps, 52)
        XCTAssertTrue(game.won)
        XCTAssertEqual(game.moves, 40) // going home on its own isn't a move
        XCTAssertFalse(game.undo())

        let defaults = UserDefaults(suiteName: "SolitaireTests")!
        defaults.removePersistentDomain(forName: "SolitaireTests")
        let progress = GameProgress(defaults: defaults)
        progress.recordSolitaireWin(moves: 40)
        progress.recordSolitaireWin(moves: 55)
        XCTAssertEqual(progress.solitaireWins, 2)
        XCTAssertEqual(progress.solitaireFewest, 40)
        // A game in progress comes back as it was left; a won one doesn't.
        var playing = Solitaire(seed: 3, drawThree: true)
        playing.draw()
        playing.draw()
        progress.solitaire = playing
        let back = progress.solitaire
        XCTAssertEqual(back?.tableau, playing.tableau)
        XCTAssertEqual(back?.waste, playing.waste)
        XCTAssertEqual(back?.moves, 2)
        XCTAssertEqual(back?.drawThree, true)
        progress.solitaire = game
        XCTAssertNil(progress.solitaire)
    }
}
