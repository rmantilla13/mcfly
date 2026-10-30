import McFlyKit
import SwiftUI

/// Pairs (display/qml/games/Pairs.qml): turn two cards over and find the
/// pairs, alone, against someone at the screen or against McFly, with Color
/// by Number's pictures on the cards. A missed pair turns back after a beat,
/// or at once on the next tap; McFly turns a card every 0.7 s. Wide (an iPad
/// on its side, the Mac) the cards sit on the left with the controls beside
/// them.
struct PairsView: View {
    @State private var game = Pairs()
    @State private var best = GameProgress.shared.pairsBest

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height * 1.4 {
                HStack(spacing: 20) {
                    board.frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            status.frame(maxWidth: .infinity, alignment: .leading)
                            GameIconButton(systemImage: "arrow.clockwise", label: "New game", prominent: game.over) { newGame() }
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
                    Button(game.over ? "Play again" : "New game") { newGame() }
                        .buttonStyle(.gamePill(game.over ? .prominent : .neutral))
                        .controlSize(.large)
                }
            }
        }
        // A missed pair turns back after a beat.
        .task(id: game.missed ? game.up : []) {
            guard game.missed else { return }
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation { game.hideNow() }
        }
        // McFly turns a card at a time.
        .task(id: moveKey) {
            guard game.computerTurn, !game.missed else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation { game.computerMove() }
        }
        .onChange(of: game.over) { _, over in
            guard over, game.solo else { return }
            GameProgress.shared.recordPairs(size: game.size, moves: game.moves)
            best = GameProgress.shared.pairsBest
        }
    }

    private var moveKey: String { "\(game.up)\(game.found.map { $0?.rawValue ?? "-" })\(game.turn)\(game.faces)" }

    private func newGame() {
        withAnimation(.easeOut(duration: 0.2)) { game.deal() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Players", selection: Binding(get: { game.mode }, set: { mode in game.setMode(mode, hard: game.hard) })) {
                Text("Solo").tag(Pairs.Mode.solo)
                Text("2 players").tag(Pairs.Mode.two)
                Text("vs McFly").tag(Pairs.Mode.mcfly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            HStack(spacing: 10) {
                if game.vsComputer {
                    Picker("Level", selection: Binding(get: { game.hard }, set: { hard in game.setMode(game.mode, hard: hard) })) {
                        Text("Easy").tag(false)
                        Text("Hard").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 150)
                }
                Picker("Cards", selection: Binding(get: { game.size }, set: { size in game.setSize(size) })) {
                    ForEach(Pairs.sizes, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 190)
            }
            HStack(spacing: 10) {
                if game.solo {
                    ScoreChip(label: "Turns", value: String(game.moves), color: Theme.muted)
                    ScoreChip(label: "Best", value: best[game.size].map(String.init) ?? "–", color: Theme.muted)
                } else {
                    ScoreChip(label: game.vsComputer ? "You" : "Orange", value: String(game.score.x), color: GameColors.x)
                    ScoreChip(label: game.vsComputer ? "McFly" : "Blue", value: String(game.score.o), color: GameColors.o)
                }
            }
        }
        .controlSize(.large)
    }

    private var statusText: String {
        if game.solo { return game.over ? "All found in \(game.moves) turns" : "\(game.pairsLeft) pairs to find" }
        if game.over {
            guard let winner = game.winner else { return "It's a draw" }
            return game.vsComputer ? (winner == .x ? "You win!" : "McFly wins!") : "\(winner == .x ? "Orange" : "Blue") wins!"
        }
        if game.computerTurn { return "McFly's turn" }
        return game.vsComputer ? "Your turn" : "\(game.turn == .x ? "Orange" : "Blue")'s turn"
    }

    private var status: some View {
        Text(statusText)
            .font(.title2.weight(.semibold))
            .foregroundStyle(game.solo || (game.over && game.winner == nil) ? Theme.text
                             : GameColors.of(game.over ? game.winner ?? .x : game.turn))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .animation(.easeOut(duration: 0.2), value: statusText)
    }

    /// The columns and rows that make `count` cards biggest in `size`.
    private static func grid(_ count: Int, in size: CGSize) -> (columns: Int, rows: Int, cell: CGFloat) {
        var out = (columns: 4, rows: count / 4, cell: CGFloat(0))
        for columns in 2...count where count % columns == 0 {
            let rows = count / columns
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            if cell > out.cell { out = (columns, rows, cell) }
        }
        return out
    }

    private var board: some View {
        GeometryReader { geo in
            let g = Self.grid(game.faces.count, in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(game.faces.indices, id: \.self) { i in
                    card(i, side: g.cell * 0.92)
                        .offset(x: CGFloat(i % g.columns) * g.cell + g.cell * 0.04, y: CGFloat(i / g.columns) * g.cell + g.cell * 0.04)
                }
            }
            .frame(width: CGFloat(g.columns) * g.cell, height: CGFloat(g.rows) * g.cell, alignment: .topLeading)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            // A new deal lays out new cards, so none turns back over showing its new picture.
            .id(game.faces)
        }
    }

    private func card(_ i: Int, side: CGFloat) -> some View {
        let by = game.found[i]
        let up = by != nil || game.up.contains(i)
        let radius = min(Theme.radiusSm, side * 0.18)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if game.over { game.deal() } else { game.play(i) }
            }
        } label: {
            FlipCard(up: up) {
                CardBack(radius: radius)
            } face: {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.palette.isDark ? Color(rgb: 0x2C2C31) : .white)
                    PairsPicture(picture: game.faces[i])
                        .padding(side * 0.12)
                    if let by {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(game.solo ? Theme.success : GameColors.of(by), lineWidth: max(3, side * 0.05))
                    }
                }
                .opacity(game.over || by == nil ? 1 : 0.8)
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(up ? ColorByNumber.pictures[game.faces[i]].title : "Card \(i + 1), face down")
    }
}

/// A picture, painted in, as the cards show it.
struct PairsPicture: View {
    let picture: Int

    var body: some View {
        ColorPictureView(picture: picture, saved: String(repeating: "1", count: ColorSheet(picture: picture).cellCount))
    }
}

/// A card's back: the accent, with a ring.
struct CardBack: View {
    let radius: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.82), Theme.accent], startPoint: .top, endPoint: .bottom))
                Circle()
                    .strokeBorder(.white.opacity(0.55), lineWidth: max(2, geo.size.width * 0.05))
                    .frame(width: geo.size.width * 0.42, height: geo.size.width * 0.42)
            }
        }
    }
}

/// A card turning over: the back turns away as the face turns in, each
/// showing only on its own half of the turn.
private struct FlipCard<Back: View, Face: View>: View {
    let up: Bool
    @ViewBuilder let back: () -> Back
    @ViewBuilder let face: () -> Face

    var body: some View {
        ZStack {
            back()
                .rotation3DEffect(.degrees(up ? 90 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
                .opacity(up ? 0 : 1)
                .animation(up ? .easeIn(duration: 0.1) : .easeOut(duration: 0.1).delay(0.1), value: up)
            face()
                .rotation3DEffect(.degrees(up ? 0 : -90), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
                .opacity(up ? 1 : 0)
                .animation(up ? .easeOut(duration: 0.1).delay(0.1) : .easeIn(duration: 0.1), value: up)
        }
    }
}
