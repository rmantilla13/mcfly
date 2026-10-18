import McFlyKit
import SwiftUI

/// Pieces the games share: who plays and how hard, the score, stars.
enum GameColors {
    /// X and orange discs; O and blue discs (the display's xColor and oColor).
    static let x = Color(rgb: 0xF07F5A)
    static let o = Color(rgb: 0x4F7CF7)
    static func of(_ mark: Mark) -> Color { mark == .x ? x : o }
}

extension Color {
    /// A colour darker or lighter by `factor`, as Qt.darker and Qt.lighter
    /// shade the display's pieces: each channel scaled (and kept in range).
    init(rgb: Int, scaled factor: Double, opacity: Double = 1) {
        func channel(_ shift: Int) -> Double { min(255, Double((rgb >> shift) & 0xFF) * factor) / 255 }
        self.init(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: opacity)
    }
}

/// "2 players | vs McFly", then "Easy | Hard" when McFly plays.
struct OpponentPickers: View {
    let vsComputer: Bool
    let hard: Bool
    let set: (_ vsComputer: Bool, _ hard: Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("Players", selection: Binding(get: { vsComputer }, set: { set($0, hard) })) {
                Text("2 players").tag(false)
                Text("vs McFly").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if vsComputer {
                Picker("Level", selection: Binding(get: { hard }, set: { set(vsComputer, $0) })) {
                    Text("Easy").tag(false)
                    Text("Hard").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 150)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: 560, alignment: .leading)
    }
}

/// You (or X), draws, McFly (or O): three chips.
struct ScoreChips: View {
    let score: Score
    let xName: String
    let oName: String

    var body: some View {
        HStack(spacing: 10) {
            chip(xName, score.x, GameColors.x)
            chip("Draws", score.draws, Theme.muted)
            chip(oName, score.o, GameColors.o)
        }
    }

    private func chip(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(String(value))
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .frame(minWidth: 72, minHeight: 50)
        .padding(.horizontal, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// ★★☆
struct Stars: View {
    let count: Int
    var size: CGFloat = 36

    var body: some View {
        Text(String(repeating: "★", count: count) + String(repeating: "☆", count: max(0, 3 - count)))
            .font(.system(size: size))
            .foregroundStyle(Theme.warning)
            .accessibilityLabel("\(count) of 3 stars")
    }
}

/// A card over a game: solved, closing time, a level's brief.
struct GameCardOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 12, content: content)
            .padding(24)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 440)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.divider, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
            .padding(16)
    }
}

/// A level picker's grid: a tile a level, the chosen one ringed.
struct LevelGrid: View {
    let count: Int
    let current: Int
    let done: (Int) -> Bool
    let stars: (Int) -> Int
    var name: ((Int) -> String)?
    var dot: ((Int) -> Color)?
    let pick: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: name == nil ? 64 : 104), spacing: 10)], spacing: 10) {
                ForEach(0..<count, id: \.self) { i in
                    Button { pick(i) } label: {
                        VStack(spacing: 2) {
                            Text(String(i + 1))
                                .font(.headline)
                                .foregroundStyle(Theme.text)
                            if let name {
                                Text(name(i))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            Text(done(i) ? String(repeating: "★", count: stars(i)) : " ")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.warning)
                        }
                        .frame(maxWidth: .infinity, minHeight: name == nil ? 64 : 76)
                        .background(done(i) ? Theme.accentSoft : Theme.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            if let dot {
                                Circle().fill(dot(i)).frame(width: 8, height: 8).padding(8)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            .stroke(Theme.accent, lineWidth: i == current ? 3 : 0))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Level \(i + 1)\(done(i) ? ", done" : "")")
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// A level picker over a game, with a close button.
struct LevelPicker<Grid: View>: View {
    let title: String
    let summary: String
    let close: () -> Void
    @ViewBuilder let grid: () -> Grid

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Text(summary).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
                GameIconButton(systemImage: "xmark", label: "Close levels", action: close)
            }
            grid()
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }
}

/// The app's pill, at least 48 points tall: the games' buttons are tapped
/// mid-play, so they're a size up from the rest of the app's.
struct GamePillStyle: ButtonStyle {
    var kind: PillButtonStyle.Kind = .prominent

    func makeBody(configuration: Configuration) -> some View {
        PillButtonStyle(kind: kind).makeBody(configuration: configuration)
            .font(.body.weight(.semibold))
            .frame(minHeight: 48)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == GamePillStyle {
    static func gamePill(_ kind: PillButtonStyle.Kind = .prominent) -> GamePillStyle { GamePillStyle(kind: kind) }
}
