import McFlyKit
import SwiftUI

/// A sky for the ambient screen: the display's Backdrop
/// (display/qml/components/Backdrop.qml), one of five moving backdrops in the
/// glow colours, each a Metal shader of its own (Backdrop.metal, from
/// display/shaders/<style>.frag), laid on the canvas by an OKLab mix so it is
/// a pastel wash on the warm canvas by day and a glow over the near-black one
/// at night. Decorative; what goes on top reads in the inks it hands its
/// content (`SkyColors`), as GradientTile does.
///
///     Backdrop(style: "arc", colors: Theme.palette.glow, dark: night) { sky in
///         Text("9:41").foregroundStyle(sky.ink)
///     }
///
/// Arc: an aurora band curving across the sky, bright along its lower edge,
/// rays running up through it. Ribbons: three thin curtains edge-on, folding.
/// Dawn: a horizon gradient, a low sun glow, haze. Silk: two sheets of satin
/// folding over each other. Pillars: columns of light standing up from the
/// bottom edge. (Mesh, the savers' other choice, is GradientTile.)
///
/// Cost is simplex noise lookups per pixel, from none (silk) to nine
/// (ribbons), so each runs at a fraction of the view's size that suits it (a
/// soft picture loses nothing scaled up) and moves at `maxFps`, the display
/// saver's pace. Like AuroraGlow, its clock only runs while it can be seen,
/// the app is in front and Reduce Motion is off, and it resumes where it
/// stopped; it starts from the wall clock, within the hour, so each showing
/// opens on a different sky and the time stays small enough for the shader's
/// 32-bit floats to step evenly.
///
/// Night comes in as one dusk, on the app's own palette ease (Appearance's
/// `withAnimation`, 1.2 s): the canvas deepens, the light turns from wash to
/// glow and the stops glide to the night glow (in OKLab, as the display's
/// palette fade does), all carried along the animation as one vector; the ink
/// flips from dark to light quickly in the middle of it, where the canvas is
/// mid-tone, so text never sits grey on grey (the display's Backdrop does the
/// same). Outside an animation all of it changes at once.
struct Backdrop<Content: View>: View, Animatable {
    /// arc | ribbons | dawn | silk | pillars (the arc for a name this build doesn't know).
    var style: String
    var dayCanvas: Int
    var nightCanvas: Int
    /// Scales the style's own strength.
    var brightness: Double
    var speed: Double
    /// Motion updates per second.
    var maxFps: Double
    /// A different sky.
    var seed: Double
    /// False while its screen is covered.
    var active: Bool
    var content: (SkyColors) -> Content

    /// The dusk and the stops, as drawn: what SwiftUI carries along an animation.
    private var shown: SkyVector
    var animatableData: SkyVector {
        get { shown }
        set { shown = newValue }
    }

    /// - Parameters:
    ///   - colors: the four glow stops, 0xRRGGBB.
    ///   - dark: the night look, a deep canvas and the light a glow rather than a wash.
    ///   - nightCanvas: the display's: its dark-mode canvas when the system is dark, else the night mood's.
    init(style: String, colors: [Int], dark: Bool,
         dayCanvas: Int = Palette.day.background,
         nightCanvas: Int = Appearance.shared.systemDark ? Palette.dark.background : Palette.night.background,
         brightness: Double = 1, speed: Double = 1, maxFps: Double = 10, seed: Double = 0, active: Bool = true,
         @ViewBuilder content: @escaping (SkyColors) -> Content) {
        self.style = style
        self.dayCanvas = dayCanvas
        self.nightCanvas = nightCanvas
        self.brightness = brightness
        self.speed = speed
        self.maxFps = maxFps
        self.seed = seed
        self.active = active
        self.content = content
        shown = SkyVector(darkness: dark ? 1 : 0, colors: colors)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var onScreen = false
    /// The wall clock's seconds into the hour when it first showed.
    @State private var origin = Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600)
    /// Seconds run before the current run, and when that began.
    @State private var banked: TimeInterval = 0
    @State private var runStart: Date?

    private var playing: Bool { active && onScreen && !reduceMotion && scenePhase == .active }

    var body: some View {
        let look = Sky.look(style)
        let dk = min(max(shown.darkness, 0), 1)
        let sky = SkyColors(darkness: dk)
        // What the shader is fed, worked out once a frame rather than once a pixel.
        let canvas = Oklab.mix(Oklab.lab(dayCanvas), Oklab.lab(nightCanvas), dk)
        let strength = min(max((look.strength.day + (look.strength.night - look.strength.day) * dk) * brightness, 0), 1)
        let stops = AuroraGlow.unwrap(shown.stops.map(Oklab.lch)).flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        let shader = ShaderFunction(library: .default, name: look.shader)
        content(sky)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { geo in
                    let full = geo.size
                    // Whole pixels: a partly covered one would fringe the edges once scaled up.
                    let pixels = max(displayScale, 1)
                    let small = CGSize(width: max(1, (full.width * look.resolution * pixels).rounded(.up)) / pixels,
                                       height: max(1, (full.height * look.resolution * pixels).rounded(.up)) / pixels)
                    TimelineView(.animation(minimumInterval: maxFps > 0 ? 1 / maxFps : nil, paused: !playing)) { context in
                        let time = (origin + seconds(at: context.date)) * speed + seed * 37
                        Rectangle()
                            .fill(.white)
                            .frame(width: small.width, height: small.height)
                            .colorEffect(shader(
                                .float2(small), .float(time), .float(strength), .float(seed), .float(pixels),
                                .float3(canvas.x, canvas.y, canvas.z), .floatArray(stops)))
                            // Rendered small, then scaled up: the skies have no hard edges.
                            .drawingGroup()
                            .scaleEffect(x: full.width / small.width, y: full.height / small.height, anchor: .topLeading)
                    }
                    .frame(width: full.width, height: full.height, alignment: .topLeading)
                }
                .accessibilityHidden(true)
            }
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
            .onChange(of: playing) { _, playing in
                if playing {
                    runStart = .now
                    return
                }
                if let runStart { banked += max(0, Date.now.timeIntervalSince(runStart)) }
                runStart = nil
            }
    }

    /// Seconds the clock has run by `date`.
    private func seconds(at date: Date) -> TimeInterval {
        banked + (runStart.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

/// Each style's look: its shader, its strength by day and at night (how much
/// of the light lands on the canvas) and the share of the view's size it runs
/// at. Backdrop.qml's table.
private enum Sky {
    struct Look {
        let shader: String
        let strength: (day: Double, night: Double)
        let resolution: Double
    }

    static let looks: [String: Look] = [
        "arc":     Look(shader: "backdropArc", strength: (0.70, 0.95), resolution: 0.5),
        "ribbons": Look(shader: "backdropRibbons", strength: (0.90, 1.00), resolution: 0.4),
        "dawn":    Look(shader: "backdropDawn", strength: (0.50, 0.90), resolution: 0.5),
        "silk":    Look(shader: "backdropSilk", strength: (0.50, 0.85), resolution: 0.5),
        "pillars": Look(shader: "backdropPillars", strength: (0.85, 0.95), resolution: 0.5),
    ]

    /// The style's look, or the arc's for a name this build doesn't know.
    static func look(_ style: String) -> Look { looks[style] ?? looks["arc"]! }
}

/// What a sky hands the content on it: how far into the night it is, and the
/// inks that read on it (the display's Backdrop `ink` and `inkMuted`).
struct SkyColors: BackdropInks {
    /// 0 by day, 1 at night.
    let darkness: Double
    /// Titles, numbers.
    let ink: Color
    /// Secondary text.
    let inkMuted: Color

    init(darkness: Double) {
        self.darkness = darkness
        // The ink turns from dark to light quickly in the middle of the dusk,
        // where the canvas is mid-tone, so text never sits grey on grey for long.
        let x = min(max((darkness - 0.44) / 0.12, 0), 1)
        let inkDk = x * x * (3 - 2 * x)
        ink = Self.mix([0x1D / 255, 0x1B / 255, 0x24 / 255, 1], [1, 1, 1, 0.92], inkDk)
        inkMuted = Self.mix([0x4A / 255, 0x45 / 255, 0x55 / 255, 1], [1, 1, 1, 0.62], inkDk)
    }

    /// sRGB with alpha, blended straight (Backdrop.qml's `_mixc`).
    private static func mix(_ a: SIMD4<Double>, _ b: SIMD4<Double>, _ t: Double) -> Color {
        let c = a + (b - a) * t
        return Color(.sRGB, red: c.x, green: c.y, blue: c.z, opacity: c.w)
    }
}

/// What reads on a backdrop: the mesh's inks (`TileColors`) or a sky's
/// (`SkyColors`), so a composition can sit on either.
protocol BackdropInks {
    var ink: Color { get }
    var inkMuted: Color { get }
}

extension TileColors: BackdropInks {}

/// The dusk (0 by day, 1 at night) and the four stops in OKLab, as one vector
/// SwiftUI can interpolate: a palette change then glides in OKLab, as the
/// display's Theme fades its tokens, and the dusk with it.
struct SkyVector: VectorArithmetic {
    /// The dusk, then L, a, b for each of the four stops.
    private var values: [Double]

    init(darkness: Double, colors: [Int]) {
        var stops = colors.prefix(4).map(Oklab.lab)
        // Fewer than four: the last stands in (the display pads with the accent).
        while stops.count < 4 { stops.append(stops.last ?? Oklab.lab(Palette.day.accent)) }
        values = [darkness] + stops.flatMap { [$0.x, $0.y, $0.z] }
    }

    private init(values: [Double]) { self.values = values }

    var darkness: Double { values[0] }
    var stops: [SIMD3<Double>] { (0..<4).map { SIMD3(values[1 + $0 * 3], values[2 + $0 * 3], values[3 + $0 * 3]) } }

    static var zero: SkyVector { SkyVector(values: Array(repeating: 0, count: 13)) }
    static func + (a: SkyVector, b: SkyVector) -> SkyVector { SkyVector(values: zip(a.values, b.values).map(+)) }
    static func - (a: SkyVector, b: SkyVector) -> SkyVector { SkyVector(values: zip(a.values, b.values).map(-)) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

/// Colour in OKLab, as the display's Theme.oklab has it: a blend in it keeps
/// lightness even and takes hues the short way. (AuroraGlow has the polar form.)
enum Oklab {
    /// 0xRRGGBB (sRGB) in OKLab (L, a, b).
    static func lab(_ rgb: Int) -> SIMD3<Double> {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let r = linear(Double((rgb >> 16) & 0xFF) / 255)
        let g = linear(Double((rgb >> 8) & 0xFF) / 255)
        let b = linear(Double(rgb & 0xFF) / 255)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s]
    }

    /// OKLab to OKLCh: lightness, chroma, hue in radians.
    static func lch(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        [lab.x, hypot(lab.y, lab.z), atan2(lab.z, lab.y)]
    }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        a + (b - a) * t
    }
}
