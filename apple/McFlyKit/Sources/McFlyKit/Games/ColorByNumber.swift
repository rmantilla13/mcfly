import CoreGraphics
import Foundation

/// Color by Number, the display's (display/src/games/ColorByNumber.cpp, with
/// qml/games/ColorByNumber.qml for the touch): pixel pictures whose cells
/// carry the number of their colour. Pick a colour and paint its cells; only
/// a cell with the chosen number takes it. Written for McFly, after Araib
/// Karim's Color by Number for iOS; none of its code or pictures (it has no
/// licence) is used. The pictures are ours: the display's picture file
/// (display/src/games/colorbynumber.txt), copied into the kit's resources and
/// read the way the display reads it. The tests hold the copy to the file.
public enum ColorByNumber {
    /// The most colours a picture has, so the palette stays one or two rows.
    public static let maxColors = 9
    /// A picture is between these many cells wide and tall.
    public static let minSize = 8, maxSize = 24
    /// How far apart (CIE76) any two of a picture's colours are, at least, so
    /// their swatches can be told apart.
    public static let minColorDistance: Double = 10
    /// The biggest a cell gets when zoomed in, in points.
    public static let maxCell: Double = 96

    /// A shelf of the gallery: animals, food, space…
    public struct Category: Sendable, Identifiable, Equatable {
        public let id: String
        public let title: String
    }

    /// A picture as written: rows of symbols, "." for an empty cell, and a
    /// legend giving each symbol its colour. Numbers follow the legend's
    /// order. A symbol the file got wrong is nil, for check() to refuse.
    public struct Source: Sendable {
        public var id: String
        public var title: String
        public var category: String
        public var legend: [(symbol: Character?, hex: String)]
        public var rows: [String]
    }

    /// The picture file, as the kit carries it.
    public static let pictureText: String = {
        guard let url = Bundle.module.url(forResource: "colorbynumber", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    private static let library = parse(pictureText)
    public static var categories: [Category] { library.categories }
    public static var sources: [Source] { library.sources }

    /// Reads the picture file (its format is at its top), as the display's
    /// `library()` does. Anything it can't read becomes a source that check()
    /// turns down, so a mistake shows in the tests, not as a gap.
    public static func parse(_ text: String) -> (categories: [Category], sources: [Source]) {
        var categories: [Category] = []
        var sources: [Source] = []
        var open = false, wantLegend = false
        func fields(_ line: String) -> [String] {
            line.dropFirst().split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        // "\n" as a string, so a "\r\n" (one Character in Swift) still splits; trimming takes the "\r".
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#") { continue }
            if line.isEmpty {
                open = false
                continue
            }
            if line.hasPrefix("@") {
                let f = fields(line)
                categories.append(Category(id: f.first ?? "", title: f.count > 1 ? f[1] : ""))
                continue
            }
            if line.hasPrefix("=") {
                let f = fields(line)
                sources.append(Source(id: f.first ?? "", title: f.count > 1 ? f[1] : "", category: f.count > 2 ? f[2] : "",
                                      legend: [], rows: []))
                open = true
                wantLegend = true
                continue
            }
            guard open else { continue }
            if wantLegend {
                wantLegend = false
                let words = line.split(separator: " ").map(String.init)
                var i = 0
                while i + 1 < words.count {
                    sources[sources.count - 1].legend.append((words[i].count == 1 ? words[i].first : nil, words[i + 1]))
                    i += 2
                }
                if words.count % 2 == 1 { sources[sources.count - 1].legend.append((nil, "")) }
                continue
            }
            sources[sources.count - 1].rows.append(line)
        }
        return (categories, sources)
    }

    /// CIE76 colour difference: how far apart two colours look (sRGB to Lab, D65).
    public static func colorDistance(_ a: RGB, _ b: RGB) -> Double {
        func lab(_ c: RGB) -> (Double, Double, Double) {
            // From float channels, as Qt's QColor::redF() hands them over, so a
            // pair near the line falls the same side of it as on the display.
            func linear(_ channel: Double) -> Double {
                let v = Double(Float(channel))
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let r = linear(c.red), g = linear(c.green), b = linear(c.blue)
            let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
            return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
        }
        let p = lab(a), q = lab(b)
        return sqrt(pow(p.0 - q.0, 2) + pow(p.1 - q.1, 2) + pow(p.2 - q.2, 2))
    }

    /// What's wrong with a source, or nil when nothing is.
    public static func check(_ source: Source) -> String? {
        if source.id.isEmpty || source.title.isEmpty { return "no id or title" }
        if !categories.contains(where: { $0.id == source.category }) { return "category \"\(source.category)\" isn't one" }
        let sizes = minSize...maxSize
        if !sizes.contains(source.rows.count) { return "\(source.rows.count) rows (\(minSize) to \(maxSize))" }
        if source.legend.isEmpty || source.legend.count > maxColors {
            return "\(source.legend.count) colours (1 to \(maxColors))"
        }
        let rows = source.rows.map(Array.init)
        let width = rows[0].count
        if !sizes.contains(width) { return "\(width) wide (\(minSize) to \(maxSize))" }
        var symbols = Set<Character>(), used = Set<Character>()
        var colours: [RGB] = []
        for entry in source.legend {
            guard let symbol = entry.symbol, symbol != ".", !symbols.contains(symbol) else {
                return "a legend symbol twice, missing, or the empty one"
            }
            guard let colour = RGB(hex: entry.hex) else { return "\(entry.hex) isn't a colour" }
            symbols.insert(symbol)
            colours.append(colour)
        }
        // Every two colours far enough apart to tell their swatches apart.
        for i in colours.indices {
            for j in colours.indices where j > i {
                let d = colorDistance(colours[i], colours[j])
                if d < minColorDistance {
                    return "\(source.legend[i].symbol.map(String.init) ?? "") and \(source.legend[j].symbol.map(String.init) ?? "") look alike (\(String(format: "%.1f", d)))"
                }
            }
        }
        for (r, row) in rows.enumerated() {
            if row.count != width { return "row \(r) is \(row.count) wide, not \(width)" }
            for c in row where c != "." {
                if !symbols.contains(c) { return "row \(r) has \(c), not in the legend" }
                used.insert(c)
            }
        }
        if let unused = source.legend.first(where: { !used.contains($0.symbol ?? ".") }) {
            return "\(unused.symbol.map(String.init) ?? "") is never used"
        }
        // Drawn to its edges: no empty row or column round the outside.
        func emptyRow(_ row: [Character]) -> Bool { row.allSatisfy { $0 == "." } }
        func emptyColumn(_ column: Int) -> Bool { rows.allSatisfy { $0[column] == "." } }
        if emptyRow(rows[0]) || emptyRow(rows[rows.count - 1]) || emptyColumn(0) || emptyColumn(width - 1) {
            return "an empty row or column round the outside"
        }
        return nil
    }

    public struct Picture: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let category: String
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
        for (i, entry) in source.legend.enumerated() {
            if let symbol = entry.symbol { number[symbol] = i + 1 }
        }
        return Picture(id: source.id, title: source.title, category: source.category, width: first.count, height: source.rows.count,
                       colors: source.legend.compactMap { RGB(hex: $0.hex) },
                       cells: source.rows.flatMap { row in row.map { number[$0] ?? 0 } })
    }

    /// A picture's place in `pictures`.
    public static func index(of id: String) -> Int? {
        pictures.firstIndex { $0.id == id }
    }

    /// The pictures in a category ("" for all of them), as indexes, in the file's order.
    public static func pictures(in category: String) -> [Int] {
        pictures.indices.filter { category.isEmpty || pictures[$0].category == category }
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
