import McFlyKit
import SwiftUI

// Scoop Shop's parlour, the display's (ScoopAwning.qml, ScoopStock.qml and
// ScoopShop.qml's wall, tiles and colours), all shapes and all McFly's own:
// candy-striped wallpaper, a scalloped awning with the shop's plaque,
// subway tiles behind the prep bench, and the stock the buttons show.
// Each piece takes only its size and colours, so it draws once and not on
// every tick of the shift's clock.

/// The shop's colours: a parlour by day, the same one lit in the evening
/// (Night and Dark).
struct ScoopLook: Equatable {
    var wall, wallStripe, awning, awningBetween, awningFrame: Int
    var rail, marble, vein, lip, lipEdge: Int
    var tile, grout, board, boardFrame: Int
    var caseBody, pane, shelf, item, plaque, plaqueInk: Int

    static let day = ScoopLook(wall: 0xFFF3EE, wallStripe: 0xFCE2EB, awning: 0xF28DB2, awningBetween: 0xFFFFFF, awningFrame: 0xD65C8A,
                               rail: 0xA8B1BA, marble: 0xF7F3EE, vein: 0xE6DFD5, lip: 0x7CCBB3, lipEdge: 0x5DB59B,
                               tile: 0xFFFFFF, grout: 0xEEE8E1, board: 0x2E3D36, boardFrame: 0xB08257,
                               caseBody: 0xD3EBF2, pane: 0xF1FAFC, shelf: 0xC9965F, item: 0xFFF8EE, plaque: 0xFFFBF2, plaqueInk: 0xC2457A)
    static let evening = ScoopLook(wall: 0x2E2538, wallStripe: 0x382C45, awning: 0xC9557F, awningBetween: 0xEADDE4, awningFrame: 0x83375A,
                                   rail: 0x8E98A4, marble: 0x4C4852, vein: 0x5D5865, lip: 0x3D7A69, lipEdge: 0x2C5E50,
                                   tile: 0x2D2C33, grout: 0x1E1D22, board: 0x22302A, boardFrame: 0x8C6A48,
                                   caseBody: 0x1F343D, pane: 0x1A2B33, shelf: 0x7A5A3E, item: 0x2B2622, plaque: 0xF4ECDF, plaqueInk: 0xA8335F)

    static func of(dark: Bool) -> ScoopLook { dark ? evening : day }
}

/// Tickets are paper, light in both themes, so their inks are fixed.
enum ScoopPaper {
    static let sheet = Color(rgb: 0xFFFBF2), shade = Color(rgb: 0xEFE5D1), ink = Color(rgb: 0x3B3530), faint = Color(rgb: 0x9A9087)
    static let good = Color(rgb: 0x2E9D68), wait = Color(rgb: 0xE39A2D), bad = Color(rgb: 0xC9381F)
}

/// A button behind the counter: a cone or cup, a flavour, a topping, or undo.
enum ScoopKey: Hashable {
    case base(ScoopBase), flavour(ScoopFlavour), topping(ScoopTopping), undo

    var name: String {
        switch self {
        case .base(let b): return b.name
        case .flavour(let f): return f.name
        case .topping(let t): return t.name
        case .undo: return "Undo"
        }
    }
}

// The menu's names, as the display has them.
extension ScoopBase {
    var name: String { self == .cone ? "Cone" : "Cup" }
}

extension ScoopFlavour {
    var name: String { self == .cookies ? "Cookies & cream" : rawValue.capitalized }
}

extension ScoopTopping {
    var name: String {
        switch self {
        case .syrup: return "Choc syrup"
        case .crunch: return "Crunch coat"
        case .rings: return "Fruit rings"
        case .cream: return "Whipped cream"
        default: return rawValue.capitalized
        }
    }
}

// MARK: The wall

/// The shop's wall: candy stripes, plain at the rounded ends.
struct ScoopWallpaper: View, Equatable {
    let look: ScoopLook
    var radius: CGFloat
    /// About how wide a stripe is.
    var stripe: CGFloat = 34

    var body: some View {
        Canvas { ctx, size in
            let r = min(radius, size.width / 2, size.height / 2)
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r, style: .continuous), with: .color(Color(rgb: look.wall)))
            let inner = size.width - 2 * r
            let stripes = max(1, Int(inner / stripe))
            let w = inner / CGFloat(stripes)
            for i in 0..<(stripes / 2) {
                ctx.fill(Path(CGRect(x: r + (2 * CGFloat(i) + 0.5) * w, y: 0, width: w, height: size.height)), with: .color(Color(rgb: look.wallStripe)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The awning: stripes in two colours across the top, each ending in a
/// scallop, under a frame. With `sign` and room for it, the shop's name
/// hangs on a plaque in the middle.
struct ScoopAwning: View, Equatable {
    let look: ScoopLook
    var sign = ""
    var stripeWidth: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            Canvas { ctx, size in
                let count = max(2, Int((size.width / stripeWidth).rounded()))
                let step = size.width / CGFloat(count)
                let scallop = min(step / 2, h * 0.3)
                for i in 0..<count {
                    let tone = Color(rgb: i % 2 == 1 ? look.awningBetween : look.awning)
                    let x = CGFloat(i) * step
                    ctx.fill(Path(CGRect(x: x, y: 0, width: step + 0.5, height: h - scallop)), with: .color(tone))
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: h - 2 * scallop, width: step, height: 2 * scallop), cornerRadius: scallop),
                             with: .color(tone))
                }
                let frame = max(3, h * 0.12)
                // A fold of shade where the stripes turn down.
                ctx.fill(Path(CGRect(x: 0, y: frame, width: size.width, height: max(2, h * 0.12))), with: .color(.black.opacity(0.06)))
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: frame), cornerRadius: frame / 2),
                         with: .color(Color(rgb: look.awningFrame)))
            }
            if !sign.isEmpty && h >= 28 {
                let ph = h * 0.62
                Text(sign)
                    .font(.system(size: max(11, ph * 0.5), weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color(rgb: look.plaqueInk))
                    .lineLimit(1)
                    .padding(.horizontal, h * 0.4)
                    .frame(height: ph)
                    .background(Capsule().fill(Color(rgb: look.plaque)))
                    .overlay(Capsule().strokeBorder(Color(rgb: look.awningFrame), lineWidth: max(2, ph * 0.08)))
                    .frame(width: geo.size.width)
                    .offset(y: h * 0.2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(sign)
        .accessibilityHidden(sign.isEmpty)
    }
}

/// Subway tiles, staggered row by row, behind the prep bench.
struct ScoopTiles: View, Equatable {
    let look: ScoopLook
    var tileHeight: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let th = tileHeight, tw = th * 2
            let rows = Int((size.height / th).rounded(.up))
            let columns = Int((size.width / tw).rounded(.up)) + 1
            var tiles = Path()
            for row in 0..<max(0, rows) {
                for i in 0..<columns {
                    let x = CGFloat(i) * tw - (row % 2 == 1 ? tw / 2 : 0) + 1
                    tiles.addRoundedRect(in: CGRect(x: x, y: CGFloat(row) * th + 1, width: tw - 2, height: th - 2),
                                         cornerSize: CGSize(width: 2, height: 2))
                }
            }
            ctx.fill(tiles, with: .color(Color(rgb: look.tile)))
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: The stock

/// What a button shows: a tub of a flavour in the freezer case, a stack of
/// cones or of cups, a jar of a topping (a squeeze bottle of syrup, a bowl
/// of whipped cream). Drawn in a square that fits the box, standing on its
/// bottom edge.
struct ScoopStockView: View, Equatable {
    let key: ScoopKey
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            Self.draw(&ctx, key, in: CGRect(origin: .zero, size: size), dark: dark)
        }
        .accessibilityHidden(true)
    }

    private static let lids: [ScoopTopping: Int] = [.sprinkles: 0xF28DB2, .cherry: 0x4E9D5B, .wafer: 0xE8BC74, .crunch: 0xB9793A, .rings: 0x9B6BD8]

    static func draw(_ ctx: inout GraphicsContext, _ key: ScoopKey, in rect: CGRect, dark: Bool) {
        let s = min(rect.width, rect.height)
        guard s > 0 else { return }
        var c = ctx
        c.translateBy(x: rect.midX - s / 2, y: rect.maxY - s)
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }
        let hair = max(1, s * 0.015)

        switch key {
        case .flavour(let flavour):
            // A tub: a steel pan of the flavour, a scoop rolled on top.
            let f = ScoopTreatView.flavours[flavour]!
            let ice = box(0.12, 0.36, 0.76, 0.34)
            part(&c, 1, ice.minX, ice.minY, ice.width, ice.height, Color(rgb: f.fill),
                 border: max(1, s * 0.02), edge: ScoopTreatView.rim(flavour, dark: dark)) { c, r in
                for bit in [(0.22, 0.3, 20.0), (0.55, 0.22, -30.0), (0.72, 0.45, 50.0)] {
                    let w = r.width * (flavour == .vanilla ? 0.04 : 0.07)
                    part(&c, 1, r.minX + r.width * bit.0, r.minY + r.height * bit.1, w, w * 0.75, Color(rgb: f.bits), rotation: bit.2,
                         radius: f.round ? w / 2 : w / 3, opacity: flavour == .chocolate ? 0.55 : 0.9)
                }
            }
            ScoopTreatView.draw(&c, ScoopOrder(scoops: [flavour]), in: box(0.36, 0.08, 0.44, 0.42), units: 3.0, dark: dark)
            // The pan, in front of the ice cream.
            c.fill(Path(roundedRect: box(0.04, 0.56, 0.92, 0.08), cornerRadius: 0.04 * s), with: .color(Color(rgb: dark ? 0xC7D0D8 : 0xDCE3E9)))
            let pan = box(0.08, 0.62, 0.84, 0.34)
            c.fill(Path(roundedRect: pan, cornerRadius: 0.05 * s),
                   with: .linearGradient(Gradient(colors: dark ? [Color(rgb: 0xA9B4BE), Color(rgb: 0x7E8A95)] : [Color(rgb: 0xC3CCD4), Color(rgb: 0x98A4AF)]),
                                         startPoint: CGPoint(x: 0, y: pan.minY), endPoint: CGPoint(x: 0, y: pan.maxY)))
            c.fill(Path(CGRect(x: pan.minX + pan.width * 0.06, y: pan.minY + pan.height * 0.18, width: pan.width * 0.88, height: max(1, pan.height * 0.06))),
                   with: .color(.white.opacity(0.45)))

        case .base(let base):
            // A stack of cones, or of cups, one in another: the top one first.
            for index in 0..<3 {
                ScoopTreatView.draw(&c, ScoopOrder(base: base), in: box(0, 0, 1, 1), units: base == .cone ? 6.4 : 5.6,
                                    lift: 0.15 + CGFloat(2 - index) * (base == .cone ? 0.85 : 0.7), dark: dark)
            }

        case .topping(.syrup):
            // A squeeze bottle of chocolate syrup.
            part(&c, s, 0.47, 0.1, 0.06, 0.16, Color(rgb: 0xD8263C))
            part(&c, s, 0.38, 0.22, 0.24, 0.13, Color(rgb: 0xD8263C), radius: 0.04 * s, border: hair, edge: Color(rgb: 0x9E1428))
            part(&c, s, 0.3, 0.33, 0.4, 0.63, Color(rgb: 0x5A2E1A), radius: 0.1 * s, border: hair, edge: Color(rgb: dark ? 0xA0705A : 0x3A1C0F)) { c, r in
                let label = CGRect(x: r.minX, y: r.minY + r.height * 0.34, width: r.width, height: r.height * 0.3)
                c.fill(Path(label), with: .color(Color(rgb: 0xF6E2C0)))
                c.fill(Path(roundedRect: CGRect(x: label.midX - label.width * 0.18, y: label.midY - label.height * 0.25,
                                                width: label.width * 0.36, height: label.height * 0.5), cornerRadius: label.height * 0.25),
                       with: .color(Color(rgb: 0x5A2E1A)))
                part(&c, 1, r.minX + r.width * 0.14, r.minY + r.height * 0.06, r.width * 0.12, r.height * 0.24, .white, opacity: 0.4)
            }

        case .topping(.cream):
            // A bowl of whipped cream.
            for (i, t) in [(0.18, 0.5, 0.64, 0.2), (0.26, 0.38, 0.48, 0.17), (0.35, 0.28, 0.3, 0.14), (0.45, 0.2, 0.12, 0.12)].enumerated() {
                part(&c, s, t.0, t.1, t.2, t.3, .white, rotation: i == 3 ? 20 : 0, border: hair, edge: Color(rgb: dark ? 0xE8E2DA : 0xD8D0C4))
            }
            let bowl = box(0.12, 0.62, 0.76, 0.32)
            let top = 0.04 * s, bottom = min(bowl.height * 0.9, bowl.height - top)
            let shape = Path(roundedRect: bowl, cornerRadii: RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top))
            c.fill(shape, with: .color(Color(rgb: dark ? 0x6E9DB6 : 0xBFE0F2)))
            c.stroke(Path(roundedRect: bowl.insetBy(dx: hair / 2, dy: hair / 2),
                          cornerRadii: RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top)),
                     with: .color(Color(rgb: dark ? 0x9CC4D8 : 0x8FC1DC)), lineWidth: hair)
            part(&c, 1, bowl.minX + bowl.width * 0.1, bowl.minY + bowl.height * 0.18, bowl.width * 0.5, max(1, bowl.height * 0.1), .white, opacity: 0.6)

        case .topping(let topping):
            // A jar: what's in it, the glass over that, a lid.
            switch topping {
            case .wafer:
                // Wafers stand up out of an open jar.
                for w in [(0.34, -8.0), (0.47, 4.0), (0.58, 12.0)] {
                    part(&c, s, w.0, 0.1, 0.1, 0.62, Color(rgb: 0xE8BC74), rotation: w.1, radius: 0.025 * s, border: hair, edge: Color(rgb: 0xB98A42)) { c, r in
                        for i in 0..<4 {
                            c.fill(Path(CGRect(x: r.minX + r.width * 0.15, y: r.minY + r.height * (0.15 + CGFloat(i) * 0.18),
                                               width: r.width * 0.7, height: max(1, s * 0.012))), with: .color(Color(rgb: 0xB98A42)))
                        }
                    }
                }
            case .sprinkles:
                let bits: [(CGFloat, CGFloat, Double, Int)] = [
                    (0.30, 0.62, 20, 0xE5484D), (0.45, 0.70, -40, 0x5B8DEF), (0.60, 0.60, 70, 0xF2B84B), (0.36, 0.80, -10, 0x3DB37A),
                    (0.55, 0.84, 35, 0x8E7CE6), (0.66, 0.74, -60, 0xE5484D), (0.28, 0.72, 80, 0xF2B84B), (0.48, 0.58, -70, 0x3DB37A),
                    (0.40, 0.90, 15, 0x5B8DEF), (0.62, 0.90, -25, 0xFFFFFF), (0.52, 0.77, 55, 0xF28DB2), (0.33, 0.52, -30, 0x8E7CE6),
                ]
                for b in bits { part(&c, 1, b.0 * s, b.1 * s, 0.1 * s, max(2, 0.035 * s), Color(rgb: b.3), rotation: b.2) }
            case .cherry:
                for p in [(0.30, 0.72), (0.50, 0.74), (0.40, 0.56), (0.58, 0.58)] as [(CGFloat, CGFloat)] {
                    part(&c, s, p.0, p.1, 0.18, 0.18, Color(rgb: 0xD8263C), border: hair, edge: Color(rgb: 0x9E1428)) { c, r in
                        c.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.18, width: r.width * 0.28, height: r.width * 0.28)),
                               with: .color(.white.opacity(0.6)))
                    }
                }
            case .crunch:
                let crumbs: [(CGFloat, CGFloat, Double, Int)] = [
                    (0.28, 0.66, 20, 0xF0BE62), (0.42, 0.74, -30, 0x8E5726), (0.56, 0.62, 45, 0xE3A94F), (0.34, 0.84, -15, 0xE3A94F),
                    (0.5, 0.86, 30, 0xF0BE62), (0.62, 0.78, -40, 0x8E5726), (0.3, 0.55, 60, 0xF7D486), (0.46, 0.52, 10, 0x8E5726),
                    (0.6, 0.5, -60, 0xF0BE62),
                ]
                for b in crumbs { part(&c, s, b.0, b.1, 0.1, 0.08, Color(rgb: b.3), rotation: b.2, radius: 0.025 * s) }
            case .rings:
                let line = max(2, s * 0.045)
                for ring in [(0.27, 0.74, 0xE5484D), (0.45, 0.8, 0xF2CF3B), (0.6, 0.72, 0x4DBF6A),
                             (0.34, 0.58, 0x9B6BD8), (0.52, 0.6, 0xF59A2F), (0.42, 0.44, 0xE5484D)] as [(CGFloat, CGFloat, Int)] {
                    c.stroke(Path(ellipseIn: box(ring.0, ring.1, 0.15, 0.15).insetBy(dx: line / 2, dy: line / 2)), with: .color(Color(rgb: ring.2)), lineWidth: line)
                }
            default:
                break
            }
            // The glass.
            part(&c, s, 0.2, 0.36, 0.6, 0.6, .white.opacity(dark ? 0.14 : 0.32), radius: 0.1 * s,
                 border: max(1, s * 0.025), edge: Color(rgb: dark ? 0x9FB0BE : 0xB9C6D1)) { c, r in
                part(&c, 1, r.minX + r.width * 0.12, r.minY + r.height * 0.12, r.width * 0.1, r.height * 0.62, .white, opacity: dark ? 0.35 : 0.7)
            }
            if topping != .wafer, let lid = lids[topping] {
                part(&c, s, 0.16, 0.27, 0.68, 0.11, Color(rgb: lid), radius: 0.04 * s, border: hair, edge: Color(rgb: lid, scaled: 1 / 1.25))
            }

        case .undo:
            break
        }
    }
}
