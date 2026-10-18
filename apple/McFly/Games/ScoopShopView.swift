import McFlyKit
import SwiftUI

/// Scoop Shop (display/qml/games/ScoopShop.qml, its rules in the kit's
/// `ScoopShift`): an ice cream parlour against the clock. Pick who works the
/// shift, build each customer's ticket from the stock behind the counter,
/// and tap the customer to hand it over. The clock runs only while the shop
/// is open and in view: how to play, the app going away, or the pause
/// button stop it, and the shop hides while paused (no peeking at tickets).
/// The best score and who worked last are kept on the device.
///
/// The counter is the shop's front: candy-striped wallpaper, a scalloped
/// awning with the shop's plaque, each order a paper ticket clipped to a
/// rail, the customers in shirts behind a marble counter with a mint front.
/// The buttons are the stock: tubs in a freezer case, stacks of cones and
/// cups and jars of toppings on wooden shelves. The treat is made on a prep
/// bench before subway tiles, with Pip or Lotl behind it, what's next on a
/// chalkboard and, where the wall has room, a menu board of the day's
/// scoops. Night and Dark light the same parlour for the evening.
struct ScoopShopView: View {
    /// How to play is over the game, or the app is away.
    let covered: Bool

    @State private var shift = ScoopShift(best: GameProgress.shared.scoopBest, worker: GameProgress.shared.scoopWorker)
    @State private var hint = ""
    @State private var hintKey = 0
    @State private var news = ""
    @State private var mood: Mood?
    @State private var hops = 0
    @State private var shakes = 0
    @State private var treatShake = 0

    private enum Mood { case happy, oops }

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(size: geo.size)
            let look = ScoopLook.of(dark: Theme.palette.isDark)
            ZStack(alignment: .topLeading) {
                if shift.playing {
                    hud(layout).frame(width: layout.hud.width, height: layout.hud.height).offset(x: layout.hud.minX, y: layout.hud.minY)
                    counter(layout, look).frame(width: layout.counter.width, height: layout.counter.height)
                        .offset(x: layout.counter.minX, y: layout.counter.minY)
                    station(layout, look).frame(width: layout.station.width, height: layout.station.height)
                        .offset(x: layout.station.minX, y: layout.station.minY)
                    if let base = layout.base {
                        baseRow(layout, look).frame(width: base.width, height: base.height).offset(x: base.minX, y: base.minY)
                    }
                    pad(layout, look).frame(width: layout.pad.width, height: layout.pad.height).offset(x: layout.pad.minX, y: layout.pad.minY)
                }
                if shift.phase != .playing {
                    chooser(layout, look, size: geo.size).frame(width: geo.size.width, height: geo.size.height)
                } else if shift.paused {
                    paused.frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        // One clock: the shift moves on while it's open and in view.
        .task(id: shift.playing) {
            guard shift.playing else { return }
            var last = Date.now
            while !Task.isCancelled && shift.playing {
                try? await Task.sleep(for: .milliseconds(33))
                let now = Date.now
                let late = shift.advance(min(250, now.timeIntervalSince(last) * 1000) * GameLaunch.clock)
                last = now
                if late > 0 { react(.oops) }
                if shift.phase == .over { saveBest() }
            }
        }
        .onChange(of: covered, initial: true) { if covered { shift.pause() } }
        .onChange(of: shift.level) { old, level in
            guard shift.phase == .playing, level > old, level > 1 else { return }
            let said = level == Scoops.newFlavours ? "Level \(level): new flavours!"
                : level == Scoops.newToppings ? "Level \(level): new toppings!" : "Level \(level): busier!"
            news = said
            Task {
                try? await Task.sleep(for: .seconds(2))
                if news == said { news = "" }
            }
        }
        // Closed mid-shift: a higher score still counts.
        .onDisappear { saveBest() }
    }

    private func saveBest() {
        if max(shift.best, shift.score) > GameProgress.shared.scoopBest { GameProgress.shared.scoopBest = max(shift.best, shift.score) }
    }

    private func nudge(_ why: ScoopShift.Nudge) {
        hint = why.rawValue
        hintKey += 1
        treatShake += 1
        let key = hintKey
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if hintKey == key { hint = "" }
        }
    }

    private func react(_ how: Mood) {
        mood = how
        if how == .happy { hops += 1 } else { shakes += 1 }
        let count = hops + shakes
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            if hops + shakes == count { mood = nil }
        }
    }

    private func tap(_ key: ScoopKey) {
        hint = ""
        switch key {
        case .base(let base): shift.pickBase(base)
        case .flavour(let f):
            if case .failure(let why)? = shift.addScoop(f) { nudge(why) }
        case .topping(let t):
            if case .failure(let why)? = shift.addTopping(t) { nudge(why) }
        case .undo: shift.undo()
        }
    }

    private func deliver(_ seat: Int) {
        switch shift.deliver(seat) {
        case .success(.right)?: react(.happy); hint = ""
        case .success(.wrong)?: react(.oops); hint = ""
        case .failure(let why)?: nudge(why)
        case nil: break
        }
        if shift.phase == .over { saveBest() }
    }

    // MARK: Layout

    /// Three shapes, from the stage alone, as the display's: much wider than
    /// tall, the counter over the buttons, the score, the cones and cups and
    /// the prep bench in a column beside them; upright, the score, the
    /// counter, the bench, the buttons; else the counter over the bench and
    /// the buttons side by side. The buttons are a grid seven across: the
    /// cone, the cup and undo, then the freezer case, then the shelf.
    private struct Layout {
        enum Shape { case side, tall, square }
        var shape: Shape
        var hud, counter, station, pad: CGRect
        /// Beside the counter: the cone, the cup and undo, over the bench.
        var base: CGRect?
        /// A button's pane in the pad, and in the base row.
        var bw: CGFloat, bh: CGFloat, baseW: CGFloat = 0
        /// The gap between panes; a button takes half of it on each side
        /// for its touch area, so a tap between two lands on one.
        let pg: CGFloat
        /// A phone-sized stage: smaller margins, corners and type.
        let narrow: Bool
        let gap: CGFloat = 12
        static let target: CGFloat = 48
        static let columns: CGFloat = 7

        var corner: CGFloat { narrow ? Theme.radiusSm : Theme.radius }

        init(size: CGSize) {
            let w = size.width, h = size.height, g = gap, t = Self.target, cols = Self.columns
            narrow = min(w, h) < 500
            let pg: CGFloat = narrow ? 6 : 10
            self.pg = pg
            if w > h * 1.4 {
                let sw = min(520, max(3 * t + 2 * pg, w * 0.3)).rounded()
                let lw = w - sw - g
                let bh = max(t, min(112, ((h - g) * 0.17).rounded(.down)))
                let ph = 2 * bh + pg
                shape = .side
                hud = CGRect(x: lw + g, y: 0, width: sw, height: t)
                counter = CGRect(x: 0, y: 0, width: lw, height: h - ph - g)
                base = CGRect(x: lw + g, y: t + g, width: sw, height: bh)
                baseW = (sw - 2 * pg) / 3
                station = CGRect(x: lw + g, y: t + g + bh + g, width: sw, height: max(0, h - t - g - bh - g))
                pad = CGRect(x: 0, y: h - ph, width: lw, height: ph)
                bw = (lw - (cols - 1) * pg) / cols
                self.bh = bh
                return
            }
            let top = t + g
            if h > w * 1.25 {
                let bw = (w - (cols - 1) * pg) / cols
                let bh = max(44, min(100, bw.rounded(.down)))
                let ph = 3 * bh + 2 * pg
                // A phone's counter is a little taller than the display's, so
                // a ticket's treat is big enough to read.
                let ch = max(150, min(w / 4 * (narrow ? 2.3 : 1.75), h - top - g - ph - g - (narrow ? 230 : 200)))
                shape = .tall
                hud = CGRect(x: 0, y: 0, width: w, height: t)
                counter = CGRect(x: 0, y: top, width: w, height: ch)
                station = CGRect(x: 0, y: top + ch + g, width: w, height: max(0, h - top - ch - g - ph - g))
                pad = CGRect(x: 0, y: h - ph, width: w, height: ph)
                self.bw = bw
                self.bh = bh
                return
            }
            let slot = min(w / 4, 320)
            let pw = max(cols * 44 + (cols - 1) * pg, min(w * 0.62, cols * 160 + (cols - 1) * pg))
            let ch = max(150, min(slot * 1.6, h - top - g - (3 * t + 2 * pg)))
            let sh = max(0, h - top - ch - g)
            let bh = max(44, min(110, ((sh - 2 * pg) / 3).rounded(.down)))
            let ph = 3 * bh + 2 * pg
            shape = .square
            hud = CGRect(x: 0, y: 0, width: w, height: t)
            counter = CGRect(x: 0, y: top, width: w, height: ch)
            station = CGRect(x: 0, y: top + ch + g, width: max(0, w - pw - g), height: sh)
            pad = CGRect(x: w - pw, y: h - ph, width: pw, height: ph)
            bw = (pw - (cols - 1) * pg) / cols
            self.bh = bh
        }

        /// The pad's buttons: [key, column, row, columns spanned].
        var keys: [(ScoopKey, Int, Int, Int)] {
            let apart = base != nil
            let bases: [(ScoopKey, Int, Int, Int)] = apart ? [] : [(.base(.cone), 0, 0, 2), (.base(.cup), 2, 0, 2), (.undo, 5, 0, 2)]
            return bases + ScoopFlavour.allCases.enumerated().map { (.flavour($1), $0, apart ? 0 : 1, 1) }
                + ScoopTopping.allCases.enumerated().map { (.topping($1), $0, apart ? 1 : 2, 1) }
        }

        /// The base row's buttons beside the counter.
        static let baseKeys: [ScoopKey] = [.base(.cone), .base(.cup), .undo]

        /// A pane in the pad.
        func cell(_ column: Int, _ row: Int, _ span: Int) -> CGRect {
            CGRect(x: CGFloat(column) * (bw + pg), y: CGFloat(row) * (bh + pg), width: CGFloat(span) * bw + CGFloat(span - 1) * pg, height: bh)
        }

        /// The panes round a set of keys, for the case and the shelves.
        func span(_ wanted: (ScoopKey) -> Bool) -> CGRect {
            keys.filter { wanted($0.0) }.map { cell($0.1, $0.2, $0.3) }.reduce(CGRect.null) { $0.union($1) }
        }
    }

    // MARK: The score, the best, the level, hearts and pause

    private func hud(_ layout: Layout) -> some View {
        HStack(spacing: 14) {
            if layout.shape == .side {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Score").font(.caption).foregroundStyle(Theme.muted)
                        Text(String(shift.score)).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
                    }
                    HStack(spacing: 6) {
                        HeartsView(left: shift.hearts, size: 18)
                        Text("Level \(shift.level)").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            } else {
                stat("Score", shift.score)
                stat("Best", max(shift.best, shift.score))
                stat("Level", shift.level)
            }
            Spacer(minLength: 0)
            if layout.shape != .side { HeartsView(left: shift.hearts, size: 24) }
            GameIconButton(systemImage: "pause.fill", label: "Pause") { shift.pause() }
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            Text(String(value)).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: The counter: the shop's front, a ticket on the rail over each seat

    /// The counter's measures, from its size.
    fileprivate struct Front {
        let w, h, slot, slotsX, critter, band, awning, railY: CGFloat
        let narrow: Bool
        let corner: CGFloat

        init(_ size: CGSize, side: Bool, narrow: Bool, corner: CGFloat) {
            w = size.width
            h = size.height
            self.narrow = narrow
            self.corner = corner
            slot = min(w / CGFloat(Scoops.maxSeats), side ? 300 : 320)
            slotsX = (w - slot * CGFloat(Scoops.maxSeats)) / 2
            critter = min(slot * 0.58, h * (side ? 0.28 : 0.33))
            band = max(12, (critter * 0.34).rounded())
            awning = max(narrow ? 18 : 14, min(64, h * 0.11)).rounded()
            // Where the tickets hang from, under the awning.
            railY = awning - (awning * 0.18).rounded()
        }
    }

    private func counter(_ layout: Layout, _ look: ScoopLook) -> some View {
        let f = Front(layout.counter.size, side: layout.shape == .side, narrow: layout.narrow, corner: layout.corner)
        return ZStack(alignment: .topLeading) {
            ScoopWallpaper(look: look, radius: f.corner, stripe: f.narrow ? 22 : 34).equatable()
                .frame(width: f.w, height: f.h - f.band * 0.5)
            ScoopAwning(look: look, sign: "Pip & Lotl's", stripeWidth: f.narrow ? 24 : 40).equatable()
                .frame(width: f.w - 2 * f.corner, height: f.awning)
                .offset(x: f.corner)
            Capsule().fill(Color(rgb: look.rail))
                .frame(width: f.w - 2 * f.corner, height: max(2, (f.awning * 0.08).rounded()))
                .offset(x: f.corner, y: f.railY)
            ForEach(0..<Scoops.maxSeats, id: \.self) { index in
                SeatView(customer: shift.seats[index], now: shift.now, open: index < shift.rules.seats,
                         playing: shift.phase == .playing, index: index, front: f, rail: look.rail) { deliver(index) }
                    .frame(width: f.slot, height: f.h)
                    .offset(x: f.slotsX + CGFloat(index) * f.slot)
            }
            CounterFront(look: look, corner: f.corner).equatable()
                .frame(width: f.w, height: f.band)
                .offset(y: f.h - f.band)
                .allowsHitTesting(false)
        }
        .frame(width: f.w, height: f.h, alignment: .topLeading)
    }

    /// The counter, in front of the customers: a marble top, a mint front
    /// rounded with the wall's bottom corners.
    private struct CounterFront: View, Equatable {
        let look: ScoopLook
        let corner: CGFloat

        var body: some View {
            Canvas { ctx, size in
                let r = min(corner, size.height)
                let all = CGRect(origin: .zero, size: size)
                ctx.fill(Path(roundedRect: all, cornerRadii: RectangleCornerRadii(topLeading: 4, bottomLeading: r, bottomTrailing: r, topTrailing: 4)),
                         with: .color(Color(rgb: look.lip)))
                let top = CGRect(x: 0, y: 0, width: size.width, height: (size.height * 0.55).rounded())
                let marble = Path(roundedRect: top, cornerRadii: RectangleCornerRadii(topLeading: 4, bottomLeading: 0, bottomTrailing: 0, topTrailing: 4))
                ctx.fill(marble, with: .color(Color(rgb: look.marble)))
                ctx.stroke(marble, with: .color(Color(rgb: look.vein)), lineWidth: 1)
                for v in [(0.12, 0.4, 0.14, 8.0), (0.38, 0.6, 0.1, -6.0), (0.66, 0.3, 0.16, 5.0), (0.86, 0.55, 0.08, -9.0)] {
                    part(&ctx, 1, top.width * v.0, top.height * v.1, top.width * v.2, 1.5, Color(rgb: look.vein), rotation: v.3, radius: 0)
                }
            }
        }
    }

    /// A ticket's paper: a sheet with a torn bottom edge, red-edged when
    /// it went wrong or its customer has flipped out. The teeth hang below
    /// the sheet, in the last `teeth` of the height.
    private struct TicketPaper: View, Equatable {
        let teeth: CGFloat
        let edged: Bool

        var body: some View {
            Canvas { ctx, size in
                let rect = CGRect(x: 0, y: 0, width: size.width, height: max(0, size.height - teeth))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(ScoopPaper.sheet))
                if edged { ctx.stroke(Path(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 2), with: .color(ScoopPaper.bad), lineWidth: 3) }
                // The torn edge: diamonds along the bottom.
                let count = max(0, Int(size.width / teeth))
                let side = teeth * 0.72
                let left = (size.width - CGFloat(count) * teeth) / 2
                var torn = Path()
                for i in 0..<count {
                    let cx = left + CGFloat(i) * teeth + teeth / 2, cy = rect.maxY
                    let d = side / 2 * 1.4142
                    torn.move(to: CGPoint(x: cx, y: cy - d))
                    torn.addLine(to: CGPoint(x: cx + d, y: cy))
                    torn.addLine(to: CGPoint(x: cx, y: cy + d))
                    torn.addLine(to: CGPoint(x: cx - d, y: cy))
                    torn.closeSubpath()
                }
                ctx.fill(torn, with: .color(ScoopPaper.sheet))
            }
        }
    }

    /// A seat at the counter: the ticket on the rail (what they'd like, and
    /// how long they'll wait) over the customer; as they leave, how it went.
    private struct SeatView: View {
        let customer: ScoopCustomer?
        let now: Double
        let open: Bool
        let playing: Bool
        let index: Int
        let front: Front
        let rail: Int
        let deliver: () -> Void

        var body: some View {
            let f = front
            let w = f.slot, h = f.h
            let pad: CGFloat = f.narrow ? 6 : 10
            let teeth: CGFloat = f.narrow ? 6 : 9
            let tx: CGFloat = f.narrow ? 5 : 10
            let ty = f.railY + 3
            let tw = w - 2 * tx, th = max(0, h - ty - f.critter - teeth)
            ZStack(alignment: .topLeading) {
                if let c = customer {
                    let arrive = Self.ease(min(1, max(0, (now - c.arrived) / 400)), out: true)
                    let leave = c.gone == .waiting ? 0 : Self.ease(min(1, max(0, (now - c.goneAt) / (ScoopShift.leaveMs - 100))), out: false)
                    let left = c.patienceLeft(at: now)
                    let face = c.face(at: now)
                    let shown = arrive * (1 - leave)
                    CritterView(kind: c.kind, face: face, shirt: CritterView.shirts[c.id % CritterView.shirts.count])
                        .frame(width: f.critter * 10 / 9, height: f.critter)
                        .offset(x: (w - f.critter * 10 / 9) / 2,
                                y: h - f.critter + (1 - arrive + leave) * f.band * 0.4 - f.band * 0.7)
                        .opacity(shown)
                    ticket(c, left: left, face: face, leave: leave, size: CGSize(width: tw, height: th), pad: pad, teeth: teeth)
                        .frame(width: tw, height: th, alignment: .topLeading)
                        .rotationEffect(.degrees(index % 2 == 1 ? 1.2 : -1.2))
                        .offset(x: tx, y: ty)
                        .opacity(shown)
                } else if !open && playing {
                    closedSign(width: w)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { if customer != nil { deliver() } }
            .accessibilityElement()
            .accessibilityLabel(customer.map(describe) ?? (open || !playing ? "An empty seat" : "Opens at level \(index < 3 ? 3 : 5)"))
            .accessibilityAddTraits(customer != nil ? .isButton : [])
            .accessibilityAction { if customer != nil { deliver() } }
        }

        private func ticket(_ c: ScoopCustomer, left: Double, face: Scoops.Face, leave: Double, size: CGSize, pad: CGFloat, teeth: CGFloat) -> some View {
            let barH: CGFloat = front.narrow ? 7 : 10
            let barY = size.height - barH - pad * 0.6
            let clip = front.narrow ? CGSize(width: 14, height: 8) : CGSize(width: 22, height: 12)
            return ZStack(alignment: .topLeading) {
                TicketPaper(teeth: teeth, edged: c.gone == .wrong || c.gone == .late || face == .furious).equatable()
                    .frame(width: size.width, height: size.height + teeth)
                if c.gone == .waiting {
                    if size.width >= 76 {
                        Text("#\(c.id)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ScoopPaper.faint)
                            .offset(x: pad, y: pad - 2)
                    }
                    ScoopTreatView(order: c.order, dark: false)
                        .frame(width: max(0, size.width - 2 * pad), height: max(0, barY - 2 * pad))
                        .offset(x: pad, y: pad)
                } else {
                    // How it went, on the ticket: the points, or what went wrong, rising.
                    Text(c.gone == .right ? "+\(c.points)" : c.gone == .wrong ? "Wrong order" : "Too slow")
                        .font(c.gone == .right ? (front.narrow ? Font.title3 : Font.title2).weight(.bold) : Font.subheadline.weight(.bold))
                        .foregroundStyle(c.gone == .right ? ScoopPaper.good : ScoopPaper.bad)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .frame(width: max(0, size.width - 2 * pad), height: size.height * 0.6)
                        .offset(x: pad, y: size.height * 0.2 - leave * size.height * 0.2)
                        .opacity(1 - leave * leave)
                }
                Capsule().fill(ScoopPaper.shade)
                    .frame(width: max(0, size.width - 2 * (pad + 2)), height: barH)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(left > 0.5 ? ScoopPaper.good : left > 0.25 ? ScoopPaper.wait : ScoopPaper.bad)
                            .frame(width: max(0, size.width - 2 * (pad + 2)) * left)
                    }
                    .offset(x: pad + 2, y: barY)
                // The clip on the rail.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(rgb: 0x5B6470))
                    .overlay(alignment: .topLeading) {
                        Rectangle().fill(.white.opacity(0.35))
                            .frame(width: clip.width * 0.6, height: max(1, clip.height * 0.18))
                            .offset(x: clip.width * 0.2, y: clip.height * 0.25)
                    }
                    .frame(width: clip.width, height: clip.height)
                    .offset(x: (size.width - clip.width) / 2, y: -clip.height * 0.55)
            }
        }

        /// A seat that opens later: a little sign on the rail.
        private func closedSign(width: CGFloat) -> some View {
            Text("Opens at level \(index < 3 ? 3 : 5)")
                .font(.caption)
                .foregroundStyle(ScoopPaper.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 4).fill(ScoopPaper.sheet))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ScoopPaper.shade, lineWidth: 1))
                .background(alignment: .top) {
                    // Two strings up to the rail.
                    GeometryReader { geo in
                        ForEach([0.2, 0.8], id: \.self) { x in
                            Rectangle().fill(Color(rgb: rail)).frame(width: 1.5, height: 16).offset(x: geo.size.width * x, y: -14)
                        }
                    }
                }
                .frame(maxWidth: width - 12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)
                .offset(y: front.railY + 14)
        }

        private func describe(_ c: ScoopCustomer) -> String {
            let o = c.order
            let toppings = o.toppings.isEmpty ? "" : ", with " + o.toppings.map { $0.name.lowercased() }.joined(separator: " and ")
            let mood = c.face(at: now) == .furious ? ", about to give up" : ""
            return "A \(c.kind.rawValue)\(mood): a \(o.base?.name.lowercased() ?? "") of \(o.scoops.map { $0.name.lowercased() }.joined(separator: ", "))\(toppings)"
        }

        static func ease(_ t: Double, out: Bool) -> Double { out ? 1 - pow(1 - t, 3) : t * t }
    }

    // MARK: The prep bench: tiles behind, the shopkeeper behind it, the treat
    // being made on it, a chalkboard for what's next, and the menu board

    private var hintText: String {
        if !hint.isEmpty { return hint }
        if !news.isEmpty { return news }
        if shift.alarm { return "Hurry!" }
        if shift.build.base == nil { return "Cone or cup?" }
        if shift.build.scoops.isEmpty { return "Now the scoops" }
        return "Tap a customer to serve"
    }

    private var hintColor: Color {
        if !hint.isEmpty || (news.isEmpty && shift.alarm) { return Color(rgb: 0xFFB3C1) }
        return news.isEmpty ? Color(rgb: 0xF4F1E8) : Color(rgb: 0xF6D57A)
    }

    /// The bench's measures, from its size.
    private struct Bench {
        let w, h, pad, benchH, benchY, boardY, boardH: CGFloat
        var boardBottom: CGFloat { boardY + boardH }
        let crew: CGRect
        var treat: CGRect
        /// Where the menu board goes, if the wall has room for it, and in
        /// how many columns.
        var menu: CGRect?
        var menuColumns = 1

        /// `menus`: the board's size in one column, then in two.
        init(_ size: CGSize, narrow: Bool, menus: [CGSize]) {
            w = size.width
            h = size.height
            pad = narrow ? 10 : 16
            benchH = max(26, min(90, h * 0.16)).rounded()
            benchY = h - benchH
            boardY = pad - 2
            boardH = narrow ? 28 : 36
            // Standing behind the bench: its top hides their feet.
            let feet = benchY + benchH * 0.55
            let ch = max(0, min(feet - boardY - boardH - 8, w * 0.48 * 1.2))
            crew = CGRect(x: pad, y: feet - ch, width: ch / 1.2, height: ch)
            // On the bench top, in proportion to whoever is making it.
            let stand = benchY + benchH * 0.3
            let th = max(0, min(stand - boardY - boardH - 4, ch * 1.5))
            treat = CGRect(x: crew.maxX, y: stand - th, width: max(0, w - crew.maxX - pad), height: th)
            // On a tall wall, the day's scoops over what stands on the bench,
            // as the display has them; on a wide one, beside the treat; in two
            // columns if one is too tall.
            let space = min(crew.minY, treat.minY) - boardY - boardH - 2 * pad
            let drawn = min(treat.width, th * 5 / 12.4)
            let room = treat.width - drawn - pad
            let tall = benchY - boardY - boardH - 2 * pad
            for (i, size) in menus.enumerated() {
                if space >= size.height && size.width <= w - 2 * pad {
                    menu = CGRect(x: (w - size.width) / 2, y: boardY + boardH + pad + (space - size.height) / 2,
                                  width: size.width, height: size.height)
                } else if room >= size.width + pad && tall >= size.height {
                    menu = CGRect(x: w - pad - size.width, y: boardY + boardH + pad + (tall - size.height) / 2,
                                  width: size.width, height: size.height)
                    treat.size.width = max(drawn, treat.width - size.width - pad)
                } else {
                    continue
                }
                menuColumns = i + 1
                break
            }
        }
    }

    private func station(_ layout: Layout, _ look: ScoopLook) -> some View {
        let flavours = shift.rules.flavours
        let rows = { (columns: Int) in CGFloat((flavours.count + columns - 1) / columns) }
        let b = Bench(layout.station.size, narrow: layout.narrow,
                      menus: [CGSize(width: 260, height: 28 + 26 + rows(1) * 26), CGSize(width: 400, height: 28 + 26 + rows(2) * 26)])
        let corner = layout.corner
        let inset = (corner * 0.3).rounded(.up)
        let u = min(b.treat.width / 5, b.treat.height / 12.4)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color(rgb: look.grout))
            ScoopTiles(look: look, tileHeight: max(14, (b.h / 13).rounded())).equatable()
                .frame(width: max(0, b.w - 2 * inset), height: max(0, b.benchY - inset))
                .offset(x: inset, y: inset)
            // What's next, on a chalkboard.
            Text(hintText)
                .font((layout.narrow ? Font.footnote : .subheadline).weight(.semibold))
                .foregroundStyle(hintColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .frame(height: b.boardH)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(rgb: look.board)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(rgb: look.boardFrame), lineWidth: layout.narrow ? 3 : 4))
                .frame(maxWidth: b.w - 2 * b.pad)
                .frame(width: b.w)
                .offset(y: b.boardY)
            if let menu = b.menu {
                menuBoard(flavours, look, columns: b.menuColumns)
                    .frame(width: menu.width, height: menu.height)
                    .offset(x: menu.minX, y: menu.minY)
            }
            ScoopCrewView(who: shift.worker, happy: mood == .happy, oops: mood == .oops, panic: shift.alarm, hops: hops, shakes: shakes)
                .frame(width: b.crew.width, height: b.crew.height)
                .offset(x: b.crew.minX, y: b.crew.minY)
            BenchFront(look: look, corner: corner).equatable()
                .frame(width: b.w, height: b.benchH)
                .offset(y: b.benchY)
            ScoopTreatView(order: shift.build)
                .frame(width: b.treat.width, height: b.treat.height)
                .overlay(alignment: .bottom) {
                    // A cone stands in a holder.
                    if shift.build.base == .cone {
                        let dark = look == .evening
                        RoundedRectangle(cornerRadius: u * 2.2 * 0.18)
                            .fill(LinearGradient(colors: dark ? [Color(rgb: 0xA9B4BE), Color(rgb: 0x7E8A95)] : [Color(rgb: 0xD2D9DF), Color(rgb: 0xA3AEB8)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: u * 2.2, height: u * 1.5)
                            .offset(y: u * 1.5 * 0.1)
                    }
                }
                .keyframeAnimator(initialValue: 0.0, trigger: treatShake) { content, x in
                    content.offset(x: x * 6)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-1, duration: 0.05)
                        LinearKeyframe(1, duration: 0.1)
                        LinearKeyframe(0, duration: 0.05)
                    }
                }
                .offset(x: b.treat.minX, y: b.treat.minY)
        }
        .frame(width: b.w, height: b.h, alignment: .topLeading)
    }

    /// The day's scoops: what's on offer at this level.
    private func menuBoard(_ flavours: [ScoopFlavour], _ look: ScoopLook, columns: Int) -> some View {
        VStack(spacing: 0) {
            Text("Today's scoops")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(rgb: 0xF6D57A))
                .frame(maxWidth: .infinity)
                .frame(height: 26, alignment: .top)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .leading), count: columns), spacing: 0) {
                ForEach(flavours, id: \.self) { f in
                    HStack(spacing: 12) {
                        Circle().fill(Color(rgb: ScoopTreatView.flavours[f]!.fill)).frame(width: 14, height: 14)
                        Text(f.name).font(.subheadline).foregroundStyle(Color(rgb: 0xF4F1E8)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(height: 26)
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(rgb: look.board)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(rgb: look.boardFrame), lineWidth: 5))
        .accessibilityElement(children: .combine)
    }

    /// The bench: a marble top over a mint front, rounded with the card.
    private struct BenchFront: View, Equatable {
        let look: ScoopLook
        let corner: CGFloat

        var body: some View {
            Canvas { ctx, size in
                let r = min(corner, size.height)
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size),
                              cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0)),
                         with: .color(Color(rgb: look.lip)))
                let top = (size.height * 0.36).rounded()
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: top)), with: .color(Color(rgb: look.marble)))
                ctx.fill(Path(CGRect(x: 0, y: top - 1, width: size.width, height: 1)), with: .color(Color(rgb: look.lipEdge)))
            }
        }
    }

    // MARK: Behind the counter: the freezer case of tubs, the shelf of
    // cones, cups and jars, and undo

    private func pad(_ layout: Layout, _ look: ScoopLook) -> some View {
        let g = layout.pg
        let caseRect = layout.span { if case .flavour = $0 { return true } else { return false } }
        var shelves = [layout.span { if case .topping = $0 { return true } else { return false } }]
        if layout.base == nil { shelves.append(layout.span { if case .base = $0 { return true } else { return false } }) }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: min(Theme.radiusSm, layout.bh * 0.25) + g / 2, style: .continuous)
                .fill(Color(rgb: look.caseBody))
                .overlay(RoundedRectangle(cornerRadius: min(Theme.radiusSm, layout.bh * 0.25) + g / 2, style: .continuous)
                    .stroke(Color(rgb: look.caseBody, scaled: 1 / 1.15), lineWidth: 1))
                .frame(width: caseRect.width + g, height: caseRect.height + g)
                .offset(x: caseRect.minX - g / 2, y: caseRect.minY - g / 2)
            ForEach(Array(shelves.enumerated()), id: \.offset) { _, r in
                shelf(look, width: r.width + g, height: max(6, g))
                    .offset(x: r.minX - g / 2, y: r.maxY - max(6, g) / 2)
            }
            ForEach(layout.keys, id: \.0) { key, column, row, span in
                let cell = layout.cell(column, row, span)
                padButton(key, look, labelled: layout.bh >= 76, gap: g)
                    .frame(width: cell.width + g, height: cell.height + g)
                    .offset(x: cell.minX - g / 2, y: cell.minY - g / 2)
            }
        }
        .frame(width: layout.pad.width, height: layout.pad.height, alignment: .topLeading)
    }

    /// Beside the counter: the cones, the cups and undo, over the bench.
    private func baseRow(_ layout: Layout, _ look: ScoopLook) -> some View {
        let g = layout.pg, bw = layout.baseW, bh = layout.bh
        return ZStack(alignment: .topLeading) {
            shelf(look, width: 2 * bw + 2 * g, height: max(6, g))
                .offset(x: -g / 2, y: bh - max(6, g) / 2)
            ForEach(Array(Layout.baseKeys.enumerated()), id: \.offset) { i, key in
                padButton(key, look, labelled: bh >= 76, gap: g)
                    .frame(width: bw + g, height: bh + g)
                    .offset(x: CGFloat(i) * (bw + g) - g / 2, y: -g / 2)
            }
        }
        .frame(width: layout.base?.width ?? 0, height: bh, alignment: .topLeading)
    }

    private func shelf(_ look: ScoopLook, width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(Color(rgb: look.shelf)).frame(width: width, height: height)
    }

    /// A button: on a pane of the freezer case, or a place on the shelf,
    /// what it adds; the chosen cone or cup and toppings already on lit up.
    private func padButton(_ key: ScoopKey, _ look: ScoopLook, labelled: Bool, gap: CGFloat) -> some View {
        let build = shift.build
        let chosen: Bool
        let ready: Bool
        let fill: Color
        switch key {
        case .base(let b):
            chosen = build.base == b
            ready = true
            fill = Color(rgb: look.item)
        case .flavour:
            chosen = false
            ready = build.base != nil
            fill = Color(rgb: look.pane)
        case .topping(let t):
            chosen = build.toppings.contains(t)
            ready = !build.scoops.isEmpty
            fill = Color(rgb: look.item)
        case .undo:
            chosen = false
            ready = true
            fill = Theme.surface
        }
        let dark = look == .evening
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { tap(key) } label: {
            VStack(spacing: 2) {
                Group {
                    if key == .undo {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
                    } else {
                        ScoopStockView(key: key, dark: dark).equatable()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(ready ? 1 : 0.4)
                if labelled {
                    Text(key.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(chosen ? Theme.accent : Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background {
                // Glass: a pane with a sheen across its top and a bright edge.
                shape.fill(chosen ? Theme.accentSoft : fill)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.08 : 0.5), .white.opacity(0)],
                                                       startPoint: .top, endPoint: .center)))
                    .overlay(shape.strokeBorder(chosen ? Theme.accent : .white.opacity(dark ? 0.12 : 0.7), lineWidth: chosen ? 2 : 1))
            }
            .padding(gap / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(key.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Who works the shift: at the start, and once the shop closes.
    // The shop front: the awning over the wall, who's on shift beneath.

    private func chooser(_ layout: Layout, _ look: ScoopLook, size: CGSize) -> some View {
        let over = shift.phase == .over
        // The words beside the cards only where the stage is short.
        let side = layout.shape == .side && size.height < 500
        let awning = side ? 24 : min(64, max(36, size.height * 0.07)).rounded()
        let below = awning + (side ? 10 : 24)
        let corner = layout.corner
        let words = VStack(alignment: side ? .leading : .center, spacing: 6) {
            Text(over ? "Closing time!" : "Who's on shift?")
                .font(.title.weight(.semibold))
                .foregroundStyle(Theme.text)
            Group {
                if over {
                    Text("\(shift.score) points, \(shift.served) served. ") + Text(shift.newBest ? "A new best!" : "Best \(shift.best).")
                } else {
                    Text(shift.best > 0 ? "Best \(shift.best). Build each order before the customer gives up." : "Build each order before the customer gives up.")
                }
            }
            .font(.subheadline.weight(over && shift.newBest ? .semibold : .regular))
            .foregroundStyle(over && shift.newBest ? Theme.success : Theme.muted)
            .multilineTextAlignment(side ? .leading : .center)
            if over {
                Text("Who's on next?").font(.subheadline).foregroundStyle(Theme.text).padding(.top, 6)
            }
        }
        let cards = HStack(spacing: 14) {
            ForEach(ScoopKeeper.allCases, id: \.self) { who in
                Button {
                    GameProgress.shared.scoopWorker = who
                    shift.start(who)
                    hint = ""
                    news = ""
                } label: {
                    VStack(spacing: 2) {
                        ScoopCrewView(who: who)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.bottom, 8)
                        Text(who == .pip ? "Pip" : "Lotl").font(.headline).foregroundStyle(Theme.text)
                        Text(who == .pip ? "the penguin" : "the axolotl").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(12)
                    .frame(maxWidth: 240, maxHeight: 300)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(who == .pip ? "Pip the penguin" : "Lotl the axolotl")
            }
        }
        return ZStack(alignment: .topLeading) {
            ScoopWallpaper(look: look, radius: corner, stripe: layout.narrow ? 22 : 34).equatable()
            ScoopAwning(look: look, sign: "Pip & Lotl's", stripeWidth: layout.narrow ? 24 : 40).equatable()
                .frame(width: max(0, size.width - 2 * corner), height: awning)
                .offset(x: corner)
            Group {
                if side {
                    HStack(spacing: 20) {
                        words.frame(maxWidth: .infinity, alignment: .leading)
                        cards.frame(maxWidth: min(480, size.width * 0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                } else {
                    VStack(spacing: 24) {
                        Spacer(minLength: 0)
                        words.frame(maxWidth: 520)
                        cards.frame(maxHeight: 320)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: size.width, height: max(0, size.height - below))
            .offset(y: below)
        }
    }

    // MARK: Paused: the shop hidden; carry on, or end the shift.

    private var paused: some View {
        VStack(spacing: 16) {
            ScoopCrewView(who: shift.worker).frame(width: 150, height: 180)
            Text("Paused").font(.largeTitle.weight(.semibold)).foregroundStyle(Theme.text)
            HStack(spacing: 14) {
                Button("Carry on") { shift.resume() }.buttonStyle(.gamePill())
                Button("End shift") {
                    shift.endShift()
                    saveBest()
                }
                .buttonStyle(.gamePill(.neutral))
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
