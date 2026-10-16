import SwiftUI

/// "Poster glow" behind the highlight tiles and the ambient screen: the
/// display's GradientTile (display/qml/components/GradientTile.qml), drawn by
/// the same shader (GradientTile.metal). A luminous pastel mesh gradient with
/// frosted-glass rings drifting across it, blurred in, under a film grain.
///
///     GradientTile(base: 0x5B7CF5, seed: 2) { tile in
///         Text("Markets").foregroundStyle(tile.ink)
///     }
///
/// The palette comes from one base colour (its hue, two analogous hues and a
/// near-white highlight, pastel by day and deep at night) or from 3–4
/// `colors` mapped the same way. One loop is `period` seconds (0.85–1.15× by
/// seed, so tiles never line up). It only moves while it can be seen, the app
/// is in front and Reduce Motion is off. Given a frame it fills it, content
/// top-leading; in a scroll view it is as tall as its content.
struct GradientTile<Content: View>: View {
    var base: Int = 0x4F7CF7
    var colors: [Int] = []
    /// Night look: deep, dim and slower. Nil follows the palette.
    var dark: Bool?
    var radius: CGFloat = Theme.radius
    var rings = 2
    var ringScale = 1.0
    var ringBias = 0.72
    /// 0 = crisp glass rings, 1 = rings blurred into the gradient.
    var blur = 1.0
    /// Static film grain (0 = off); 70% at night.
    var grain = 0.035
    var seed = 0.0
    var period: Double = 48
    var fps: Double = 30
    /// False while the tile's screen is covered.
    var active = true
    @ViewBuilder var content: (TileColors) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var onScreen = false

    private var playing: Bool { active && onScreen && !reduceMotion && scenePhase == .active }

    var body: some View {
        let isDark = dark ?? Theme.palette.isDark
        let tile = TileColors(base: base, colors: colors, dark: isDark)
        // The shader's own numbers, worked out once per palette rather than per frame.
        let pal = tile.shaderPalette
        let glass = Float(1 - 0.65 * tile.dk)
        let grain = Float(grain * (1 - 0.3 * tile.dk))
        let speed = 2 * Double.pi / (period * (0.85 + 0.30 * Self.wrap(seed * 0.618034 + 0.3))) * (1 - 0.35 * tile.dk)
        let shape = (seed: Float(seed), rings: Float(rings), scale: Float(ringScale), bias: Float(ringBias),
                     soft: Float(blur), dpr: Float(max(displayScale, 1)))

        // The content fills a fixed frame and sizes the tile where there is
        // none (a tile in a scroll view hugs what's on it); the gradient is
        // its background, so it covers whichever that comes to.
        content(tile)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                TimelineView(.animation(minimumInterval: 1 / fps, paused: !playing)) { context in
                    let phase = Float((context.date.timeIntervalSinceReferenceDate * speed)
                        .truncatingRemainder(dividingBy: 2 * .pi)) + shape.seed * 1.7
                    Rectangle()
                        .fill(Color(rgb: base))
                        .visualEffect { content, proxy in
                            content.colorEffect(ShaderLibrary.gradientTile(
                                .float2(proxy.size), .float(phase), .float(shape.seed), .float(shape.rings),
                                .float(shape.scale), .float(shape.bias), .float(glass), .float(grain), .float(shape.soft),
                                .float(shape.dpr), .floatArray(pal)))
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }

    static func wrap(_ x: Double) -> Double { x - x.rounded(.down) }
}

extension GradientTile where Content == EmptyView {
    init(base: Int = 0x4F7CF7, colors: [Int] = [], dark: Bool? = nil, radius: CGFloat = Theme.radius, rings: Int = 2,
         ringScale: Double = 1, seed: Double = 0, period: Double = 48, fps: Double = 30, active: Bool = true) {
        self.init(base: base, colors: colors, dark: dark, radius: radius, rings: rings, ringScale: ringScale, seed: seed,
                  period: period, fps: fps, active: active) { _ in EmptyView() }
    }
}

/// A tile's palette and the inks that read on it, worked out as the
/// display's QML does.
struct TileColors {
    /// 0 by day, 1 at night.
    let dk: Double
    /// Main hue, the two analogous ones, the highlight.
    let fill: [RGB]
    /// Titles and numbers.
    let ink: Color
    /// Secondary text.
    let inkMuted: Color
    /// Fills and icons.
    let strong: Color
    /// A glass card on the tile.
    let glassFill: Color
    let glassStroke: Color

    init(base: Int, colors: [Int] = [], dark: Bool) {
        let dk = dark ? 1.0 : 0.0
        self.dk = dk

        // Source hues: main, analogous +, analogous −, highlight. `nh` is the
        // hue used at night: a narrower spread reads calmer.
        struct Source { var h: Double; var s: Double; var nh: Double? = nil }
        let sources: [Source]
        if colors.count >= 3 {
            var list = colors.prefix(4).map { RGB(rgb: $0).hsl }.map { Source(h: $0.h, s: $0.s) }
            if list.count < 4 { list.append(Source(h: Self.wrap(list[0].h + 0.03), s: list[0].s * 0.7)) }
            sources = list
        } else {
            let b = RGB(rgb: base).hsl
            sources = [Source(h: b.h, s: b.s),
                       Source(h: Self.wrap(b.h + 0.075), s: b.s * 0.95, nh: Self.wrap(b.h + 0.03)),
                       Source(h: Self.wrap(b.h - 0.085), s: b.s * 0.90, nh: Self.wrap(b.h - 0.035)),
                       Source(h: Self.wrap(b.h + 0.03), s: b.s * 0.70, nh: b.h)]
        }
        // Pastel saturation: lively but never neon; greys stay grey.
        func sat(_ s: Double) -> Double { s < 0.08 ? s : min(max(s, 0.38), 0.78) }
        func nh(_ i: Int) -> Double { sources[i].nh ?? sources[i].h }
        let light = [RGB(h: sources[0].h, s: sat(sources[0].s), l: 0.79),
                     RGB(h: sources[1].h, s: sat(sources[1].s), l: 0.83),
                     RGB(h: sources[2].h, s: sat(sources[2].s), l: 0.76),
                     RGB(h: sources[3].h, s: sat(sources[3].s) * 0.8, l: 0.94)]
        let night = [RGB(h: nh(0), s: sat(sources[0].s) * 0.55, l: 0.19),
                     RGB(h: nh(1), s: sat(sources[1].s) * 0.50, l: 0.22),
                     RGB(h: nh(2), s: sat(sources[2].s) * 0.50, l: 0.15),
                     RGB(h: nh(3), s: sat(sources[3].s) * 0.45, l: 0.27)]
        fill = zip(light, night).map { $0.mix($1, dk) }

        let h = sources[0].h, s = sources[0].s
        ink = RGB(h: h, s: min(s, 0.45), l: 0.15).mix(RGB(h: h, s: min(s, 0.25), l: 0.96), dk).color
        inkMuted = RGB(h: h, s: min(s, 0.38), l: 0.26).mix(RGB(h: h, s: min(s, 0.25), l: 0.87), dk).color
        let strongSat = min(max(s, 0.40), 0.62)
        strong = RGB(h: h, s: strongSat, l: 0.42).mix(RGB(h: h, s: strongSat, l: 0.72), dk).color
        glassFill = Color.white.opacity(0.50 - 0.42 * dk)
        glassStroke = Color.white.opacity(0.85 - 0.65 * dk)
    }

    /// The four colours, the rim's colour, then the rim's strength.
    var shaderPalette: [Float] {
        fill.flatMap { [Float($0.r), Float($0.g), Float($0.b)] } + [1, 1, 1, Float(0.80 - 0.35 * dk)]
    }

    static func wrap(_ x: Double) -> Double { x - x.rounded(.down) }
}

/// sRGB, 0...1, with the HSL conversions the display's tiles use (Qt's).
struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(rgb: Int) {
        self.init(r: Double((rgb >> 16) & 0xFF) / 255, g: Double((rgb >> 8) & 0xFF) / 255, b: Double(rgb & 0xFF) / 255)
    }

    /// Hue 0...1 (wrapped), saturation and lightness 0...1.
    init(h: Double, s: Double, l: Double) {
        guard s > 0 else { self.init(r: l, g: l, b: l); return }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t: Double) -> Double {
            var t = t - t.rounded(.down)
            if t < 0 { t += 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        self.init(r: channel(h + 1.0 / 3), g: channel(h), b: channel(h - 1.0 / 3))
    }

    /// A grey has hue 0 and saturation 0, as Qt's −1 hue is read by the tile.
    var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let l = (maxC + minC) / 2
        let d = maxC - minC
        guard d > 1e-9 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        if maxC == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if maxC == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}
