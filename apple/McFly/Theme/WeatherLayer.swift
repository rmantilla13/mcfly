import McFlyKit
import SwiftUI

/// Weather over Ambient's backdrop, under its words: the displays' choice
/// (`AccountWeather`), drawn as the display's saver draws it
/// (display/qml/components/Weather.qml). Snow drifts down swaying, petals blow
/// across turning over, leaves rock down like a pendulum, fireflies wander the
/// lower part of the screen glowing and dimming, in the palette's glow
/// colours, brightened at night. How many is `AccountWeather.count`, the
/// display's and the console's numbers: a few dozen at most.
///
/// One `Canvas` on the backdrop's clock (`maxFps`, 15 as Ambient's backdrop
/// runs): each particle's place is worked out from the time alone, so nothing
/// is kept between frames, and a flake that has fallen out at the bottom comes
/// in again at the top somewhere else. It stops with the scene, and draws
/// nothing with Reduce Motion asked for or in Low Power Mode.
struct WeatherLayer: View {
    let setting: String
    var palette: Palette = Theme.palette
    var maxFps: Double = 15
    var active: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The wall clock when it first showed: times are counted from it.
    @State private var origin = Date.now

    var body: some View {
        let kind = AccountWeather.kind(for: setting)
        GeometryReader { geo in
            if let kind, !reduceMotion, !lowPower, geo.size.width > 0 {
                let scene = WeatherScene(kind: kind, size: geo.size)
                let tones = WeatherTones(palette: palette)
                TimelineView(.animation(minimumInterval: 1 / maxFps, paused: !(active && scenePhase == .active))) { context in
                    let t = context.date.timeIntervalSince(origin)
                    Canvas { ctx, size in scene.draw(in: &ctx, size: size, at: t, tones: tones) }
                }
                // Another kind or size: a new scene (the same seed keeps it calm).
                .id("\(kind) \(Int(geo.size.width))x\(Int(geo.size.height))")
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

/// The palette's glows as the weather wears them: blue, coral, amber, cream
/// (stop 0 to 3, as `Palette.glow`), lifted toward white at night.
struct WeatherTones {
    let snow: Color
    let petals: [Color]
    let leaves: [Color]
    let flies: [Color]

    init(palette: Palette) {
        let g = palette.glow + Array(repeating: palette.glow.last ?? 0xFFFFFF, count: max(0, 4 - palette.glow.count))
        let dark = palette.isDark
        func lift(_ c: Int, _ day: Double, _ night: Double) -> Color { Color(rgb: WeatherTones.mix(c, 0xFFFFFF, dark ? night : day)) }
        // Snow: a cool grey by day, so it shows on the pale canvas; near white at night.
        snow = Color(rgb: dark ? WeatherTones.mix(0xFFFFFF, g[0], 0.1) : WeatherTones.mix(g[0], palette.textMuted, 0.55))
        petals = [lift(g[1], 0.05, 0.4), lift(g[1], 0.3, 0.6), Color(rgb: WeatherTones.mix(g[1], g[3], 0.55))]
        leaves = [g[1], g[2], WeatherTones.mix(g[1], g[2], 0.5), WeatherTones.mix(g[2], g[3], 0.4)].map { lift($0, 0, 0.25) }
        flies = [lift(g[2], 0.1, 0.45), lift(g[3], 0, 0.4)]
    }

    /// `share` of `b` into `a`, 0xRRGGBB.
    static func mix(_ a: Int, _ b: Int, _ share: Double) -> Int {
        func ch(_ v: Int, _ s: Int) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: Int) -> Int { Int((ch(a, s) + (ch(b, s) - ch(a, s)) * share).rounded()) << s }
        return m(16) | m(8) | m(0)
    }
}

/// The particles of one kind for one screen: their sizes, paces and phases,
/// from a seeded generator so a redraw is the same scene.
struct WeatherScene {
    struct Particle {
        var size: Double, alpha: Double, tone: Int
        var duration: Double, phase: Double          // a fall: seconds top to bottom, where in it at t = 0
        var drift: Double, sway: Double, swayRate: Double, swayPhase: Double
        var spin: Double, spinFrom: Double, tilt: Double
        var flipRate: Double, flipPhase: Double
        // Fireflies: where they wander and glow.
        var cx: Double, cy: Double, ax: Double, ay: Double, wx: Double, wy: Double, px: Double, py: Double
        var glowRate: Double, glowPhase: Double
        var seed: UInt64
    }

    let kind: String
    let particles: [Particle]

    init(kind: String, size: CGSize) {
        self.kind = kind
        var rng = SplitMix(seed: 0x5EA50)
        let w = Double(size.width), h = Double(size.height)
        // Points, not the display's pixels: a phone's 400 is already full size.
        let u = max(1, min(1.8, min(w, h) / 600))
        let wind: Double = rng.next() < 0.5 ? -1 : 1
        let n = AccountWeather.count(kind, width: w, height: h)
        particles = (0..<n).map { i in
            func r(_ lo: Double, _ hi: Double) -> Double { lo + rng.next() * (hi - lo) }
            var p = Particle(size: 8, alpha: 1, tone: 0, duration: 20, phase: r(0, 1), drift: 0, sway: 0,
                             swayRate: r(1.2, 2.6), swayPhase: r(0, 6.3), spin: 0, spinFrom: r(0, 360), tilt: 0,
                             flipRate: r(1.6, 3.6), flipPhase: r(0, 6.3), cx: 0, cy: 0, ax: 0, ay: 0, wx: 0, wy: 0,
                             px: r(0, 6.3), py: r(0, 6.3), glowRate: r(0.9, 2.0), glowPhase: r(0, 6.3), seed: UInt64(i) &* 0x9E3779B97F4A7C15)
            switch kind {
            case "snow":
                let z = r(0, 1)                               // nearer: bigger, faster, brighter
                p.size = (4 + z * 8) * u
                p.alpha = 0.45 + z * 0.5
                p.duration = 24 - z * 12
                p.sway = (4 + z * 16) * u
                p.drift = wind * r(0, 6) / 100 * w
            case "petals":
                p.size = r(24, 38) * u
                p.alpha = r(0.8, 0.95)
                p.tone = i % 3
                p.duration = r(18, 28)
                p.sway = r(20, 50) * u
                p.spin = r(-90, 90)
                p.drift = wind * r(20, 45) / 100 * w
            case "leaves":
                p.size = r(36, 56) * u
                p.alpha = r(0.85, 0.97)
                p.tone = i % 4
                p.duration = r(14, 22)
                p.sway = r(36, 90) * u
                p.tilt = r(25, 60)
                p.drift = wind * r(5, 20) / 100 * w
            default:                                          // fireflies, over most of the height: a phone's cards fill its lower half
                p.size = r(36, 60) * u
                p.tone = i % 2
                p.cx = r(0.05, 0.95) * w; p.cy = r(0.12, 0.88) * h
                p.ax = r(30, 90) * u; p.ay = r(20, 60) * u
                p.wx = r(0.12, 0.3); p.wy = r(0.15, 0.35)
            }
            return p
        }
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize, at t: Double, tones: WeatherTones) {
        let w = Double(size.width), h = Double(size.height)
        for p in particles {
            var c = ctx
            if kind == "fireflies" {
                let glow = max(0, sin(t * p.glowRate + p.glowPhase))
                let x = p.cx + p.ax * sin(t * p.wx + p.px) + p.ax * 0.4 * sin(t * p.wx * 2.3 + p.py)
                let y = p.cy + p.ay * sin(t * p.wy + p.py)
                let s = p.size * (0.6 + 0.4 * glow)
                c.opacity = 0.08 + 0.92 * glow * glow
                let tone = tones.flies[p.tone % 2]
                let rect = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
                c.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(stops: [.init(color: .white.opacity(0.9), location: 0), .init(color: tone, location: 0.16),
                                     .init(color: tone.opacity(0.3), location: 0.4), .init(color: tone.opacity(0), location: 1)]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: s / 2))
                continue
            }
            // Where in its fall: each fall comes in again at the top, somewhere
            // else across (a hash of the particle and which fall it is).
            let run = t / p.duration + p.phase
            let fall = floor(run)
            let progress = run - fall
            let across = Self.unit(p.seed ^ UInt64(bitPattern: Int64(fall))) * 1.2 - 0.1
            let swing = sin(t * p.swayRate + p.swayPhase)
            let x = across * w + p.drift * progress + p.sway * swing
            let y = -0.14 * h + progress * 1.28 * h
            c.opacity = p.alpha
            c.translateBy(x: x, y: y)
            switch kind {
            case "snow":
                let r = p.size / 2
                c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: p.size, height: p.size)), with: .radialGradient(
                    Gradient(stops: [.init(color: tones.snow, location: 0), .init(color: tones.snow, location: 0.55),
                                     .init(color: tones.snow.opacity(0), location: 1)]),
                    center: .zero, startRadius: 0, endRadius: r))
            case "petals":
                c.rotate(by: .degrees(p.spinFrom + p.spin * t))
                c.scaleBy(x: 1, y: cos(t * p.flipRate + p.flipPhase))      // turning over
                let tone = tones.petals[p.tone % 3]
                let s = CGSize(width: p.size, height: p.size * 0.82)
                c.fill(Self.petal(s), with: .linearGradient(Gradient(colors: [tone.opacity(0.75), tone]),
                                                            startPoint: CGPoint(x: -s.width / 2, y: -s.height / 2),
                                                            endPoint: CGPoint(x: s.width / 2, y: s.height / 2)))
            default:                                                      // a leaf rocks with its swing
                c.rotate(by: .degrees(p.spinFrom + p.tilt * swing))
                c.scaleBy(x: 1, y: cos(t * p.flipRate + p.flipPhase))
                let tone = tones.leaves[p.tone % 4]
                let s = CGSize(width: p.size, height: p.size * 0.56)
                c.fill(Self.leaf(s), with: .linearGradient(Gradient(colors: [tone, tone.opacity(0.8)]),
                                                           startPoint: CGPoint(x: 0, y: -s.height / 2), endPoint: CGPoint(x: 0, y: s.height / 2)))
                var rib = Path()
                rib.move(to: CGPoint(x: -0.44 * s.width, y: 0))
                rib.addLine(to: CGPoint(x: 0.44 * s.width, y: 0))
                c.stroke(rib, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: max(1, s.height * 0.07), lineCap: .round))
            }
        }
    }

    /// A cherry petal centred on the origin: a rounded teardrop, its point
    /// where it met the flower, a notch in its round end.
    static func petal(_ s: CGSize) -> Path {
        let w = s.width, h = s.height
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (x - 0.5) * w, y: (y - 0.5) * h) }
        var p = Path()
        p.move(to: pt(0.02, 0.5))
        p.addCurve(to: pt(0.98, 0.38), control1: pt(0.25, -0.05), control2: pt(0.85, -0.05))
        p.addLine(to: pt(0.84, 0.5))
        p.addLine(to: pt(0.98, 0.62))
        p.addCurve(to: pt(0.02, 0.5), control1: pt(0.85, 1.05), control2: pt(0.25, 1.05))
        p.closeSubpath()
        return p
    }

    /// A leaf centred on the origin: pointed at both ends.
    static func leaf(_ s: CGSize) -> Path {
        let w = s.width, h = s.height
        var p = Path()
        p.move(to: CGPoint(x: -0.48 * w, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0.48 * w, y: 0), control: CGPoint(x: -0.05 * w, y: -0.85 * h))
        p.addQuadCurve(to: CGPoint(x: -0.48 * w, y: 0), control: CGPoint(x: 0.05 * w, y: 0.85 * h))
        p.closeSubpath()
        return p
    }

    /// 0..<1 from a 64-bit value (SplitMix's finaliser).
    static func unit(_ x: UInt64) -> Double {
        var z = x &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// A small seeded generator, so a scene redraws the same.
    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            return WeatherScene.unit(state)
        }
    }
}
