import McFlyKit
import Observation
import SwiftUI

/// Color by Number, the display's (display/qml/games/ColorByNumber.qml):
/// pick a picture, pick a colour, and fill in every cell with its number.
/// Written for McFly, after Araib Karim's Color by Number for iOS (none of
/// its code or pictures is used; the pictures are ours, in the kit's
/// ColorByNumber.swift, the same as the display's).
///
/// The cells are smaller than a fingertip, so painting forgives: only cells
/// with the chosen number take its colour, and a sweep fills every cell it
/// crosses. One finger does both jobs: a drag that starts on a cell of the
/// chosen number paints, a drag from anywhere else moves the picture, and a
/// tap on another number's cell picks that colour. −, + and a pinch zoom.
///
/// Every picture's progress is kept as you go, and when the game closes.
struct ColorByNumberView: View {
    @State private var game = ColorGame()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch game.showing {
            case .gallery: ColorGallery(game: game)
            case .paint: ColorEasel(game: game)
            }
        }
        .onDisappear { game.save() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.save() }
        }
    }
}

/// The pictures, their progress, and the touch on the one being painted.
@Observable
final class ColorGame {
    enum Showing { case gallery, paint }

    var showing = Showing.gallery
    var board = ColorBoard()
    /// Each picture's progress (`ColorBoard.saved`), by its id.
    private(set) var progress = GameProgress.shared.colorProgress

    /// The touch under way: where it started and was last, and whether it
    /// paints, has moved past a tap, or turned into a pinch. A new start is a
    /// new touch: a drag that two fingers took over never gets its end.
    @ObservationIgnored private var start: CGPoint?
    @ObservationIgnored private var last: CGPoint?
    @ObservationIgnored private var painting = false
    @ObservationIgnored private var moved = false
    @ObservationIgnored private var pinched = false
    @ObservationIgnored private var lastScale: CGFloat = 1
    @ObservationIgnored private var pinchStart: CGPoint?
    /// How far a finger travels before a tap is a drag.
    private let tapSlop: CGFloat = 8

    init() {
        if let name = GameLaunch.colorPicture, let i = ColorByNumber.pictures.firstIndex(where: { $0.id == name }) {
            open(i)
        }
    }

    /// The picture being painted, to the store and to the gallery.
    func save() {
        guard showing == .paint else { return }
        let id = board.pictureID, saved = board.saved
        guard progress[id] != saved else { return }
        progress[id] = saved
        GameProgress.shared.saveColors(saved, for: id)
    }

    func open(_ index: Int) {
        save()
        board.setPicture(index)
        board.setSaved(progress[board.pictureID] ?? "")
        showing = .paint
    }

    func showGallery() {
        save()
        showing = .gallery
    }

    func openNext() { open((board.picture + 1) % board.pictureCount) }

    /// How much of a saved picture is done, 0 to 1.
    func share(_ id: String) -> Double {
        guard let saved = progress[id], !saved.isEmpty else { return 0 }
        return Double(saved.filter { $0 == "1" }.count) / Double(saved.count)
    }

    func resize(_ size: CGSize) {
        if board.size != size { board.resize(to: size) }
    }

    /// Paints with `stroke`; the last cell of the picture fits it to the view.
    private func paint(_ stroke: (inout ColorBoard) -> Int) {
        if stroke(&board) > 0 && board.done {
            board.fit()
            save()
        }
    }

    // One finger: paint from a cell of the chosen number, move the picture
    // from anywhere else, pick a colour with a tap.
    func drag(_ value: DragGesture.Value) {
        if start != value.startLocation {
            let at = value.startLocation
            start = at
            last = at
            moved = false
            pinched = false
            let n = board.numberAt(at)
            painting = n > 0 && n == board.selected
            if painting { paint { $0.paintAt(at) } }
        }
        guard let from = last, !pinched else { return }
        let to = value.location
        // A finger wobbles: a tap stays a tap until it travels.
        if !moved && hypot(to.x - from.x, to.y - from.y) < tapSlop { return }
        moved = true
        if painting {
            paint { $0.paintLine(from: from, to: to) }
        } else {
            board.pan(by: to.x - from.x, to.y - from.y)
        }
        last = to
    }

    func release(_ value: DragGesture.Value) {
        if !painting && !moved && !pinched {
            let n = board.numberAt(value.location)
            if n > 0 && board.sheet.remaining(n) > 0 { board.select(n) }
        }
        start = nil
        last = nil
        pinched = false
        save()
    }

    func pinch(_ value: MagnifyGesture.Value) {
        if pinchStart != value.startLocation {
            pinchStart = value.startLocation
            lastScale = 1
        }
        pinched = true
        board.zoom(by: value.magnification / lastScale, at: value.startLocation)
        lastScale = value.magnification
    }

    func pinchEnded() {
        pinchStart = nil
        lastScale = 1
    }
}

// MARK: The gallery

/// The pictures to choose from: each shows its colours faintly until it's
/// done, and says how far along it is.
private struct ColorGallery: View {
    let game: ColorGame
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick a picture")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ColorByNumber.pictures.indices, id: \.self) { i in
                        let picture = ColorByNumber.pictures[i]
                        let share = game.share(picture.id)
                        Button { game.open(i) } label: {
                            card(picture, index: i, share: share)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(picture.title), \(status(share).isEmpty ? "not started" : status(share))")
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func status(_ share: Double) -> String {
        share >= 1 ? "Done" : share > 0 ? "\(Int((share * 100).rounded(.down)))%" : ""
    }

    private func card(_ picture: ColorByNumber.Picture, index: Int, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPictureView(picture: index, saved: game.progress[picture.id] ?? "")
                .padding(10)
                .aspectRatio(1.3, contentMode: .fit)
                .background(Theme.palette.isDark ? Theme.background : Theme.sunken,
                            in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
            HStack {
                Text(picture.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(status(share))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(share >= 1 ? Theme.success : Theme.muted)
            }
            .padding(.horizontal, 6)
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// A picture as a thumbnail: no numbers or grid, its unpainted cells a
/// faint tint of their colour, the painted ones in full.
struct ColorPictureView: View {
    let picture: Int
    let saved: String

    var body: some View {
        Canvas { context, size in
            var board = ColorBoard(picture: picture, size: size)
            board.setSaved(saved)
            ColorBoardDrawing.draw(board, preview: true, dark: Theme.palette.isDark, in: &context)
        }
    }
}

// MARK: Painting

/// Painting a picture: the board, the tools and the palette, beside the
/// picture on a stage much wider than tall, under it otherwise.
private struct ColorEasel: View {
    let game: ColorGame
    private let gap: CGFloat = 12
    private let panelWidth: CGFloat = 264

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width >= geo.size.height + panelWidth + gap
            if side {
                HStack(alignment: .top, spacing: gap) {
                    canvas.frame(width: min(geo.size.height, geo.size.width - panelWidth - gap))
                    VStack(alignment: .leading, spacing: gap) {
                        tools
                        caption
                        palette
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: gap) {
                    canvas
                    HStack(spacing: gap) {
                        tools
                        caption
                    }
                    palette
                }
            }
        }
        .sensoryFeedback(.success, trigger: game.board.done) { _, done in done }
    }

    /// The picture, on a panel of its own.
    private var canvas: some View {
        ColorBoardView(game: game)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.palette.isDark ? Theme.surface : Theme.sunken,
                        in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var tools: some View {
        HStack(spacing: 10) {
            GameIconButton(systemImage: "square.grid.2x2", label: "All pictures") { game.showGallery() }
            tool("minus", "Zoom out", enabled: game.board.canZoomOut) { game.board.zoomOut() }
            tool("plus", "Zoom in", enabled: game.board.canZoomIn) { game.board.zoomIn() }
            tool("photo", "Whole picture", enabled: game.board.canZoomOut) { game.board.fit() }
        }
    }

    private func tool(_ image: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        GameIconButton(systemImage: image, label: label, action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
    }

    private var caption: some View {
        Text(game.board.caption)
            .font(.headline)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The colours, or once it's finished, on to the next picture.
    @ViewBuilder
    private var palette: some View {
        if game.board.done {
            FlowLayout(spacing: 12) {
                Text("Finished!")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.success)
                    .frame(minHeight: 48)
                Button("Next picture") { game.openNext() }
                    .buttonStyle(.gamePill())
                Button("All pictures") { game.showGallery() }
                    .buttonStyle(.gamePill(.neutral))
            }
            .padding(.vertical, 4) // as tall as the swatches, so the picture stays put
        } else {
            FlowLayout(spacing: 8) {
                ForEach(game.board.colors) { swatch in
                    ColorSwatch(swatch: swatch, chosen: game.board.selected == swatch.number) {
                        game.board.select(swatch.number)
                    }
                }
            }
            .padding(4) // room for the chosen ring
        }
    }
}

/// A colour to paint with: its number on it, a ring when it's the one, a
/// check once its cells are all painted.
private struct ColorSwatch: View {
    let swatch: ColorBoard.Swatch
    let chosen: Bool
    let pick: () -> Void
    private let size: CGFloat = 48

    var body: some View {
        let finished = swatch.remaining == 0
        Button(action: pick) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(swatch.color))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.divider, lineWidth: 1))
                .overlay {
                    if finished {
                        Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                    } else {
                        Text(String(swatch.number)).font(.headline)
                    }
                }
                .foregroundStyle(Color(swatch.ink))
                .frame(width: size, height: size)
                .opacity(finished ? 0.35 : 1)
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.text, lineWidth: 3)
                        .opacity(chosen ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(finished)
        .padding(-4)
        .accessibilityLabel("Colour \(swatch.number)")
        .accessibilityValue(finished ? "done" : "\(swatch.remaining) of \(swatch.total) left")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The board itself: the picture drawn as the kit's board says, taking one
/// finger to paint, move and choose, and two to zoom.
private struct ColorBoardView: View {
    let game: ColorGame

    var body: some View {
        Canvas { context, _ in
            ColorBoardDrawing.draw(game.board, preview: false, dark: Theme.palette.isDark, in: &context)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { game.resize($0) }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { game.drag($0) }
                .onEnded { game.release($0) }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { game.pinch($0) }
                .onEnded { _ in game.pinchEnded() }
        )
        .accessibilityElement()
        .accessibilityLabel(game.board.title)
        .accessibilityValue("\(100 * game.board.painted / max(1, game.board.total)) percent painted")
        .accessibilityHint("Drag from a cell numbered \(game.board.selected) to paint.")
    }
}

/// Draws a board: the display's ColorByNumberBoard::paint, cell for cell.
enum ColorBoardDrawing {
    /// Unpainted cells are white in the light (the board sits on a darker
    /// panel, so a picture's own white still shows), a dark grey at night.
    static func draw(_ board: ColorBoard, preview: Bool, dark: Bool, in context: inout GraphicsContext) {
        guard let view = board.cellsInView else { return }
        let picture = board.sheet.picture
        let cell = board.cellSize
        let base = ColorByNumber.RGB(dark ? 0x2C2C31 : 0xFFFFFF)
        let grid = Color(rgb: dark ? 0x3D3D45 : 0xDED8D0)
        let number = Color(rgb: dark ? 0xA9A9B2 : 0x857E77)
        let showNumbers = !preview && cell >= 14
        let gap: CGFloat = !preview && !board.done && cell >= 10 ? 1 : 0
        let fontSize = max(8, (cell * 0.46).rounded(.down))

        // Each number's text, plain and (for the chosen colour) bold on its tint.
        let chosenFill = picture.colors.indices.contains(board.selected - 1)
            ? base.mixed(with: picture.colors[board.selected - 1], by: 0.45) : base
        var plain: [Int: GraphicsContext.ResolvedText] = [:]
        var bold: GraphicsContext.ResolvedText?
        if showNumbers {
            for n in 1...picture.colors.count {
                plain[n] = context.resolve(Text(String(n)).font(.system(size: fontSize)).foregroundColor(number))
            }
            bold = context.resolve(Text(String(board.selected)).font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(Color(chosenFill.ink)))
        }

        // Cells on whole points, so neighbours meet without a seam.
        func edge(_ v: Double) -> CGFloat { CGFloat(v.rounded()) }
        for row in view.rows {
            let y0 = edge(board.offset.y + Double(row) * cell), y1 = edge(board.offset.y + Double(row + 1) * cell)
            for column in view.columns {
                let n = picture.cells[row * picture.width + column]
                guard n != 0 else { continue }
                let x0 = edge(board.offset.x + Double(column) * cell), x1 = edge(board.offset.x + Double(column + 1) * cell)
                let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                let colour = picture.colors[n - 1]
                if board.sheet.isPainted(column, row) {
                    context.fill(Path(rect), with: .color(Color(colour)))
                    continue
                }
                let chosen = !preview && n == board.selected
                // A thumbnail shows the picture faintly, a hint of what it'll be.
                let fill = chosen ? chosenFill : preview ? base.mixed(with: colour, by: 0.22) : base
                let inner = CGRect(x: rect.minX, y: rect.minY, width: rect.width - gap, height: rect.height - gap)
                if gap > 0 { context.fill(Path(rect), with: .color(grid)) }
                context.fill(Path(inner), with: .color(Color(fill)))
                if showNumbers, let text = chosen ? bold : plain[n] {
                    context.draw(text, at: CGPoint(x: inner.midX, y: inner.midY), anchor: .center)
                }
            }
        }
    }
}

extension Color {
    init(_ rgb: ColorByNumber.RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Lays its children out in rows, left to right, starting a new row when
/// one is full (the display's Flow).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
