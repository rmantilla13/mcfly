import McFlyKit
import Observation
import SwiftUI

/// A level running: the kit's `PenguinSim` on the clock, a tick every 50 ms
/// (three when fast), and where to draw the penguins between ticks. The
/// terrain's pictures follow the digs and bricks as they happen.
@MainActor
@Observable
final class PenguinWorld {
    private(set) var sim: PenguinSim
    private(set) var level: Int
    /// Playing the level's recorded solution ("Show me").
    private(set) var demo = false
    @ObservationIgnored private var replayer = PenguinReplayer()
    @ObservationIgnored private var carry: Double = 0
    /// How far between the last two ticks to draw.
    private(set) var alpha: Double = 1
    /// Bumped every frame drawn.
    private(set) var frame = 0
    private(set) var terrain: PenguinTerrain?
    private(set) var water: [CGImage?] = []

    init(level: Int) {
        let index = max(0, min(PenguinLevel.all.count - 1, level))
        self.level = index
        sim = PenguinSim(PenguinLevel.all[index])
    }

    func load(_ index: Int) {
        level = max(0, min(PenguinLevel.all.count - 1, index))
        // In place, so the generation goes on rising and the terrain is painted anew.
        sim.load(PenguinLevel.all[level])
        reset(demo: false)
    }

    /// The level from the start; with `demo`, playing its solution.
    func restart(demo: Bool) {
        sim.restart()
        reset(demo: demo)
    }

    private func reset(demo: Bool) {
        self.demo = demo
        replayer = demo ? PenguinReplayer(sim.level.solution) : PenguinReplayer()
        carry = 0
        alpha = 1
        frame += 1
    }

    /// Moves the level on by `ms` of the clock (already sped up).
    func advance(_ ms: Double) {
        carry += ms
        var n = 0
        while carry >= Double(Penguins.tickMs) && !sim.finished {
            if replayer.active { replayer.apply(&sim) }
            sim.step()
            carry -= Double(Penguins.tickMs)
            n += 1
            // A stall isn't made up for.
            if n >= 8 {
                carry = 0
                break
            }
        }
        alpha = sim.finished ? 1 : min(1, max(0, carry / Double(Penguins.tickMs)))
        terrain?.apply(sim.edits)
        frame += 1
    }

    /// Gives `skill` to the penguin nearest (x, y), world pixels, that can
    /// take it, within `reach`. Returns where it was, or nil.
    func tap(_ skill: PenguinSkill, x: Double, y: Double, reach: Double) -> CGPoint? {
        guard !sim.finished, !demo, let id = sim.pick(skill, x: x, y: y, radius: reach), sim.assign(skill, to: id) else { return nil }
        let p = sim.penguins[id]
        frame += 1
        return CGPoint(x: Double(p.x) + 0.5, y: Double(p.y) + 1 - Double(Penguins.height) / 2)
    }

    func finish() {
        sim.finish()
        frame += 1
    }

    /// Paints the terrain for this size and palette, if it isn't already.
    func paint(px: CGFloat, dark: Bool) {
        let px = (px * 4).rounded() / 4
        if let t = terrain, t.generation == sim.generation, t.px == px, t.dark == dark {
            t.apply(sim.edits)
            return
        }
        terrain = PenguinTerrain(sim: sim, px: px, dark: dark)
        water = sim.level.water.map { paintPenguinWater($0, px: px, dark: dark) }
    }
}

/// Penguin March (display/qml/games/PenguinMarch.qml): penguins drop from a
/// hatch and walk, and it's up to you to get enough of them home to the
/// igloo. Pick a skill, then tap a penguin: the nearest one that can take
/// it, within a finger's reach. Where the whole level would leave the
/// penguins too small (an iPhone), the world is shown bigger and pans
/// sideways, starting on the hatch, with a pointer to the igloo. The level
/// and the most penguins saved on each are kept on the device.
struct PenguinMarchView: View {
    let covered: Bool

    @State private var world = PenguinWorld(level: GameProgress.shared.penguinLevel)
    @State private var playing = false
    @State private var fast = false
    @State private var skill: PenguinSkill?
    @State private var briefed = false
    @State private var picking = false
    @State private var best = GameProgress.shared.penguinBest
    @State private var ripple: Ripple?
    @State private var panX: CGFloat = 0
    /// Where the view pans to (a world x, in steps of 20), centred.
    @State private var anchor: Int?
    @Environment(\.displayScale) private var displayScale

    private struct Ripple: Equatable {
        var at: CGPoint
        var color: Color
        var id = UUID()
    }

    private var sim: PenguinSim { world.sim }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let barHeight: CGFloat = wide ? 100 : 92
            let headerHeight: CGFloat = 52
            let room = CGSize(width: geo.size.width, height: max(120, geo.size.height - headerHeight - barHeight - 24))
            let fit = min(room.width / 400, room.height / 184)
            // A penguin is 16 world pixels: the whole level shows where that
            // leaves one 24 points tall or more; else it's shown bigger and pans.
            let zoom = max(fit, min(room.height / 184, 1.9))
            let viewHeight = min(room.height, 184 * zoom)
            ZStack(alignment: .top) {
                VStack(spacing: 12) {
                    header(compact: geo.size.width < 520).frame(height: headerHeight)
                    Spacer(minLength: 0)
                    stage(zoom: zoom).frame(height: viewHeight)
                    skillBar(height: barHeight)
                    Spacer(minLength: 0)
                }
                if picking { picker.transition(.opacity) }
            }
        }
        .onAppear { load(world.level) }
        .task(id: playing && !picking && !covered && !sim.finished) {
            guard playing && !picking && !covered && !sim.finished else { return }
            var last = Date.now
            while !Task.isCancelled && !sim.finished {
                try? await Task.sleep(for: .milliseconds(16))
                let now = Date.now
                world.advance(min(100, now.timeIntervalSince(last) * 1000) * (fast ? 3 : 1) * GameLaunch.clock)
                last = now
            }
        }
        .onChange(of: covered) { if covered { playing = false } }
        .onChange(of: sim.finished) { _, done in
            guard done else { return }
            playing = false
            if !world.demo {
                GameProgress.shared.recordPenguins(level: world.level, saved: sim.saved, need: sim.level.need)
                best = GameProgress.shared.penguinBest
            }
        }
    }

    private func load(_ index: Int) {
        world.load(index)
        playing = false
        fast = false
        briefed = false
        picking = false
        skill = PenguinSkill.allCases.first { sim.left($0) > 0 }
        GameProgress.shared.penguinLevel = world.level
        anchor = Self.anchor(world.sim.level.entrance.x)
    }

    private func start() {
        briefed = true
        playing = true
    }

    private func restart() {
        world.restart(demo: false)
        skill = skill.flatMap { sim.left($0) > 0 ? $0 : nil } ?? PenguinSkill.allCases.first { sim.left($0) > 0 }
        start()
    }

    private func showMe() {
        world.restart(demo: true)
        start()
    }

    /// The pan anchor nearest a world x.
    private static func anchor(_ x: Int) -> Int { max(0, min(380, (x / 20) * 20)) }

    private static func stars(saved: Int, need: Int, total: Int) -> Int {
        saved >= total ? 3 : saved >= need + Int((Double(total - need) / 2).rounded(.up)) ? 2 : saved >= need ? 1 : 0
    }

    private var countLine: String {
        let toCome = sim.level.total - sim.released
        var line = "\(sim.saved) of \(sim.level.need) home"
        if sim.out > 0 { line += " · \(sim.out) out" }
        if toCome > 0 && sim.tick > 0 { line += " · \(toCome) to come" }
        return line
    }

    // MARK: Header: the level and its count, and the controls

    private func header(compact: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(compact ? sim.level.name : "Level \(world.level + 1) · \(sim.level.name)")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(compact ? "Level \(world.level + 1) · " + countLine : countLine)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GameIconButton(systemImage: playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Play",
                           prominent: !playing && !sim.finished, size: 44) {
                if briefed { playing.toggle() } else { start() }
            }
            .disabled(sim.finished)
            GameIconButton(systemImage: "forward.fill", label: fast ? "Normal speed" : "Fast forward", active: fast, size: 44) { fast.toggle() }
                .disabled(sim.finished)
            GameIconButton(systemImage: "arrow.clockwise", label: "Start the level over", size: 44) { restart() }
            GameIconButton(systemImage: "square.grid.2x2", label: "Levels", size: 44) {
                playing = false
                picking = true
            }
        }
    }

    // MARK: The world

    private func stage(zoom: CGFloat) -> some View {
        GeometryReader { geo in
            let worldSize = CGSize(width: 400 * zoom, height: 184 * zoom)
            let pans = worldSize.width > geo.size.width + 1
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    // Places to pan to, every 20 world pixels, with the world over them.
                    HStack(spacing: 0) {
                        ForEach(Array(stride(from: 0, to: 400, by: 20)), id: \.self) { _ in
                            Color.clear.frame(width: 20 * zoom, height: worldSize.height)
                        }
                    }
                    .scrollTargetLayout()
                    .overlay { worldView(zoom: zoom) }
                    .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .scrollView).minX } action: { panX = $0 }
                }
                .scrollPosition(id: $anchor, anchor: .center)
                .scrollDisabled(!pans)
                .frame(width: min(geo.size.width, worldSize.width), height: worldSize.height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))

                overlays(zoom: zoom, view: CGSize(width: min(geo.size.width, worldSize.width), height: worldSize.height), pans: pans)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func worldView(zoom: CGFloat) -> some View {
        let dark = Theme.palette.isDark
        let px = min(4, zoom * displayScale)
        let frame = world.frame // redraw with every frame
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: PenguinPalette.sky(dark: dark), startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                _ = frame
                let s = size.width / 400
                guard let terrain = world.terrain else { return }
                if let ground = terrain.ground {
                    ctx.draw(Image(decorative: ground, scale: 1), in: CGRect(origin: .zero, size: size))
                }
                if let rock = terrain.rock {
                    ctx.draw(Image(decorative: rock, scale: 1), in: CGRect(origin: .zero, size: size))
                }
                let sim = world.sim
                let alpha = world.alpha
                let pal = PenguinPalette(dark: dark)
                ctx.withCGContext { c in
                    c.scaleBy(x: s, y: s)
                    // The igloo, the penguins between their last two ticks, the hatch.
                    let door = sim.level.exit
                    c.saveGState()
                    c.translateBy(x: CGFloat(door.x) + 0.5 - PenguinProps.iglooAnchor.x, y: CGFloat(door.y) + 1 - PenguinProps.iglooAnchor.y)
                    PenguinProps.igloo(c, pal)
                    c.restoreGState()
                    for p in sim.penguins where !p.gone {
                        guard let f = PenguinFrames.frame(for: p, tick: sim.tick) else { continue }
                        let x = Double(p.px) + Double(p.x - p.px) * alpha + 0.5
                        let y = Double(p.py) + Double(p.y - p.py) * alpha + 1
                        // Going in at the door, it gets smaller.
                        let k = p.state == .exiting ? 1 - 0.6 * min(1, (Double(p.timer) + alpha) / Double(Penguins.exitTicks)) : 1
                        c.saveGState()
                        c.translateBy(x: x, y: y)
                        c.scaleBy(x: k, y: k)
                        c.translateBy(x: -PenguinFrames.footX, y: -PenguinFrames.ground)
                        PenguinFrames.draw(c, frame: f, pal)
                        c.restoreGState()
                    }
                    let e = sim.level.entrance
                    c.saveGState()
                    c.translateBy(x: CGFloat(e.x) + 0.5 - PenguinProps.hatchAnchor.x, y: CGFloat(e.y) + 1 - PenguinProps.hatchAnchor.y)
                    PenguinProps.hatch(c, frame: sim.hatchOpen <= 0 ? 0 : sim.hatchOpen < 1 ? 1 : 2, pal)
                    c.restoreGState()
                }
                for (i, rect) in sim.level.water.enumerated() {
                    guard i < world.water.count, let image = world.water[i] else { continue }
                    ctx.draw(Image(decorative: image, scale: 1),
                             in: CGRect(x: CGFloat(rect.x) * s, y: CGFloat(rect.y - 2) * s, width: CGFloat(rect.width) * s, height: CGFloat(rect.height + 2) * s))
                }
            }
            if let ripple {
                RippleView(color: ripple.color)
                    .position(ripple.at)
                    .id(ripple.id)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in tap(value.location, zoom: zoom) })
        .onAppear { world.paint(px: px, dark: dark) }
        .onChange(of: px) { world.paint(px: px, dark: dark) }
        .onChange(of: dark) { world.paint(px: px, dark: dark) }
        .onChange(of: sim.generation) { world.paint(px: px, dark: dark) }
        .accessibilityElement()
        .accessibilityLabel("The level: \(countLine)")
    }

    private func tap(_ point: CGPoint, zoom: CGFloat) {
        guard briefed, !sim.finished, !world.demo else { return }
        guard let skill, sim.left(skill) > 0,
              let at = world.tap(skill, x: point.x / zoom, y: point.y / zoom, reach: 40 / zoom) else {
            ripple = Ripple(at: point, color: Theme.muted)
            return
        }
        ripple = Ripple(at: CGPoint(x: at.x * zoom, y: at.y * zoom), color: Color(rgb: PenguinPalette.skillColors[skill]!))
        if sim.left(skill) == 0 {
            self.skill = PenguinSkill.allCases.first { sim.left($0) > 0 } ?? skill
        }
    }

    private struct RippleView: View {
        let color: Color
        @State private var grown = false

        var body: some View {
            Circle()
                .stroke(color, lineWidth: 4)
                .frame(width: grown ? 80 : 24, height: grown ? 80 : 24)
                .opacity(grown ? 0 : 0.95)
                .onAppear { withAnimation(.easeOut(duration: 0.36)) { grown = true } }
        }
    }

    @ViewBuilder
    private func overlays(zoom: CGFloat, view: CGSize, pans: Bool) -> some View {
        ZStack {
            // Finish, once enough are home and the rest can't be (or needn't);
            // a way through, once the skills are spent and they aren't.
            let enough = sim.saved >= sim.level.need
            let spent = PenguinSkill.allCases.allSatisfy { sim.left($0) == 0 }
            if sim.tick > 0 && !sim.finished && !world.demo && (enough ? sim.out > 0 : spent) {
                Button(enough ? "Finish" : "Show me") { if enough { world.finish() } else { showMe() } }
                    .buttonStyle(.gamePill(enough ? .prominent : .neutral))
                    .padding(10)
                    .frame(width: view.width, height: view.height, alignment: .topTrailing)
            }
            // Where the view pans: which way the igloo is, while it's out of sight.
            if pans && !sim.finished {
                let door = CGFloat(sim.level.exit.x) * zoom - panX
                let onRight = door > view.width
                if onRight || door < 0 {
                    Button { withAnimation(.easeInOut(duration: 0.5)) { anchor = Self.anchor(sim.level.exit.x) } } label: {
                        HStack(spacing: 4) {
                            if !onRight { Image(systemName: "chevron.left").font(.headline) }
                            PenguinPicture(kind: .igloo).frame(width: 40, height: 33)
                            if onRight { Image(systemName: "chevron.right").font(.headline) }
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 48)
                        .background(Theme.surface.opacity(0.94), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Show the igloo")
                    .padding(.horizontal, 10)
                    // At the igloo's height, kept inside the view.
                    .offset(y: max(10, min(view.height - 58, CGFloat(sim.level.exit.y) * zoom - 48)))
                    .frame(width: view.width, height: view.height, alignment: onRight ? .topTrailing : .topLeading)
                }
            }
            if !briefed && !world.demo {
                GameCardOverlay {
                    Text("Level \(world.level + 1) of \(PenguinLevel.all.count)").font(.caption).foregroundStyle(Theme.muted)
                    Text(sim.level.name).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Get \(sim.level.need) of \(sim.level.total) penguins home.")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    Text(sim.level.hint)
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Play", action: start).buttonStyle(.gamePill()).padding(.top, 4)
                }
                .frame(maxWidth: min(view.width, 460))
            } else if sim.finished {
                result.frame(maxWidth: min(view.width, 460))
            }
        }
        .frame(width: view.width, height: view.height)
    }

    private var result: some View {
        let won = sim.won
        let demo = world.demo
        return GameCardOverlay {
            if won { Stars(count: Self.stars(saved: sim.saved, need: sim.level.need, total: sim.level.total), size: 32) }
            Text(won ? "\(sim.saved) of \(sim.level.total) home!" : "\(sim.saved) of \(sim.level.total) home")
                .font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
            Text(demo ? "That's one way. Your turn."
                 : won ? (sim.saved >= sim.level.total ? "Every one of them." : "You needed \(sim.level.need).")
                 : "It takes \(sim.level.need). Try again, or see a way through.")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Two at most: they fit side by side on a phone.
            HStack(spacing: 10) { resultButtons(won: won, demo: demo) }
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func resultButtons(won: Bool, demo: Bool) -> some View {
        if !won && !demo {
            Button("Show me", action: showMe).buttonStyle(.gamePill(.neutral))
        }
        Button(won && !demo ? "Play again" : "Try again") { if demo { load(world.level) } else { restart() } }
            .buttonStyle(.gamePill(won && !demo ? .neutral : .prominent))
        if won && !demo {
            Button(world.level + 1 < PenguinLevel.all.count ? "Next level" : "All levels") {
                if world.level + 1 < PenguinLevel.all.count { load(world.level + 1) } else { picking = true }
            }
            .buttonStyle(.gamePill())
        }
    }

    // MARK: Skills

    @ViewBuilder
    private func skillBar(height: CGFloat) -> some View {
        if world.demo {
            HStack(spacing: 12) {
                Text("Showing a way through").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Button("Stop") { load(world.level) }.buttonStyle(.gamePill(.neutral))
            }
            .frame(height: height)
        } else {
            HStack(spacing: 8) {
                ForEach(PenguinSkill.allCases) { s in
                    let left = sim.left(s)
                    let chosen = skill == s
                    Button { skill = s } label: {
                        VStack(spacing: 0) {
                            PenguinPicture(kind: .skill(s)).frame(width: 52, height: 52)
                            Text(s.name).font(.footnote.weight(.medium)).foregroundStyle(chosen ? Theme.accent : Theme.text)
                        }
                        .frame(maxWidth: 104, maxHeight: .infinity)
                        .background(chosen ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous).stroke(Theme.accent, lineWidth: chosen ? 2 : 0))
                        .overlay(alignment: .topTrailing) {
                            // How many are left, in the skill's colour.
                            Text(String(left))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(minWidth: 24, minHeight: 24)
                                .background(left > 0 ? Color(rgb: PenguinPalette.skillColors[s]!) : Theme.muted, in: Capsule())
                                .padding(4)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(left == 0)
                    .opacity(left > 0 ? 1 : 0.4)
                    .accessibilityLabel("\(s.name), \(left) left")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .frame(height: height)
        }
    }

    // MARK: Levels

    private var picker: some View {
        LevelPicker(title: "Choose a level", summary: "\(best.count) of \(PenguinLevel.all.count) won", close: { picking = false }) {
            LevelGrid(count: PenguinLevel.all.count, current: world.level, done: { best[$0] != nil },
                      stars: { i in
                          let l = PenguinLevel.all[i]
                          return Self.stars(saved: best[i] ?? 0, need: l.need, total: l.total)
                      },
                      name: { PenguinLevel.all[$0].name }) { load($0) }
        }
    }
}
