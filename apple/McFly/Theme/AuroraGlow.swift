// AuroraGlow, from React Bits' Aurora (https://github.com/DavidHDev/react-bits,
// src/ts-tailwind/Backgrounds/Aurora, commit 963f4d2), ported for McFly's
// SwiftUI app. The display has the same curtain for Qt
// (display/qml/components/AuroraGlow.qml, display/shaders/aurora.frag) and
// the console for the web (admin/components/reactbits/Aurora.tsx).
//
// MIT + Commons Clause License Condition v1.0
//
// Copyright (c) 2026 David Haz
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, and distribute the Software as part of
// an application, website, or product, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// Commons Clause Restriction: You may use this Software, including for any
// commercial purpose, so long as you do not sell, sublicense, or redistribute the
// components themselves-whether alone, in a bundle, or as a ported version.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Changes for SwiftUI: the shader is a colour effect (AuroraGlow.metal) on a
// rectangle `resolution` the view's size, drawn into its own layer and scaled
// up; the clock is a TimelineView's, and it counts only the seconds it runs;
// there is no intro (it fades in) and it always hangs from the top; the
// pointer's pull is gone. The rest is the second pass both other ports have:
// the colours are converted to OKLCh here, once, and a new palette glides in
// over 1.5 s; light mode eases over 0.6 s; the hue's sway is worked out here
// once a tick; the clock starts from the wall clock, within the hour.

import SwiftUI

/// An aurora: a curtain of light in the glow colours hangs from the top edge,
/// its hem folding slowly, faint rays running down it, the colour running left
/// to right. The display hangs the same one over its night-time screen saver
/// and the console over its ambient view. Decorative; lay it over a backdrop,
/// under the content.
///
///     AuroraGlow(lightMode: false, opacity: 0.5)
///
/// Cost: five noise lookups per pixel and layer (four with `rays: 0`), so it
/// runs at `resolution` of its size (a soft curtain loses nothing scaled up)
/// and moves at `maxFps`. Like GradientTile, its clock only runs while it can
/// be seen, the app is in front and Reduce Motion is off, and it resumes where
/// it stopped. A change of colours glides over 1.5 s, light mode over 0.6 s and
/// the first showing fades in over 1.2 s, all on that clock; with the clock
/// stopped, colours and light mode simply change, and under Reduce Motion it is
/// there at once, still.
struct AuroraGlow: View {
    // MARK: Look

    /// 2–5 colours, left to right, as 0xRRGGBB.
    var colors: [Int] = AuroraGlow.glowStops
    /// Ink on a light canvas; false: light over a dark one.
    var lightMode = !Theme.palette.isDark
    /// Where the hem rests, 0 (top) … 1 (bottom).
    var hem = 0.45
    /// How tall the waves along the hem are.
    var amplitude = 1.0
    /// 0…1, how softly the hem fades out.
    var blend = 0.5
    /// Horizontal frequency of the waves.
    var waveScale = 1.0
    /// How far the light spills past the hem.
    var glow = 0.6
    /// 0…2.
    var brightness = 1.0
    /// 1–3 curtains, one behind the other.
    var layers = 1
    /// 0…1, faint rays down the curtain; 0 also skips their noise.
    var rays = 0.6
    /// The strength: the picture's opacity.
    var opacity = 1.0

    // MARK: Motion

    var speed = 1.0
    /// Motion updates per second.
    var maxFps: Double = 15
    /// The share of its size, each way, the shader runs at.
    var resolution = 0.5
    /// False while its screen is covered.
    var active = true

    /// The glow's blue, coral and amber in this palette, blue at both ends so
    /// the curtain closes on itself (the display's and the console's stops).
    static var glowStops: [Int] {
        let glow = Theme.palette.glow
        return [glow[0], glow[1], glow[2], glow[0]]
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var onScreen = false
    /// The wall clock's seconds into the hour when it first showed, so each
    /// showing opens on a different curtain and the time stays small enough
    /// for the shader's 32-bit floats to step evenly.
    @State private var origin = Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600)
    /// Seconds run before the current run, and when that began. Everything
    /// that moves or eases goes by these seconds, so all of it waits while
    /// the clock is stopped.
    @State private var banked: TimeInterval = 0
    @State private var runStart: Date?
    /// The palette a glide sets out from, and when (in seconds run).
    @State private var paletteFrom: [Lch] = []
    @State private var paletteSince = -Double.infinity
    /// The light mode an ease sets out from (0…1), and when.
    @State private var lightFrom = 0.0
    @State private var lightSince = -Double.infinity

    private var playing: Bool { active && onScreen && !reduceMotion && scenePhase == .active }

    var body: some View {
        GeometryReader { geo in
            let full = geo.size
            // Whole pixels: a partly covered one would fringe the edges once scaled up.
            let pixels = max(displayScale, 1)
            let share = min(max(resolution, 0.1), 1)
            let small = CGSize(width: max(1, (full.width * share * pixels).rounded(.up)) / pixels,
                               height: max(1, (full.height * share * pixels).rounded(.up)) / pixels)
            TimelineView(.animation(minimumInterval: maxFps > 0 ? 1 / maxFps : nil, paused: !playing)) { context in
                let tick = uniforms(at: context.date)
                Rectangle()
                    .fill(.white)
                    .frame(width: small.width, height: small.height)
                    .colorEffect(ShaderLibrary.auroraGlow(
                        .float2(small), .float(tick.time), .float(1), .float(amplitude), .float(blend),
                        .float(hem), .float(waveScale), .float(glow), .float(brightness),
                        .float(Double(min(max(layers, 1), 3))), .float(0), .float(tick.light),
                        .float(min(max(rays, 0), 1)), .float(tick.opacity), .float(pixels),
                        .float3(tick.drift.x, tick.drift.y, tick.drift.z), .floatArray(tick.stops)))
                    // Rendered small, then scaled up: the curtain has no hard edges.
                    .drawingGroup()
                    .scaleEffect(x: full.width / small.width, y: full.height / small.height, anchor: .topLeading)
            }
            .frame(width: full.width, height: full.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onChange(of: playing) { _, playing in
            if playing {
                runStart = .now
                return
            }
            if let runStart { banked += max(0, Date.now.timeIntervalSince(runStart)) }
            runStart = nil
            // Stopped: colours and light mode take their new look at once.
            paletteSince = -.infinity
            lightSince = -.infinity
        }
        // A new palette glides in from the one on screen, mid-glide or not.
        .onChange(of: colors) { old, new in
            let now = seconds(at: .now)
            let from = palette(Self.stops(old), at: now)
            guard playing, from.count == Self.stops(new).count else {
                paletteSince = -.infinity
                return
            }
            paletteFrom = from
            paletteSince = now
        }
        .onChange(of: lightMode) { old, _ in
            let now = seconds(at: .now)
            lightFrom = light(old, at: now)
            lightSince = playing ? now : -.infinity
        }
    }

    // MARK: A tick

    private struct Uniforms {
        var time: Double, light: Double, opacity: Double
        var drift: SIMD3<Double>
        var stops: [Float]
    }

    private func uniforms(at date: Date) -> Uniforms {
        let run = seconds(at: date)
        let time = (origin + run) * speed
        let stops = palette(Self.stops(colors), at: run).flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        let appear = reduceMotion ? 1 : Self.ease(min(1, run / 1.2))
        return Uniforms(time: time, light: light(lightMode, at: run), opacity: min(max(opacity, 0), 1) * appear,
                     drift: [Self.hueDrift(time, layer: 0), Self.hueDrift(time, layer: 1), Self.hueDrift(time, layer: 2)],
                     stops: stops)
    }

    /// Seconds the clock has run by `date`.
    private func seconds(at date: Date) -> TimeInterval {
        banked + (runStart.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// The palette on screen: part way from `paletteFrom` while a glide is under way.
    private func palette(_ target: [Lch], at run: TimeInterval) -> [Lch] {
        let t = playing ? min(1, max(0, (run - paletteSince) / 1.5)) : 1
        guard t < 1, paletteFrom.count == target.count else { return target }
        return Self.blendPalettes(paletteFrom, target, Self.ease(t))
    }

    /// Light mode on screen, 0…1.
    private func light(_ mode: Bool, at run: TimeInterval) -> Double {
        let target = mode ? 1.0 : 0.0
        let t = playing ? min(1, max(0, (run - lightSince) / 0.6)) : 1
        return t < 1 ? lightFrom + (target - lightFrom) * Self.ease(t) : target
    }

    // MARK: Colour

    /// OKLCh: lightness, chroma, hue in radians.
    typealias Lch = SIMD3<Double>

    /// The stops as the shader takes them: 2–5 colours in OKLCh, each hue
    /// unwrapped toward the one before.
    static func stops(_ colors: [Int]) -> [Lch] {
        let source = colors.count >= 2 ? colors : Array(glowStops.prefix(2))
        return unwrap(source.prefix(5).map(oklch))
    }

    /// 0xRRGGBB (sRGB) in OKLCh.
    static func oklch(_ rgb: Int) -> Lch {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let r = linear(Double((rgb >> 16) & 0xFF) / 255)
        let g = linear(Double((rgb >> 8) & 0xFF) / 255)
        let b = linear(Double(rgb & 0xFF) / 255)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        return [L, hypot(A, B), atan2(B, A)]
    }

    /// Each hue unwrapped toward the one before, so the blend between
    /// neighbouring stops takes the short way round. A grey takes its
    /// neighbour's hue.
    static func unwrap(_ stops: [Lch]) -> [Lch] {
        var previous = stops.first { $0.y > 0.02 }?.z ?? 0
        return stops.map { stop in
            var hue = stop.y > 0.02 ? stop.z : previous
            while hue - previous > .pi { hue -= 2 * .pi }
            while hue - previous < -.pi { hue += 2 * .pi }
            previous = hue
            return [stop.x, stop.y, hue]
        }
    }

    /// One palette part way to another, stop by stop: lightness and chroma
    /// straight across, the hue the short way round (a grey stop takes its
    /// partner's hue). AuroraGlow.qml and Aurora.tsx glide the same way.
    static func blendPalettes(_ from: [Lch], _ to: [Lch], _ t: Double) -> [Lch] {
        unwrap(to.indices.map { i in
            let b = to[i]
            let a = i < from.count ? from[i] : b
            let ha = a.y > 0.02 ? a.z : b.z
            let hb = b.y > 0.02 ? b.z : ha
            let turn = hb - ha - 2 * .pi * ((hb - ha) / (2 * .pi)).rounded()
            return [a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, ha + turn * t]
        })
    }

    // MARK: Motion

    /// InOutSine.
    static func ease(_ t: Double) -> Double { 0.5 - 0.5 * cos(.pi * t) }

    /// The hue's slow sway, per layer: two octaves of smooth 1D gradient noise
    /// on the layer's own clock. The same for every pixel, so it's worked out
    /// here once a tick, not in the shader. AuroraGlow.qml has the same.
    static func hueDrift(_ time: Double, layer: Double) -> Double {
        let pace = time * (1 - layer * 0.18)
        return 0.07 * (0.7 * noise1(pace * 0.03 + layer * 3.1) + 0.3 * noise1(pace * 0.071 + 7.7 + layer * 1.3))
    }

    private static func lattice(_ i: Double) -> Double {
        let s = sin(i * 127.1 + 311.7) * 43758.5453
        return (s - s.rounded(.down)) * 2 - 1
    }

    private static func noise1(_ x: Double) -> Double {
        let i = x.rounded(.down)
        let f = x - i
        let s = f * f * f * (f * (f * 6 - 15) + 10)
        return 2 * (lattice(i) * f * (1 - s) + lattice(i + 1) * (f - 1) * s)
    }
}
