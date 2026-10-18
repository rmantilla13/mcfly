import McFlyKit
import SwiftUI

/// Traffic Jam (display/qml/games/TrafficJam.qml): slide the cars and
/// trucks until the red car can drive out. A drag only lands where the
/// board's moves allow it (Michael Fogleman's Rush Hour logic, in the kit).
/// The level and each level's fewest moves are kept on the device.
struct TrafficJamView: View {
    @State private var game = TrafficJam(level: GameProgress.shared.trafficLevel)
    @State private var best = GameProgress.shared.trafficBest
    @State private var picking = false
    @State private var dragging: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var limits: ClosedRange<Int> = 0...0
    @State private var driveOut: CGFloat = 0
    @State private var showSolved = false
    /// Bumped by each load: a new lot, not the last one's cars sliding over.
    @State private var round = 0

    static let carColors = [0x5B8DEF, 0xF2B84B, 0x3DB37A, 0x8E7CE6, 0xEF8A6F, 0x5FB3B3,
                            0xD77FC1, 0xF29F67, 0x6BC2E8, 0xA3C55A, 0xC9A27A, 0x7F8FA6]
    static let red = 0xE5484D
    static let wall = 0x8F95A1

    static func bandColor(_ band: TrafficJam.Band) -> Color {
        switch band {
        case .beginner: return Color(rgb: 0x3DB37A)
        case .intermediate: return Color(rgb: 0x4F7CF7)
        case .advanced: return Color(rgb: 0xE0912A)
        case .expert: return Color(rgb: 0xE5484D)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width > geo.size.height * 1.4
            ZStack {
                if side {
                    HStack(spacing: 20) {
                        lot.frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(alignment: .leading, spacing: 16) {
                            levelInfo
                            HStack(spacing: 12) { movesCount; Spacer(); buttons }
                            Spacer()
                        }
                        .frame(width: min(340, geo.size.width * 0.4))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            levelInfo
                            Spacer()
                            movesCount
                        }
                        buttons
                        lot.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if picking {
                    LevelPicker(title: "Choose a level", summary: "\(best.count) of \(TrafficJam.levels.count) solved",
                                close: { picking = false }) {
                        LevelGrid(count: TrafficJam.levels.count, current: game.level,
                                  done: { best[$0] != nil },
                                  stars: { TrafficJam.stars(moves: best[$0] ?? 0, par: TrafficJam.levels[$0].par) },
                                  dot: { Self.bandColor(TrafficJam.Band(par: TrafficJam.levels[$0].par)) }) { load($0) }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func load(_ level: Int) {
        game = TrafficJam(level: level)
        driveOut = 0
        showSolved = false
        picking = false
        round += 1
        GameProgress.shared.trafficLevel = game.level
    }

    private var levelInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Level \(game.level + 1)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                let band = TrafficJam.Band(par: game.par)
                Tag(text: band.name, color: Self.bandColor(band))
                Text(best[game.level].map { "Fewest moves \(game.par) · your best \($0)" } ?? "Fewest moves \(game.par)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var movesCount: some View {
        VStack(spacing: 0) {
            Text("Moves").font(.caption).foregroundStyle(Theme.muted)
            Text(String(game.moves)).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            GameIconButton(systemImage: "arrow.uturn.backward", label: "Undo") {
                withAnimation(.easeOut(duration: 0.2)) { game.undo() }
            }
            .disabled(game.moves == 0 || game.solved)
            .opacity(game.moves == 0 || game.solved ? 0.45 : 1)
            GameIconButton(systemImage: "arrow.clockwise", label: "Start the level over") { load(game.level) }
            Button("Levels") { picking = true }
                .buttonStyle(.gamePill(.neutral))
                .frame(minHeight: 48)
        }
    }

    // MARK: The lot

    private var lot: some View {
        GeometryReader { geo in
            // Room on the right for the exit lane.
            let width = max(0, min(geo.size.height, geo.size.width / 1.12))
            let pad = width * 0.035
            let cell = (width - 2 * pad) / 6
            let inset = cell * 0.05
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface)
                ForEach(0..<36, id: \.self) { i in
                    RoundedRectangle(cornerRadius: cell * 0.14, style: .continuous)
                        .fill(Theme.sunken)
                        .frame(width: cell - 2 * inset, height: cell - 2 * inset)
                        .offset(x: pad + CGFloat(i % 6) * cell + inset, y: pad + CGFloat(i / 6) * cell + inset)
                }
                // The way out, on the right of the red car's row.
                RoundedRectangle(cornerRadius: cell * 0.14, style: .continuous)
                    .fill(Theme.sunken)
                    .frame(width: pad + cell * 0.55, height: cell - 2 * inset)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: min(30, cell * 0.36), weight: .bold))
                            .foregroundStyle(game.solved ? Theme.success : Theme.muted)
                            .padding(.trailing, 4)
                    }
                    .offset(x: width - pad - inset, y: pad + CGFloat(game.board.primaryRow) * cell + inset)
                ForEach(Array(game.board.pieces.enumerated()), id: \.offset) { index, piece in
                    car(index, piece, pad: pad, cell: cell, inset: inset)
                }
                if showSolved {
                    solvedCard
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .zIndex(5)
                }
            }
            .frame(width: width, height: width)
            .id(round)
            .position(x: geo.size.width / 2 - width * 0.04, y: geo.size.height / 2)
        }
    }

    private func car(_ index: Int, _ piece: RushBoard.Piece, pad: CGFloat, cell: CGFloat, inset: CGFloat) -> some View {
        let horizontal = piece.stride == 1
        let paint = piece.fixed ? Self.wall : index == 0 ? Self.red : Self.carColors[(index - 1) % Self.carColors.count]
        let along = CGFloat(piece.size) * cell - 2 * inset
        let across = cell - 2 * inset
        let drag = dragging == index ? dragOffset : 0
        let exit = index == 0 ? driveOut : 0
        let x = pad + CGFloat(piece.position % 6) * cell + inset + (horizontal ? drag + exit : 0)
        let y = pad + CGFloat(piece.position / 6) * cell + inset + (horizontal ? 0 : drag)
        return CarShape(paint: paint, horizontal: horizontal, fixed: piece.fixed, cell: cell)
            .frame(width: horizontal ? along : across, height: horizontal ? across : along)
            .scaleEffect(dragging == index ? 1.03 : 1)
            .opacity(index == 0 && game.solved ? Double(max(0, 1 - driveOut / (cell * 2.6))) : 1)
            .offset(x: x, y: y)
            .zIndex(dragging == index ? 2 : 1)
            .animation(dragging == index ? nil : .easeOut(duration: 0.2), value: piece.position)
            .gesture(piece.fixed || game.solved ? nil : DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragging != index {
                        limits = game.range(index)
                        dragging = index
                    }
                    let moved = horizontal ? value.translation.width : value.translation.height
                    dragOffset = max(CGFloat(limits.lowerBound) * cell, min(CGFloat(limits.upperBound) * cell, moved))
                }
                .onEnded { _ in
                    let steps = Int((dragOffset / cell).rounded())
                    let slid = game.slide(index, steps)
                    if slid {
                        // The car stays where it was let go and eases into its square.
                        dragging = nil
                        dragOffset = 0
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                        dragging = nil
                    }
                    if game.solved { solved(cell: cell) }
                })
            .accessibilityLabel(index == 0 ? "Red car" : piece.fixed ? "Wall" : "Car \(index)")
    }

    private func solved(cell: CGFloat) {
        GameProgress.shared.recordTraffic(level: game.level, moves: game.moves)
        best = GameProgress.shared.trafficBest
        withAnimation(.easeIn(duration: 0.6)) { driveOut = cell * 2.6 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75).delay(0.5)) { showSolved = true }
    }

    private var solvedCard: some View {
        GameCardOverlay {
            Stars(count: TrafficJam.stars(moves: game.moves, par: game.par), size: 40)
            Text("Out in \(game.moves) moves!")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text(game.moves <= game.par ? "That's the fewest possible." : "It can be done in \(game.par).")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Play again") { load(game.level) }
                    .buttonStyle(.gamePill(.neutral))
                Button(game.level + 1 < TrafficJam.levels.count ? "Next level" : "All levels") {
                    if game.level + 1 < TrafficJam.levels.count { load(game.level + 1) } else { picking = true }
                }
                .buttonStyle(.gamePill())
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
    }
}

/// A car or truck seen from above: body, a windscreen at each end, roof between.
private struct CarShape: View {
    let paint: Int
    let horizontal: Bool
    let fixed: Bool
    let cell: CGFloat

    var body: some View {
        GeometryReader { geo in
            let along = horizontal ? geo.size.width : geo.size.height
            let across = horizontal ? geo.size.height : geo.size.width
            let glass = cell * 0.13
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous).fill(Color(rgb: paint))
                if !fixed {
                    ForEach(0..<2, id: \.self) { i in
                        let start = i == 0 ? cell * 0.16 : along - cell * 0.16 - glass
                        RoundedRectangle(cornerRadius: cell * 0.05)
                            .fill(Color(rgb: paint, scaled: 1 / 1.5))
                            .frame(width: horizontal ? glass : across * 0.66, height: horizontal ? across * 0.66 : glass)
                            .offset(x: horizontal ? start : across * 0.17, y: horizontal ? across * 0.17 : start)
                    }
                    let length = along - 2 * (cell * 0.16 + glass + cell * 0.07)
                    RoundedRectangle(cornerRadius: cell * 0.1)
                        .fill(Color(rgb: paint, scaled: 1.12))
                        .frame(width: horizontal ? length : across * 0.62, height: horizontal ? across * 0.62 : length)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
    }
}
