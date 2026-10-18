import McFlyKit
import SwiftUI

/// Each game's card picture, from its own colours and pieces (the display's
/// card art in GamesScreen.qml).
struct GameArt: View {
    let game: GameID

    var body: some View {
        switch game {
        case .trafficJam: TrafficArt()
        case .ticTacToe: TicTacToeArt()
        case .fourInARow: FourInARowArt()
        case .game2048: Art2048()
        case .scoopShop: ScoopArt()
        case .penguinMarch: PenguinArtCard()
        }
    }
}

private struct TrafficArt: View {
    // [column, row, length, across, colour]: a level's opening position.
    private let cars: [(Int, Int, Int, Bool, Int)] = [(0, 2, 2, true, 0xE5484D), (2, 1, 3, false, 0x5B8DEF), (3, 0, 3, true, 0xF2B84B),
                                                      (4, 2, 2, false, 0x3DB37A), (0, 4, 2, true, 0x8E7CE6), (5, 3, 3, false, 0xEF8A6F),
                                                      (1, 0, 2, false, 0x5FB3B3)]

    var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width, geo.size.height) * 0.8 / 6
            let origin = CGPoint(x: (geo.size.width - cell * 6) / 2, y: (geo.size.height - cell * 6) / 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface)
                    .frame(width: cell * 0.5, height: cell * 0.8)
                    .offset(x: origin.x + cell * 6 - 2, y: origin.y + cell * 2.1)
                ForEach(cars.indices, id: \.self) { i in
                    let c = cars[i]
                    RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous)
                        .fill(Color(rgb: c.4))
                        .frame(width: CGFloat(c.3 ? c.2 : 1) * cell - cell * 0.12, height: CGFloat(c.3 ? 1 : c.2) * cell - cell * 0.12)
                        .offset(x: origin.x + CGFloat(c.0) * cell + cell * 0.06, y: origin.y + CGFloat(c.1) * cell + cell * 0.06)
                }
            }
        }
    }
}

private struct TicTacToeArt: View {
    private let marks: [Mark?] = [.x, .o, nil, nil, .x, .o, nil, nil, .x]

    var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width, geo.size.height) * 0.26
            Grid(horizontalSpacing: cell * 0.08, verticalSpacing: cell * 0.08) {
                ForEach(0..<3, id: \.self) { r in
                    GridRow {
                        ForEach(0..<3, id: \.self) { c in
                            RoundedRectangle(cornerRadius: Theme.radiusSm * 0.6, style: .continuous)
                                .fill(Theme.surface)
                                .frame(width: cell, height: cell)
                                .overlay { if let mark = marks[r * 3 + c] { MarkGlyph(mark: mark, size: cell * 0.95) } }
                        }
                    }
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

private struct FourInARowArt: View {
    // Bottom row first; a diagonal four for orange.
    private let marks = ["XOOXO..", ".XXO...", ".OXX...", "..OX...", ".......", "......."]

    var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / 7.6, geo.size.height / 6.6)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cell * 0.4, style: .continuous).fill(Theme.surface)
                ForEach(0..<42, id: \.self) { i in
                    let row = Array(marks[i / 7])[i % 7]
                    Circle()
                        .fill(row == "X" ? GameColors.x : row == "O" ? GameColors.o : Theme.sunken)
                        .frame(width: cell * 0.8, height: cell * 0.8)
                        .offset(x: CGFloat(i % 7) * cell + cell * 0.1, y: CGFloat(5 - i / 7) * cell + cell * 0.1)
                }
            }
            .frame(width: cell * 7, height: cell * 6)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

private struct Art2048: View {
    var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width, geo.size.height) * 0.3
            ZStack {
                Color(rgb: 0xFAF8EF)
                Grid(horizontalSpacing: cell * 0.12, verticalSpacing: cell * 0.12) {
                    GridRow { tile(2, cell); tile(8, cell) }
                    GridRow { tile(64, cell); tile(2048, cell) }
                }
            }
        }
    }

    private func tile(_ value: Int, _ cell: CGFloat) -> some View {
        Text(String(value))
            .font(.system(size: cell * (value > 1000 ? 0.3 : 0.45), weight: .bold))
            .foregroundStyle(value <= 4 ? Color(rgb: 0x776E65) : Color(rgb: 0xF9F6F2))
            .frame(width: cell, height: cell)
            .background(Game2048View.tileColor(value), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The shop front: the awning over Pip, a cone of mango and strawberry
/// with syrup and a cherry, and Lotl.
private struct ScoopArt: View {
    var body: some View {
        let dark = Theme.palette.isDark
        GeometryReader { geo in
            let size = min(geo.size.height * 0.72, geo.size.width / 2.6)
            let awning = max(10, (geo.size.height * 0.18).rounded())
            ZStack(alignment: .top) {
                ScoopAwning(look: .of(dark: dark), stripeWidth: max(14, awning * 1.1)).equatable()
                    .frame(width: max(0, geo.size.width - 2 * Theme.radiusSm), height: awning)
                HStack(alignment: .bottom, spacing: -size * 0.08) {
                    ScoopCrewView(who: .pip).frame(width: size * 0.8, height: size * 0.96)
                    ScoopTreatView(order: ScoopOrder(base: .cone, scoops: [.mango, .strawberry], toppings: [.syrup, .cherry]), units: 10.4)
                        .frame(width: size * 0.6, height: size)
                    ScoopCrewView(who: .lotl).frame(width: size * 0.8, height: size * 0.96)
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.94, alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

/// Three penguins walking (one under an umbrella) towards the igloo, on ice
/// under a cap of snow.
private struct PenguinArtCard: View {
    var body: some View {
        let dark = Theme.palette.isDark
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let unit = min(w / 9, h / 4.2)
            let groundY = h * 0.7
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: PenguinPalette.sky(dark: dark), startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: dark ? [Color(rgb: 0xA9C6DE), Color(rgb: 0x3F6489)] : [Color(rgb: 0xD6EAF8), Color(rgb: 0x86B3D9)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: h - groundY)
                    .overlay(alignment: .top) {
                        Rectangle().fill(dark ? Color(rgb: 0xE4EEF7) : .white).frame(height: max(4, unit * 0.25))
                    }
                    .offset(y: groundY)
                PenguinPicture(kind: .igloo)
                    .frame(width: unit * 2.6, height: unit * 2.6 * 40 / 48)
                    .offset(x: w * 0.62, y: groundY - unit * 2.6 * 40 / 48)
                ForEach(Array([(0.1, false, 0.0), (0.27, false, 0.0), (0.42, true, 1.3)].enumerated()), id: \.offset) { _, p in
                    PenguinPicture(kind: p.1 ? .skill(.float) : .walk)
                        .frame(width: unit * 1.5, height: unit * 1.5)
                        .offset(x: w * p.0, y: groundY - unit * 1.5 * 26 / 28 - p.2 * unit)
                }
            }
        }
    }
}
