import SwiftUI

/// The McFly mark: the flux capacitor's Y, three tubes in blue, coral and
/// amber running in to a white core, on a dark tile. Fixed colours, so the
/// logo doesn't follow the time of day. The same numbers as the display's
/// FluxMark.qml, the console's mark and scripts/flux_mark.py (the app icon
/// and the launch mark).
struct FluxMark: View {
    private static let arms: [(dx: Double, dy: Double, outer: Int, inner: Int)] = [
        (-0.8660254, -0.5, 0x5B7CF5, 0xB5C4FA),
        (0.8660254, -0.5, 0xF07F5A, 0xF8C5B5),
        (0, 1, 0xF6B94A, 0xFBE0AE),
    ]

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let tile = Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerRadius: s * 0.26, style: .continuous)
            context.clip(to: tile)
            context.fill(tile, with: .linearGradient(Gradient(colors: [Color(rgb: 0x30323A), Color(rgb: 0x121317)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: s)))
            let center = CGPoint(x: s / 2, y: s * 0.53)
            for arm in Self.arms {
                let inner = CGPoint(x: center.x + arm.dx * s * 0.14, y: center.y + arm.dy * s * 0.14)
                let outer = CGPoint(x: center.x + arm.dx * s * 0.36, y: center.y + arm.dy * s * 0.36)
                var tube = Path()
                tube.move(to: inner)
                tube.addLine(to: outer)
                var layer = context
                layer.addFilter(.shadow(color: Color(rgb: arm.outer), radius: s * 0.06))
                layer.stroke(tube,
                             with: .linearGradient(Gradient(colors: [Color(rgb: arm.outer), Color(rgb: arm.inner)]),
                                                   startPoint: outer, endPoint: inner),
                             style: StrokeStyle(lineWidth: s * 0.12, lineCap: .round))
            }
            var core = context
            core.addFilter(.shadow(color: .white, radius: s * 0.08))
            let r = s * 0.075
            core.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// "McFly" in the logo's face, Exo 2 Black Italic (Theme/Fonts, SIL OFL),
/// as the boot clip, the display and the console set it.
struct Wordmark: View {
    var size: CGFloat

    var body: some View {
        Text(verbatim: "McFly")
            .font(.custom("Exo2-BlackItalic", fixedSize: size))
    }
}
