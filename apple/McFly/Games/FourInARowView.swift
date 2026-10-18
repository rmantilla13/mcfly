import McFlyKit
import SwiftUI

/// Four in a Row (display/qml/games/FourInARow.qml): tap a column and the
/// disc drops to the lowest free hole. Against McFly, its look-ahead runs off
/// the main thread while it "thinks", and its disc drops once yours has
/// landed. Every column is a full-height tap target.
struct FourInARowView: View {
    @State private var game = FourInARow()

    private let columns = FourInARow.columns
    private let rows = FourInARow.rows

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width > geo.size.height * 1.4
            if side {
                HStack(spacing: 20) {
                    board.frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 16) {
                        controls
                        status
                        Spacer()
                        roundButton
                    }
                    .frame(width: min(400, geo.size.width * 0.4))
                }
            } else {
                VStack(spacing: 16) {
                    controls
                    status
                    board.frame(maxWidth: .infinity, maxHeight: .infinity)
                    roundButton
                }
            }
        }
        // McFly's move: the search off the main thread, the disc after the
        // last one has landed (the longest drop is 450 ms).
        .task(id: moveKey) {
            guard game.computerTurn else { return }
            let board = game
            async let started = Task.sleep(for: .milliseconds(600))
            let column = await Task.detached(priority: .userInitiated) {
                var rng = SystemRandomNumberGenerator()
                return board.computerColumn(using: &rng)
            }.value
            try? await started
            guard !Task.isCancelled, let column, game.cells == board.cells else { return }
            game.place(column)
        }
    }

    private var moveKey: String { game.cells.map { $0?.rawValue ?? "-" }.joined() + game.turn.rawValue + "\(game.vsComputer)\(game.hard)" }

    private func name(_ mark: Mark) -> String { mark == .x ? "Orange" : "Blue" }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpponentPickers(vsComputer: game.vsComputer, hard: game.hard) { vs, hard in game.setMode(vsComputer: vs, hard: hard) }
            ScoreChips(score: game.score, xName: game.vsComputer ? "You" : "Orange", oName: game.vsComputer ? "McFly" : "Blue")
        }
    }

    private var statusText: String {
        if let winner = game.winner {
            return game.vsComputer ? (winner == .x ? "You win!" : "McFly wins!") : "\(name(winner)) wins!"
        }
        if game.draw { return "It's a draw" }
        if game.computerTurn { return "McFly is thinking…" }
        return game.vsComputer ? "Your turn" : "\(name(game.turn))'s turn"
    }

    private var status: some View {
        Text(statusText)
            .font(.title2.weight(.semibold))
            .foregroundStyle(game.winner.map(GameColors.of) ?? Theme.text)
            .animation(.easeOut(duration: 0.2), value: statusText)
    }

    private var roundButton: some View {
        Button(game.over ? "Play again" : "Start over") { game.newRound() }
            .buttonStyle(.gamePill(game.over ? .prominent : .neutral))
            .controlSize(.large)
            .frame(minHeight: 44)
    }

    private var board: some View {
        GeometryReader { geo in
            // Columns at least 44 points wide; rows follow, up to square.
            let colWidth = max(44, min(geo.size.width / CGFloat(columns), geo.size.height / CGFloat(rows)))
            let rowHeight = min(colWidth, geo.size.height / CGFloat(rows))
            let disc = min(colWidth, rowHeight) * 0.8
            let width = colWidth * CGFloat(columns), height = rowHeight * CGFloat(rows)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: min(Theme.radius, disc * 0.5), style: .continuous)
                    .fill(Theme.surface)
                ForEach(0..<(rows * columns), id: \.self) { index in
                    let column = index % columns, row = index / columns
                    let center = CGPoint(x: (CGFloat(column) + 0.5) * colWidth,
                                         y: (CGFloat(rows - 1 - row) + 0.5) * rowHeight)
                    Circle().fill(Theme.sunken)
                        .frame(width: disc, height: disc)
                        .position(center)
                    if let mark = game.cells[index] {
                        Disc(mark: mark, size: disc, lit: game.winLine?.contains(index) ?? false,
                             last: !game.over && game.lastMove == index, dim: game.over && !(game.winLine?.contains(index) ?? false),
                             fall: CGFloat(rows - row) * rowHeight, duration: 0.12 + Double(rows - row) * 0.055)
                            .position(center)
                    }
                }
                // The columns: each a tap target the full height of the board.
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let target = FourInARow.landing(game.cells, column)
                        Button {
                            if game.over { game.newRound() } else { game.play(column) }
                        } label: {
                            Color.clear.frame(width: colWidth, height: height).contentShape(Rectangle())
                        }
                        .buttonStyle(ColumnStyle(tint: GameColors.of(game.turn), open: target != nil && !game.over && !game.computerTurn,
                                                 landing: target.map { (CGFloat(rows - 1 - $0 / columns) + 0.5) * rowHeight },
                                                 disc: disc))
                        .accessibilityLabel("Column \(column + 1)")
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: min(Theme.radius, disc * 0.5), style: .continuous))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

/// A column held down: tinted, with where the disc will land.
private struct ColumnStyle: ButtonStyle {
    let tint: Color
    let open: Bool
    let landing: CGFloat?
    let disc: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(tint.opacity(configuration.isPressed && open ? 0.12 : 0))
            .overlay(alignment: .top) {
                if configuration.isPressed, open, let landing {
                    Circle().fill(tint.opacity(0.4))
                        .frame(width: disc, height: disc)
                        .offset(y: landing - disc / 2)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// A disc: it drops in from above the board, bouncing as it lands; the
/// winning four get a white ring, the last one dropped a white dot.
private struct Disc: View {
    let mark: Mark
    let size: CGFloat
    let lit: Bool
    let last: Bool
    let dim: Bool
    let fall: CGFloat
    let duration: Double
    @State private var landed = false

    var body: some View {
        Circle()
            .fill(GameColors.of(mark))
            .overlay {
                if lit {
                    Circle().strokeBorder(.white, lineWidth: max(2, size * 0.08)).padding(size * 0.19)
                } else if last {
                    Circle().fill(.white.opacity(0.85)).frame(width: size * 0.22, height: size * 0.22)
                }
            }
            .frame(width: size, height: size)
            .opacity(dim ? 0.45 : 1)
            .animation(.easeOut(duration: 0.25), value: dim)
            .offset(y: landed ? 0 : -fall)
            .onAppear {
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 260, damping: 14).speed(0.45 / max(0.2, duration))) {
                    landed = true
                }
            }
    }
}
