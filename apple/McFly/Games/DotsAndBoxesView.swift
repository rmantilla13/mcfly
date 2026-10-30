import McFlyKit
import SwiftUI

/// Dots and Boxes (display/qml/games/DotsAndBoxes.qml): two people at the
/// screen, or one against McFly, whose lines land half a second apart. The
/// whole board takes the tap and draws the line nearest it. Wide (an iPad on
/// its side, the Mac) the board sits on the left with the controls beside it.
struct DotsAndBoxesView: View {
    @State private var game = DotsAndBoxes()

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height * 1.4 {
                HStack(spacing: 20) {
                    board.frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            status.frame(maxWidth: .infinity, alignment: .leading)
                            GameIconButton(systemImage: "arrow.clockwise", label: "Start over", prominent: game.over) { newRound() }
                        }
                        controls
                        Spacer()
                    }
                    .frame(width: min(400, max(300, geo.size.width * 0.36)))
                }
            } else {
                VStack(spacing: 14) {
                    controls.frame(maxWidth: .infinity, alignment: .leading)
                    status
                    board.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button(game.over ? "Play again" : "Start over") { newRound() }
                        .buttonStyle(.gamePill(game.over ? .prominent : .neutral))
                        .controlSize(.large)
                }
            }
        }
        // McFly's lines, one at a time.
        .task(id: moveKey) {
            guard game.computerTurn else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { game.computerMove() }
        }
    }

    private var moveKey: String { game.lines.map { $0?.rawValue ?? "-" }.joined() + game.turn.rawValue + "\(game.vsComputer)\(game.hard)" }

    private func newRound() {
        withAnimation(.easeOut(duration: 0.2)) { game.newRound() }
    }

    private func name(_ mark: Mark) -> String {
        game.vsComputer ? (mark == .x ? "You" : "McFly") : (mark == .x ? "Orange" : "Blue")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpponentPickers(vsComputer: game.vsComputer, hard: game.hard) { vs, hard in
                game.setMode(vsComputer: vs, hard: hard, size: game.size)
            }
            Picker("Size", selection: Binding(get: { game.size }, set: { size in
                game.setMode(vsComputer: game.vsComputer, hard: game.hard, size: size)
            })) {
                ForEach(DotsAndBoxes.sizes, id: \.self) { Text("\($0)×\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(maxWidth: 240)
            // The boxes in this game, with the games won once there are any.
            HStack(spacing: 10) {
                ForEach([Mark.x, .o], id: \.self) { mark in
                    let won = game.score[mark]
                    ScoreChip(label: won == 0 ? name(mark) : "\(name(mark)) · \(won) win\(won == 1 ? "" : "s")",
                              value: String(mark == .x ? game.xBoxes : game.oBoxes), color: GameColors.of(mark))
                }
            }
        }
    }

    private var statusText: String {
        if game.over {
            guard let winner = game.winner else { return "It's a draw" }
            return game.vsComputer ? (winner == .x ? "You win!" : "McFly wins!") : "\(name(winner)) wins!"
        }
        if game.computerTurn { return "McFly is thinking…" }
        return game.vsComputer ? "Your turn" : "\(name(game.turn))'s turn"
    }

    private var status: some View {
        Text(statusText)
            .font(.title2.weight(.semibold))
            .foregroundStyle(game.over ? game.winner.map(GameColors.of) ?? Theme.text : GameColors.of(game.turn))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .animation(.easeOut(duration: 0.2), value: statusText)
    }

    // MARK: The board

    private var board: some View {
        GeometryReader { geo in
            let n = CGFloat(game.size)
            // A box's side; 0.4 of one around the dots, so the outer lines
            // take a tap from outside them too.
            let box = min(geo.size.width, geo.size.height) / (n + 0.8)
            let pad = box * 0.4
            let thick = max(5, box * 0.09)
            let dot = max(10, box * 0.16)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface)
                ForEach(game.boxes.indices, id: \.self) { b in
                    let owner = game.boxes[b]
                    RoundedRectangle(cornerRadius: min(Theme.radiusSm, box * 0.15), style: .continuous)
                        .fill(owner.map(GameColors.of) ?? .clear)
                        .opacity(owner == nil ? 0 : 0.28)
                        .frame(width: box - thick, height: box - thick)
                        .offset(x: pad + CGFloat(b % game.size) * box + thick / 2, y: pad + CGFloat(b / game.size) * box + thick / 2)
                }
                ForEach(game.lines.indices, id: \.self) { l in
                    let r = lineRect(l, box: box, pad: pad, thick: thick)
                    let by = game.lines[l]
                    Capsule()
                        .fill(by.map(GameColors.of) ?? Theme.sunken)
                        .opacity(by == nil ? 0.7 : 1)
                        .overlay {
                            // The last line drawn, with a white stripe through it.
                            if l == game.lastLine, !game.over {
                                Capsule()
                                    .fill(.white.opacity(0.85))
                                    .frame(width: r.width > r.height ? r.width * 0.4 : r.width * 0.34,
                                           height: r.width > r.height ? r.height * 0.34 : r.height * 0.4)
                            }
                        }
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
                ForEach(0..<((game.size + 1) * (game.size + 1)), id: \.self) { i in
                    Circle()
                        .fill(Theme.text)
                        .frame(width: dot, height: dot)
                        .offset(x: pad + CGFloat(i % (game.size + 1)) * box - dot / 2, y: pad + CGFloat(i / (game.size + 1)) * box - dot / 2)
                }
            }
            .frame(width: n * box + 2 * pad, height: n * box + 2 * pad, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                withAnimation(.easeOut(duration: 0.2)) {
                    if game.over {
                        game.newRound()
                    } else if let l = lineAt(point, box: box, pad: pad) {
                        game.play(l)
                    }
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .accessibilityElement()
            .accessibilityLabel("Board, \(game.xBoxes) boxes to \(game.oBoxes)")
        }
    }

    private func lineRect(_ l: Int, box: CGFloat, pad: CGFloat, thick: CGFloat) -> CGRect {
        if l < game.across {
            let r = l / game.columns, c = l % game.columns
            return CGRect(x: pad + CGFloat(c) * box, y: pad + CGFloat(r) * box - thick / 2, width: box, height: thick)
        }
        let i = l - game.across, r = i / (game.columns + 1), c = i % (game.columns + 1)
        return CGRect(x: pad + CGFloat(c) * box - thick / 2, y: pad + CGFloat(r) * box, width: thick, height: box)
    }

    /// The line nearest a point on the board, or nil when both lines near it are drawn.
    private func lineAt(_ p: CGPoint, box: CGFloat, pad: CGFloat) -> Int? {
        let x = (p.x - pad) / box, y = (p.y - pad) / box
        let r = max(0, min(game.rows, Int(y.rounded())))
        let c = max(0, min(game.columns - 1, Int(x.rounded(.down))))
        let dc = max(0, min(game.columns, Int(x.rounded())))
        let dr = max(0, min(game.rows - 1, Int(y.rounded(.down))))
        let near = [(abs(y - CGFloat(r)), game.acrossLine(r, c)), (abs(x - CGFloat(dc)), game.downLine(dr, dc))].sorted { $0.0 < $1.0 }
        return near.first { game.lines[$0.1] == nil }?.1
    }
}
