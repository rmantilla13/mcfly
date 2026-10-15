import SwiftUI
import os

// Copied from Homestead (App/Homestead/Voice/VoiceGlow.swift). The one change: the
// level meter's lock is `OSAllocatedUnfairLock` rather than `Synchronization.Mutex`,
// which needs iOS 18 / macOS 15; this app runs on iOS 17 / macOS 14.

/// Audio levels shared between audio callbacks (any thread) and the glow (read once per
/// frame), so a fast-changing meter never forces SwiftUI re-renders.
final class LevelMeter: Sendable {
    struct Levels: Sendable {
        var level: Float = 0
        var low: Float = 0
        var mid: Float = 0
        var high: Float = 0
    }

    private struct State: Sendable {
        var levels = Levels()
        var pulseStrength: Float = 0
        var pulseTime: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Continuous input, e.g. the microphone (0...1 each).
    func set(_ levels: Levels) {
        state.withLock { $0.levels = levels }
    }

    /// A short burst, e.g. a word being spoken by text-to-speech; it decays on its own.
    func pulse(_ strength: Float) {
        let now = Date.timeIntervalSinceReferenceDate
        state.withLock {
            $0.pulseStrength = min(1, strength)
            $0.pulseTime = now
        }
    }

    func reset() {
        state.withLock { $0 = State() }
    }

    func read(at time: TimeInterval) -> Levels {
        state.withLock { s in
            let decay = Float(exp(-max(0, time - s.pulseTime) / 0.22))
            let pulse = s.pulseStrength * decay
            var out = s.levels
            out.level = max(out.level, pulse)
            out.low = max(out.low, pulse * 0.9)
            out.mid = max(out.mid, pulse)
            out.high = max(out.high, pulse * 0.7)
            return out
        }
    }
}

extension LevelMeter {
    /// A gentle, steady level for decorative glows (the Ask tile), so they idle with life.
    static let ambient: LevelMeter = {
        let meter = LevelMeter()
        meter.set(.init(level: 0.5, low: 0.45, mid: 0.55, high: 0.4))
        return meter
    }()
}

/// A native recreation of libraries.dev's voice-glow (`VoiceBeam`, "colorful"): soft colour
/// lobes rise from the bottom of a dark host with the voice, in front of them a layered band of
/// light bends up into a wide dome, and a thin spectrum line runs along the rounded bottom edge.
/// While a reply is prepared, everything gathers into one lit beam that travels side to side.
/// Decorative only; pair it with a text status.
struct VoiceGlow: View {
    enum Kind {
        /// The bottom of a full voice screen (voice-glow's `mobile` host).
        case screen
        /// A chat-input-sized host (voice-glow's `default`).
        case input
    }

    let meter: LevelMeter
    var processing = false
    var kind: Kind = .screen
    /// Corner radius of the host, so the edge line and corner light follow its shape.
    var cornerRadius: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var smoother = VoiceGlowSmoother()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let state = smoother.update(meter.read(at: time), processing: processing, time: time)
                VoiceGlowRenderer.draw(in: &context, size: size, time: time, state: state, kind: kind,
                                       cornerRadius: cornerRadius, motion: reduceMotion ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fast attack, slower release, and an eased blend into the processing beam.
final class VoiceGlowSmoother {
    struct State {
        var level: Float = 0, low: Float = 0, mid: Float = 0, high: Float = 0
        var processing: Float = 0
    }

    private var state = State()
    private var lastTime: TimeInterval = 0

    func update(_ input: LevelMeter.Levels, processing: Bool, time: TimeInterval) -> State {
        let dt = Float(lastTime == 0 ? 1.0 / 60 : min(0.1, time - lastTime))
        lastTime = time
        func follow(_ current: Float, _ target: Float) -> Float {
            let rate: Float = target > current ? 14 : 3.2   // attack, release (per second)
            return current + (target - current) * min(1, rate * dt)
        }
        state.level = follow(state.level, input.level)
        state.low = follow(state.low, input.low)
        state.mid = follow(state.mid, input.mid)
        state.high = follow(state.high, input.high)
        state.processing += ((processing ? 1 : 0) - state.processing) * min(1, 2.6 * dt)
        return state
    }
}

/// The drawing, kept separate from the view so it can be rendered at fixed levels for tuning.
///
/// Two parts, as in voice-glow: seven soft colour lobes that rise with the voice and flow slowly
/// sideways, and in front of them the band, a layered strip of light (below, mid, core, above)
/// along the host's bottom edge that bends up into a wide dome as the voice gets louder.
enum VoiceGlowRenderer {
    /// The "colorful" palette, in the order the hue drifts: magenta, violet, blue, teal, green,
    /// amber, coral.
    static let palette: [SIMD3<Double>] = [
        SIMD3(0.86, 0.28, 0.70), SIMD3(0.56, 0.34, 0.90), SIMD3(0.26, 0.50, 0.96),
        SIMD3(0.14, 0.76, 0.76), SIMD3(0.30, 0.76, 0.40), SIMD3(0.96, 0.66, 0.24),
        SIMD3(0.96, 0.38, 0.38),
    ]

    /// Sizes, in units of `unit`: the host's width for a voice screen, its height for an input.
    private struct Tuning {
        var unit: CGFloat
        var restReach: CGFloat, reach: CGFloat     // how high the lobes rise
        var restBend: CGFloat, bend: CGFloat       // how high the band's crest bends
        var spread: CGFloat                        // the dome's half width, as a fraction of the width
        var lobeWidth: CGFloat, lobeBlur: CGFloat
        var bandWidth: CGFloat, bandBlur: CGFloat

        init(kind: VoiceGlow.Kind, size: CGSize) {
            switch kind {
            case .screen:
                self.init(unit: size.width, restReach: 0.1, reach: 0.56, restBend: 0.012, bend: 0.115, spread: 0.5,
                          lobeWidth: 0.24, lobeBlur: 0.04, bandWidth: 0.04, bandBlur: 0.016)
            case .input:
                self.init(unit: size.height, restReach: 0.22, reach: 0.55, restBend: 0.03, bend: 0.36, spread: 0.36,
                          lobeWidth: 0.9, lobeBlur: 0.1, bandWidth: 0.07, bandBlur: 0.03)
            }
        }

        private init(unit: CGFloat, restReach: CGFloat, reach: CGFloat, restBend: CGFloat, bend: CGFloat, spread: CGFloat,
                     lobeWidth: CGFloat, lobeBlur: CGFloat, bandWidth: CGFloat, bandBlur: CGFloat) {
            self.unit = unit
            self.restReach = restReach; self.reach = reach
            self.restBend = restBend; self.bend = bend; self.spread = spread
            self.lobeWidth = lobeWidth; self.lobeBlur = lobeBlur
            self.bandWidth = bandWidth; self.bandBlur = bandBlur
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval,
                     state: VoiceGlowSmoother.State, kind: VoiceGlow.Kind, cornerRadius: CGFloat, motion: Double) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let tuning = Tuning(kind: kind, size: size)
        let u = tuning.unit
        let level = CGFloat(state.level)
        let process = CGFloat(state.processing)
        let bands = [state.low, state.mid, state.high, state.mid, state.low, state.high, state.mid].map { CGFloat($0) }
        let radius = min(cornerRadius, w / 2, h / 2)

        // Everything stays inside the host's shape, like the original's overflow clip.
        context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius, style: .continuous))
        context.blendMode = .plusLighter

        // Hue drift: the palette slowly rotates, so the lobes and the band change colour.
        let drift = time * 0.045 * motion
        func tint(_ position: Double, _ opacity: Double, white: Double = 0) -> Color {
            let rgb = color(at: position + drift)
            let mixed = rgb + (SIMD3(repeating: 1) - rgb) * white
            return Color(red: mixed.x, green: mixed.y, blue: mixed.z, opacity: max(0, min(1, opacity)))
        }

        // While a reply is prepared, everything gathers at one beam that travels the range and
        // back (centered with Reduce Motion).
        let beamX = w * (0.5 + 0.3 * CGFloat(sin(time * 1.3)) * motion)
        let energy = max(level, 0.7 * process)
        let centerX = w / 2 + (beamX - w / 2) * process
        let halfWidth = w * (tuning.spread + (0.17 - tuning.spread) * process)
        /// The dome's profile: 1 in the middle, falling off gently toward the corners.
        func bell(_ x: CGFloat) -> CGFloat {
            let d = (x - centerX) / (halfWidth * 0.47)
            return 1 / (1 + d * d)
        }
        /// The host's bottom edge at x, rising around the rounded corners.
        func floorY(_ x: CGFloat) -> CGFloat {
            let dx = x < radius ? radius - x : (x > w - radius ? x - (w - radius) : 0)
            return h - radius + (radius * radius - dx * dx).squareRoot()
        }

        // 1. Lobes: soft columns of colour rising from the band, tallest in the middle, each
        //    following one voice band; they flow slowly to the right and wrap out of sight.
        struct Lobe { var x: CGFloat, height: CGFloat, width: CGFloat, alpha: Double, colorPosition: Double, weight: CGFloat }
        let count = 7
        let lobes: [Lobe] = (0..<count).map { i in
            let flow = (Double(i) / Double(count) + time * 0.05 * motion).truncatingRemainder(dividingBy: 1)
            let s = CGFloat(flow * 2 - 1) * 1.2                             // -1.2...1.2 across the host
            let restX = w / 2 + s * w / 2
            let edgeFade = min(1, max(0, (1.2 - abs(s)) / 0.35))
            let band = bands[i]
            let breath = 0.025 * CGFloat(sin(time * 0.9 + Double(i) * 2.1)) * motion
            let voiceHeight = u * (tuning.restReach + breath + tuning.reach * band) * (0.55 + 0.45 * bell(restX))
            let weight = edgeFade + (1 - edgeFade) * process
            return Lobe(x: restX + (beamX + CGFloat(i - count / 2) * w * 0.03 - restX) * process,
                        height: voiceHeight + (u * tuning.reach * 0.8 - voiceHeight) * process,
                        width: u * tuning.lobeWidth * (1 - 0.3 * process),
                        alpha: Double((0.16 + 0.55 * max(band, level * 0.6)) * edgeFade * (0.3 + 0.7 * bell(restX))) * Double(1 - process)
                            + 0.45 * Double(process),
                        colorPosition: Double(i), weight: weight)
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: u * tuning.lobeBlur))
            for lobe in lobes {
                let top = h - lobe.height
                let column = Path(roundedRect: CGRect(x: lobe.x - lobe.width / 2, y: top, width: lobe.width, height: lobe.height * 2),
                                  cornerRadius: lobe.width / 2)
                // Strongest a little above the band, so the dome stays pale rather than saturated.
                layer.fill(column, with: .linearGradient(
                    Gradient(stops: [.init(color: tint(lobe.colorPosition, 0), location: 0),
                                     .init(color: tint(lobe.colorPosition, lobe.alpha), location: 0.72),
                                     .init(color: tint(lobe.colorPosition, lobe.alpha * 0.5), location: 1)]),
                    startPoint: CGPoint(x: lobe.x, y: top), endPoint: CGPoint(x: lobe.x, y: h)))
            }
        }

        // 2. The band: strips of light along a curve that follows the bottom edge and bends up
        //    in the middle with the voice. It takes its colour from the lobes behind it, and is
        //    brightest in the middle, fading toward the corners.
        let crest = u * (tuning.restBend + tuning.bend * energy) * (1 - process) + u * tuning.bend * 0.85 * process
        let bandWidth = u * tuning.bandWidth
        var centerline = Path()
        let steps = 80
        for step in 0...steps {
            let x = w * CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: x, y: floorY(x) - bandWidth * 0.5 - crest * bell(x))
            if step == 0 { centerline.move(to: point) } else { centerline.addLine(to: point) }
        }
        /// The lobes' colour at x: a blend of the nearby lobes' palette colours.
        func lobeColor(at x: CGFloat) -> SIMD3<Double> {
            var sum = SIMD3<Double>(repeating: 0), total = 0.0
            for lobe in lobes {
                let d = Double((x - lobe.x) / (w * 0.16))
                let weight = exp(-d * d) * Double(lobe.weight) + 1e-6
                sum += color(at: lobe.colorPosition + drift) * weight
                total += weight
            }
            return sum / total
        }
        let samples = 14
        let sampleColors = (0...samples).map { lobeColor(at: w * CGFloat($0) / CGFloat(samples)) }
        let strength = 0.4 + 0.6 * Double(energy)
        /// A strip's shading: the lobe colours across the width, lightened toward white, and
        /// fading toward the corners down to `floor`.
        func strip(_ opacity: Double, white: Double, floor: Double = 0.1) -> GraphicsContext.Shading {
            let stops = sampleColors.enumerated().map { index, rgb in
                let x = w * CGFloat(index) / CGFloat(samples)
                let mixed = rgb + (SIMD3(repeating: 1) - rgb) * white
                let fade = floor + (1 - floor) * Double(bell(x))
                return Gradient.Stop(color: Color(red: mixed.x, green: mixed.y, blue: mixed.z, opacity: min(1, opacity * strength * fade)),
                                     location: CGFloat(index) / CGFloat(samples))
            }
            return .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: w, y: 0))
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: u * tuning.bandBlur))
            var body = centerline
            body.addLine(to: CGPoint(x: w, y: h + 2))
            body.addLine(to: CGPoint(x: 0, y: h + 2))
            body.closeSubpath()
            layer.fill(body, with: strip(0.42, white: 0.45, floor: 0.3))                                                  // the dome, pale
            layer.stroke(centerline.offsetBy(dx: 0, dy: bandWidth * 0.5), with: strip(0.3, white: 0.3), lineWidth: bandWidth)   // mid
            layer.stroke(centerline, with: strip(0.45, white: 0.65, floor: 0.4), lineWidth: bandWidth * 0.6)              // core: the bright rim
            layer.stroke(centerline.offsetBy(dx: 0, dy: -bandWidth * 0.6), with: strip(0.3, white: 0.2, floor: 0.25), lineWidth: bandWidth)  // above: a halo
        }

        // 3. A thin line in the same colours right on the bottom edge, around the corners too.
        var edge = Path()
        for step in 0...steps {
            let x = w * CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: x, y: floorY(x) - 1)
            if step == 0 { edge.move(to: point) } else { edge.addLine(to: point) }
        }
        let lineAlpha = 0.25 + 0.45 * Double(energy)
        let spectrum = Gradient(stops: sampleColors.enumerated().map { index, rgb in
            let position = Double(index) / Double(samples)
            let mixed = rgb + (SIMD3(repeating: 1) - rgb) * 0.2
            return Gradient.Stop(color: Color(red: mixed.x, green: mixed.y, blue: mixed.z,
                                              opacity: lineAlpha * (0.35 + 0.65 * sin(position * .pi))),
                                 location: position)
        })
        let lineShading = GraphicsContext.Shading.linearGradient(spectrum, startPoint: CGPoint(x: 0, y: h), endPoint: CGPoint(x: w, y: h))
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.5))
            layer.stroke(edge, with: lineShading, lineWidth: 3)
        }
        context.stroke(edge, with: lineShading, lineWidth: kind == .screen ? 1.6 : 1.2)
    }

    /// A palette colour at a fractional position, blended smoothly between neighbours.
    static func color(at position: Double) -> SIMD3<Double> {
        let n = Double(palette.count)
        var p = position.truncatingRemainder(dividingBy: n)
        if p < 0 { p += n }
        let index = Int(p) % palette.count
        let next = (index + 1) % palette.count
        let f = p - p.rounded(.down)
        return palette[index] + (palette[next] - palette[index]) * f
    }
}
