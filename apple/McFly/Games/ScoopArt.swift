import McFlyKit
import SwiftUI

// Scoop Shop's drawings, the display's (ScoopTreat.qml, ScoopCrew.qml and
// ScoopShop.qml's Critter), all shapes, nothing from anywhere else: a treat,
// Pip the penguin and Lotl the axolotl, and the customers.

/// A rounded box in a drawing's units, turned about its middle: the
/// display's Rectangle with `radius: min(width, height) / 2` unless given.
private func part(_ ctx: inout GraphicsContext, _ k: CGFloat, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                  _ color: Color, rotation: Double = 0, radius: CGFloat? = nil, border: CGFloat = 0, edge: Color = .clear,
                  opacity: Double = 1, inside: ((inout GraphicsContext, CGRect) -> Void)? = nil) {
    let rect = CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
    var c = ctx
    c.opacity = opacity
    if rotation != 0 {
        c.translateBy(x: rect.midX, y: rect.midY)
        c.rotate(by: .degrees(rotation))
        c.translateBy(x: -rect.midX, y: -rect.midY)
    }
    let r = radius ?? min(rect.width, rect.height) / 2
    let shape = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
    c.fill(shape, with: .color(color))
    if border > 0 { c.stroke(Path(roundedRect: rect.insetBy(dx: border / 2, dy: border / 2), cornerRadius: max(0, r - border / 2)), with: .color(edge), lineWidth: border) }
    inside?(&c, rect)
}

/// Points along an ellipse from one angle to another (radians, y down).
private func arc(_ path: inout Path, center: CGPoint, rx: CGFloat, ry: CGFloat, from a0: Double, to a1: Double, steps: Int = 16) {
    for i in 1...steps {
        let a = a0 + (a1 - a0) * Double(i) / Double(steps)
        path.addLine(to: CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a)))
    }
}

// MARK: The treat

/// A cone or a cup, the scoops on it from the bottom up, the toppings on the
/// top scoop. It draws to a unit: at the default 12 units tall a cone with
/// three scoops and a cherry fits, so every ticket is at the same scale. A
/// button's picture sets `units` to its one piece and `lift` to raise it.
struct ScoopTreatView: View {
    let order: ScoopOrder
    var units: CGFloat = 12
    var lift: CGFloat = 0

    private struct Flavour { let fill: Int, rim: Int, bits: Int }
    private static let flavours: [ScoopFlavour: Flavour] = [
        .vanilla: Flavour(fill: 0xF7E6B0, rim: 0xD7B86C, bits: 0xB88A4E),
        .chocolate: Flavour(fill: 0x8B5332, rim: 0x5C331C, bits: 0xC9946A),
        .strawberry: Flavour(fill: 0xF59BB6, rim: 0xD7638A, bits: 0xC9374F),
        .mint: Flavour(fill: 0x9FE2C4, rim: 0x56AE8A, bits: 0x3B271C),
    ]

    var body: some View {
        let dark = Theme.palette.isDark
        Canvas { ctx, size in
            draw(&ctx, size: size, dark: dark)
        }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, dark: Bool) {
        let u = max(0, min(size.width / 5, size.height / units))
        guard u > 0 else { return }
        let vessel: CGFloat = order.base == .cone ? 4.2 : order.base == .cup ? 3.2 : 0
        let r: CGFloat = 1.6
        func scoopY(_ i: Int) -> CGFloat { -vessel + (order.base != nil ? 0.5 : 0) - 0.53 * r - 1.85 * CGFloat(i) }
        let count = order.scoops.count
        let topY = count > 0 ? scoopY(count - 1) : -units / 2
        // The art's origin: the bottom centre.
        ctx.translateBy(x: size.width / 2, y: size.height - lift * u)
        let thin = max(1, u * 0.12)

        switch order.base {
        case .cone:
            var cone = Path()
            cone.move(to: CGPoint(x: -1.7 * u, y: -4.2 * u))
            cone.addLine(to: CGPoint(x: 1.7 * u, y: -4.2 * u))
            cone.addLine(to: .zero)
            cone.closeSubpath()
            ctx.fill(cone, with: .color(Color(rgb: 0xE5A653)))
            // Lines from the cone's top edge to the far side, both ways.
            var hatch = Path()
            let h: CGFloat = 4.2, w: CGFloat = 1.7
            for x0 in [-0.95, -0.1, 0.75] as [CGFloat] {
                let s = (w - x0) / (2 * w)
                hatch.move(to: CGPoint(x: x0 * u, y: -h * u))
                hatch.addLine(to: CGPoint(x: (x0 + w * s) * u, y: (-h + h * s) * u))
                hatch.move(to: CGPoint(x: -x0 * u, y: -h * u))
                hatch.addLine(to: CGPoint(x: -(x0 + w * s) * u, y: (-h + h * s) * u))
            }
            ctx.stroke(hatch, with: .color(Color(rgb: 0xBF8037)), style: StrokeStyle(lineWidth: thin, lineCap: .round))
            ctx.stroke(cone, with: .color(Color(rgb: dark ? 0xF0C182 : 0xB5772F)), style: StrokeStyle(lineWidth: thin, lineJoin: .round))
            ctx.fill(Path(roundedRect: CGRect(x: -1.85 * u, y: -4.45 * u, width: 3.7 * u, height: 0.6 * u), cornerRadius: 0.3 * u),
                     with: .color(Color(rgb: 0xD08C40)))
        case .cup:
            var cup = Path()
            cup.move(to: CGPoint(x: -2 * u, y: -3.2 * u))
            cup.addLine(to: CGPoint(x: 2 * u, y: -3.2 * u))
            cup.addLine(to: CGPoint(x: 1.5 * u, y: 0))
            cup.addLine(to: CGPoint(x: -1.5 * u, y: 0))
            cup.closeSubpath()
            ctx.fill(cup, with: .color(Color(rgb: 0x7DC4E6)))
            var band = Path()
            band.move(to: CGPoint(x: -1.81 * u, y: -2.0 * u))
            band.addLine(to: CGPoint(x: 1.81 * u, y: -2.0 * u))
            band.addLine(to: CGPoint(x: 1.69 * u, y: -1.2 * u))
            band.addLine(to: CGPoint(x: -1.69 * u, y: -1.2 * u))
            band.closeSubpath()
            ctx.fill(band, with: .color(.white))
            ctx.stroke(cup, with: .color(Color(rgb: dark ? 0xA9DBF2 : 0x4E9DC4)), style: StrokeStyle(lineWidth: thin, lineJoin: .round))
            ctx.fill(Path(roundedRect: CGRect(x: -2.2 * u, y: -3.5 * u, width: 4.4 * u, height: 0.6 * u), cornerRadius: 0.3 * u),
                     with: .color(Color(rgb: 0x5AAED6)))
        case nil:
            break
        }

        // Scoops, bottom first: each one over the one under it.
        for (i, flavour) in order.scoops.enumerated() {
            let f = Self.flavours[flavour]!
            var c = ctx
            c.translateBy(x: 0, y: scoopY(i) * u)
            // A round top and a wavy, melting bottom edge.
            let rr = r * u, b = 0.2 * rr, s = rr / 3
            var scoop = Path()
            scoop.move(to: CGPoint(x: -rr, y: b))
            arc(&scoop, center: CGPoint(x: 0, y: b), rx: rr, ry: rr, from: .pi, to: 2 * .pi, steps: 28)
            for cx in [2 * s, 0, -2 * s] {
                arc(&scoop, center: CGPoint(x: cx, y: b), rx: s, ry: s * 1.05, from: 0, to: .pi, steps: 10)
            }
            scoop.closeSubpath()
            c.fill(scoop, with: .color(Color(rgb: f.fill)))
            let rim = dark ? Color(rgb: f.fill, scaled: flavour == .chocolate ? 1.7 : 1.15) : Color(rgb: f.rim)
            c.stroke(scoop, with: .color(rim), style: StrokeStyle(lineWidth: max(1, u * 0.14), lineJoin: .round))
            // Bits in it: vanilla's specks, chocolate's swirl, strawberry pieces, mint's chips.
            let small = flavour == .vanilla
            for bit in [(-0.75, -0.55, 25.0), (0.35, -0.95, -30.0), (0.7, -0.15, 60.0), (-0.2, 0.05, -10.0)] {
                let w = (small ? 0.22 : 0.42) * u, h = (small ? 0.22 : 0.3) * u
                part(&c, 1, CGFloat(bit.0) * u, CGFloat(bit.1) * u, w, h, Color(rgb: f.bits), rotation: bit.2,
                     radius: w / 3, opacity: flavour == .chocolate ? 0.55 : 0.9)
            }
            // A shine, top left.
            part(&c, u, -1.05, -1.15, 0.75, 0.4, .white, rotation: -35, opacity: 0.55)
        }

        // The wafer, over the scoops.
        if order.toppings.contains(.wafer) {
            let y = count > 0 ? topY - 2.6 : topY - 1.5
            part(&ctx, u, 0.25, y, 0.7, 3.0, Color(rgb: 0xE8BC74), rotation: 28, radius: 0.2 * u,
                 border: max(1, u * 0.1), edge: Color(rgb: dark ? 0xF5D9A8 : 0xB98A42)) { c, rect in
                for i in 0..<3 {
                    c.fill(Path(CGRect(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * (0.25 + CGFloat(i) * 0.25),
                                       width: rect.width * 0.7, height: max(1, u * 0.1))), with: .color(Color(rgb: 0xB98A42)))
                }
            }
        }

        // Sprinkles over the top scoop.
        if order.toppings.contains(.sprinkles) {
            let bits: [(CGFloat, CGFloat, Double, Int)] = [(-0.95, -0.6, 30, 0xE5484D), (-0.25, -1.15, -40, 0x5B8DEF), (0.55, -0.85, 70, 0xF2B84B),
                                                            (1.0, -0.25, -20, 0x3DB37A), (-0.55, 0.0, 80, 0x8E7CE6), (0.25, -0.2, 10, 0xFFFFFF),
                                                            (-1.15, 0.15, -60, 0x3DB37A)]
            for b in bits {
                part(&ctx, 1, (b.0 - 0.24) * u, (topY + b.1) * u, 0.5 * u, max(2, 0.17 * u), Color(rgb: b.3), rotation: b.2,
                     border: b.3 == 0xFFFFFF ? 1 : 0, edge: Color(rgb: 0xD0C8C0))
            }
        }

        // The cherry on top, with its stem.
        if order.toppings.contains(.cherry) {
            var c = ctx
            c.translateBy(x: 0, y: (count > 0 ? topY - r - 0.05 : topY + 0.45) * u)
            var stem = Path()
            stem.move(to: CGPoint(x: 0, y: -0.45 * u))
            stem.addQuadCurve(to: CGPoint(x: 0.6 * u, y: -1.25 * u), control: CGPoint(x: 0.1 * u, y: -1.1 * u))
            c.stroke(stem, with: .color(Color(rgb: dark ? 0x8FCB6E : 0x4E7D3A)), style: StrokeStyle(lineWidth: max(1.5, u * 0.16), lineCap: .round))
            let ball = CGRect(x: -0.58 * u, y: -0.95 * u, width: 1.16 * u, height: 1.16 * u)
            c.fill(Path(ellipseIn: ball), with: .color(Color(rgb: 0xD8263C)))
            let bw = max(1, u * 0.1)
            c.stroke(Path(ellipseIn: ball.insetBy(dx: bw / 2, dy: bw / 2)), with: .color(Color(rgb: dark ? 0xFF7A88 : 0x9E1428)), lineWidth: bw)
            c.fill(Path(ellipseIn: CGRect(x: ball.minX + ball.width * 0.2, y: ball.minY + ball.height * 0.18,
                                          width: ball.width * 0.28, height: ball.width * 0.28)), with: .color(.white.opacity(0.6)))
        }
    }
}

// MARK: The crew

/// Scoop Shop's two shopkeepers, Pip the penguin and Lotl the axolotl, each
/// in the shop's paper hat, on a 10 × 12 grid, standing on the bottom edge.
/// `mood` hops (an order out right) or shakes (a wrong one, a customer gone).
struct ScoopCrewView: View {
    let who: ScoopKeeper
    var happy = false
    var oops = false
    /// Bumped to hop or to shake.
    var hops = 0
    var shakes = 0

    var body: some View {
        let dark = Theme.palette.isDark
        Canvas { ctx, size in
            let k = max(0, min(size.width / 10, size.height / 12))
            ctx.translateBy(x: (size.width - 10 * k) / 2, y: size.height - 12 * k)
            if who == .pip { pip(&ctx, k, dark) } else { lotl(&ctx, k, dark) }
            // The shop's paper hat, on both.
            part(&ctx, k, 3.0, who == .pip ? 0.25 : 0.65, 4.0, 1.3, .white, rotation: -6, radius: 0.4 * k,
                 border: k * 0.1, edge: Color(rgb: 0xD9D2CA)) { c, rect in
                c.fill(Path(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.42, width: rect.width, height: rect.height * 0.3)),
                       with: .color(Color(rgb: 0x56C3A0)))
            }
        }
        .keyframeAnimator(initialValue: 0.0, trigger: hops) { content, hop in
            content.offset(y: -hop * 11)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.16)
                CubicKeyframe(0, duration: 0.22)
            }
        }
        .keyframeAnimator(initialValue: 0.0, trigger: shakes) { content, shake in
            content.offset(x: shake * 4)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-1, duration: 0.06)
                LinearKeyframe(1, duration: 0.12)
                LinearKeyframe(-1, duration: 0.12)
                LinearKeyframe(1, duration: 0.12)
                LinearKeyframe(0, duration: 0.06)
            }
        }
        .accessibilityLabel(who == .pip ? "Pip the penguin" : "Lotl the axolotl")
    }

    private func eye(_ c: inout GraphicsContext, _ k: CGFloat, _ x: CGFloat, _ y: CGFloat, _ happyY: CGFloat, _ size: CGFloat, _ ink: Int) {
        part(&c, k, x - size / 2, happy ? happyY : y, size, happy ? 0.3 : size, Color(rgb: ink)) { c, rect in
            guard !happy else { return }
            c.fill(Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.14,
                                          width: rect.width * 0.36, height: rect.width * 0.36)), with: .color(.white))
        }
    }

    private func pip(_ c: inout GraphicsContext, _ k: CGFloat, _ dark: Bool) {
        let navy = Color(rgb: 0x34405C), edge = Color(rgb: dark ? 0x7083B0 : 0x27314A)
        let cream = Color(rgb: 0xFFF6E6), orange = Color(rgb: 0xF39A3B)
        part(&c, k, 2.6, 11.0, 2.2, 0.95, orange)
        part(&c, k, 5.2, 11.0, 2.2, 0.95, orange)
        part(&c, k, 0.85, 5.0, 1.3, 4.4, navy, rotation: 18, border: k * 0.16, edge: edge)
        part(&c, k, 7.85, 5.0, 1.3, 4.4, navy, rotation: -18, border: k * 0.16, edge: edge)
        part(&c, k, 1.5, 1.0, 7.0, 10.4, navy, border: k * 0.18, edge: edge)
        // The white front: a mask round the eyes running into the belly.
        part(&c, k, 2.6, 5.0, 4.8, 5.9, cream)
        part(&c, k, 2.3, 2.1, 3.2, 3.2, cream)
        part(&c, k, 4.5, 2.1, 3.2, 3.2, cream)
        for x in [4.0, 6.0] as [CGFloat] { eye(&c, k, x, 3.18, 3.5, 0.86, 0x1E2333) }
        part(&c, k, 2.6, 4.45, 1.0, 0.55, Color(rgb: 0xFF9AAE), opacity: 0.75)
        part(&c, k, 6.4, 4.45, 1.0, 0.55, Color(rgb: 0xFF9AAE), opacity: 0.75)
        part(&c, k, 4.48, 3.95, 1.04, 1.04, orange, rotation: 45, radius: k * 0.22)
        // A drop of worry.
        if oops { part(&c, k, 8.3, 1.6, 0.7, 1.0, Color(rgb: 0x7CC4F2)) }
    }

    private func lotl(_ c: inout GraphicsContext, _ k: CGFloat, _ dark: Bool) {
        let pink = Color(rgb: 0xF6A8C3), edge = Color(rgb: dark ? 0xFFD0E0 : 0xE07FA3), limb = Color(rgb: 0xF09AB8)
        part(&c, k, 6.1, 9.3, 3.4, 1.3, limb, rotation: -25, border: k * 0.14, edge: edge)
        part(&c, k, 2.9, 11.0, 1.6, 0.9, limb)
        part(&c, k, 5.5, 11.0, 1.6, 0.9, limb)
        part(&c, k, 1.9, 7.3, 1.1, 2.4, pink, rotation: 25, border: k * 0.14, edge: edge)
        part(&c, k, 7.0, 7.3, 1.1, 2.4, pink, rotation: -25, border: k * 0.14, edge: edge)
        part(&c, k, 2.6, 6.2, 4.8, 5.3, pink, border: k * 0.16, edge: edge)
        part(&c, k, 3.5, 7.3, 3.0, 3.5, Color(rgb: 0xFDD9E5))
        // Three feathery gills on each side, fanning out from the head.
        for (gy, angle) in [(2.8, 28.0), (3.95, 0.0), (5.1, -28.0)] as [(CGFloat, Double)] {
            for side in [-1.0, 1.0] {
                let rect = CGRect(x: (side < 0 ? 0.0 : 7.8) * k, y: (gy - 0.38) * k, width: 2.2 * k, height: 0.76 * k)
                var g = c
                // Turned about its end at the head.
                let pivot = CGPoint(x: side < 0 ? rect.maxX : rect.minX, y: rect.midY)
                g.translateBy(x: pivot.x, y: pivot.y)
                g.rotate(by: .degrees(angle * -side))
                g.translateBy(x: -pivot.x, y: -pivot.y)
                g.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(Color(rgb: 0xE2558A)))
                for i in 0..<2 {
                    let d = rect.height * 0.62
                    g.fill(Path(ellipseIn: CGRect(x: rect.minX + rect.width * (0.18 + CGFloat(i) * 0.34), y: rect.minY - rect.height * 0.25,
                                                  width: d, height: d)), with: .color(Color(rgb: 0xEE77A2)))
                }
            }
        }
        part(&c, k, 1.4, 1.6, 7.2, 5.2, pink, radius: k * 2.5, border: k * 0.16, edge: edge)
        for x in [3.3, 6.7] as [CGFloat] { eye(&c, k, x, 3.5, 3.85, 0.8, 0x2B1E2A) }
        part(&c, k, 2.2, 4.55, 1.0, 0.55, Color(rgb: 0xFF7FA8), opacity: 0.6)
        part(&c, k, 6.8, 4.55, 1.0, 0.55, Color(rgb: 0xFF7FA8), opacity: 0.6)
        if oops {
            let ring = CGRect(x: 4.7 * k, y: 4.75 * k, width: 0.6 * k, height: 0.6 * k)
            c.stroke(Path(ellipseIn: ring.insetBy(dx: k * 0.11, dy: k * 0.11)), with: .color(Color(rgb: 0x9A3A60)), lineWidth: k * 0.22)
        } else {
            // A smile, a wider one when happy.
            let w: CGFloat = happy ? 1.2 : 0.8
            var smile = Path()
            smile.move(to: CGPoint(x: (5 - w) * k, y: 4.7 * k))
            smile.addQuadCurve(to: CGPoint(x: (5 + w) * k, y: 4.7 * k), control: CGPoint(x: 5 * k, y: (happy ? 5.9 : 5.4) * k))
            c.stroke(smile, with: .color(Color(rgb: 0x9A3A60)), style: StrokeStyle(lineWidth: max(1.5, k * 0.24), lineCap: .round))
        }
    }
}

// MARK: The customers

/// A customer: a round animal face over the counter, on a 10 × 9 grid.
struct CritterView: View {
    enum Face { case smile, flat, frown, happy, cross }

    let kind: ScoopCustomer.Kind
    let face: Face

    static func tint(_ kind: ScoopCustomer.Kind) -> Int {
        switch kind {
        case .bear: return 0xC49A6C
        case .bunny: return 0xEEE6F4
        case .cat: return 0xF3B36B
        case .frog: return 0x86CF7E
        case .chick: return 0xF7D65A
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width / 10, size.height / 9)
            ctx.translateBy(x: (size.width - 10 * k) / 2, y: size.height - 9 * k)
            draw(&ctx, k)
        }
        .accessibilityHidden(true)
    }

    private func draw(_ c: inout GraphicsContext, _ k: CGFloat) {
        let tint = Self.tint(kind)
        let fill = Color(rgb: tint), edge = Color(rgb: tint, scaled: 1 / 1.3), line = k * 0.12
        let ink = Color(rgb: 0x2B2230), pinkInside = Color(rgb: 0xF2B8C6)
        part(&c, k, 1.6, 7.0, 6.8, 3.0, Color(rgb: tint, scaled: 1 / 1.08), border: line, edge: edge)
        // Ears, or a frog's eye bumps, or a chick's tuft.
        switch kind {
        case .bear:
            for x in [2.0, 5.6] as [CGFloat] {
                part(&c, k, x, 2.0, 2.4, 2.4, fill, border: line, edge: edge) { c, rect in
                    c.fill(Path(ellipseIn: CGRect(x: rect.minX + 0.6 * k, y: rect.minY + 0.6 * k, width: 1.2 * k, height: 1.2 * k)),
                           with: .color(pinkInside))
                }
            }
        case .bunny:
            for (x, angle) in [(3.0, -12.0), (5.5, 12.0)] as [(CGFloat, Double)] {
                part(&c, k, x, -0.2, 1.5, 4.2, fill, rotation: angle, border: line, edge: edge) { c, rect in
                    c.fill(Path(roundedRect: CGRect(x: rect.minX + 0.4 * k, y: rect.minY + 0.5 * k, width: 0.7 * k, height: 2.9 * k),
                                cornerRadius: 0.35 * k), with: .color(pinkInside))
                }
            }
        case .cat:
            var ears = Path()
            for (a, b, d) in [((2.3, 4.6), (2.7, 1.2), (4.9, 3.0)), ((7.7, 4.6), (7.3, 1.2), (5.1, 3.0))] as [((CGFloat, CGFloat), (CGFloat, CGFloat), (CGFloat, CGFloat))] {
                ears.move(to: CGPoint(x: a.0 * k, y: a.1 * k))
                ears.addLine(to: CGPoint(x: b.0 * k, y: b.1 * k))
                ears.addLine(to: CGPoint(x: d.0 * k, y: d.1 * k))
                ears.closeSubpath()
            }
            c.fill(ears, with: .color(fill))
            c.stroke(ears, with: .color(edge), style: StrokeStyle(lineWidth: line, lineJoin: .round))
        case .frog:
            for x in [3.4, 6.6] as [CGFloat] {
                part(&c, k, x - 1.3, 1.9, 2.6, 2.6, fill, border: line, edge: edge) { c, rect in
                    c.fill(Path(ellipseIn: CGRect(x: rect.minX + 0.5 * k, y: rect.minY + 0.5 * k, width: 1.6 * k, height: 1.6 * k)), with: .color(.white))
                    let happy = face == .happy
                    c.fill(Path(roundedRect: CGRect(x: rect.minX + 0.9 * k, y: rect.minY + (happy ? 1.2 : 0.9) * k,
                                                    width: 0.8 * k, height: (happy ? 0.3 : 0.8) * k), cornerRadius: (happy ? 0.15 : 0.4) * k),
                           with: .color(ink))
                }
            }
        case .chick:
            for (x, angle) in [(4.3, -25.0), (4.85, 0.0), (5.4, 25.0)] as [(CGFloat, Double)] {
                part(&c, k, x, 1.4, 0.5, 1.6, Color(rgb: tint, scaled: 1 / 1.15), rotation: angle)
            }
        }
        // The head.
        part(&c, k, 2.0, 2.6, 6.0, 6.0, fill, border: line, edge: edge)
        // Eyes (a frog's are on top), and brows when cross.
        if kind != .frog {
            for x in [3.8, 6.2] as [CGFloat] {
                part(&c, k, x - 0.4, face == .happy ? 5.3 : 5.0, 0.8, face == .happy ? 0.3 : 0.8, ink)
            }
        }
        if face == .cross {
            for (x, angle) in [(3.3, 18.0), (5.7, -18.0)] as [(CGFloat, Double)] {
                part(&c, k, x, kind == .frog ? 1.5 : 4.3, 1.0, 0.28, ink, rotation: angle)
            }
        }
        part(&c, k, 2.9, 6.1, 0.9, 0.5, Color(rgb: 0xFF8FA8), opacity: 0.55)
        part(&c, k, 6.2, 6.1, 0.9, 0.5, Color(rgb: 0xFF8FA8), opacity: 0.55)
        // A beak for the chick, a mouth for the rest.
        if kind == .chick {
            part(&c, k, 4.55, 5.85, 0.9, 0.9, Color(rgb: 0xF39A3B), rotation: 45, radius: k * 0.15)
        } else {
            let l: [CGFloat]
            switch face {
            case .smile: l = [4.3, 6.4, 7.0, 5.7]
            case .happy: l = [4.1, 6.3, 7.5, 5.9]
            case .flat: l = [4.4, 6.7, 6.7, 5.6]
            case .frown: l = [4.3, 7.0, 6.4, 5.7]
            case .cross: l = [4.3, 7.1, 6.3, 5.7]
            }
            var mouth = Path()
            mouth.move(to: CGPoint(x: l[0] * k, y: l[1] * k))
            mouth.addQuadCurve(to: CGPoint(x: l[3] * k, y: l[1] * k), control: CGPoint(x: 5 * k, y: l[2] * k))
            c.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, k * 0.22), lineCap: .round))
        }
    }
}

/// Three hearts, the ones lost dimmed.
struct HeartsView: View {
    let left: Int
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<Scoops.hearts, id: \.self) { i in
                Heart()
                    .fill(i < left ? Color(rgb: 0xF0566E) : Theme.sunken)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(left) of \(Scoops.hearts) hearts")
    }

    private struct Heart: Shape {
        func path(in rect: CGRect) -> Path {
            let k = min(rect.width, rect.height) / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
            var path = Path()
            path.move(to: p(12, 20.5))
            path.addCurve(to: p(3, 9.6), control1: p(5.6, 16.2), control2: p(3, 13))
            path.addCurve(to: p(7.5, 5), control1: p(3, 7), control2: p(5, 5))
            path.addCurve(to: p(12, 7.6), control1: p(9.3, 5), control2: p(10.9, 6))
            path.addCurve(to: p(16.5, 5), control1: p(13.1, 6), control2: p(14.7, 5))
            path.addCurve(to: p(21, 9.6), control1: p(19, 5), control2: p(21, 7))
            path.addCurve(to: p(12, 20.5), control1: p(21, 13), control2: p(18.4, 16.2))
            path.closeSubpath()
            return path
        }
    }
}
