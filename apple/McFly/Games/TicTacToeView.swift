import McFlyKit
import SwiftUI

/// Tic-tac-toe (display/qml/games/TicTacToe.qml): two people at the screen,
/// or one against McFly, whose move lands a beat after yours. Wide (an iPad
/// on its side) the board sits on the left with everything else beside it.
struct TicTacToeView: View {
    @State private var game = TicTacToe()

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
                    .frame(width: min(400, geo.size.width * 0.42))
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
        // McFly's move, a beat after yours.
        .task(id: moveKey) {
            guard game.computerTurn else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { game.computerMove() }
        }
    }

    private var moveKey: String { game.cells.map { $0?.rawValue ?? "-" }.joined() + game.turn.rawValue + "\(game.vsComputer)" }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpponentPickers(vsComputer: game.vsComputer, hard: game.hard) { vs, hard in game.setMode(vsComputer: vs, hard: hard) }
            ScoreChips(score: game.score, xName: game.vsComputer ? "You" : "X", oName: game.vsComputer ? "McFly" : "O")
        }
    }

    private var statusText: String {
        if let winner = game.winner {
            return game.vsComputer ? (winner == .x ? "You win!" : "McFly wins!") : "\(winner.rawValue) wins!"
        }
        if game.draw { return "It's a draw" }
        if game.computerTurn { return "McFly is thinking…" }
        return game.vsComputer ? "Your turn" : "\(game.turn.rawValue)'s turn"
    }

    private var status: some View {
        Text(statusText)
            .font(.title2.weight(.semibold))
            .foregroundStyle(game.winner.map(GameColors.of) ?? Theme.text)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.2), value: statusText)
    }

    private var roundButton: some View {
        Button(game.over ? "Play again" : "Start over") {
            withAnimation(.easeOut(duration: 0.2)) { game.newRound() }
        }
        .buttonStyle(.gamePill(game.over ? .prominent : .neutral))
        .controlSize(.large)
        .frame(minHeight: 44)
    }

    private var board: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let gap = size * 0.03
            let cell = (size - 2 * gap) / 3
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            square(row * 3 + column, cell: cell)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func square(_ index: Int, cell: CGFloat) -> some View {
        let mark = game.cells[index]
        let lit = game.winLine?.contains(index) ?? false
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                if game.over { game.newRound() } else { game.play(index) }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: min(Theme.radius, cell * 0.2), style: .continuous)
                    .fill(lit ? (mark.map(GameColors.of) ?? Theme.surface).opacity(0.18) : Theme.surface)
                if let mark {
                    MarkGlyph(mark: mark, size: cell)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .opacity(game.over && !lit && mark != nil ? 0.55 : 1)
            .frame(width: cell, height: cell)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mark.map { "\($0.rawValue)" } ?? "Empty square \(index + 1)")
    }
}

/// X as two rounded bars, O as a ring.
struct MarkGlyph: View {
    let mark: Mark
    let size: CGFloat

    var body: some View {
        if mark == .x {
            ZStack {
                ForEach([45.0, -45.0], id: \.self) { angle in
                    Capsule()
                        .fill(GameColors.x)
                        .frame(width: size * 0.56 * 1.2, height: size * 0.12)
                        .rotationEffect(.degrees(angle))
                }
            }
        } else {
            Circle()
                .strokeBorder(GameColors.o, lineWidth: size * 0.11)
                .frame(width: size * 0.6, height: size * 0.6)
        }
    }
}
