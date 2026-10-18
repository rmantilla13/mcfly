import McFlyKit
import SwiftUI

// Scoop Shop's drawings, the display's (ScoopTreat.qml, ScoopCrew.qml and
// ScoopShop.qml's Critter), all shapes, nothing from anywhere else: a treat,
// Pip the penguin and Lotl the axolotl, and the customers. The parlour round
// them (the awning, the wall, the stock) is in ScoopParlour.swift.

/// A rounded box in a drawing's units, turned about its middle: the
/// display's Rectangle with `radius: min(width, height) / 2` unless given.
/// The border is inside the box, as a Rectangle's is.
func part(_ ctx: inout GraphicsContext, _ k: CGFloat, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
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
func scoopArc(_ path: inout Path, center: CGPoint, rx: CGFloat, ry: CGFloat, from a0: Double, to a1: Double, steps: Int = 16) {
    for i in 1...steps {
        let a = a0 + (a1 - a0) * Double(i) / Double(steps)
        path.addLine(to: CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a)))
    }
}

// MARK: The treat

/// A cone or a cup, the scoops on it from the bottom up, the toppings on the
/// top scoop. It draws to a unit: at the default 12.4 units tall a cone with
/// three scoops, whipped cream and a cherry fits, so every ticket is at the
/// same scale. A button's picture sets `units` to its one piece and `lift` to
/// raise it. A ticket is paper, light in both themes, and sets `dark` false.
struct ScoopTreatView: View {
    let order: ScoopOrder
    var units: CGFloat = 12.4
    var lift: CGFloat = 0
    var dark: Bool?

    var body: some View {
        let dark = self.dark ?? Theme.palette.isDark
        Canvas { ctx, size in
            Self.draw(&ctx, order, in: CGRect(origin: .zero, size: size), units: units, lift: lift, dark: dark)
        }
        .accessibilityHidden(true)
    }

    /// Each flavour's colours, and its bits: their size in units, round or not.
    struct Flavour { let fill: Int, rim: Int, bits: Int, bit: (CGFloat, CGFloat), round: Bool }
    static let flavours: [ScoopFlavour: Flavour] = [
        .vanilla: Flavour(fill: 0xF7E6B0, rim: 0xD7B86C, bits: 0xB88A4E, bit: (0.22, 0.22), round: false),
        .chocolate: Flavour(fill: 0x8B5332, rim: 0x5C331C, bits: 0xC9946A, bit: (0.42, 0.3), round: false),
        .strawberry: Flavour(fill: 0xF59BB6, rim: 0xD7638A, bits: 0xC9374F, bit: (0.42, 0.3), round: false),
        .mint: Flavour(fill: 0x9FE2C4, rim: 0x56AE8A, bits: 0x3B271C, bit: (0.42, 0.3), round: false),
        .mango: Flavour(fill: 0xFFB547, rim: 0xDB8A1C, bits: 0xFFE08F, bit: (0.46, 0.34), round: false),
        .blueberry: Flavour(fill: 0x97A3EE, rim: 0x5F6BC8, bits: 0x3A3488, bit: (0.34, 0.34), round: true),
        .cookies: Flavour(fill: 0xF4F0E9, rim: 0xB9AE9F, bits: 0x2E2622, bit: (0.56, 0.42), round: false),
    ]

    /// A scoop's rim: on the dark canvas a dark rim disappears, so it lifts.
    static func rim(_ flavour: ScoopFlavour, dark: Bool) -> Color {
        let f = flavours[flavour]!
        return dark ? Color(rgb: f.fill, scaled: flavour == .chocolate ? 1.7 : 1.15) : Color(rgb: f.rim)
    }

    /// Draws `order` in `rect`, standing on its bottom edge.
    static func draw(_ ctx: inout GraphicsContext, _ order: ScoopOrder, in rect: CGRect, units: CGFloat = 12.4, lift: CGFloat = 0,
                     dark: Bool) {
        let u = max(0, min(rect.width / 5, rect.height / units))
        guard u > 0 else { return }
        var ctx = ctx
        let vessel: CGFloat = order.base == .cone ? 4.2 : order.base == .cup ? 3.2 : 0
        let r: CGFloat = 1.6
        func scoopY(_ i: Int) -> CGFloat { -vessel + (order.base != nil ? 0.5 : 0) - 0.53 * r - 1.85 * CGFloat(i) }
        let count = order.scoops.count
        let topY = count > 0 ? scoopY(count - 1) : -units / 2
        let has = Set(order.toppings)
        // The art's origin: the bottom centre.
        ctx.translateBy(x: rect.midX, y: rect.maxY - lift * u)
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
            let f = flavours[flavour]!
            var c = ctx
            c.translateBy(x: 0, y: scoopY(i) * u)
            // A round top and a wavy, melting bottom edge.
            let rr = r * u, b = 0.2 * rr, s = rr / 3
            var scoop = Path()
            scoop.move(to: CGPoint(x: -rr, y: b))
            scoopArc(&scoop, center: CGPoint(x: 0, y: b), rx: rr, ry: rr, from: .pi, to: 2 * .pi, steps: 28)
            for cx in [2 * s, 0, -2 * s] {
                scoopArc(&scoop, center: CGPoint(x: cx, y: b), rx: s, ry: s * 1.05, from: 0, to: .pi, steps: 10)
            }
            scoop.closeSubpath()
            c.fill(scoop, with: .color(Color(rgb: f.fill)))
            c.stroke(scoop, with: .color(rim(flavour, dark: dark)), style: StrokeStyle(lineWidth: max(1, u * 0.14), lineJoin: .round))
            // Bits in it: vanilla's specks, chocolate's swirl, strawberry and
            // mango pieces, mint's chips, blueberries, cookie chunks.
            for bit in [(-0.75, -0.55, 25.0), (0.35, -0.95, -30.0), (0.7, -0.15, 60.0), (-0.2, 0.05, -10.0)] {
                let w = f.bit.0 * u, h = f.bit.1 * u
                part(&c, 1, CGFloat(bit.0) * u, CGFloat(bit.1) * u, w, h, Color(rgb: f.bits), rotation: bit.2,
                     radius: f.round ? w / 2 : w / 3, opacity: flavour == .chocolate ? 0.55 : 0.9)
            }
            // A shine, top left.
            part(&c, u, -1.05, -1.15, 0.75, 0.4, .white, rotation: -35, opacity: 0.55)
        }

        // The wafer, over the scoops.
        if has.contains(.wafer) {
            let y = count > 0 ? topY - 2.6 : topY - 1.5
            part(&ctx, u, 0.25, y, 0.7, 3.0, Color(rgb: 0xE8BC74), rotation: 28, radius: 0.2 * u,
                 border: max(1, u * 0.1), edge: Color(rgb: dark ? 0xF5D9A8 : 0xB98A42)) { c, rect in
                for i in 0..<3 {
                    c.fill(Path(CGRect(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * (0.25 + CGFloat(i) * 0.25),
                                       width: rect.width * 0.7, height: max(1, u * 0.1))), with: .color(Color(rgb: 0xB98A42)))
                }
            }
        }

        // Chocolate syrup, then a crunch coat, over the top scoop: a cap round
        // its top with a dripping edge.
        if count > 0 {
            for (topping, fill, edge, drips) in [(ScoopTopping.syrup, 0x5A2E1A, 0x3A1C0F, true), (.crunch, 0xC8873F, 0x9A6128, false)]
            where has.contains(topping) {
                var c = ctx
                c.translateBy(x: 0, y: topY * u)
                let rr = r * u, d: CGFloat = drips ? 1 : 0.35
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * rr, y: y * rr) }
                var cap = Path()
                cap.move(to: p(-0.95, -0.12))
                // The small arc of radius 0.98 over the top, from one side to the other.
                let cy = -0.12 + (0.98 * 0.98 - 0.95 * 0.95).squareRoot()
                scoopArc(&cap, center: p(0, cy), rx: 0.98 * rr, ry: 0.98 * rr, from: atan2(-0.12 - cy, -0.95), to: atan2(-0.12 - cy, 0.95), steps: 24)
                for (to, control) in [((0.74, 0.02), (0.9, 0.08)), ((0.5, 0.02), (0.62, 0.55 * d)), ((0.16, 0.02), (0.3, 0.1)),
                                      ((-0.1, 0.02), (0.04, 0.7 * d)), ((-0.44, 0.02), (-0.3, 0.1)), ((-0.68, 0.0), (-0.56, 0.45 * d)),
                                      ((-0.95, -0.12), (-0.88, 0.04))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
                    cap.addQuadCurve(to: p(to.0, to.1), control: p(control.0, control.1))
                }
                cap.closeSubpath()
                c.fill(cap, with: .color(Color(rgb: fill)))
                c.stroke(cap, with: .color(dark ? Color(rgb: fill, scaled: 1.6) : Color(rgb: edge)),
                         style: StrokeStyle(lineWidth: max(1, u * 0.1), lineJoin: .round))
                if drips {
                    // The syrup: a shine.
                    part(&c, u, -0.95, -1.25, 0.7, 0.22, .white, rotation: -30, opacity: 0.35)
                } else {
                    // The crunch: golden crumbs.
                    let crumbs: [(CGFloat, CGFloat, Double, Int)] = [
                        (-1.0, -0.7, 20, 0xF0BE62), (-0.45, -1.25, -30, 0x8E5726), (0.15, -1.4, 45, 0xF0BE62),
                        (0.7, -1.05, -15, 0xE3A94F), (1.1, -0.45, 30, 0x8E5726), (-0.7, -0.15, -40, 0xE3A94F),
                        (-0.05, -0.75, 10, 0x8E5726), (0.5, -0.35, 60, 0xF0BE62), (-0.35, -0.45, 75, 0xF7D486),
                    ]
                    for b in crumbs {
                        part(&c, u, b.0 - 0.14, b.1, 0.3, 0.24, Color(rgb: b.3), rotation: b.2, radius: 0.3 * u * 0.25)
                    }
                }
            }
        }

        // Sprinkles over the top scoop.
        if has.contains(.sprinkles) {
            let bits: [(CGFloat, CGFloat, Double, Int)] = [(-0.95, -0.6, 30, 0xE5484D), (-0.25, -1.15, -40, 0x5B8DEF), (0.55, -0.85, 70, 0xF2B84B),
                                                            (1.0, -0.25, -20, 0x3DB37A), (-0.55, 0.0, 80, 0x8E7CE6), (0.25, -0.2, 10, 0xFFFFFF),
                                                            (-1.15, 0.15, -60, 0x3DB37A)]
            for b in bits {
                part(&ctx, 1, (b.0 - 0.24) * u, (topY + b.1) * u, 0.5 * u, max(2, 0.17 * u), Color(rgb: b.3), rotation: b.2,
                     border: b.3 == 0xFFFFFF ? 1 : 0, edge: Color(rgb: 0xD0C8C0))
            }
        }

        // Fruit rings: cereal hoops in bright colours on the top scoop.
        if count > 0 && has.contains(.rings) {
            let line = max(2, 0.19 * u)
            for ring in [(-1.0, -0.95, 0xE5484D), (0.15, -1.45, 0xF59A2F), (0.85, -0.75, 0xF2CF3B),
                         (-0.35, -0.35, 0x4DBF6A), (0.55, 0.0, 0x9B6BD8)] as [(CGFloat, CGFloat, Int)] {
                let box = CGRect(x: (ring.0 - 0.33) * u, y: (topY + ring.1) * u, width: 0.66 * u, height: 0.66 * u)
                ctx.stroke(Path(ellipseIn: box.insetBy(dx: line / 2, dy: line / 2)), with: .color(Color(rgb: ring.2)), lineWidth: line)
            }
        }

        // Whipped cream: a swirl in tiers on the top scoop, bottom tier first.
        if count > 0 && has.contains(.cream) {
            let tiers: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(-1.25, -0.45, 2.5, 0.75), (-0.95, -0.85, 1.9, 0.62),
                                                                  (-0.6, -1.15, 1.2, 0.52), (-0.2, -1.38, 0.45, 0.45)]
            for (i, t) in tiers.enumerated() {
                part(&ctx, u, t.0, topY - r + t.1, t.2, t.3, .white, rotation: i == 3 ? 20 : 0,
                     border: max(1, u * 0.08), edge: Color(rgb: dark ? 0xF2EEE8 : 0xDDD6CC))
            }
        }

        // The cherry on top, with its stem: on the cream, when there is some.
        if has.contains(.cherry) {
            var c = ctx
            c.translateBy(x: 0, y: (count > 0 ? topY - r - (has.contains(.cream) ? 1.0 : 0.05) : topY + 0.45) * u)
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
/// With `panic` (a customer about to give up) they sweat, look worried and
/// tremble.
struct ScoopCrewView: View {
    let who: ScoopKeeper
    var happy = false
    var oops = false
    var panic = false
    /// Bumped to hop or to shake.
    var hops = 0
    var shakes = 0

    private var worried: Bool { panic && !happy && !oops }

    var body: some View {
        let dark = Theme.palette.isDark
        let worried = worried
        TimelineView(.animation(paused: !worried)) { timeline in
            // A tremble: over and back, then a rest (the display's 340 ms loop).
            let tremble = worried ? Self.tremble(timeline.date.timeIntervalSinceReferenceDate) : 0
            GeometryReader { geo in
                let k = max(0, min(geo.size.width / 10, geo.size.height / 12))
                Canvas { ctx, size in
                    ctx.translateBy(x: (size.width - 10 * k) / 2 + tremble * 0.6 * 0.35 * k, y: size.height - 12 * k)
                    if who == .pip { pip(&ctx, k, dark, worried) } else { lotl(&ctx, k, dark, worried) }
                    // The shop's paper hat, on both.
                    part(&ctx, k, 3.0, who == .pip ? 0.25 : 0.65, 4.0, 1.3, .white, rotation: -6, radius: 0.4 * k,
                         border: k * 0.1, edge: Color(rgb: 0xD9D2CA)) { c, rect in
                        c.fill(Path(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.42, width: rect.width, height: rect.height * 0.3)),
                               with: .color(Color(rgb: 0x56C3A0)))
                    }
                }
                // Room over the head for the hat and a drop of worry.
                .frame(width: geo.size.width, height: geo.size.height + k)
                .offset(y: -k)
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

    /// 0 → 1 in 40 ms, → −1 in 80, → 0 in 40, then still for 180.
    static func tremble(_ t: TimeInterval) -> CGFloat {
        let ms = (t * 1000).truncatingRemainder(dividingBy: 340)
        if ms < 40 { return ms / 40 }
        if ms < 120 { return 1 - 2 * (ms - 40) / 80 }
        if ms < 160 { return -1 + (ms - 120) / 40 }
        return 0
    }

    private func eye(_ c: inout GraphicsContext, _ k: CGFloat, _ x: CGFloat, _ y: CGFloat, _ happyY: CGFloat, _ size: CGFloat, _ ink: Int) {
        part(&c, k, x - size / 2, happy ? happyY : y, size, happy ? 0.3 : size, Color(rgb: ink)) { c, rect in
            guard !happy else { return }
            c.fill(Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.14,
                                          width: rect.width * 0.36, height: rect.width * 0.36)), with: .color(.white))
        }
    }

    private func pip(_ c: inout GraphicsContext, _ k: CGFloat, _ dark: Bool, _ worried: Bool) {
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
        // Drops of worry, and brows up in the middle.
        if oops || worried { part(&c, k, 8.3, 1.6, 0.7, 1.0, Color(rgb: 0x7CC4F2)) }
        if worried {
            part(&c, k, 1.0, 2.4, 0.6, 0.85, Color(rgb: 0x7CC4F2))
            part(&c, k, 3.45, 2.55, 1.1, 0.24, Color(rgb: 0x1E2333), rotation: -18)
            part(&c, k, 5.45, 2.55, 1.1, 0.24, Color(rgb: 0x1E2333), rotation: 18)
        }
    }

    private func lotl(_ c: inout GraphicsContext, _ k: CGFloat, _ dark: Bool, _ worried: Bool) {
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
        // Drops of worry, and brows up in the middle.
        if oops || worried { part(&c, k, 8.0, 0.9, 0.7, 1.0, Color(rgb: 0x7CC4F2)) }
        if worried {
            part(&c, k, 1.4, 1.2, 0.6, 0.85, Color(rgb: 0x7CC4F2))
            part(&c, k, 2.8, 2.85, 1.1, 0.24, Color(rgb: 0x2B1E2A), rotation: -18)
            part(&c, k, 6.1, 2.85, 1.1, 0.24, Color(rgb: 0x2B1E2A), rotation: 18)
        }
        if oops || worried {
            // An "o".
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

/// A customer: a round animal face in a shirt over the counter, on a 10 × 9
/// grid. Furious (about to give up), they go red in the face, steam, shout,
/// shake and stomp.
struct CritterView: View {
    let kind: ScoopCustomer.Kind
    let face: Scoops.Face
    var shirt = 0x5B8DEF

    static func tint(_ kind: ScoopCustomer.Kind) -> Int {
        switch kind {
        case .bear: return 0xC49A6C
        case .bunny: return 0xE6DCF0
        case .cat: return 0xF3B36B
        case .frog: return 0x86CF7E
        case .chick: return 0xF7D65A
        }
    }

    /// The customers' shirts, one a customer by their number.
    static let shirts = [0x5B8DEF, 0xF2B84B, 0x3DB37A, 0xE5484D, 0x8E7CE6, 0xEF8A6F]

    var body: some View {
        let furious = face == .furious
        TimelineView(.animation(paused: !furious)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let k = min(geo.size.width / 10, geo.size.height / 9)
                // Shaking (a 410 ms loop) and stomping (480 ms), steam rising (900 ms).
                let jitter = furious ? Self.jitter(t) : 0
                let stomp = furious ? Self.stomp(t) : 0
                let puff = furious ? CGFloat((t / 0.9).truncatingRemainder(dividingBy: 1)) : 0
                Canvas { ctx, size in
                    ctx.translateBy(x: (size.width - 10 * k) / 2 + jitter * k * 0.35, y: size.height - 9 * k - stomp * k * 0.8)
                    draw(&ctx, k, puff: puff)
                }
                // Room over the head for ears and steam.
                .frame(width: geo.size.width, height: geo.size.height + 2 * k)
                .offset(y: -2 * k)
            }
        }
        .accessibilityHidden(true)
    }

    static func jitter(_ t: TimeInterval) -> CGFloat {
        let ms = (t * 1000).truncatingRemainder(dividingBy: 410)
        if ms < 45 { return ms / 45 }
        if ms < 135 { return 1 - 2 * (ms - 45) / 90 }
        if ms < 225 { return -1 + 2 * (ms - 135) / 90 }
        if ms < 270 { return 1 - (ms - 225) / 45 }
        return 0
    }

    static func stomp(_ t: TimeInterval) -> CGFloat {
        let ms = (t * 1000).truncatingRemainder(dividingBy: 480)
        if ms < 110 { let x = ms / 110; return 1 - (1 - x) * (1 - x) }
        if ms < 240 { let x = (ms - 110) / 130; return 1 - x * x }
        return 0
    }

    private func draw(_ c: inout GraphicsContext, _ k: CGFloat, puff: CGFloat) {
        let tint = Self.tint(kind)
        let fill = Color(rgb: tint), edge = Color(rgb: tint, scaled: 1 / 1.3), line = k * 0.12
        let ink = Color(rgb: 0x2B2230), pinkInside = Color(rgb: 0xF2B8C6)
        let furious = face == .furious
        // Shoulders in a shirt, and a collar.
        part(&c, k, 1.4, 7.2, 7.2, 1.8, Color(rgb: shirt), border: line, edge: Color(rgb: shirt, scaled: 1 / 1.3))
        part(&c, k, 3.9, 7.6, 2.2, 1.0, .white, opacity: 0.85)
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
        // The head, red in it when furious.
        part(&c, k, 2.0, 2.6, 6.0, 6.0, fill, border: line, edge: edge)
        if furious {
            part(&c, k, 2.0, 2.6, 6.0, 6.0, Color(rgb: 0xFF3B30), opacity: 0.4)
            // Steam off both sides of the head, two puffs a side.
            for (x, dir, phase) in [(1.7, -1.0, 0.0), (1.7, -1.0, 0.5), (8.3, 1.0, 0.25), (8.3, 1.0, 0.75)] as [(CGFloat, CGFloat, CGFloat)] {
                let p = (puff + phase).truncatingRemainder(dividingBy: 1)
                let w = 1.0 + p * 1.3
                part(&c, k, x - w / 2 + dir * p, 3.0 - p * 2.9, w, w, .white,
                     border: max(1, k * 0.08), edge: Color(rgb: 0xD9D2CA), opacity: Double((1 - p) * 0.9))
            }
        }
        // Eyes (a frog's are on top), and brows when cross or furious.
        if kind != .frog {
            for x in [3.8, 6.2] as [CGFloat] {
                part(&c, k, x - 0.4, face == .happy ? 5.3 : 5.0, 0.8, face == .happy ? 0.3 : 0.8, ink)
            }
        }
        if face == .cross || furious {
            for (x, angle) in [(3.3, 18.0), (5.7, -18.0)] as [(CGFloat, Double)] {
                part(&c, k, x, kind == .frog ? 1.5 : 4.3, 1.0, 0.28, ink, rotation: angle)
            }
        }
        part(&c, k, 2.9, 6.1, 0.9, 0.5, Color(rgb: 0xFF8FA8), opacity: 0.55)
        part(&c, k, 6.2, 6.1, 0.9, 0.5, Color(rgb: 0xFF8FA8), opacity: 0.55)
        if furious {
            // A cross mark, top right of the head.
            for m in [(6.9, 2.75, 0.18, 0.5), (6.9, 3.65, 0.18, 0.5), (6.35, 3.31, 0.5, 0.18), (7.25, 3.31, 0.5, 0.18)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                part(&c, k, m.0, m.1, m.2, m.3, Color(rgb: 0xE5383B))
            }
            // Shouting.
            if kind != .chick {
                part(&c, k, 4.35, 6.1, 1.3, 1.05, ink) { c, rect in
                    c.fill(Path(roundedRect: CGRect(x: rect.minX + 0.3 * k, y: rect.minY + 0.55 * k, width: 0.7 * k, height: 0.4 * k),
                                cornerRadius: 0.2 * k), with: .color(Color(rgb: 0xE5484D)))
                }
            }
        }
        // A beak for the chick, a mouth for the rest.
        if kind == .chick {
            part(&c, k, 4.55, 5.85, 0.9, 0.9, Color(rgb: 0xF39A3B), rotation: 45, radius: k * 0.15)
        } else if !furious {
            let l: [CGFloat]
            switch face {
            case .smile, .furious: l = [4.3, 6.4, 7.0, 5.7]
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
