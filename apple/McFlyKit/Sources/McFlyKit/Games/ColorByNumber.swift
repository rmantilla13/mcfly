import CoreGraphics
import Foundation

/// Color by Number, the display's (display/src/games/ColorByNumber.cpp, with
/// qml/games/ColorByNumber.qml for the touch): pixel pictures whose cells
/// carry the number of their colour. Pick a colour and paint its cells; only
/// a cell with the chosen number takes it. Written for McFly, after Araib
/// Karim's Color by Number for iOS; none of its code or pictures (it has no
/// licence) is used. The pictures are ours, the display's, copied here
/// exactly, and the tests hold the two to each other cell for cell.
public enum ColorByNumber {
    /// The most colours a picture has, so the palette stays one or two rows.
    public static let maxColors = 9
    /// The biggest a cell gets when zoomed in, in points.
    public static let maxCell: Double = 96

    /// A picture as written: rows of symbols, "." for an empty cell, and a
    /// legend giving each symbol its colour. Numbers follow the legend's order.
    public struct Source: Sendable {
        public var id: String
        public var title: String
        public var rows: [String]
        public var legend: [(symbol: Character, hex: String)]
    }

    /// The pictures, easiest first: the display's `Colors::sources()`.
    public static let sources: [Source] = [
        Source(id: "heart", title: "Heart", rows: [
            ".rrr....rrr.",
            "rwwrr..rrrrr",
            "rwrrrrrrrrrd",
            "rrrrrrrrrrrd",
            "rrrrrrrrrrrd",
            ".rrrrrrrrrd.",
            "..rrrrrrrd..",
            "...rrrrrd...",
            "....rrrd....",
            ".....rd.....",
        ], legend: [
            ("r", "#E5484D"), ("d", "#B8303A"), ("w", "#FFC9CB"),
        ]),
        Source(id: "strawberry", title: "Strawberry", rows: [
            "....g..g....",
            "...ghgghg...",
            "..ghhgghhg..",
            ".rrgrrrrgrr.",
            "rrwryrrrryrd",
            "rwrrrrryrrrd",
            "rrryrrrrrrrd",
            ".rrrrryrrrd.",
            ".rryrrrrryd.",
            "..rrrrryrd..",
            "...rryrrd...",
            "....rrdd....",
            ".....dd.....",
        ], legend: [
            ("r", "#E5484D"), ("d", "#B8303A"), ("y", "#FCE38A"), ("w", "#FFC9CB"),
            ("g", "#3DB37A"), ("h", "#23824F"),
        ]),
        Source(id: "rainbow", title: "Rainbow", rows: [
            "....rrrrrrrr....",
            "..rroooooooorr..",
            ".rooyyyyyyyyoor.",
            "rooyyggggggyyoor",
            "royyggbbbbggyyor",
            "roygbbvvvvbbgyor",
            "roygbv....vbgyor",
            "wwwwbv....vbwwww",
            "cwwwwc....cwwwwc",
        ], legend: [
            ("r", "#E5484D"), ("o", "#F59E0B"), ("y", "#FDE047"), ("g", "#4CBF6B"),
            ("b", "#5B8DEF"), ("v", "#8E7CE6"), ("w", "#FFFFFF"), ("c", "#C9D3E3"),
        ]),
        Source(id: "mushroom", title: "Mushroom", rows: [
            "....rrrrrr....",
            "..rrwwrrrrrr..",
            ".rrwwwwrrrwwr.",
            ".rrrwwrrrwwwr.",
            "rrrrrrrrrrwwrd",
            "rwwrrrrrrrrrrd",
            "rwwrrrwwrrrrdd",
            ".ddrrrwwrrrdd.",
            "...sssssssst..",
            "...sskssksst..",
            "...sssssssst..",
            "...sssssssst..",
            "....sssssst...",
        ], legend: [
            ("r", "#E5484D"), ("d", "#B8303A"), ("w", "#FFFFFF"), ("s", "#F5E6C8"),
            ("t", "#D9C29A"), ("k", "#3A2E2A"),
        ]),
        Source(id: "icecream", title: "Ice Cream", rows: [
            ".....s......",
            "....cc......",
            "....cc......",
            "..pppppppp..",
            ".pwwppppppp.",
            "pwwppppppppq",
            "pwpppppppppq",
            "ppppppppppqq",
            "qpqpqpqpqpqq",
            ".klklklklkl.",
            ".lklklklklk.",
            "..klklklkl..",
            "..lklklklk..",
            "...klklkl...",
            "....lklk....",
            ".....kl.....",
        ], legend: [
            ("p", "#F7A1C4"), ("q", "#E27BA6"), ("w", "#FFE4EF"), ("k", "#E8A65D"),
            ("l", "#B9773A"), ("c", "#D7263D"), ("s", "#3E7C3A"),
        ]),
        Source(id: "flower", title: "Flower", rows: [
            ".....ppp.....",
            "..pp.ppp.pp..",
            ".pppqpppqppp.",
            ".ppppqyqpppp.",
            "..ppqyyoyqpp.",
            "pppqyyooyyqpp",
            "pppqyyyyyyqpp",
            "..ppqyyyyqpp.",
            ".ppppqqqqpppp",
            ".ppp..g..ppp.",
            "......g......",
            "..hh..g......",
            "...hh.g..hh..",
            "....hhghh....",
            "......g......",
        ], legend: [
            ("p", "#F78FB3"), ("q", "#D9568F"), ("y", "#FDD34D"), ("o", "#F2A93B"),
            ("g", "#3DB37A"), ("h", "#23824F"),
        ]),
        Source(id: "cat", title: "Cat", rows: [
            "oo..........oo",
            "opo........opo",
            "oppo......oppo",
            "oooooddddooooo",
            "ooooooddoooooo",
            "oogkoooooogkoo",
            "oogkoooooogkoo",
            "dooooowwoooood",
            "dooowwppwwoood",
            ".ooowwwwwwooo.",
            ".oowwkwwkwwoo.",
            "..oowwkkwwoo..",
            "....oooooo....",
        ], legend: [
            ("o", "#F2A04A"), ("d", "#C46A1E"), ("w", "#FFF6EA"), ("p", "#F7A6B5"),
            ("g", "#7FD17A"), ("k", "#2B2B2B"),
        ]),
        Source(id: "rocket", title: "Rocket", rows: [
            ".....rr.....",
            "....rrrr....",
            "...rrrrrr...",
            "...wwwwwg...",
            "..wwwwwwgg..",
            "..wwnnnngg..",
            "..wwnbbngg..",
            "..wwnbbngg..",
            "..wwnnnngg..",
            "..wwwwwwgg..",
            ".rwwwwwwggr.",
            "rrwwwwwwggrr",
            "rr.wwwwgg.rr",
            "r...oyyo...r",
            "....oyyo....",
            ".....oo.....",
        ], legend: [
            ("r", "#E5484D"), ("w", "#F4F4F6"), ("g", "#C3C7D1"), ("n", "#2F4A8A"),
            ("b", "#7FB3F5"), ("o", "#F59E0B"), ("y", "#FDE047"),
        ]),
        Source(id: "tree", title: "Apple Tree", rows: [
            ".....gggg.....",
            "...gglggggg...",
            "..glllgggrgg..",
            ".gllgggggggh..",
            ".ggggrgggggggh",
            "gggggggggrgghh",
            "gglgggggggghh.",
            ".gggrgggggghhh",
            ".gggggggggghh.",
            "..hggggghhhh..",
            "....hhthhh....",
            "......tu......",
            "......tu......",
            "......tu......",
            ".....ttuu.....",
            "....tt..uu....",
        ], legend: [
            ("g", "#4CBF6B"), ("h", "#2E9150"), ("l", "#8BE09B"), ("r", "#E5484D"),
            ("t", "#8A5A3B"), ("u", "#5E3C26"),
        ]),
        Source(id: "house", title: "House", rows: [
            "...........mm...",
            ".......rr..mm...",
            "......rrrr.mm...",
            ".....rrrrrrmm...",
            "....rrrrrrrr....",
            "...rrrrrrrrrr...",
            ".ssssssssssssss.",
            "..ccccccccccce..",
            "..cbbcnnnncbbe..",
            "..cbbcnnnncbbe..",
            "..ccccnnknccce..",
            "..ccccnnnnccce..",
            "gggggggggggggggg",
            ".g.g.g.g.g.g.g.g",
        ], legend: [
            ("r", "#D64545"), ("s", "#A83232"), ("c", "#FFF1D6"), ("e", "#E9D3A8"),
            ("b", "#7FB3F5"), ("n", "#8A5A3B"), ("k", "#F2C14E"), ("m", "#8C8C94"),
            ("g", "#4CBF6B"),
        ]),
        Source(id: "pip", title: "Pip", rows: [
            "....hhhhhh....",
            "...gggggggg...",
            "...nnnnnnnn...",
            "..nnnnnnnnnn..",
            ".nnnbbbbbbnnn.",
            ".nnbekbbekbnn.",
            ".nnbbbbbbbbnn.",
            ".nnpbboobbpnn.",
            "nnnbbbbbbbbnnn",
            "nnbbbbbbbbbbnn",
            "nnbbbbbbbbbbnn",
            "nnbbbbbbbbbbnn",
            ".nnbbbbbbbbnn.",
            "..nnbbbbbbnn..",
            "...nnnnnnnn...",
            "..oooo..oooo..",
        ], legend: [
            ("n", "#26345A"), ("b", "#FFF4DF"), ("o", "#F29A38"), ("e", "#FFFFFF"),
            ("k", "#111111"), ("p", "#F7A6B5"), ("h", "#FAFAFA"), ("g", "#3DB37A"),
        ]),
        Source(id: "lotl", title: "Lotl", rows: [
            "dd............dd",
            "..d..pppppp..d..",
            "ddd.pppppppp.ddd",
            "...pppppppppp...",
            "dddppppppppppddd",
            "..ppwkppppwkpp..",
            "..ppkkppppkkpp..",
            "..pppppmmppppp..",
            "...pppllllppp...",
            "....pllllllp....",
            "...ppllllllpp...",
            "..p.pllllllp.p..",
            "..p..pppppp..p..",
            "......pppp......",
        ], legend: [
            ("p", "#F7A8C8"), ("d", "#E05A93"), ("l", "#FDD7E6"), ("k", "#2B1B2A"),
            ("w", "#FFFFFF"), ("m", "#B03A6A"),
        ]),
    ]

    /// What's wrong with a source, or nil when nothing is.
    public static func check(_ source: Source) -> String? {
        if source.id.isEmpty || source.title.isEmpty { return "no id or title" }
        guard let first = source.rows.first else { return "no rows" }
        if source.legend.isEmpty || source.legend.count > maxColors {
            return "\(source.legend.count) colours (1 to \(maxColors))"
        }
        var symbols = Set<Character>(), used = Set<Character>()
        for entry in source.legend {
            if entry.symbol == "." || symbols.contains(entry.symbol) { return "symbol \(entry.symbol) twice, or the empty one" }
            if RGB(hex: entry.hex) == nil { return "\(entry.hex) isn't a colour" }
            symbols.insert(entry.symbol)
        }
        for (r, row) in source.rows.enumerated() {
            if row.count != first.count { return "row \(r) is \(row.count) wide, not \(first.count)" }
            for c in row where c != "." {
                if !symbols.contains(c) { return "row \(r) has \(c), not in the legend" }
                used.insert(c)
            }
        }
        if let unused = source.legend.first(where: { !used.contains($0.symbol) }) { return "\(unused.symbol) is never used" }
        return nil
    }

    public struct Picture: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let width: Int
        public let height: Int
        /// Number n is colors[n - 1].
        public let colors: [RGB]
        /// Row by row from the top; 0 for an empty cell.
        public let cells: [Int]
    }

    /// The sources that pass check(), numbered (the tests say which fail and why).
    public static let pictures: [Picture] = sources.compactMap { source in
        guard check(source) == nil, let first = source.rows.first else { return nil }
        var number: [Character: Int] = [:]
        for (i, entry) in source.legend.enumerated() { number[entry.symbol] = i + 1 }
        return Picture(id: source.id, title: source.title, width: first.count, height: source.rows.count,
                       colors: source.legend.compactMap { RGB(hex: $0.hex) },
                       cells: source.rows.flatMap { row in row.map { number[$0] ?? 0 } })
    }

    /// A colour as the board mixes it: sRGB channels from 0 to 1.
    public struct RGB: Sendable, Hashable {
        public var red: Double, green: Double, blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init(_ rgb: Int) {
            self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
        }

        /// "#RRGGBB", or nil.
        public init?(hex: String) {
            guard hex.count == 7, hex.first == "#", let value = Int(hex.dropFirst(), radix: 16) else { return nil }
            self.init(value)
        }

        /// "#rrggbb", as QColor::name() writes it.
        public var hex: String {
            func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
            return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
        }

        /// `t` of the way from this colour to `other`.
        public func mixed(with other: RGB, by t: Double) -> RGB {
            RGB(red: red + (other.red - red) * t, green: green + (other.green - green) * t, blue: blue + (other.blue - blue) * t)
        }

        /// Dark ink on a light colour, white on a dark one.
        public var ink: RGB {
            0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6 ? RGB(0x2B2522) : RGB(0xFFFFFF)
        }
    }
}

/// One picture being painted: which numbered cells are done (`Colors::Sheet`).
public struct ColorSheet: Sendable {
    public let pictureIndex: Int
    private var paintedCells: [Bool] = []
    private var left: [Int] = [] // per number, 1-based
    public private(set) var painted = 0
    public private(set) var cellCount = 0

    public init(picture: Int = 0) {
        pictureIndex = min(max(0, picture), ColorByNumber.pictures.count - 1)
        clear()
    }

    public var picture: ColorByNumber.Picture { ColorByNumber.pictures[pictureIndex] }
    public var width: Int { picture.width }
    public var height: Int { picture.height }
    public var done: Bool { cellCount > 0 && painted == cellCount }

    /// 0 for an empty cell or one off the picture.
    public func numberAt(_ column: Int, _ row: Int) -> Int {
        let p = picture
        guard column >= 0, row >= 0, column < p.width, row < p.height else { return 0 }
        return p.cells[row * p.width + column]
    }

    public func isPainted(_ column: Int, _ row: Int) -> Bool {
        numberAt(column, row) != 0 && paintedCells[row * picture.width + column]
    }

    /// Paints a cell if it carries `number` and isn't painted yet.
    @discardableResult
    public mutating func paint(_ column: Int, _ row: Int, number: Int) -> Bool {
        let n = numberAt(column, row)
        guard n != 0, n == number else { return false }
        let i = row * picture.width + column
        guard !paintedCells[i] else { return false }
        paintedCells[i] = true
        left[n] -= 1
        painted += 1
        return true
    }

    public func total(_ number: Int) -> Int {
        guard number >= 1, number <= picture.colors.count else { return 0 }
        return picture.cells.filter { $0 == number }.count
    }

    public func remaining(_ number: Int) -> Int {
        guard number >= 1, number < left.count else { return 0 }
        return left[number]
    }

    /// Progress as text, a 0 or 1 for each numbered cell in order: what the
    /// app keeps. load() takes back what save() gave, and refuses anything
    /// else (another picture's, a damaged one).
    public func save() -> String {
        String(zip(picture.cells, paintedCells).compactMap { n, done -> Character? in n == 0 ? nil : (done ? "1" : "0") })
    }

    @discardableResult
    public mutating func load(_ saved: String) -> Bool {
        guard saved.count == cellCount, saved.allSatisfy({ $0 == "0" || $0 == "1" }) else { return false }
        clear()
        let cells = picture.cells
        var marks = saved.makeIterator()
        for i in cells.indices where cells[i] != 0 {
            if marks.next() == "1" {
                paintedCells[i] = true
                left[cells[i]] -= 1
                painted += 1
            }
        }
        return true
    }

    public mutating func clear() {
        let p = picture
        paintedCells = Array(repeating: false, count: p.cells.count)
        left = Array(repeating: 0, count: p.colors.count + 1)
        cellCount = 0
        for n in p.cells where n > 0 {
            left[n] += 1
            cellCount += 1
        }
        painted = 0
    }
}

/// The board (`ColorByNumberBoard`): a picture at the size it's shown, the
/// chosen colour, and the zoom and pan. Zoom 1 fits the whole picture; it
/// goes up to cells of `maxCell` points. The screen passes touches here and
/// draws what it says; all the painting and panning is decided here.
public struct ColorBoard: Sendable {
    public private(set) var sheet = ColorSheet()
    public private(set) var selected = 1
    public private(set) var zoom: Double = 1
    /// The picture's top left, in the board's coordinates.
    public private(set) var offset = CGPoint.zero
    public private(set) var size = CGSize.zero

    public init(picture: Int = 0, size: CGSize = .zero) {
        sheet = ColorSheet(picture: picture)
        self.size = size
        place()
    }

    public var picture: Int { sheet.pictureIndex }
    public var pictureCount: Int { ColorByNumber.pictures.count }
    public var pictureID: String { sheet.picture.id }
    public var title: String { sheet.picture.title }
    public var painted: Int { sheet.painted }
    public var total: Int { sheet.cellCount }
    public var done: Bool { sheet.done }
    public var saved: String { sheet.save() }
    /// The caption: "Title · NN%", or the title alone once it's done.
    public var caption: String {
        done ? title : "\(title) · \(100 * painted / max(1, total))%"
    }

    /// The swatches: each colour, its ink, and how many of its cells are left.
    public struct Swatch: Sendable, Identifiable {
        public let number: Int
        public let color: ColorByNumber.RGB
        public let total: Int
        public let remaining: Int
        public var id: Int { number }
        public var ink: ColorByNumber.RGB { color.ink }
    }

    public var colors: [Swatch] {
        sheet.picture.colors.enumerated().map { i, color in
            Swatch(number: i + 1, color: color, total: sheet.total(i + 1), remaining: sheet.remaining(i + 1))
        }
    }

    public var cellSize: Double { fitCell * zoom }
    public var canZoomIn: Bool { zoom < maxZoom - 1e-6 }
    public var canZoomOut: Bool { zoom > 1 + 1e-6 }

    private var fitCell: Double {
        guard sheet.width > 0, sheet.height > 0 else { return 1 }
        return max(1, min(size.width / Double(sheet.width), size.height / Double(sheet.height)))
    }

    private var maxZoom: Double { max(1, ColorByNumber.maxCell / fitCell) }

    /// Another picture, from the start: the first colour, zoomed to fit.
    public mutating func setPicture(_ index: Int) {
        let index = min(max(0, index), pictureCount - 1)
        if index == sheet.pictureIndex && sheet.painted == 0 && zoom == 1 { return }
        sheet = ColorSheet(picture: index)
        selected = 1
        zoom = 1
        place()
    }

    public mutating func select(_ number: Int) {
        selected = min(max(1, number), sheet.picture.colors.count)
    }

    /// Carries on from saved progress (`saved`); anything that isn't this
    /// picture's starts it over. Starts on a colour that has cells to paint.
    public mutating func setSaved(_ saved: String) {
        if saved == sheet.save() { return }
        if !sheet.load(saved) { sheet.clear() }
        if sheet.remaining(selected) == 0,
           let n = (1...sheet.picture.colors.count).first(where: { sheet.remaining($0) > 0 }) {
            selected = n
        }
    }

    public mutating func clear() {
        sheet.clear()
        selected = 1
    }

    /// The board was laid out at a new size: the zoom stays in range and
    /// the picture in view.
    public mutating func resize(to size: CGSize) {
        self.size = size
        zoom = min(zoom, maxZoom)
        place()
    }

    /// Keeps the picture in view: centred along a side where it fits, and
    /// covering the board where it doesn't.
    private mutating func place() {
        let cell = cellSize
        func axis(_ offset: Double, _ picture: Double, _ view: Double) -> Double {
            picture <= view ? (view - picture) / 2 : min(max(view - picture, offset), 0)
        }
        offset = CGPoint(x: axis(offset.x, Double(sheet.width) * cell, size.width),
                         y: axis(offset.y, Double(sheet.height) * cell, size.height))
    }

    /// The cell under a point, which may be off the picture.
    public func cell(at point: CGPoint) -> (column: Int, row: Int) {
        let cell = cellSize
        return (Int(((point.x - offset.x) / cell).rounded(.down)), Int(((point.y - offset.y) / cell).rounded(.down)))
    }

    /// The number of the cell under a point (0 for none).
    public func numberAt(_ point: CGPoint) -> Int {
        let at = cell(at: point)
        return sheet.numberAt(at.column, at.row)
    }

    /// The middle of a cell, where it's drawn now.
    public func cellCenter(_ column: Int, _ row: Int) -> CGPoint {
        CGPoint(x: offset.x + (Double(column) + 0.5) * cellSize, y: offset.y + (Double(row) + 0.5) * cellSize)
    }

    /// The columns and rows in view, for drawing only those; nil when none are.
    public var cellsInView: (columns: ClosedRange<Int>, rows: ClosedRange<Int>)? {
        let cell = cellSize
        let c0 = max(0, Int((-offset.x / cell).rounded(.down))), r0 = max(0, Int((-offset.y / cell).rounded(.down)))
        let c1 = min(sheet.width - 1, Int(((size.width - offset.x) / cell).rounded(.down)))
        let r1 = min(sheet.height - 1, Int(((size.height - offset.y) / cell).rounded(.down)))
        guard c0 <= c1, r0 <= r1 else { return nil }
        return (c0...c1, r0...r1)
    }

    /// Paints the cell under a point if it carries the chosen number.
    /// Returns how many cells it painted; the picture is finished when that
    /// is more than none and `done`.
    @discardableResult
    public mutating func paintAt(_ point: CGPoint) -> Int {
        let at = cell(at: point)
        let count = sheet.paint(at.column, at.row, number: selected) ? 1 : 0
        afterPainting(count)
        return count
    }

    /// Paints every cell of the chosen number along a drag from `from` to
    /// `to`, sampled every third of a cell, so a quick sweep leaves no gaps.
    @discardableResult
    public mutating func paintLine(from: CGPoint, to: CGPoint) -> Int {
        let step = max(1, cellSize / 3)
        let samples = Int((hypot(to.x - from.x, to.y - from.y) / step).rounded(.up)) + 1
        var count = 0
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let at = cell(at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            count += sheet.paint(at.column, at.row, number: selected) ? 1 : 0
        }
        afterPainting(count)
        return count
    }

    /// A colour finished: on to the next one that has cells left.
    private mutating func afterPainting(_ count: Int) {
        guard count > 0, sheet.remaining(selected) == 0, !sheet.done else { return }
        let colors = sheet.picture.colors.count
        for step in 1..<max(1, colors) {
            let n = (selected - 1 + step) % colors + 1
            if sheet.remaining(n) > 0 {
                selected = n
                return
            }
        }
    }

    /// Zooms by `factor`, keeping the point under `center` where it is.
    public mutating func zoom(by factor: Double, at center: CGPoint) {
        let next = min(max(1, zoom * factor), maxZoom)
        // qFuzzyCompare: the same zoom to twelve places is no change.
        if abs(next - zoom) * 1e12 <= min(abs(next), abs(zoom)) { return }
        let before = cellSize
        zoom = next
        let k = cellSize / before
        offset = CGPoint(x: center.x - (center.x - offset.x) * k, y: center.y - (center.y - offset.y) * k)
        place()
    }

    public mutating func zoomIn() { zoom(by: 1.6, at: CGPoint(x: size.width / 2, y: size.height / 2)) }
    public mutating func zoomOut() { zoom(by: 1 / 1.6, at: CGPoint(x: size.width / 2, y: size.height / 2)) }

    /// The whole picture again.
    public mutating func fit() {
        guard zoom != 1 else { return }
        zoom = 1
        place()
    }

    public mutating func pan(by dx: Double, _ dy: Double) {
        offset = CGPoint(x: offset.x + dx, y: offset.y + dy)
        place()
    }
}
