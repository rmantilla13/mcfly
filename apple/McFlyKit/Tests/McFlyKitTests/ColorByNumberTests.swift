import XCTest
@testable import McFlyKit

/// Color by Number, as the display's tst_colors checks it: the pictures,
/// painting and progress, and the board's view and touch. Then the Swift
/// held to the display: the kit's copy of the picture file against
/// display/src/games/colorbynumber.txt byte for byte, every picture cell for
/// cell, and a scripted run of the board, with the numbers a scratch build of
/// display/src/games/ColorByNumber.cpp printed.
final class ColorByNumberTests: XCTestCase {
    /// The first cell (column, row) carrying `number`.
    private func firstOf(_ sheet: ColorSheet, _ number: Int) -> (column: Int, row: Int)? {
        for row in 0..<sheet.height {
            for column in 0..<sheet.width where sheet.numberAt(column, row) == number {
                return (column, row)
            }
        }
        return nil
    }

    /// A sweep across every row of the picture, as tst_colors makes them,
    /// counting the paint calls that finished it.
    private func sweepRows(_ board: inout ColorBoard, finished: inout Int) {
        for r in 0..<board.sheet.height {
            let count = board.paintLine(from: board.cellCenter(0, r), to: board.cellCenter(board.sheet.width - 1, r))
            if count > 0 && board.done { finished += 1 }
        }
    }

    func testEveryPictureIsWellFormed() {
        var ids = Set<String>()
        for source in ColorByNumber.sources {
            XCTAssertNil(ColorByNumber.check(source), source.id)
            XCTAssertTrue(ids.insert(source.id).inserted, source.id)
        }
        // None was dropped for a fault, and there are plenty to choose from.
        XCTAssertEqual(ColorByNumber.pictures.count, ColorByNumber.sources.count)
        XCTAssertGreaterThanOrEqual(ColorByNumber.pictures.count, 600)
        // The first twelve keep their places (the card's art and these tests count on them).
        XCTAssertEqual(ColorByNumber.pictures.prefix(12).map(\.id),
                       ["heart", "strawberry", "rainbow", "mushroom", "icecream", "flower", "cat", "rocket", "tree", "house", "pip", "lotl"])
        XCTAssertEqual(ColorByNumber.index(of: "pip"), 10)
        XCTAssertNil(ColorByNumber.index(of: "nothing"))
        // Every category has a shelf's worth.
        XCTAssertGreaterThanOrEqual(ColorByNumber.categories.count, 6)
        for c in ColorByNumber.categories {
            XCTAssertGreaterThanOrEqual(ColorByNumber.pictures(in: c.id).count, 8, c.id)
            XCTAssertFalse(c.title.isEmpty)
        }
        XCTAssertEqual(ColorByNumber.pictures(in: "").count, ColorByNumber.pictures.count)
        // Colours that look alike are told apart from ones that don't.
        func rgb(_ hex: String) -> ColorByNumber.RGB { ColorByNumber.RGB(hex: hex)! }
        XCTAssertLessThan(ColorByNumber.colorDistance(rgb("#FFFFFF"), rgb("#FAFAFA")), ColorByNumber.minColorDistance)
        XCTAssertGreaterThan(ColorByNumber.colorDistance(rgb("#E5484D"), rgb("#5B8DEF")), ColorByNumber.minColorDistance)
        for p in ColorByNumber.pictures {
            XCTAssertLessThanOrEqual(p.colors.count, ColorByNumber.maxColors, p.id)
            XCTAssertTrue((8...24).contains(p.width) && (8...24).contains(p.height), p.id)
            XCTAssertEqual(p.cells.count, p.width * p.height)
            // Every number is used (a gap inside, like the rain under its
            // cloud, is fine; check() keeps the edges filled).
            for n in 1...p.colors.count { XCTAssertTrue(p.cells.contains(n), "\(p.id) \(n)") }
        }
        // check() catches a broken one.
        var broken = ColorByNumber.sources[0]
        broken.rows[1].removeLast()
        XCTAssertNotNil(ColorByNumber.check(broken))
        broken = ColorByNumber.sources[0]
        broken.rows[0] = "z" + broken.rows[0].dropFirst()
        XCTAssertNotNil(ColorByNumber.check(broken))
        broken = ColorByNumber.sources[0]
        broken.category = "nowhere"
        XCTAssertNotNil(ColorByNumber.check(broken))
        broken = ColorByNumber.sources[0]
        broken.legend[1].hex = broken.legend[0].hex // two swatches alike
        XCTAssertNotNil(ColorByNumber.check(broken))
        broken = ColorByNumber.sources[0]
        broken.rows.insert(String(repeating: ".", count: broken.rows[0].count), at: 0) // an empty edge
        XCTAssertNotNil(ColorByNumber.check(broken))
        // A legend the file got wrong reads as a source check() refuses.
        let odd = ColorByNumber.parse("@ things | Things\n= odd | Odd | things\nr #E5484D dd #B8303A w\n" + String(repeating: "rrrrrrrr\n", count: 8))
        XCTAssertEqual(odd.sources.first?.legend.count, 3)
        XCTAssertNil(odd.sources.first?.legend[1].symbol)
        XCTAssertNotNil(odd.sources.first.flatMap(ColorByNumber.check))
    }

    func testPaintingTakesOnlyItsNumber() throws {
        var sheet = ColorSheet(picture: 0)
        let one = try XCTUnwrap(firstOf(sheet, 1)), two = try XCTUnwrap(firstOf(sheet, 2))
        let left = sheet.remaining(1)
        XCTAssertFalse(sheet.paint(two.column, two.row, number: 1)) // the wrong colour does nothing
        XCTAssertFalse(sheet.paint(-1, 0, number: 1))
        XCTAssertTrue(sheet.paint(one.column, one.row, number: 1))
        XCTAssertFalse(sheet.paint(one.column, one.row, number: 1)) // once
        XCTAssertTrue(sheet.isPainted(one.column, one.row))
        XCTAssertEqual(sheet.remaining(1), left - 1)
        XCTAssertEqual(sheet.painted, 1)
        XCTAssertFalse(sheet.done)
    }

    func testProgressIsSavedAndRestored() {
        var sheet = ColorSheet(picture: 3)
        var painted = 0
        for row in stride(from: 0, to: sheet.height, by: 2) {
            for column in 0..<sheet.width where sheet.paint(column, row, number: sheet.numberAt(column, row)) {
                painted += 1
            }
        }
        let saved = sheet.save()
        XCTAssertEqual(saved.count, sheet.cellCount)
        XCTAssertEqual(saved.filter { $0 == "1" }.count, painted)

        var again = ColorSheet(picture: 3)
        XCTAssertTrue(again.load(saved))
        XCTAssertEqual(again.painted, painted)
        XCTAssertEqual(again.save(), saved)
        for n in 1...again.picture.colors.count { XCTAssertEqual(again.remaining(n), sheet.remaining(n)) }
        // Another picture's progress, or a damaged one, is refused.
        XCTAssertFalse(again.load(String(saved.dropLast())))
        XCTAssertFalse(again.load(String(repeating: "x", count: saved.count)))
        var heart = ColorSheet(picture: 0)
        XCTAssertFalse(heart.load(saved))
    }

    func testEveryPictureCanBeFinished() {
        for i in ColorByNumber.pictures.indices {
            var sheet = ColorSheet(picture: i)
            for row in 0..<sheet.height {
                for column in 0..<sheet.width { sheet.paint(column, row, number: sheet.numberAt(column, row)) }
            }
            XCTAssertTrue(sheet.done, sheet.picture.id)
            XCTAssertEqual(sheet.painted, sheet.cellCount)
            XCTAssertFalse(sheet.save().contains("0"))
        }
    }

    func testBoardPaintsByTouch() throws {
        var board = ColorBoard(picture: 0, size: CGSize(width: 400, height: 300)) // 12 x 10: cells of 30
        XCTAssertEqual(board.cellSize, 30)
        XCTAssertEqual(board.selected, 1)
        var finished = 0

        // Only cells with the selected number take paint.
        let sheet = ColorSheet(picture: 0)
        let one = try XCTUnwrap(firstOf(sheet, 1)), two = try XCTUnwrap(firstOf(sheet, 2))
        XCTAssertEqual(board.numberAt(board.cellCenter(one.column, one.row)), 1)
        XCTAssertEqual(board.paintAt(board.cellCenter(two.column, two.row)), 0)
        XCTAssertEqual(board.paintAt(board.cellCenter(one.column, one.row)), 1)
        XCTAssertEqual(board.painted, 1)
        XCTAssertEqual(board.numberAt(CGPoint(x: -5, y: -5)), 0)

        // A sweep across a row paints every selected cell it crossed.
        let row = 3
        let ones = (0..<sheet.width).filter { sheet.numberAt($0, row) == 1 }.count
        XCTAssertGreaterThan(ones, 2)
        XCTAssertEqual(board.paintLine(from: board.cellCenter(0, row), to: board.cellCenter(sheet.width - 1, row)), ones)

        // Finishing a colour moves on to the next one with cells left.
        sweepRows(&board, finished: &finished)
        XCTAssertEqual(board.colors.first?.remaining, 0)
        XCTAssertEqual(board.selected, 2)
        XCTAssertEqual(board.caption, "Heart · \(100 * board.painted / board.total)%")
        // Then all of them: finished, once.
        for n in 2...sheet.picture.colors.count {
            board.select(n)
            sweepRows(&board, finished: &finished)
        }
        XCTAssertTrue(board.done)
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(board.caption, "Heart")

        // The progress goes out as text and comes back.
        let saved = board.saved
        board.clear()
        XCTAssertEqual(board.painted, 0)
        board.setSaved(saved)
        XCTAssertTrue(board.done)
        board.setSaved("nonsense")
        XCTAssertEqual(board.painted, 0)
    }

    func testBoardZoomsAndPans() {
        var board = ColorBoard(picture: 11, size: CGSize(width: 400, height: 300)) // 16 x 14: cells of 300 / 14
        let fit = board.cellSize
        XCTAssertFalse(board.canZoomOut)
        XCTAssertTrue(board.canZoomIn)
        // At fit the picture can't move.
        let corner = board.cellCenter(0, 0)
        board.pan(by: 50, 50)
        XCTAssertEqual(board.cellCenter(0, 0), corner)

        // Zoom in on the middle: bigger cells, never past maxCell.
        board.zoomIn()
        XCTAssertGreaterThan(board.cellSize, fit)
        XCTAssertTrue(board.canZoomOut)
        for _ in 0..<10 { board.zoomIn() }
        XCTAssertEqual(board.cellSize, ColorByNumber.maxCell, accuracy: 1e-9)
        XCTAssertFalse(board.canZoomIn)
        // Panned as far as it goes, the picture still covers the board.
        board.pan(by: 10000, 10000)
        XCTAssertEqual(board.cellCenter(0, 0).x, board.cellSize / 2, accuracy: 1e-9)
        XCTAssertEqual(board.cellCenter(0, 0).y, board.cellSize / 2, accuracy: 1e-9)
        board.pan(by: -10000, -10000)
        let last = board.cellCenter(15, 13)
        XCTAssertEqual(last.x + board.cellSize / 2, 400, accuracy: 1e-9)
        XCTAssertEqual(last.y + board.cellSize / 2, 300, accuracy: 1e-9)
        // Back to fit.
        board.fit()
        XCTAssertEqual(board.cellSize, fit)
        XCTAssertEqual(board.cellCenter(0, 0), corner)

        // A new size keeps the zoom in range and the picture in view.
        for _ in 0..<10 { board.zoomIn() }
        board.resize(to: CGSize(width: 1600, height: 1400)) // fits at cells of 100: no zoom left
        XCTAssertEqual(board.zoom, 1)
        XCTAssertEqual(board.cellSize, 100)
        XCTAssertEqual(board.cellsInView?.columns, 0...15)
    }

    // MARK: The display's own numbers

    /// FNV-1a over each picture as the C++ printed it:
    /// "id|title|category|WxH|#rrggbb,...,|cells", from `Colors::pictures()`.
    private static let pictureHashes: [String: UInt64] = [
        "heart": 0xf483_945b_13c2_a5f5,
        "strawberry": 0xa1c1_33c6_c3d7_739c,
        "rainbow": 0xd5b1_340d_6a15_a7c7,
        "mushroom": 0xb370_6108_bdf0_bbd0,
        "icecream": 0xedea_fa38_9ec5_25b3,
        "flower": 0x5cbc_a475_09e7_fc20,
        "cat": 0xeb7d_f621_bbf4_9423,
        "rocket": 0x358f_523c_fc5f_2728,
        "tree": 0x3e14_d5f1_ee10_838f,
        "house": 0x6b87_d070_3374_e540,
        "pip": 0x2aa1_e698_220a_d0a5,
        "lotl": 0xf275_8c23_00d6_e206,
    ]
    /// The same lines for every picture in the file, one under the other.
    private static let allPicturesHash: UInt64 = 0x1f41_6251_cd0a_445e
    /// Every picture's swatch inks, a line each ("#ffffff,#2b2522,…").
    private static let allInksHash: UInt64 = 0xe6a8_bd54_c7af_5a04

    private static func fnv(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static func line(_ p: ColorByNumber.Picture) -> String {
        "\(p.id)|\(p.title)|\(p.category)|\(p.width)x\(p.height)|" + p.colors.map { $0.hex + "," }.joined()
            + "|" + p.cells.map(String.init).joined()
    }

    /// The kit's picture file is the display's, byte for byte: edit the
    /// display's and copy it over.
    func testPictureFileIsTheDisplays() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let display = root.appendingPathComponent("display/src/games/colorbynumber.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: display.path), display.path)
        let theirs = try String(contentsOf: display, encoding: .utf8)
        XCTAssertFalse(ColorByNumber.pictureText.isEmpty)
        XCTAssertTrue(ColorByNumber.pictureText == theirs,
                      "apple/McFlyKit/Sources/McFlyKit/Resources/colorbynumber.txt differs from the display's: copy it over")
    }

    /// Each picture on a 400 x 300 board: the swatches' ink, the cell, and
    /// where the first cell's middle is.
    private static let boards: [(ink: String, cell: Double, x: Double, y: Double)] = [
        ("#ffffff,#ffffff,#2b2522", 30, 35, 15),
        ("#ffffff,#ffffff,#2b2522,#2b2522,#ffffff,#ffffff", 23.076923076923077, 73.07692307692308, 11.538461538461538),
        ("#ffffff,#2b2522,#2b2522,#2b2522,#ffffff,#ffffff,#2b2522,#2b2522", 25, 12.5, 50),
        ("#ffffff,#ffffff,#2b2522,#2b2522,#2b2522,#ffffff", 23.076923076923077, 49.999999999999993, 11.538461538461538),
        ("#2b2522,#ffffff,#2b2522,#2b2522,#ffffff,#ffffff,#ffffff", 18.75, 96.875, 9.375),
        ("#2b2522,#ffffff,#2b2522,#2b2522,#ffffff,#ffffff", 20, 80, 10),
        ("#2b2522,#ffffff,#2b2522,#2b2522,#2b2522,#ffffff", 23.076923076923077, 49.999999999999993, 11.538461538461538),
        ("#ffffff,#2b2522,#2b2522,#ffffff,#2b2522,#2b2522,#2b2522", 18.75, 96.875, 9.375),
        ("#2b2522,#ffffff,#2b2522,#ffffff,#ffffff,#ffffff", 18.75, 78.125, 9.375),
        ("#ffffff,#ffffff,#2b2522,#2b2522,#2b2522,#ffffff,#2b2522,#ffffff,#2b2522", 21.428571428571427, 39.285714285714299, 10.714285714285714),
        ("#ffffff,#2b2522,#2b2522,#2b2522,#ffffff,#2b2522,#2b2522,#ffffff", 18.75, 78.125, 9.375),
        ("#2b2522,#ffffff,#2b2522,#ffffff,#2b2522,#ffffff", 21.428571428571427, 39.285714285714299, 10.714285714285714),
    ]

    /// When the picture file changes, these two hashes change with it: take
    /// them from the display's C++ (the scratch build that printed them).
    func testPicturesMatchTheDisplay() {
        XCTAssertEqual(Self.fnv(ColorByNumber.pictures.map(Self.line).joined(separator: "\n")), Self.allPicturesHash)
        XCTAssertEqual(Self.fnv(ColorByNumber.pictures.indices.map { i in
            ColorBoard(picture: i).colors.map(\.ink.hex).joined(separator: ",")
        }.joined(separator: "\n")), Self.allInksHash)
        // The colour distances the C++ printed.
        func rgb(_ hex: String) -> ColorByNumber.RGB { ColorByNumber.RGB(hex: hex)! }
        let distances: [(String, String, Double)] = [
            ("#FFFFFF", "#FAFAFA", 1.7279763048083254), ("#E5484D", "#5B8DEF", 98.966785169302938),
            ("#26345A", "#111111", 30.865362248324914), ("#FFF4DF", "#FFFFFF", 11.953614059503561),
            ("#3DB37A", "#23824F", 18.554875742835033),
        ]
        for (a, b, d) in distances {
            XCTAssertEqual(ColorByNumber.colorDistance(rgb(a), rgb(b)), d, accuracy: 1e-9, "\(a) \(b)")
        }
        // The first twelve, one at a time, and on a board.
        for (i, p) in ColorByNumber.pictures.prefix(12).enumerated() {
            let line = Self.line(p)
            XCTAssertEqual(Self.fnv(line), Self.pictureHashes[p.id], "\(p.id): \(line)")

            let board = ColorBoard(picture: i, size: CGSize(width: 400, height: 300))
            let golden = Self.boards[i]
            XCTAssertEqual(board.colors.map(\.ink.hex).joined(separator: ","), golden.ink, p.id)
            XCTAssertEqual(board.cellSize, golden.cell, accuracy: 1e-9, p.id)
            XCTAssertEqual(board.cellCenter(0, 0).x, golden.x, accuracy: 1e-9, p.id)
            XCTAssertEqual(board.cellCenter(0, 0).y, golden.y, accuracy: 1e-9, p.id)
        }
    }

    private func assertPoint(_ p: CGPoint, _ x: Double, _ y: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: 1e-9, file: file, line: line)
    }

    /// The same moves the scratch C++ made on its board, with its results.
    func testBoardMatchesTheDisplay() {
        var board = ColorBoard(picture: 11, size: CGSize(width: 400, height: 300))
        board.zoom(by: 2.5, at: CGPoint(x: 120, y: 90))
        XCTAssertEqual(board.cellSize, 53.571428571428569, accuracy: 1e-9)
        assertPoint(board.cellCenter(0, 0), -81.785714285714278, -108.21428571428572)
        board.pan(by: -37.5, 12.25)
        assertPoint(board.cellCenter(0, 0), -119.28571428571428, -95.964285714285722)
        board.zoomIn()
        XCTAssertEqual(board.cellSize, 85.714285714285708, accuracy: 1e-9)
        assertPoint(board.cellCenter(0, 0), -310.85714285714283, -243.54285714285712)
        XCTAssertTrue(board.canZoomIn)
        XCTAssertTrue(board.canZoomOut)
        board.zoomOut()
        board.zoomOut()
        XCTAssertEqual(board.cellSize, 33.482142857142854, accuracy: 1e-9)
        assertPoint(board.cellCenter(0, 0), 0.44642857142859427, -3.727678571428573)

        // Slanted sweeps across the whole view, each colour in turn.
        var counts: [Int] = []
        for n in 1...6 {
            board.select(n)
            for y in stride(from: 0, through: 300, by: 7) {
                counts.append(board.paintLine(from: CGPoint(x: -10, y: y), to: CGPoint(x: 410, y: y + 3)))
            }
        }
        let golden = "0,0,6,0,0,0,0,8,0,0,0,1,9,0,0,0,7,3,0,0,0,7,0,0,0,0,7,0,0,0,0,9,0,0,0,3,3,0,0,0,2,0,0,2,0,1,0,0,0,0,3,0,"
            + "0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"
            + "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,4,"
            + "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,2,0,0,0,0,"
            + "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
        XCTAssertEqual(counts.map(String.init).joined(separator: ","), golden)
        XCTAssertEqual(counts.reduce(0, +), 94)
        XCTAssertEqual(board.painted, 94)
        XCTAssertEqual(board.selected, 6)
        XCTAssertEqual(board.saved, "110011111110111111111110001111111111111111111111100011111111111011111111111011111111111011"
                       + "111111111111111100000000000000000000000000000000")

        // A diagonal sweep over the heart, fitted.
        board.setPicture(0)
        XCTAssertEqual(board.paintLine(from: .zero, to: CGPoint(x: 400, y: 300)), 11)
        XCTAssertEqual(board.selected, 1)
        XCTAssertEqual(board.saved, "0000001000000000001100000000000110000000000011000000000001100000000110000000000000")
    }

    func testProgressIsKeptAndTheCardSaysWhere() {
        let suite = "colors-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = GameProgress(defaults: defaults)
        XCTAssertEqual(progress.colorProgress, [:])
        var board = ColorBoard(picture: 0, size: CGSize(width: 400, height: 300))
        board.paintLine(from: board.cellCenter(0, 3), to: board.cellCenter(11, 3))
        progress.saveColors(board.saved, for: board.pictureID)
        let again = GameProgress(defaults: defaults)
        XCTAssertEqual(again.colorProgress["heart"], board.saved)

        var reopened = ColorBoard(picture: 0, size: CGSize(width: 400, height: 300))
        reopened.setSaved(again.colorProgress["heart"] ?? "")
        XCTAssertEqual(reopened.painted, board.painted)

        XCTAssertEqual(GameID.colorByNumber.credit, "Made for McFly, after Araib Karim's Color by Number for iOS. The pictures are ours.")
        XCTAssertNil(GameID.colorByNumber.licence)
        XCTAssertFalse(GameID.colorByNumber.timed)
    }
}
