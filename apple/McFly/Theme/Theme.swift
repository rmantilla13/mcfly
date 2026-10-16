import McFlyKit
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Design tokens: the display's (display/qml/Theme.qml). Four time-of-day
// palettes (warm morning, clear day, violet evening, dim night) and a black
// one for dark mode, all from the same names, so every screen
// shifts together as the day goes on. `Appearance` picks the palette.
enum Theme {
    static var palette: Palette { Appearance.shared.palette }

    static var background: Color { Color(rgb: palette.background) }
    static var surface: Color { Color(rgb: palette.surface) }
    static var surfaceAlt: Color { Color(rgb: palette.surfaceAlt) }
    static var sunken: Color { Color(rgb: palette.sunken) }
    static var text: Color { Color(rgb: palette.text) }
    static var muted: Color { Color(rgb: palette.textMuted) }
    static var divider: Color { Color(rgb: palette.divider) }
    static var accent: Color { Color(rgb: palette.accent) }
    static var accentSoft: Color { Color(rgb: palette.accentSoft) }
    /// Problems: a blocked project, a revoked key.
    static var danger: Color { Color(rgb: palette.danger) }
    /// "Waiting" text on an amber tint.
    static var warningInk: Color { Color(rgb: palette.warningInk) }
    /// The voice glow's colours in this palette: blue, coral, amber, cream by day.
    static var glow: [Color] { palette.glow.map { Color(rgb: $0) } }

    static let accentInk = Color.white
    static let success = Color(rgb: 0x3DB37A)
    static let warning = Color(rgb: 0xF2A93B)
    // The brand's own hues, the same in every palette: the icon's, the seed agents'.
    static let blue = Color(rgb: 0x5B7CF5)
    static let coral = Color(rgb: 0xF07F5A)
    static let amber = Color(rgb: 0xF6B94A)
    static let up = success
    static let down = Color(rgb: 0xE5604D)
    /// A market up or down: saturated, as on the display (Theme.qml gain/loss),
    /// brighter on the dark palettes.
    static var gain: Color { Color(rgb: palette.isDark ? 0x32E06E : 0x00B54A) }
    static var loss: Color { Color(rgb: palette.isDark ? 0xFF4D4D : 0xF2262B) }

    static let radius: CGFloat = 24
    static let radiusSm: CGFloat = 16
    /// Space between the screen edge and the content.
    static let page: CGFloat = 20

    static let springy = Animation.spring(response: 0.38, dampingFraction: 0.75)
}

/// One set of the display's tokens, as 0xRRGGBB.
struct Palette: Equatable, Sendable {
    var background: Int, surface: Int, surfaceAlt: Int, sunken: Int
    var text: Int, textMuted: Int, divider: Int
    var accent: Int, accentSoft: Int, danger: Int, warningInk: Int
    /// Blue, coral, amber, cream: the glow and the gradient tiles.
    var glow: [Int]
    var isDark: Bool

    static let morning = Palette(background: 0xF6F0E9, surface: 0xFFFFFF, surfaceAlt: 0xF6F0E9, sunken: 0xEEE5DA,
                                 text: 0x221C19, textMuted: 0x7D736C, divider: 0xE9DFD3,
                                 accent: 0xE2725B, accentSoft: 0xFBE4DC, danger: 0xA8301F, warningInk: 0x9A5B00,
                                 glow: [0xF6B94A, 0xF07F5A, 0xF2A7C3, 0xFBE6B0], isDark: false)
    static let day = Palette(background: 0xF1EFEB, surface: 0xFFFFFF, surfaceAlt: 0xF1EFEB, sunken: 0xE9E6E0,
                             text: 0x1C1C1F, textMuted: 0x77767B, divider: 0xE4E0D9,
                             accent: 0x4F7CF7, accentSoft: 0xE3EAFE, danger: 0xB23224, warningInk: 0x9A5B00,
                             glow: [0x5B7CF5, 0xF07F5A, 0xF6B94A, 0xFBE6B0], isDark: false)
    static let evening = Palette(background: 0xEFEDF3, surface: 0xFFFFFF, surfaceAlt: 0xEFEDF3, sunken: 0xE5E1EC,
                                 text: 0x1D1B24, textMuted: 0x76727F, divider: 0xE1DCE8,
                                 accent: 0x7A64E8, accentSoft: 0xECE8FD, danger: 0xB33A47, warningInk: 0x9A5B00,
                                 glow: [0x7A64E8, 0xE86A92, 0xF07F5A, 0xF6B94A], isDark: false)
    static let night = Palette(background: 0x121317, surface: 0x1C1E24, surfaceAlt: 0x262931, sunken: 0x2C2F38,
                               text: 0xECEDEF, textMuted: 0x8F95A1, divider: 0x30333C,
                               accent: 0x8EA2FF, accentSoft: 0x2A3554, danger: 0xFF7B6B, warningInk: 0xF2A93B,
                               glow: [0x3B4FB8, 0x7A64E8, 0xA04E78, 0x6B4A2A], isDark: true)
    /// Dark mode: true black with neutral greys, cards a step up from the canvas, the
    /// day's blue accent, as the display's (Theme.qml). A warm near-black read brown.
    static let dark = Palette(background: 0x000000, surface: 0x161618, surfaceAlt: 0x202023, sunken: 0x2A2A2E,
                              text: 0xF4F4F5, textMuted: 0xA1A1A8, divider: 0x48484E,
                              accent: 0x4F7CF7, accentSoft: 0x243056, danger: 0xF2826B, warningInk: 0xF2A93B,
                              glow: [0x3B5BD4, 0xC45A3A, 0xC48A2E, 0x8A7350], isDark: true)

    static func of(_ mood: Mood) -> Palette {
        switch mood {
        case .morning: return .morning
        case .day: return .day
        case .evening: return .evening
        case .night: return .night
        }
    }
}

/// Which palette is showing: the system's dark mode gets the black one,
/// otherwise the time of day picks (the display's Settings → Dark mode and
/// its moods). Views read it through `Theme`, so a change redraws them.
///
/// `-McFlyMood morning|day|evening|night|dark` (or MCFLY_MOOD, as on the
/// display) pins it, for screenshots.
@Observable
final class Appearance: @unchecked Sendable {
    static let shared = Appearance()

    private(set) var mood: Mood
    private(set) var systemDark: Bool

    var palette: Palette { systemDark ? .dark : .of(mood) }
    var isDark: Bool { palette.isDark }

    @ObservationIgnored private let pinned: (mood: Mood, dark: Bool)?

    /// First read by the root view's first body, on the main thread, with the
    /// scene already there: so the first frame is in the right palette, not a
    /// light one fading to dark.
    private init() {
        let pinned = Self.pinnedFromLaunch()
        self.pinned = pinned
        mood = pinned?.mood ?? Mood(date: .now)
        systemDark = pinned?.dark ?? (Thread.isMainThread && MainActor.assumeIsolated { Self.systemIsDark() })
    }

    /// Re-reads the clock and the system's appearance; the palette eases over
    /// when either changed.
    @MainActor
    func refresh(now: Date = .now) {
        let newMood = pinned?.mood ?? Mood(date: now)
        let newDark = pinned?.dark ?? Self.systemIsDark()
        guard newMood != mood || newDark != systemDark else { return }
        withAnimation(.easeInOut(duration: 1.2)) {
            mood = newMood
            systemDark = newDark
        }
    }

    /// Keeps the palette right while the app is open: on each change of mood,
    /// and within a minute of the system switching between light and dark
    /// (nothing reports that to an app that sets its own colour scheme; coming
    /// back to the front re-reads it at once).
    @MainActor
    func run() async {
        while !Task.isCancelled {
            refresh()
            let wait = min(60, max(1, Mood.nextChange(after: .now).timeIntervalSinceNow + 1))
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    #if canImport(UIKit)
    /// The screen's traits are the system's: the app's forced colour scheme
    /// overrides its windows and its scene, never the screen.
    @MainActor
    private static func systemIsDark() -> Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.traitCollection.userInterfaceStyle == .dark
    }

    #else
    @MainActor
    private static func systemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
    #endif

    private static func pinnedFromLaunch() -> (mood: Mood, dark: Bool)? {
        let arguments = ProcessInfo.processInfo.arguments
        var value = ProcessInfo.processInfo.environment["MCFLY_MOOD"]
        if let i = arguments.firstIndex(of: "-McFlyMood"), i + 1 < arguments.count { value = arguments[i + 1] }
        guard let value = value?.lowercased() else { return nil }
        if value == "dark" { return (.day, true) }
        return Mood(rawValue: value).map { ($0, false) }
    }
}

extension View {
    /// The palette for the whole app: its colour scheme (a night palette is
    /// dark even when the system is light), the accent, and the clock that
    /// moves it along.
    func followsAppearance() -> some View { modifier(AppearanceFollower()) }
}

private struct AppearanceFollower: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let appearance = Appearance.shared
        content
            .preferredColorScheme(appearance.isDark ? .dark : .light)
            .tint(Theme.accent)
            .task { await appearance.run() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { appearance.refresh() }
            }
    }
}

// MARK: Colors

extension Color {
    init(rgb: Int, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: opacity)
    }

    /// "#RRGGBB" → Color. Agent colors are stored this way so the display and phone match.
    init(hex: String) {
        self.init(rgb: Self.rgb(hex: hex))
    }

    static func rgb(hex: String) -> Int {
        Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x5B7CF5
    }

    /// A market's move: green up, red down (the display's gain and loss), muted flat.
    static func change(_ value: Double?) -> Color {
        guard let value, value != 0 else { return Theme.muted }
        return value > 0 ? Theme.gain : Theme.loss
    }
}

/// Colors offered for a new agent (the seed's, plus the glow).
let agentPalette = ["#7A64E8", "#3DB37A", "#E2725B", "#5B7CF5", "#F6B94A", "#5FB3B3", "#E58FB5"]

// MARK: Glow

/// Soft layered glow (blurred circles in an arch): the sign-in hero and the
/// Voice tile. The live voice screen uses `VoiceGlow` instead.
struct GlowView: View {
    var colors: [Color] = Theme.glow
    var opacity: Double = 0.9
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Circle().fill(colors[0]).frame(width: w * 0.75, height: w * 0.75).offset(x: -w * 0.32, y: w * 0.12)
                Circle().fill(colors[1]).frame(width: w * 0.7, height: w * 0.7).offset(x: w * 0.02, y: w * 0.02)
                Circle().fill(colors[2]).frame(width: w * 0.7, height: w * 0.7).offset(x: w * 0.34, y: w * 0.12)
                Ellipse().fill(colors[3]).frame(width: w * 0.9, height: w * 0.35).offset(y: w * 0.32)
            }
            .frame(width: w, height: geo.size.height)
            .scaleEffect(breathe ? 1.05 : 0.97)
            .blur(radius: w * 0.16)
            .opacity(opacity)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// MARK: Cards, pills, tags

struct CardBackground: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 14, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = Theme.radius) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }

    /// The screen canvas behind scroll views.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case prominent, soft, neutral, destructive }
    var kind: Kind = .prominent

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(configuration: configuration, kind: kind)
    }

    private struct PillLabel: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .prominent, .destructive: return .white
            case .soft: return Theme.accent
            case .neutral: return Theme.text
            }
        }

        private var background: Color {
            switch kind {
            case .prominent: return Theme.accent
            case .soft: return Theme.accentSoft
            case .neutral: return Theme.sunken
            case .destructive: return Theme.down
            }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillButtonStyle.Kind = .prominent) -> PillButtonStyle { PillButtonStyle(kind: kind) }
}

/// Slight press-down for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Small uppercase tinted label ("DAILY", "GROK").
struct Tag: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
