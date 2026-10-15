import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Design tokens: a dark-friendly canvas with white (or near-black) cards, and
// the glow colors as accents: blue, coral and amber, the same three the Pi's
// voice card and the icon use.
enum Theme {
    static let background = Color(light: 0xF3F2F7, dark: 0x0E0F14)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1A1C24)
    static let sunken = Color(light: 0xE8E7EE, dark: 0x262932)
    static let text = Color(light: 0x16171C, dark: 0xECEDF2)
    static let muted = Color(light: 0x71727A, dark: 0x8E93A1)
    static let divider = Color(light: 0xE1E0E8, dark: 0x2F323C)

    static let blue = Color(rgb: 0x5B7CF5)
    static let coral = Color(rgb: 0xF07F5A)
    static let amber = Color(rgb: 0xF6B94A)
    static let accent = blue
    static let accentSoft = Color(light: 0xE3EAFE, dark: 0x27335A)
    static let up = Color(rgb: 0x3DB37A)
    static let down = Color(rgb: 0xE5604D)
    static let glow: [Color] = [blue, coral, amber, Color(rgb: 0xFBE6B0)]

    static let radius: CGFloat = 22
    static let radiusSm: CGFloat = 14
    /// Space between the screen edge and the content.
    static let page: CGFloat = 20

    static let springy = Animation.spring(response: 0.38, dampingFraction: 0.75)
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

    /// A color that follows light/dark mode on both platforms.
    init(light: Int, dark: Int) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
        #endif
    }

    /// "#RRGGBB" → Color. Agent colors are stored this way so the display and phone match.
    init(hex: String) {
        let value = Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x5B7CF5
        self.init(rgb: value)
    }

    /// Green up, red down, muted flat.
    static func change(_ value: Double?) -> Color {
        guard let value, value != 0 else { return Theme.muted }
        return value > 0 ? Theme.up : Theme.down
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(rgb: Int) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#else
extension NSColor {
    convenience init(rgb: Int) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif

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
