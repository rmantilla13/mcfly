import McFlyKit
import SwiftUI

/// 2048 (display/qml/games/Game2048.qml, the rules MIT-licensed in the kit):
/// swipe the board to slide the tiles, or use the arrow keys. The original
/// game's colours and timing: a 100 ms slide, then the new and merged tiles
/// pop in. The best score and the game in progress are kept on the device
/// after every move, so closing the game never loses one.
struct Game2048View: View {
    @State private var game = Game2048(saved: GameProgress.shared.game2048)
    @State private var best = GameProgress.shared.best2048
    @State private var gained: Int?
    @State private var gainKey = 0
    @FocusState private var focused: Bool

    private static let paper = Color(rgb: 0xFAF8EF)
    private static let ink = Color(rgb: 0x776E65)
    private static let brightInk = Color(rgb: 0xF9F6F2)
    private static let frame = Color(rgb: 0xBBADA0)
    private static let button = Color(rgb: 0x8F7A66)

    static func tileColor(_ value: Int) -> Color {
        let colors: [Int: Int] = [2: 0xEEE4DA, 4: 0xEDE0C8, 8: 0xF2B179, 16: 0xF59563, 32: 0xF67C5F,
                                  64: 0xF65E3B, 128: 0xEDCF72, 256: 0xEDCC61, 512: 0xEDC850,
                                  1024: 0xEDC53F, 2048: 0xEDC22E]
        return Color(rgb: colors[value] ?? 0x3C3A32)
    }

    /// Font size as a share of the tile.
    static func textScale(_ value: Int) -> CGFloat {
        value < 100 ? 0.52 : value < 1000 ? 0.42 : value <= 2048 ? 0.33 : 0.28
    }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width > geo.size.height * 1.4
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Self.paper)
                if side {
                    HStack(alignment: .top, spacing: 20) {
                        board(size: min(geo.size.height - 32, geo.size.width * 0.55))
                        VStack(alignment: .leading, spacing: 14) {
                            title
                            scores
                            newGame
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 16) {
                        HStack(alignment: .center) {
                            title
                            Spacer()
                            newGame
                        }
                        scores.frame(maxWidth: .infinity, alignment: .leading)
                        board(size: min(geo.size.width - 32, geo.size.height - 200))
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                move(abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up))
            })
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            switch press.key {
            case .upArrow: move(.up)
            case .downArrow: move(.down)
            case .leftArrow: move(.left)
            default: move(.right)
            }
            return .handled
        }
    }

    private func move(_ direction: Game2048.Direction) {
        let before = game.score
        var moved = false
        withAnimation(.easeInOut(duration: 0.1)) { moved = game.move(direction) }
        guard moved else { return }
        if game.score > before {
            gained = game.score - before
            gainKey += 1
        }
        best = max(best, game.score)
        GameProgress.shared.best2048 = best
        GameProgress.shared.game2048 = game.saved
    }

    private func restart() {
        withAnimation(.easeOut(duration: 0.15)) { game.restart() }
        GameProgress.shared.game2048 = game.saved
    }

    private var title: some View {
        Text("2048")
            .font(.system(size: 52, weight: .bold, design: .rounded))
            .foregroundStyle(Self.ink)
    }

    private var scores: some View {
        HStack(spacing: 10) {
            scoreBox("SCORE", game.score)
                .overlay {
                    if let gained {
                        Text("+\(gained)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Self.ink.opacity(0.9))
                            .modifier(FloatAway(key: gainKey))
                    }
                }
            scoreBox("BEST", max(best, game.score))
        }
    }

    private func scoreBox(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(rgb: 0xEEE4DA))
            Text(String(value)).font(.system(size: 24, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(minWidth: 88, minHeight: 56)
        .padding(.horizontal, 10)
        .background(Self.frame, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }

    private var newGame: some View {
        Button(action: restart) {
            Text("New Game")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Self.brightInk)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .background(Self.button, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PressableStyle())
    }

    private func board(size: CGFloat) -> some View {
        let size = max(120, size)
        let gap = size * 0.03
        let cell = (size - gap * 5) / 4
        func at(_ i: Int) -> CGFloat { gap + CGFloat(i) * (cell + gap) + cell / 2 }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Self.frame)
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(rgb: 0xEEE4DA, opacity: 0.35))
                    .frame(width: cell, height: cell)
                    .position(x: at(i % 4), y: at(i / 4))
            }
            ForEach(game.tiles) { tile in
                TileView(tile: tile, cell: cell)
                    .position(x: at(tile.x), y: at(tile.y))
                    .zIndex(tile.mergedFrom != nil ? 2 : 1)
                    .transition(tile.mergedFrom != nil ? .pop : tile.previousPosition == nil ? .appear : .identity)
            }
            if game.terminated {
                Message(won: game.won, keep: {
                    withAnimation { game.continuePlaying() }
                    GameProgress.shared.game2048 = game.saved
                }, again: restart)
                .zIndex(3)
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
    }

    private struct TileView: View {
        let tile: Game2048.Tile
        let cell: CGFloat

        var body: some View {
            Text(String(tile.value))
                .font(.system(size: max(1, cell * Game2048View.textScale(tile.value)), weight: .bold))
                .foregroundStyle(tile.value <= 4 ? Game2048View.ink : Game2048View.brightInk)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: cell, height: cell)
                .background(Game2048View.tileColor(tile.value), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    /// "You win!" or "Game over!", fading in once the last tiles settle.
    private struct Message: View {
        let won: Bool
        let keep: () -> Void
        let again: () -> Void
        @State private var shown = false

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(won ? Color(rgb: 0xEDC22E, opacity: 0.5) : Color(rgb: 0xEEE4DA, opacity: 0.73))
                VStack(spacing: 24) {
                    Text(won ? "You win!" : "Game over!")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(won ? Game2048View.brightInk : Game2048View.ink)
                    HStack(spacing: 12) {
                        if won { button("Keep going", keep) }
                        button("Try again", again)
                    }
                }
            }
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.easeIn(duration: 0.8).delay(1.2)) { shown = true } }
        }

        private func button(_ title: String, _ action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Game2048View.brightInk)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(Game2048View.button, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(PressableStyle())
        }
    }
}

private extension AnyTransition {
    /// A new tile: appears after the slide.
    static var appear: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.01).animation(.easeInOut(duration: 0.2).delay(0.1)), removal: .identity)
    }

    /// A merged tile: pops past full size after the slide.
    static var pop: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.01).animation(.spring(response: 0.22, dampingFraction: 0.55).delay(0.1)),
                    removal: .identity)
    }
}

/// The points from the last move float up out of the score.
private struct FloatAway: ViewModifier {
    let key: Int
    @State private var t: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .offset(y: 10 - 60 * t)
            .opacity(Double(1 - t))
            .onChange(of: key, initial: true) {
                t = 0
                withAnimation(.easeIn(duration: 0.6)) { t = 1 }
            }
            .allowsHitTesting(false)
    }
}
