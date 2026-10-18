import McFlyKit
import SwiftUI

/// The display's Games tab (display/qml/screens/GamesScreen.qml): a card per
/// game, and a tapped one full screen, with an X to close it and (i) for how
/// to play and where it comes from. Same Game and Maroon in Trouble, the Qt
/// demos, are the display's only.
///
/// On the Mac a game opens in a sheet over the window, as the voice screen
/// does; Esc closes it.
struct GamesView: View {
    @State private var open: GameID? = GameLaunch.game
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Puzzles and games for a break")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(GameID.allCases) { game in
                        Button { open = game } label: { GameCard(game: game) }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("\(game.title), \(game.players). \(game.tagline)")
                    }
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Games")
        #if os(iOS)
        .fullScreenCover(item: $open) { game in
            GameScreen(game: game)
        }
        #else
        .sheet(item: $open) { game in
            GameScreen(game: game)
                .frame(minWidth: 860, idealWidth: 1000, minHeight: 640, idealHeight: 760)
        }
        #endif
    }
}

/// A game's card: its picture, name, players and one line about it.
private struct GameCard: View {
    let game: GameID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GameArt(game: game)
                .frame(height: 118)
                .frame(maxWidth: .infinity)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                .padding(.bottom, 4)
            Text(game.title)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(game.tagline)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(2, reservesSpace: true)
            Tag(text: game.players, color: Theme.accent)
        }
        .card(padding: 12, radius: Theme.radius)
    }
}

/// One game, full screen: the game as large as fits, and an X and an (i).
/// Upright (an iPhone, an iPad held tall) the name, (i) and X run along the
/// top; wide (an iPad on its side, the Mac) the X and (i) stand down the
/// right, as on the display. How to play covers the game while it's open,
/// and a game against the clock waits under it (and while the app is away).
struct GameScreen: View {
    let game: GameID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var howTo = false

    private var covered: Bool { howTo || scenePhase != .active }

    var body: some View {
        GeometryReader { geo in
            let upright = geo.size.height >= geo.size.width
            let gap: CGFloat = upright ? 12 : 16
            Group {
                if upright {
                    VStack(spacing: gap) {
                        HStack(spacing: 10) {
                            Text(game.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            infoButton
                            closeButton
                        }
                        stage
                    }
                } else {
                    HStack(alignment: .top, spacing: gap) {
                        stage
                        VStack(spacing: gap) {
                            closeButton
                            infoButton
                        }
                    }
                }
            }
            .padding(.horizontal, upright ? 16 : Theme.page)
            .padding(.top, upright ? 8 : Theme.page)
            .padding(.bottom, upright ? 8 : Theme.page)
        }
        .background(Theme.background.ignoresSafeArea())
        .followsAppearance()
        #if os(iOS)
        .persistentSystemOverlays(.hidden)
        #endif
    }

    private var stage: some View {
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(!howTo)
            if howTo {
                HowToCard(game: game) { withAnimation(.easeOut(duration: 0.2)) { howTo = false } }
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch game {
        case .trafficJam: TrafficJamView()
        case .ticTacToe: TicTacToeView()
        case .fourInARow: FourInARowView()
        case .game2048: Game2048View()
        case .scoopShop: ScoopShopView(covered: covered)
        case .penguinMarch: PenguinMarchView(covered: covered)
        case .colorByNumber: ColorByNumberView()
        }
    }

    private var closeButton: some View {
        GameIconButton(systemImage: "xmark", label: "Close \(game.title)") { dismiss() }
            .keyboardShortcut(.cancelAction)
    }

    private var infoButton: some View {
        GameIconButton(systemImage: "info", label: howTo ? "Hide how to play" : "How to play", active: howTo) {
            withAnimation(.easeOut(duration: 0.2)) { howTo.toggle() }
        }
    }
}

/// The game's name, how to play it and where it comes from, over the game.
private struct HowToCard: View {
    let game: GameID
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(game.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(game.howTo)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(game.credit)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let licence = game.licence {
                    DisclosureGroup("Licence") {
                        Text(licence)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .font(.footnote)
                    .tint(Theme.accent)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        // The game doesn't peek out past the card's rounded corners.
        .background(Theme.background)
        .contentShape(Rectangle())
        // A tap closes it; the licence's disclosure takes its own taps first.
        .onTapGesture(perform: close)
    }
}

/// A round button: the X, the (i), a game's own controls. 48 points across,
/// past Apple's 44.
struct GameIconButton: View {
    let systemImage: String
    let label: String
    var active = false
    var prominent = false
    var size: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(prominent ? Theme.accentInk : active ? Theme.accent : Theme.text)
                .frame(width: size, height: size)
                .background(prominent ? Theme.accent : active ? Theme.accentSoft : Theme.surface, in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// `-McFlyGame <name>` (screenshots): opens on the Games list with that
/// game open (`list` for the list alone). Names: traffic, tictactoe,
/// fourinarow, 2048, scoops, penguins, colors. `-McFlyGameClock` slows the
/// clock; `-McFlyColorPicture <id>` opens Color by Number on that picture.
enum GameLaunch {
    static let requested: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-McFlyGame"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1].lowercased()
    }()

    /// `-McFlyGameClock <factor>`: a game against the clock runs this much
    /// slower or faster, for checking one by hand (0.1 is a tenth of the speed).
    static let clock: Double = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-McFlyGameClock"), i + 1 < arguments.count,
              let factor = Double(arguments[i + 1]), factor > 0 else { return 1 }
        return factor
    }()

    static let game: GameID? = {
        switch requested {
        case "traffic": return .trafficJam
        case "tictactoe": return .ticTacToe
        case "fourinarow": return .fourInARow
        case "2048": return .game2048
        case "scoops": return .scoopShop
        case "penguins": return .penguinMarch
        case "colors": return .colorByNumber
        default: return nil
        }
    }()

    /// `-McFlyColorPicture <id>` (heart, pip…): Color by Number opens painting it.
    static let colorPicture: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-McFlyColorPicture"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1].lowercased()
    }()
}
