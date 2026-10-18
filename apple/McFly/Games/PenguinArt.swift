import CoreGraphics
import McFlyKit
import SwiftUI

// Penguin March's pictures, the display's (display/src/games/PenguinArt.cpp)
// drawn with Core Graphics: the terrain (ground, which digging cuts, and
// rock, which it never does), the penguins in each pose, the hatch, the
// igloo and the water. All of it our own drawing. Drawing happens in world
// pixels in a y-down space, as on the display.

private func cg(_ rgb: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
}

private func cg(_ rgb: Int, darker factor: CGFloat) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255 / factor, green: CGFloat((rgb >> 8) & 0xFF) / 255 / factor,
            blue: CGFloat(rgb & 0xFF) / 255 / factor, alpha: 1)
}

/// Daylight, or the night scene for dark mode (the penguins keep a light rim
/// so they read on a dark sky).
struct PenguinPalette {
    var iceTop, iceBottom, snow, iceShade, speck: CGColor
    var rock, rockTop, rockShade: CGColor
    var plank = cg(0xC98B4E), plankTop = cg(0xE8B47A), plankShade = cg(0x94612F)
    var body = cg(0x28324A), rim: CGColor, belly = cg(0xFFFFFF), beak = cg(0xF5A524), eye = cg(0x121823)
    var blush = cg(0xF28C96, 150 / 255)
    var water, waterDeep, crest: CGColor
    var igloo: CGColor, iglooLine: CGColor, iglooArch: CGColor, door: CGColor, flag = cg(0xF07F5A)
    var hatch, hatchLine, hatchDoor: CGColor
    var snowDim: CGColor
    let dark: Bool

    /// The skills' colours, the same on their buttons.
    static let skillColors: [PenguinSkill: Int] = [.block: 0xE5484D, .dig: 0xE0912A, .bash: 0x8E7CE6, .build: 0x3DB37A, .float: 0x4F7CF7]
    func skill(_ s: PenguinSkill) -> CGColor { cg(Self.skillColors[s]!) }

    static func sky(dark: Bool) -> [Color] {
        dark ? [Color(rgb: 0x0B1424), Color(rgb: 0x1D2C47)] : [Color(rgb: 0xB9DCF3), Color(rgb: 0xEDF6FC)]
    }

    init(dark: Bool) {
        self.dark = dark
        if !dark {
            iceTop = cg(0xD6EAF8); iceBottom = cg(0x86B3D9); snow = cg(0xFFFFFF); iceShade = cg(0x6A97C2)
            speck = cg(0xFFFFFF, 120 / 255)
            rock = cg(0x7D8798); rockTop = cg(0xA9B2C0); rockShade = cg(0x5D6677)
            water = CGColor(srgbRed: 46 / 255, green: 128 / 255, blue: 190 / 255, alpha: 225 / 255)
            waterDeep = CGColor(srgbRed: 24 / 255, green: 78 / 255, blue: 132 / 255, alpha: 240 / 255)
            crest = cg(0xBFE6FA)
            igloo = cg(0xF4F9FD); iglooLine = cg(0xA9C7E2); iglooArch = cg(0xF4F9FD, darker: 1.06); door = cg(0x24364F)
            hatch = cg(0x5E7391); hatchLine = cg(0x3E4F68); hatchDoor = cg(0x2B3A50)
            rim = cg(0x121823)
            snowDim = cg(0xFFFFFF, darker: 1.08)
        } else {
            iceTop = cg(0xA9C6DE); iceBottom = cg(0x3F6489); snow = cg(0xE4EEF7); iceShade = cg(0x2C4B6C)
            speck = cg(0xFFFFFF, 70 / 255)
            rock = cg(0x5D6574); rockTop = cg(0x868F9E); rockShade = cg(0x41485A)
            water = CGColor(srgbRed: 38 / 255, green: 104 / 255, blue: 160 / 255, alpha: 225 / 255)
            waterDeep = CGColor(srgbRed: 16 / 255, green: 52 / 255, blue: 92 / 255, alpha: 240 / 255)
            crest = cg(0x8FCBEA)
            igloo = cg(0xDCE8F3); iglooLine = cg(0x8DA9C4); iglooArch = cg(0xDCE8F3, darker: 1.06); door = cg(0x0E1828)
            hatch = cg(0x4C5F7C); hatchLine = cg(0x2E3B50); hatchDoor = cg(0x1E2838)
            rim = cg(0x9FB2D2) // a light rim reads on the night sky
            snowDim = cg(0xE4EEF7, darker: 1.08)
        }
    }
}

/// A small, fixed scatter (no randomness: the same picture every time).
private func scatter(_ v: UInt32) -> UInt32 {
    var x = v
    x ^= x >> 16
    x = x &* 0x7FEB_352D
    x ^= x >> 15
    x = x &* 0x846C_A68B
    x ^= x >> 16
    return x
}

private func bitmap(_ width: Int, _ height: Int) -> CGContext? {
    CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
}

/// Runs `draw` with world pixels, y down, on a bitmap whose own space is
/// device pixels, y up.
private func inWorld(_ ctx: CGContext, px: CGFloat, _ draw: (CGContext) -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(ctx.height))
    ctx.scaleBy(x: px, y: -px)
    draw(ctx)
    ctx.restoreGState()
}

private func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
    CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)
}

/// Points along an ellipse between two angles (radians, y down).
private func arc(_ path: CGMutablePath, _ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat, from a0: CGFloat, to a1: CGFloat, steps: Int = 16) {
    for i in 1...steps {
        let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
        path.addLine(to: CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a)))
    }
}

// MARK: Terrain

/// A level's terrain as pictures: rock, which never changes, and ground,
/// which digs and bricks are painted onto as they happen.
final class PenguinTerrain {
    let px: CGFloat
    let dark: Bool
    let generation: Int
    let rock: CGImage?
    private(set) var ground: CGImage?
    private let groundLayer: CGContext?
    private let palette: PenguinPalette
    private(set) var painted = 0

    init(sim: PenguinSim, px: CGFloat, dark: Bool) {
        self.px = px
        self.dark = dark
        generation = sim.generation
        palette = PenguinPalette(dark: dark)
        let level = sim.level
        let w = Int((CGFloat(level.width) * px).rounded(.up)), h = Int((CGFloat(level.height) * px).rounded(.up))
        let g = bitmap(w, h), r = bitmap(w, h)
        groundLayer = g
        guard let g, let r else {
            rock = nil
            return
        }
        let pal = palette
        let colors = [pal.iceTop, pal.iceBottom] as CFArray
        let ice = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
        for shape in level.shapes {
            let path = Self.path(shape)
            switch shape.kind {
            case .ground:
                inWorld(g, px: px) { c in
                    c.addPath(path)
                    c.clip()
                    c.drawLinearGradient(ice, start: .zero, end: CGPoint(x: 0, y: level.height), options: [])
                }
                inWorld(r, px: px) { c in
                    c.setBlendMode(.clear)
                    c.addPath(path)
                    c.fillPath()
                }
            case .steel:
                inWorld(r, px: px) { c in
                    c.setFillColor(pal.rock)
                    c.addPath(path)
                    c.fillPath()
                }
            case .cut:
                for layer in [g, r] {
                    inWorld(layer, px: px) { c in
                        c.setBlendMode(.clear)
                        c.addPath(path)
                        c.fillPath()
                    }
                }
            }
        }
        // Specks of frost in the ice, and seams in the rock: a few small
        // marks on a fixed scatter, kept inside each layer.
        let cols = level.width / 12 + 1, rows = level.height / 12 + 1
        inWorld(g, px: px) { gc in
            inWorld(r, px: px) { rc in
                gc.setBlendMode(.sourceAtop)
                rc.setBlendMode(.sourceAtop)
                gc.setFillColor(pal.speck)
                rc.setStrokeColor(pal.rockShade)
                rc.setLineWidth(0.6)
                rc.setLineCap(.round)
                for j in 0..<rows {
                    for i in 0..<cols {
                        let hv = scatter(UInt32(j * 977 + i * 131 + 7))
                        let x = CGFloat(i * 12) + CGFloat(hv % 12), y = CGFloat(j * 12) + CGFloat((hv >> 8) % 12)
                        let len = 2 + CGFloat((hv >> 16) % 4)
                        gc.fillEllipse(in: ellipse(CGPoint(x: x, y: y), 0.7, 0.7))
                        if (hv >> 20) % 3 == 0 {
                            rc.move(to: CGPoint(x: x, y: y))
                            rc.addLine(to: CGPoint(x: x + len, y: y + CGFloat((hv >> 24) % 3) - 1))
                            rc.strokePath()
                        }
                    }
                }
            }
        }
        // Snow on every top, a darker edge under every overhang; rock's lit top.
        Self.addEdge(g, Int((3 * px).rounded()), pal.snow)
        Self.addEdge(g, -Int((2 * px).rounded()), pal.iceShade, alpha: 200 / 255)
        Self.addEdge(r, Int((2 * px).rounded()), pal.rockTop)
        Self.addEdge(r, -Int((2 * px).rounded()), pal.rockShade)
        rock = r.makeImage()
        ground = g.makeImage()
        apply(sim.edits)
    }

    static func path(_ shape: PenguinShape) -> CGPath {
        if shape.ellipse {
            let b = shape.bounds
            return CGPath(ellipseIn: CGRect(x: b.x, y: b.y, width: b.width - 1, height: b.height - 1), transform: nil)
        }
        let path = CGMutablePath()
        path.addLines(between: shape.points.map { CGPoint(x: $0.x, y: $0.y) })
        path.closeSubpath()
        return path
    }

    /// A band along the top (snow, rock's lit edge) or under overhangs: where
    /// the layer has something and the pixel `offset` above (below, if
    /// negative) is empty. In device pixels, y up.
    private static func addEdge(_ layer: CGContext, _ offset: Int, _ color: CGColor, alpha: CGFloat = 1) {
        guard let image = layer.makeImage(), let band = bitmap(layer.width, layer.height) else { return }
        let full = CGRect(x: 0, y: 0, width: layer.width, height: layer.height)
        band.draw(image, in: full)
        band.setBlendMode(.sourceIn)
        band.setFillColor(color.copy(alpha: alpha) ?? color)
        band.fill(full)
        band.setBlendMode(.destinationOut)
        // Shifted down on screen by `offset`: down is minus y here.
        band.draw(image, in: full.offsetBy(dx: 0, dy: -CGFloat(offset)))
        guard let edge = band.makeImage() else { return }
        layer.saveGState()
        layer.setBlendMode(.sourceAtop)
        layer.draw(edge, in: full)
        layer.restoreGState()
    }

    /// Paints the edits made since the last call (a cut, a brick); true if
    /// any were.
    @discardableResult
    func apply(_ edits: [PenguinEdit]) -> Bool {
        guard let g = groundLayer, painted < edits.count else { return false }
        let pal = palette
        inWorld(g, px: px) { c in
            for edit in edits[painted...] {
                let r = CGRect(x: edit.rect.x, y: edit.rect.y, width: edit.rect.width, height: edit.rect.height)
                switch edit.kind {
                case .cut:
                    c.setBlendMode(.clear)
                    c.fill(r)
                    c.setBlendMode(.normal)
                case .brick:
                    // A plank: lit along the top, shaded under.
                    c.setFillColor(pal.plank)
                    c.addPath(CGPath(roundedRect: r, cornerWidth: 0.5, cornerHeight: 0.5, transform: nil))
                    c.fillPath()
                    c.setFillColor(pal.plankTop)
                    c.fill(CGRect(x: r.minX + 0.3, y: r.minY, width: r.width - 0.6, height: 0.6))
                    c.setFillColor(pal.plankShade)
                    c.fill(CGRect(x: r.minX + 0.3, y: r.maxY - 0.5, width: r.width - 0.6, height: 0.5))
                }
            }
        }
        painted = edits.count
        ground = g.makeImage()
        return true
    }
}

/// The water in `rect`, world pixels: a wavy surface with a crest (rising 2
/// px above it) and a few glints. The picture starts 2 px above the rect.
func paintPenguinWater(_ rect: PenguinRect, px: CGFloat, dark: Bool) -> CGImage? {
    let pal = PenguinPalette(dark: dark)
    guard let ctx = bitmap(Int((CGFloat(rect.width) * px).rounded(.up)), Int((CGFloat(rect.height + 2) * px).rounded(.up))) else { return nil }
    inWorld(ctx, px: px) { w in
        w.translateBy(x: 0, y: 2) // the crest rises above the surface
        let width = CGFloat(rect.width), height = CGFloat(rect.height)
        func wave(_ path: CGMutablePath) {
            path.move(to: .zero)
            var x: CGFloat = 0
            while x <= width {
                path.addQuadCurve(to: CGPoint(x: x + 3, y: 0), control: CGPoint(x: x + 1.5, y: -1.6))
                path.addQuadCurve(to: CGPoint(x: x + 6, y: 0), control: CGPoint(x: x + 4.5, y: 1.2))
                x += 6
            }
        }
        let body = CGMutablePath()
        wave(body)
        body.addLine(to: CGPoint(x: width, y: height))
        body.addLine(to: CGPoint(x: 0, y: height))
        body.closeSubpath()
        w.clip(to: CGRect(x: 0, y: -2, width: width, height: height + 2))
        w.saveGState()
        w.addPath(body)
        w.clip()
        let deep = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [pal.water, pal.waterDeep] as CFArray, locations: [0, 1])!
        w.drawLinearGradient(deep, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        w.restoreGState()
        let crest = CGMutablePath()
        wave(crest)
        w.addPath(crest)
        w.setStrokeColor(pal.crest)
        w.setLineWidth(1)
        w.setLineCap(.round)
        w.strokePath()
        // A few glints.
        w.setStrokeColor(CGColor(gray: 1, alpha: 90 / 255))
        w.setLineWidth(0.7)
        for i in 0..<(rect.width / 22) {
            let hv = scatter(UInt32(i * 53 + rect.x))
            let x = CGFloat(i * 22) + CGFloat(hv % 14)
            let y = 4 + CGFloat(Int(hv >> 8) % max(1, rect.height - 6))
            w.move(to: CGPoint(x: x, y: y))
            w.addLine(to: CGPoint(x: x + 3, y: y))
            w.strokePath()
        }
    }
    return ctx.makeImage()
}

// MARK: Penguins

/// A penguin's frame: a cell of 28 × 28 world pixels with the feet at
/// (14, 26). Frames 0 ..< 31 face right; 31 ..< 62 are the same mirrored.
enum PenguinFrames {
    static let cell: CGFloat = 28
    static let footX: CGFloat = 14
    static let ground: CGFloat = 26
    static let count = 31

    static let walk = 0, walkUmbrella = 4, fall = 8, float = 10, block = 12, dig = 14, bash = 18, build = 22
    static let splat = 24, drown = 27, exit = 29

    /// The frame to show for a penguin, facing its way; nil for none.
    static func frame(for p: Penguin, tick: Int) -> Int? {
        let f: Int
        switch p.state {
        case .walking: f = (p.floater ? walkUmbrella : walk) + ((p.x >> 1) & 3)
        case .falling: f = fall + ((tick >> 1) & 1)
        case .floating: f = float + ((tick >> 3) & 1)
        case .blocking: f = block + ((tick >> 4) & 1)
        case .digging: f = dig + ((tick >> 1) & 3)
        case .bashing: f = bash + min(3, ((p.timer - 1) % Penguins.bashPeriod) * 4 / Penguins.bashPeriod + ((tick >> 2) & 1))
        case .building: f = build + (((p.timer - 1) % Penguins.buildPeriod) * 2 >= Penguins.buildPeriod ? 1 : 0)
        case .splatting: f = splat + min(2, p.timer * 3 / Penguins.splatTicks)
        case .drowning: f = drown + ((p.timer >> 2) & 1)
        case .exiting: f = exit + ((p.timer >> 2) & 1)
        case .saved, .lost: return nil
        }
        // Facing us (blocking, digging, waving at the door): no left or right.
        let front = (f >= block && f < bash) || f >= exit
        return !front && p.dir < 0 ? f + count : f
    }

    /// A picture of each skill, for its button.
    static func frame(for skill: PenguinSkill) -> Int {
        switch skill {
        case .block: return block
        case .dig: return dig + 1
        case .bash: return bash + 2
        case .build: return build + 1
        case .float: return float
        }
    }

    private struct Pose {
        var front = false
        var tilt: CGFloat = 0           // degrees, about the feet
        var lift: CGFloat = 0           // the body raised (+) or sunk (-)
        var flipper: CGFloat = 12       // side: degrees forward from hanging down
        var left: CGFloat = 20, right: CGFloat = 20 // front: each flipper, degrees out from hanging
        var footA: CGFloat = 0, footB: CGFloat = 0
        var squash: CGFloat = 1         // < 1 flattens (a hard landing)
    }

    private static func rad(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    private static func flipper(_ c: CGContext, _ pivot: CGPoint, _ angle: CGFloat, _ pal: PenguinPalette, length: CGFloat = 5) {
        c.saveGState()
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: rad(angle))
        let r = CGRect(x: -1.5, y: -0.6, width: 3.0, height: length)
        c.setFillColor(pal.body)
        c.fillEllipse(in: r)
        c.setStrokeColor(pal.rim)
        c.setLineWidth(0.7)
        c.strokeEllipse(in: r)
        c.restoreGState()
    }

    private static func penguin(_ c: CGContext, _ pose: Pose, _ pal: PenguinPalette) {
        c.saveGState()
        c.translateBy(x: footX, y: ground)
        c.rotate(by: rad(pose.tilt))
        c.scaleBy(x: 1, y: pose.squash)
        c.translateBy(x: -footX, y: -ground - pose.lift)

        // Feet first: the body sits on them.
        c.setFillColor(pal.beak)
        if pose.front {
            c.fillEllipse(in: ellipse(CGPoint(x: 11.4 + pose.footA, y: 25.2), 2.3, 1.05))
            c.fillEllipse(in: ellipse(CGPoint(x: 16.6 + pose.footB, y: 25.2), 2.3, 1.05))
        } else {
            c.fillEllipse(in: ellipse(CGPoint(x: 12.4 + pose.footA, y: 25.2), 2.3, 1.05))
            c.fillEllipse(in: ellipse(CGPoint(x: 15.6 + pose.footB, y: 25.3), 2.3, 1.05))
        }
        let torso = CGPath(ellipseIn: pose.front ? ellipse(CGPoint(x: 14, y: 17.8), 6.2, 7.6) : ellipse(CGPoint(x: 13.4, y: 17.8), 5.5, 7.6), transform: nil)
        let head = CGPath(ellipseIn: pose.front ? ellipse(CGPoint(x: 14, y: 12.0), 4.7, 4.5) : ellipse(CGPoint(x: 14.6, y: 12.2), 4.4, 4.3), transform: nil)
        let body = torso.union(head)
        c.addPath(body)
        c.setFillColor(pal.body)
        c.setStrokeColor(pal.rim)
        c.setLineWidth(0.8)
        c.drawPath(using: .fillStroke)

        // Belly and face.
        c.saveGState()
        c.addPath(body)
        c.clip()
        c.setFillColor(pal.belly)
        if pose.front {
            c.fillEllipse(in: ellipse(CGPoint(x: 14, y: 19.0), 4.4, 6.0))
            c.fillEllipse(in: ellipse(CGPoint(x: 12.4, y: 12.6), 2.1, 2.0))
            c.fillEllipse(in: ellipse(CGPoint(x: 15.6, y: 12.6), 2.1, 2.0))
        } else {
            c.fillEllipse(in: ellipse(CGPoint(x: 15.9, y: 19.2), 3.4, 5.8))
            c.fillEllipse(in: ellipse(CGPoint(x: 16.6, y: 12.4), 2.0, 1.9))
        }
        c.restoreGState()

        func triangle(_ a: CGPoint, _ b: CGPoint, _ d: CGPoint) {
            c.move(to: a)
            c.addLine(to: b)
            c.addLine(to: d)
            c.closePath()
            c.fillPath()
        }
        if pose.front {
            c.setFillColor(pal.eye)
            c.fillEllipse(in: ellipse(CGPoint(x: 12.5, y: 12.2), 0.8, 0.95))
            c.fillEllipse(in: ellipse(CGPoint(x: 15.5, y: 12.2), 0.8, 0.95))
            c.setFillColor(pal.blush)
            c.fillEllipse(in: ellipse(CGPoint(x: 11.2, y: 14.4), 1.0, 0.6))
            c.fillEllipse(in: ellipse(CGPoint(x: 16.8, y: 14.4), 1.0, 0.6))
            c.setFillColor(pal.beak)
            triangle(CGPoint(x: 12.9, y: 13.5), CGPoint(x: 15.1, y: 13.5), CGPoint(x: 14.0, y: 15.4))
            flipper(c, CGPoint(x: 8.4, y: 15.2), pose.left, pal, length: 5.6)
            flipper(c, CGPoint(x: 19.6, y: 15.2), -pose.right, pal, length: 5.6)
        } else {
            c.setFillColor(pal.eye)
            c.fillEllipse(in: ellipse(CGPoint(x: 16.9, y: 11.9), 0.85, 0.95))
            c.setFillColor(pal.blush)
            c.fillEllipse(in: ellipse(CGPoint(x: 16.6, y: 14.3), 1.0, 0.6))
            c.setFillColor(pal.beak)
            triangle(CGPoint(x: 18.4, y: 12.3), CGPoint(x: 21.8, y: 13.3), CGPoint(x: 18.4, y: 14.4))
            flipper(c, CGPoint(x: 12.4, y: 15.2), pose.flipper, pal, length: 5.4)
        }
        c.restoreGState()
    }

    private static func umbrellaOpen(_ c: CGContext, _ sway: CGFloat, _ pal: PenguinPalette) {
        c.saveGState()
        c.translateBy(x: 14, y: 13)
        c.rotate(by: rad(sway))
        c.setStrokeColor(pal.rim)
        c.setLineWidth(0.8)
        c.setLineCap(.round)
        c.move(to: .zero)
        c.addLine(to: CGPoint(x: 0, y: -9))
        c.strokePath()
        let canopy = CGMutablePath()
        canopy.move(to: CGPoint(x: -10, y: -8))
        canopy.addCurve(to: CGPoint(x: 10, y: -8), control1: CGPoint(x: -9, y: -15.5), control2: CGPoint(x: 9, y: -15.5))
        // Scalloped hem.
        for i in 0..<4 {
            let x0 = 10 - CGFloat(i) * 5
            canopy.addQuadCurve(to: CGPoint(x: x0 - 5, y: -8), control: CGPoint(x: x0 - 2.5, y: -10))
        }
        canopy.closeSubpath()
        c.addPath(canopy)
        c.setLineWidth(0.7)
        c.setFillColor(pal.skill(.float))
        c.drawPath(using: .fillStroke)
        c.addPath(canopy)
        c.clip()
        c.setFillColor(CGColor(gray: 1, alpha: 110 / 255))
        c.fillEllipse(in: ellipse(CGPoint(x: -4, y: -11), 1.6, 5))
        c.fillEllipse(in: ellipse(CGPoint(x: 4, y: -11), 1.6, 5))
        c.restoreGState()
    }

    private static func umbrellaFolded(_ c: CGContext, _ pal: PenguinPalette) {
        c.saveGState()
        c.setLineCap(.round)
        c.setStrokeColor(pal.skill(.float))
        c.setLineWidth(1.8)
        c.move(to: CGPoint(x: 9.0, y: 21.5))
        c.addLine(to: CGPoint(x: 7.6, y: 10.0))
        c.strokePath()
        // The hook at the bottom of the handle.
        let hook = CGMutablePath()
        hook.move(to: CGPoint(x: 7.3, y: 21.9))
        arc(hook, CGPoint(x: 8.6, y: 21.9), 1.3, 1.3, from: .pi, to: 0, steps: 8)
        c.addPath(hook)
        c.setStrokeColor(pal.rim)
        c.setLineWidth(0.7)
        c.strokePath()
        c.restoreGState()
    }

    private static func pickaxe(_ c: CGContext, _ angle: CGFloat, _ pal: PenguinPalette) {
        c.saveGState()
        c.translateBy(x: 13.2, y: 16.0)
        c.rotate(by: rad(angle))
        c.setStrokeColor(cg(0x8A5A2B))
        c.setLineWidth(1.1)
        c.setLineCap(.round)
        c.move(to: .zero)
        c.addLine(to: CGPoint(x: 9.5, y: 0))
        c.strokePath()
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 9.5, y: -4.2))
        head.addQuadCurve(to: CGPoint(x: 9.5, y: 4.2), control: CGPoint(x: 11.4, y: 0))
        head.addQuadCurve(to: CGPoint(x: 9.5, y: -4.2), control: CGPoint(x: 10.6, y: 0))
        c.addPath(head)
        c.setStrokeColor(pal.rim)
        c.setLineWidth(0.5)
        c.setFillColor(pal.skill(.bash))
        c.drawPath(using: .fillStroke)
        c.restoreGState()
    }

    private static func shovel(_ c: CGContext, _ drop: CGFloat, _ pal: PenguinPalette) {
        c.saveGState()
        c.translateBy(x: 0, y: drop)
        c.setStrokeColor(cg(0x8A5A2B))
        c.setLineWidth(1.1)
        c.setLineCap(.round)
        c.move(to: CGPoint(x: 14, y: 12.5))
        c.addLine(to: CGPoint(x: 14, y: 21))
        c.strokePath()
        c.addPath(CGPath(roundedRect: CGRect(x: 12.2, y: 20.4, width: 3.6, height: 4.0), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
        c.setStrokeColor(pal.rim)
        c.setLineWidth(0.5)
        c.setFillColor(pal.skill(.dig))
        c.drawPath(using: .fillStroke)
        c.restoreGState()
    }

    private static func plank(_ c: CGContext, _ at: CGPoint, _ pal: PenguinPalette) {
        c.addPath(CGPath(roundedRect: CGRect(x: at.x, y: at.y, width: 8, height: 2), cornerWidth: 0.5, cornerHeight: 0.5, transform: nil))
        c.setStrokeColor(pal.plankShade)
        c.setLineWidth(0.5)
        c.setFillColor(pal.plank)
        c.drawPath(using: .fillStroke)
    }

    private static func chips(_ c: CGContext, _ phase: Int, _ color: CGColor) {
        let up: CGFloat = phase % 2 != 0 ? 3 : 0
        c.setFillColor(color)
        c.fillEllipse(in: ellipse(CGPoint(x: 6.5 - up * 0.3, y: 21 - up), 0.9, 0.9))
        c.fillEllipse(in: ellipse(CGPoint(x: 21.5 + up * 0.3, y: 20 - up), 0.8, 0.8))
        c.fillEllipse(in: ellipse(CGPoint(x: 8.5, y: 18 - up * 1.4), 0.6, 0.6))
    }

    /// One frame (0 ..< 62), drawn in its cell's world pixels (0 ... 28).
    static func draw(_ c: CGContext, frame: Int, _ pal: PenguinPalette) {
        if frame >= count {
            c.saveGState()
            c.translateBy(x: cell, y: 0)
            c.scaleBy(x: -1, y: 1)
            draw(c, frame: frame - count, pal)
            c.restoreGState()
            return
        }
        var pose = Pose()
        if frame < fall {
            let f = frame % 4
            pose.tilt = [-5, 0, 5, 0][f]
            pose.flipper = [22, 10, -4, 10][f]
            pose.lift = f % 2 != 0 ? 0.6 : 0
            pose.footA = f == 0 ? 1.4 : f == 2 ? -0.8 : 0.3
            pose.footB = f == 2 ? 1.4 : f == 0 ? -0.8 : 0.3
            if frame >= walkUmbrella { umbrellaFolded(c, pal) }
            penguin(c, pose, pal)
            return
        }
        switch frame {
        case fall, fall + 1:
            pose.flipper = frame == fall ? 150 : 120
            pose.footA = -0.6
            pose.footB = 0.8
            pose.lift = 0.8
            penguin(c, pose, pal)
        case float, float + 1:
            let sway: CGFloat = frame == float ? -5 : 5
            umbrellaOpen(c, sway, pal)
            pose.flipper = 175
            pose.tilt = sway * 0.4
            pose.lift = 0.5
            penguin(c, pose, pal)
        case block, block + 1:
            pose.front = true
            pose.left = frame == block ? 82 : 96
            pose.right = pose.left
            pose.footA = -0.8
            pose.footB = 0.8
            penguin(c, pose, pal)
            // A stop band across the chest.
            c.addPath(CGPath(roundedRect: CGRect(x: 9.6, y: 16.2, width: 8.8, height: 1.8), cornerWidth: 0.9, cornerHeight: 0.9, transform: nil))
            c.setFillColor(pal.skill(.block))
            c.fillPath()
        case dig..<(dig + 4):
            let f = frame - dig
            pose.front = true
            pose.lift = f % 2 != 0 ? -0.6 : 0
            pose.left = f % 2 != 0 ? 6 : 24
            pose.right = pose.left
            penguin(c, pose, pal)
            shovel(c, f % 2 != 0 ? 1.6 : -1.0, pal)
            chips(c, f, pal.snowDim)
        case bash..<(bash + 4):
            let swing: [CGFloat] = [-120, -60, 0, 30]
            let f = frame - bash
            pose.flipper = 80 + swing[f] * 0.4
            pose.tilt = f >= 2 ? 6 : -3
            penguin(c, pose, pal)
            pickaxe(c, swing[f], pal)
            if f == 2 { chips(c, 1, pal.snowDim) }
        case build, build + 1:
            pose.flipper = frame == build ? 70 : 40
            pose.tilt = frame == build ? 0 : 7
            penguin(c, pose, pal)
            plank(c, frame == build ? CGPoint(x: 15.5, y: 14.5) : CGPoint(x: 17.0, y: 23.0), pal)
        case splat, splat + 1:
            pose.squash = frame == splat ? 0.5 : 0.28
            pose.flipper = 90
            pose.footA = -2
            pose.footB = 2
            penguin(c, pose, pal)
            c.setFillColor(cg(0xF6B94A))
            for i in 0..<3 {
                c.fillEllipse(in: ellipse(CGPoint(x: 9 + CGFloat(i) * 5, y: frame == splat ? 15 : 13), 0.9, 0.9))
            }
        case splat + 2:
            c.setFillColor(CGColor(gray: 1, alpha: 220 / 255))
            c.fillEllipse(in: ellipse(CGPoint(x: 10, y: 22), 3.4, 3.0))
            c.fillEllipse(in: ellipse(CGPoint(x: 15, y: 20.5), 4.2, 3.8))
            c.fillEllipse(in: ellipse(CGPoint(x: 19.5, y: 22.5), 3.0, 2.6))
            c.setFillColor(CGColor(gray: 1, alpha: 140 / 255))
            c.fillEllipse(in: ellipse(CGPoint(x: 13, y: 16), 1.8, 1.8))
            c.fillEllipse(in: ellipse(CGPoint(x: 18, y: 15.5), 1.2, 1.2))
        case drown, drown + 1:
            pose.lift = frame == drown ? -6 : -10
            pose.flipper = frame == drown ? 160 : 130
            penguin(c, pose, pal)
            c.setFillColor(pal.crest)
            c.fillEllipse(in: ellipse(CGPoint(x: 7, y: frame == drown ? 18 : 20), 0.9, 0.9))
            c.fillEllipse(in: ellipse(CGPoint(x: 21, y: frame == drown ? 17 : 19), 0.9, 0.9))
        case exit, exit + 1:
            pose.front = true
            pose.left = 18
            pose.right = frame == exit ? 160 : 125
            penguin(c, pose, pal)
        default:
            break
        }
    }
}

// MARK: The igloo and the hatch

enum PenguinProps {
    /// The igloo: 48 × 40 world pixels, its door at (24, 40).
    static let iglooSize = CGSize(width: 48, height: 40)
    static let iglooAnchor = CGPoint(x: 24, y: 40)
    /// The hatch: 40 × 30, the drop point at (20, 18).
    static let hatchSize = CGSize(width: 40, height: 30)
    static let hatchAnchor = CGPoint(x: 20, y: 18)

    static func igloo(_ p: CGContext, _ pal: PenguinPalette) {
        // A pennant on a pole.
        p.setLineCap(.round)
        p.setStrokeColor(pal.rim)
        p.setLineWidth(0.8)
        p.move(to: CGPoint(x: 31, y: 14))
        p.addLine(to: CGPoint(x: 31, y: 1.5))
        p.strokePath()
        p.setFillColor(pal.flag)
        p.move(to: CGPoint(x: 31.3, y: 1.5))
        p.addLine(to: CGPoint(x: 38.5, y: 4))
        p.addLine(to: CGPoint(x: 31.3, y: 6.5))
        p.closePath()
        p.fillPath()

        // The dome, in courses of snow blocks.
        let dome = CGPath(ellipseIn: CGRect(x: 2, y: 12, width: 44, height: 56), transform: nil)
            .intersection(CGPath(rect: CGRect(x: 0, y: 0, width: 48, height: 40), transform: nil))
        p.addPath(dome)
        p.setFillColor(pal.igloo)
        p.setStrokeColor(pal.iglooLine)
        p.setLineWidth(0.9)
        p.drawPath(using: .fillStroke)
        p.saveGState()
        p.addPath(dome)
        p.clip()
        p.setLineWidth(0.6)
        for row in 0..<4 {
            let y = 19 + CGFloat(row) * 5.5
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: 48, y: y))
            for i in 0..<6 {
                let x = 4 + CGFloat(i) * 8 + (row % 2 != 0 ? 4 : 0)
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x, y: y + 5.5))
            }
        }
        p.strokePath()
        p.restoreGState()

        // The way in.
        let arch = CGMutablePath()
        arch.move(to: CGPoint(x: 16.5, y: 40))
        arch.addLine(to: CGPoint(x: 16.5, y: 31))
        arc(arch, CGPoint(x: 24, y: 31), 7.5, 7, from: .pi, to: 2 * .pi)
        arch.addLine(to: CGPoint(x: 31.5, y: 40))
        arch.closeSubpath()
        p.addPath(arch)
        p.setFillColor(pal.iglooArch)
        p.setLineWidth(0.9)
        p.drawPath(using: .fillStroke)
        let door = CGMutablePath()
        door.move(to: CGPoint(x: 19, y: 40))
        door.addLine(to: CGPoint(x: 19, y: 32))
        arc(door, CGPoint(x: 24, y: 32), 5, 5, from: .pi, to: 2 * .pi)
        door.addLine(to: CGPoint(x: 29, y: 40))
        door.closeSubpath()
        p.addPath(door)
        p.setFillColor(pal.door)
        p.fillPath()
    }

    /// Frame 0 shut, 1 swinging, 2 hanging open.
    static func hatch(_ p: CGContext, frame: Int, _ pal: PenguinPalette) {
        // The doors under the box.
        let swing: CGFloat = frame == 0 ? 0 : frame == 1 ? 45 : 82
        p.setStrokeColor(pal.hatchLine)
        p.setLineWidth(0.8)
        p.setFillColor(pal.hatchDoor)
        for side in 0..<2 {
            p.saveGState()
            p.translateBy(x: side == 1 ? 34 : 6, y: 17)
            p.rotate(by: (side == 1 ? -swing : swing) * .pi / 180)
            let r = side == 1 ? CGRect(x: -14, y: -1, width: 14, height: 2.4) : CGRect(x: 0, y: -1, width: 14, height: 2.4)
            p.addPath(CGPath(roundedRect: r, cornerWidth: 0.8, cornerHeight: 0.8, transform: nil))
            p.drawPath(using: .fillStroke)
            p.restoreGState()
        }
        // The box, with a snowflake on its side and snow on its lid.
        p.addPath(CGPath(roundedRect: CGRect(x: 3, y: 2, width: 34, height: 15.5), cornerWidth: 3, cornerHeight: 3, transform: nil))
        p.setStrokeColor(pal.hatchLine)
        p.setLineWidth(0.9)
        p.setFillColor(pal.hatch)
        p.drawPath(using: .fillStroke)
        p.addPath(CGPath(roundedRect: CGRect(x: 2, y: 0.6, width: 36, height: 4.2), cornerWidth: 2, cornerHeight: 2, transform: nil))
        p.setFillColor(pal.snow)
        p.fillPath()
        p.setStrokeColor(pal.snow)
        p.setLineCap(.round)
        let c = CGPoint(x: 20, y: 11)
        for i in 0..<3 {
            let a = (30 + CGFloat(i) * 60) * .pi / 180
            let d = CGPoint(x: cos(a) * 3.6, y: sin(a) * 3.6)
            p.move(to: CGPoint(x: c.x - d.x, y: c.y - d.y))
            p.addLine(to: CGPoint(x: c.x + d.x, y: c.y + d.y))
        }
        p.strokePath()
    }
}

/// A penguin doing one skill, or the igloo, or a walker: the skill buttons,
/// the card, the igloo pointer.
struct PenguinPicture: View {
    enum Kind { case skill(PenguinSkill), walk, igloo }
    let kind: Kind
    var mirrored = false

    var body: some View {
        let dark = Theme.palette.isDark
        Canvas { ctx, size in
            let box: CGSize
            switch kind {
            case .igloo: box = PenguinProps.iglooSize
            default: box = CGSize(width: PenguinFrames.cell, height: PenguinFrames.cell)
            }
            let k = min(size.width / box.width, size.height / box.height)
            guard k > 0 else { return }
            ctx.withCGContext { c in
                c.translateBy(x: (size.width - box.width * k) / 2, y: (size.height - box.height * k) / 2)
                c.scaleBy(x: k, y: k)
                if mirrored {
                    c.translateBy(x: box.width, y: 0)
                    c.scaleBy(x: -1, y: 1)
                }
                let pal = PenguinPalette(dark: dark)
                switch kind {
                case .igloo: PenguinProps.igloo(c, pal)
                case .walk: PenguinFrames.draw(c, frame: PenguinFrames.walk + 1, pal)
                case .skill(let s): PenguinFrames.draw(c, frame: PenguinFrames.frame(for: s), pal)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
