import McFlyKit
import SwiftUI

/// Solitaire (display/qml/games/Solitaire.qml): Klondike, a tap a move. The
/// deck, the waste, a space and the four home piles in a row, the seven
/// columns under them; each column is one tap target, and cards glide to
/// where a tap sends them. Wide (an iPad on its side, the Mac) the controls
/// stand beside the table; upright, above it. The game in progress is kept
/// as you go, and once every card is face up the rest go home on their own.
struct SolitaireView: View {
    @State private var game = GameProgress.shared.solitaire ?? Solitaire()
    @State private var wins = GameProgress.shared.solitaireWins

    private static let glide = Animation.easeOut(duration: 0.16)

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height * 1.25 {
                HStack(alignment: .top, spacing: 16) {
                    table
                    VStack(alignment: .leading, spacing: 14) {
                        status
                        buttons
                        drawPicker
                        chips
                    }
                    .frame(width: min(300, max(220, geo.size.width * 0.24)), alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        status.frame(maxWidth: .infinity, alignment: .leading)
                        buttons
                    }
                    HStack(spacing: 12) {
                        drawPicker
                        chips
                    }
                    table
                }
            }
        }
        .onChange(of: game) { _, now in GameProgress.shared.solitaire = now }
        .onChange(of: game.won) { _, won in
            guard won else { return }
            GameProgress.shared.recordSolitaireWin(moves: game.moves)
            wins = GameProgress.shared.solitaireWins
        }
        // With every card face up, one goes home every 110 ms.
        .task(id: game.finishing) {
            while game.finishing, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(Self.glide) { _ = game.finishStep() }
            }
        }
    }

    private var statusText: String {
        if game.won { return "You win!" }
        if game.finishing { return "Going home…" }
        return game.moves == 0 ? "Tap a card to move it" : "\(game.home) of 52 home"
    }

    private var status: some View {
        Text(statusText)
            .font(.title3.weight(.semibold))
            .foregroundStyle(game.won ? Theme.success : Theme.text)
            .lineLimit(2)
            .contentTransition(.opacity)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            GameIconButton(systemImage: "arrow.uturn.backward", label: "Undo") {
                withAnimation(Self.glide) { _ = game.undo() }
            }
            .disabled(!game.canUndo)
            .opacity(game.canUndo ? 1 : 0.4)
            GameIconButton(systemImage: "arrow.clockwise", label: "New game", prominent: game.won) {
                withAnimation(.easeOut(duration: 0.25)) { game.deal() }
            }
        }
    }

    private var drawPicker: some View {
        Picker("Draw", selection: Binding(get: { game.drawThree }, set: { three in
            withAnimation(.easeOut(duration: 0.25)) { game.setDrawThree(three) }
        })) {
            Text("Draw 1").tag(false)
            Text("Draw 3").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(maxWidth: 220)
    }

    private var chips: some View {
        HStack(spacing: 10) {
            ScoreChip(label: "Moves", value: String(game.moves), color: Theme.muted)
            ScoreChip(label: "Wins", value: String(wins), color: Theme.muted)
        }
    }

    // MARK: The table

    private var table: some View {
        GeometryReader { geo in
            let t = TableLayout(size: geo.size, game: game)
            ZStack(alignment: .topLeading) {
                // Where piles go when they're empty.
                ForEach([0, 1, 3, 4, 5, 6], id: \.self) { i in
                    RoundedRectangle(cornerRadius: t.radius, style: .continuous)
                        .fill(Theme.sunken)
                        .overlay {
                            if i >= 3 {
                                SuitMark(suit: i - 3)
                                    .fill(Theme.text.opacity(0.12))
                                    .frame(width: t.cardWidth * 0.42, height: t.cardWidth * 0.42)
                            } else if i == 0, game.stock.isEmpty, !game.waste.isEmpty {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: min(30, t.cardWidth * 0.36), weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(width: t.cardWidth, height: t.cardHeight)
                        .offset(x: t.slotX(i), y: 0)
                }
                ForEach(0..<7, id: \.self) { c in
                    RoundedRectangle(cornerRadius: t.radius, style: .continuous)
                        .strokeBorder(Theme.sunken, lineWidth: 2)
                        .frame(width: t.cardWidth, height: t.cardHeight)
                        .offset(x: t.slotX(c), y: t.columnsTop)
                }
                // The cards.
                ForEach(0..<52, id: \.self) { card in
                    let at = t.places[card]
                    PlayingCard(card: card, up: at.up)
                        .frame(width: t.cardWidth, height: t.cardHeight)
                        .offset(x: at.x, y: at.y)
                        .zIndex(Double(at.z) + (game.lastMoved.contains(card) ? 100 : 0))
                        .allowsHitTesting(false)
                }
                // The tap targets: the deck, the waste, the home piles, the columns.
                target(x: t.left, y: 0, width: t.slot, height: t.cardHeight, label: "Deck") { _ in _ = game.draw() }
                target(x: t.left + t.slot, y: 0, width: t.slot * 2, height: t.cardHeight, label: "Waste") { _ in _ = game.tapWaste() }
                ForEach(0..<4, id: \.self) { s in
                    target(x: t.left + CGFloat(3 + s) * t.slot, y: 0, width: t.slot, height: t.cardHeight,
                           label: "Home pile \(s + 1)") { _ in _ = game.tapHome(s) }
                }
                ForEach(0..<7, id: \.self) { c in
                    target(x: t.left + CGFloat(c) * t.slot, y: t.columnsTop, width: t.slot, height: t.columnsHeight,
                           label: "Column \(c + 1)") { y in _ = game.tapColumn(c, at: t.index(in: c, at: t.columnsTop + y)) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func target(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, label: String,
                        tap: @escaping (CGFloat) -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: width, height: height)
            .onTapGesture(coordinateSpace: .local) { point in
                withAnimation(Self.glide) { tap(point.y) }
            }
            .offset(x: x, y: y)
            .zIndex(300)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

/// Where everything on the table goes, as the display's Solitaire.qml lays
/// it out: seven slots across, the cards 1.4 times as tall as wide, each
/// column squeezed to fit.
private struct TableLayout {
    struct Place { var x: CGFloat, y: CGFloat, z: Int, up: Bool }

    let slot: CGFloat, cardWidth: CGFloat, cardHeight: CGFloat, left: CGFloat
    let columnsTop: CGFloat, columnsHeight: CGFloat, radius: CGFloat
    let game: Solitaire
    private(set) var places: [Place]

    init(size: CGSize, game: Solitaire) {
        self.game = game
        slot = max(1, min(size.width / 7, size.height / 2.7 / 1.4 / 0.9))
        cardWidth = slot * 0.9
        cardHeight = cardWidth * 1.4
        left = (size.width - 7 * slot) / 2
        columnsTop = cardHeight + max(8, cardHeight * 0.12)
        columnsHeight = max(cardHeight, size.height - columnsTop)
        radius = min(Theme.radiusSm, cardWidth * 0.1)
        places = Array(repeating: Place(x: 0, y: 0, z: 0, up: false), count: 52)
        let step = slot * 0.4
        for (i, c) in game.stock.enumerated() { places[c] = Place(x: slotX(0), y: 0, z: i, up: false) }
        let fanFrom = game.drawThree ? max(0, game.waste.count - 3) : game.waste.count
        for (i, c) in game.waste.enumerated() {
            places[c] = Place(x: slotX(1) + CGFloat(max(0, i - fanFrom)) * step, y: 0, z: i, up: true)
        }
        for (s, pile) in game.foundations.enumerated() {
            for (i, c) in pile.enumerated() { places[c] = Place(x: slotX(3 + s), y: 0, z: i, up: true) }
        }
        for (column, cards) in game.tableau.enumerated() {
            let gaps = spacing(column), down = game.hidden[column]
            for (i, c) in cards.enumerated() {
                let y = columnsTop + CGFloat(min(i, down)) * gaps.down + CGFloat(max(0, i - down)) * gaps.open
                places[c] = Place(x: slotX(column), y: y, z: i, up: i >= down)
            }
        }
    }

    func slotX(_ i: Int) -> CGFloat { left + CGFloat(i) * slot + (slot - cardWidth) / 2 }

    /// How far apart a column's face-down and face-up cards sit.
    func spacing(_ column: Int) -> (down: CGFloat, open: CGFloat) {
        let n = game.tableau[column].count, down = CGFloat(game.hidden[column]), open = CGFloat(n - game.hidden[column])
        let room = columnsHeight - cardHeight
        var d = cardHeight * 0.1, o = cardHeight * 0.27
        if down * d + max(0, open - 1) * o > room, open > 1 { o = max(cardHeight * 0.17, (room - down * d) / (open - 1)) }
        if down * d + max(0, open - 1) * o > room, down > 0 { d = max(cardHeight * 0.04, (room - max(0, open - 1) * o) / down) }
        if down * d + max(0, open - 1) * o > room, open > 1 { o = max(0, (room - down * d) / (open - 1)) }
        return (d, o)
    }

    /// The card in a column under a point `y` down the table.
    func index(in column: Int, at y: CGFloat) -> Int {
        var found = 0
        for (i, c) in game.tableau[column].enumerated() where places[c].y <= y { found = i }
        return found
    }
}

/// One playing card: face up, its rank and suit in the top band (all that
/// shows when cards overlap) and a big suit below; face down, the accent
/// with a ring. The display's SolitaireCard.qml.
struct PlayingCard: View {
    let card: Int
    let up: Bool

    private static let ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let band = h * 0.22
            let radius = min(Theme.radiusSm, w * 0.1)
            let dark = Theme.palette.isDark
            if up {
                let ink = Solitaire.isRed(card) ? Color(rgb: 0xD2343A) : Color(rgb: 0x1C1C1F)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(dark ? Color(rgb: 0xDCDCE0) : .white)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.black.opacity(dark ? 0.35 : 0.13), lineWidth: 1)
                    HStack(spacing: w * 0.04) {
                        Text(Self.ranks[Solitaire.rank(of: card) - 1])
                            .font(.system(size: max(10, band * 0.78), weight: .bold))
                            .tracking(Solitaire.rank(of: card) == 10 ? -1 : 0)
                            .foregroundStyle(ink)
                        SuitMark(suit: Solitaire.suit(of: card))
                            .fill(ink)
                            .frame(width: band * 0.62, height: band * 0.62)
                    }
                    .frame(height: band)
                    .padding(.leading, w * 0.08)
                    SuitMark(suit: Solitaire.suit(of: card))
                        .fill(ink)
                        .frame(width: w * 0.52, height: w * 0.52)
                        .offset(x: (w - w * 0.52) / 2, y: band + (h - band - w * 0.52) / 2)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.82), Theme.accent], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(dark ? Color(rgb: 0xDCDCE0) : .white, lineWidth: max(2, w * 0.04))
                    Circle()
                        .strokeBorder(.white.opacity(0.5), lineWidth: max(2, w * 0.05))
                        .frame(width: w * 0.44, height: w * 0.44)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A card suit, drawn for McFly in a 100 × 100 box and scaled to fit: 0
/// spades, 1 hearts, 2 diamonds, 3 clubs (the display's CardSuit.qml).
struct SuitMark: Shape {
    let suit: Int

    func path(in rect: CGRect) -> Path {
        let fit = min(rect.width, rect.height) / 100
        let ox = rect.minX + (rect.width - 100 * fit) / 2, oy = rect.minY + (rect.height - 100 * fit) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * fit, y: oy + y * fit) }
        var path = Path()
        switch suit {
        case 0: // spades: a leaf on a flared stem
            path.move(to: p(50, 4))
            path.addCurve(to: p(6, 60), control1: p(38, 24), control2: p(6, 38))
            path.addCurve(to: p(28, 83), control1: p(6, 74), control2: p(16, 83))
            path.addCurve(to: p(47, 72), control1: p(37, 83), control2: p(44, 79))
            path.addCurve(to: p(33, 96), control1: p(46, 84), control2: p(42, 91))
            path.addLine(to: p(67, 96))
            path.addCurve(to: p(53, 72), control1: p(58, 91), control2: p(54, 84))
            path.addCurve(to: p(72, 83), control1: p(56, 79), control2: p(63, 83))
            path.addCurve(to: p(94, 60), control1: p(84, 83), control2: p(94, 74))
            path.addCurve(to: p(50, 4), control1: p(94, 38), control2: p(62, 24))
            path.closeSubpath()
        case 1: // hearts
            path.move(to: p(50, 92))
            path.addCurve(to: p(4, 32), control1: p(22, 70), control2: p(4, 52))
            path.addCurve(to: p(29, 6), control1: p(4, 16), control2: p(16, 6))
            path.addCurve(to: p(50, 20), control1: p(38, 6), control2: p(46, 11))
            path.addCurve(to: p(71, 6), control1: p(54, 11), control2: p(62, 6))
            path.addCurve(to: p(96, 32), control1: p(84, 6), control2: p(96, 16))
            path.addCurve(to: p(50, 92), control1: p(96, 52), control2: p(78, 70))
            path.closeSubpath()
        case 2: // diamonds, the sides drawn in a little
            path.move(to: p(50, 3))
            path.addCurve(to: p(90, 50), control1: p(62, 22), control2: p(74, 36))
            path.addCurve(to: p(50, 97), control1: p(74, 64), control2: p(62, 78))
            path.addCurve(to: p(10, 50), control1: p(38, 78), control2: p(26, 64))
            path.addCurve(to: p(50, 3), control1: p(26, 36), control2: p(38, 22))
            path.closeSubpath()
        default: // clubs: three discs, the space between them, and the stem
            var stem = Path()
            stem.move(to: p(46, 60))
            stem.addCurve(to: p(32, 96), control1: p(46, 78), control2: p(42, 89))
            stem.addLine(to: p(68, 96))
            stem.addCurve(to: p(54, 60), control1: p(58, 89), control2: p(54, 78))
            stem.closeSubpath()
            path = Path(ellipseIn: CGRect(origin: p(29, 9), size: CGSize(width: 42 * fit, height: 42 * fit)))
                .union(Path(ellipseIn: CGRect(origin: p(6, 37), size: CGSize(width: 42 * fit, height: 42 * fit))))
                .union(Path(ellipseIn: CGRect(origin: p(52, 37), size: CGSize(width: 42 * fit, height: 42 * fit))))
                .union(Path(CGRect(origin: p(40, 44), size: CGSize(width: 20 * fit, height: 22 * fit))))
                .union(stem)
        }
        return path
    }
}
