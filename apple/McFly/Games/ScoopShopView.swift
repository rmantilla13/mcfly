import McFlyKit
import SwiftUI

/// Scoop Shop (display/qml/games/ScoopShop.qml, its rules in the kit's
/// `ScoopShift`): an ice cream counter against the clock. Pick who works the
/// shift, build each customer's ticket from the buttons, and tap the
/// customer to hand it over. The clock runs only while the shop is open and
/// in view: how to play, the app going away, or the pause button stop it,
/// and the shop hides while paused (no peeking at tickets). The best score
/// and who worked last are kept on the device.
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
            ZStack(alignment: .topLeading) {
                if shift.playing {
                    hud(layout).frame(width: layout.hud.width, height: layout.hud.height).offset(x: layout.hud.minX, y: layout.hud.minY)
                    counter(layout).frame(width: layout.counter.width, height: layout.counter.height)
                        .offset(x: layout.counter.minX, y: layout.counter.minY)
                    station.frame(width: layout.station.width, height: layout.station.height)
                        .offset(x: layout.station.minX, y: layout.station.minY)
                    pad(layout).frame(width: layout.pad.width, height: layout.pad.height).offset(x: layout.pad.minX, y: layout.pad.minY)
                }
                if shift.phase != .playing {
                    chooser(side: layout.shape == .side).frame(width: geo.size.width, height: geo.size.height)
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
            news = "Level \(level): busier!"
            Task {
                try? await Task.sleep(for: .seconds(2))
                if news == "Level \(level): busier!" { news = "" }
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

    private func tap(_ key: Key) {
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
    /// tall, the counter over the buttons and the treat beside them; upright,
    /// the score, the counter, the treat, the buttons; else the counter over
    /// the treat and the buttons side by side.
    private struct Layout {
        enum Shape { case side, tall, square }
        var shape: Shape
        var hud, counter, station, pad: CGRect
        var bw: CGFloat, bh: CGFloat
        let pg: CGFloat = 10
        let gap: CGFloat = 12
        static let target: CGFloat = 48

        init(size: CGSize) {
            let w = size.width, h = size.height, g = gap, t = Self.target, pg = pg
            if w > h * 1.4 {
                let sw = (min(300, max(200, w * 0.28))).rounded()
                let lw = w - sw - g
                let bh = max(t, min(96, ((h - g) * 0.22).rounded(.down)))
                let ph = 2 * bh + pg
                shape = .side
                hud = CGRect(x: lw + g, y: 0, width: sw, height: t)
                counter = CGRect(x: 0, y: 0, width: lw, height: h - ph - g)
                station = CGRect(x: lw + g, y: t + g, width: sw, height: h - t - g)
                pad = CGRect(x: 0, y: h - ph, width: lw, height: ph)
                bw = (lw - 5 * pg) / 6
                self.bh = bh
                return
            }
            let top = t + g
            if h > w * 1.25 {
                let bw = (w - 3 * pg) / 4
                let bh = max(t, min(104, (bw * 0.75).rounded(.down)))
                let ph = 3 * bh + 2 * pg
                let ch = max(150, min(w / 4 * 1.75, h - top - g - ph - g - 200))
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
            let pw = min(w * 0.6, 4 * 180 + 3 * pg)
            let ch = max(150, min(slot * 1.6, h - top - g - (3 * t + 2 * pg)))
            let sh = max(0, h - top - ch - g)
            let bh = max(t, min(110, ((sh - 2 * pg) / 3).rounded(.down)))
            let ph = 3 * bh + 2 * pg
            shape = .square
            hud = CGRect(x: 0, y: 0, width: w, height: t)
            counter = CGRect(x: 0, y: top, width: w, height: ch)
            station = CGRect(x: 0, y: top + ch + g, width: max(0, w - pw - g), height: sh)
            pad = CGRect(x: w - pw, y: h - ph, width: pw, height: ph)
            bw = (pw - 3 * pg) / 4
            self.bh = bh
        }

        /// The buttons: [key, column, row, columns spanned], in the side
        /// shape's 6 × 2 grid and the others' 4 × 3.
        var keys: [(Key, Int, Int, Int)] {
            if shape == .side {
                return [(.base(.cone), 0, 0, 1), (.base(.cup), 1, 0, 1), (.flavour(.vanilla), 2, 0, 1), (.flavour(.chocolate), 3, 0, 1),
                        (.flavour(.strawberry), 4, 0, 1), (.flavour(.mint), 5, 0, 1), (.topping(.sprinkles), 0, 1, 1),
                        (.topping(.cherry), 1, 1, 1), (.topping(.wafer), 2, 1, 1), (.undo, 5, 1, 1)]
            }
            return [(.base(.cone), 0, 0, 2), (.base(.cup), 2, 0, 2), (.flavour(.vanilla), 0, 1, 1), (.flavour(.chocolate), 1, 1, 1),
                    (.flavour(.strawberry), 2, 1, 1), (.flavour(.mint), 3, 1, 1), (.topping(.sprinkles), 0, 2, 1),
                    (.topping(.cherry), 1, 2, 1), (.topping(.wafer), 2, 2, 1), (.undo, 3, 2, 1)]
        }
    }

    fileprivate enum Key: Hashable {
        case base(ScoopBase), flavour(ScoopFlavour), topping(ScoopTopping), undo

        var name: String {
            switch self {
            case .base(let b): return b.rawValue.capitalized
            case .flavour(let f): return f.rawValue.capitalized
            case .topping(let t): return t.rawValue.capitalized
            case .undo: return "Undo"
            }
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

    // MARK: The counter

    private func counter(_ layout: Layout) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let slot = layout.shape == .side ? w / CGFloat(Scoops.maxSeats) : min(w / CGFloat(Scoops.maxSeats), 320)
            let slotsX = (w - slot * CGFloat(Scoops.maxSeats)) / 2
            let critter = min(slot * 0.62, h * (layout.shape == .side ? 0.3 : 0.36))
            let band = (critter * 0.3).rounded()
            ZStack(alignment: .topLeading) {
                ForEach(0..<Scoops.maxSeats, id: \.self) { index in
                    SeatView(customer: shift.seats[index], now: shift.now, open: index < shift.rules.seats,
                             playing: shift.phase == .playing, index: index, critter: critter, band: band) { deliver(index) }
                        .frame(width: slot, height: h)
                        .offset(x: slotsX + CGFloat(index) * slot)
                }
                // The counter top, in front of the customers.
                RoundedRectangle(cornerRadius: min(Theme.radiusSm, band / 2), style: .continuous)
                    .fill(Theme.surface)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(rgb: 0x56C3A0)).frame(height: 4).padding(.horizontal, min(Theme.radiusSm, band / 2))
                    }
                    .frame(width: w, height: band)
                    .offset(y: h - band)
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
    }

    /// A seat at the counter: the ticket (what they'd like, and how long
    /// they'll wait) over the customer; as they leave, how it went.
    private struct SeatView: View {
        let customer: ScoopCustomer?
        let now: Double
        let open: Bool
        let playing: Bool
        let index: Int
        let critter: CGFloat
        let band: CGFloat
        let deliver: () -> Void

        var body: some View {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let pad: CGFloat = 6
                let ticketH = h - critter - 4
                if let c = customer {
                    let arrive = Self.ease(min(1, max(0, (now - c.arrived) / 400)), out: true)
                    let leave = c.gone == .waiting ? 0 : Self.ease(min(1, max(0, (now - c.goneAt) / (ScoopShift.leaveMs - 100))), out: false)
                    let left = c.patienceLeft(at: now)
                    let shown = arrive * (1 - leave)
                    ZStack(alignment: .topLeading) {
                        // The ticket's tail, down to the customer.
                        Rectangle().fill(Theme.surface)
                            .frame(width: 12, height: 12)
                            .rotationEffect(.degrees(45))
                            .offset(x: (w - 12) / 2, y: ticketH - 7)
                        VStack(spacing: pad) {
                            if c.gone == .waiting {
                                ScoopTreatView(order: c.order)
                            } else {
                                Spacer()
                            }
                            Capsule().fill(Theme.sunken)
                                .frame(height: 8)
                                .overlay(alignment: .leading) {
                                    GeometryReader { bar in
                                        Capsule()
                                            .fill(left > 0.5 ? Theme.success : left > 0.25 ? Theme.warning : Theme.danger)
                                            .frame(width: bar.size.width * left)
                                    }
                                }
                        }
                        .padding(pad)
                        .frame(width: w - 8, height: ticketH)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.danger, lineWidth: c.gone == .wrong || c.gone == .late ? 3 : 0))
                        .offset(x: 4)
                        CritterView(kind: c.kind, face: face(c, left))
                            .frame(width: critter * 10 / 9, height: critter)
                            .offset(x: (w - critter * 10 / 9) / 2,
                                    y: h - critter + (1 - arrive + leave) * band * 0.6 - band * 0.4)
                        // How it went, on the ticket: the points, or what went wrong, rising.
                        if c.gone != .waiting {
                            Text(c.gone == .right ? "+\(c.points)" : c.gone == .wrong ? "Wrong order" : "Too slow")
                                .font(c.gone == .right ? .title2.weight(.bold) : .subheadline.weight(.bold))
                                .foregroundStyle(c.gone == .right ? Theme.success : Theme.danger)
                                .multilineTextAlignment(.center)
                                .frame(width: w - 16)
                                .offset(x: 8, y: ticketH / 2 - 14 - leave * ticketH * 0.2)
                                .opacity(1 - leave * leave)
                        }
                    }
                    .opacity(shown)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: deliver)
                    .accessibilityElement()
                    .accessibilityLabel(describe(c))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { deliver() }
                } else if !open && playing {
                    // A seat that opens later.
                    Text("Opens at level \(index < 3 ? 3 : 5)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(width: w - 12)
                        .offset(x: 6, y: ticketH * 0.45)
                }
            }
        }

        private func face(_ c: ScoopCustomer, _ left: Double) -> CritterView.Face {
            switch c.gone {
            case .right: return .happy
            case .wrong, .late: return .cross
            case .waiting: return left > 0.5 ? .smile : left > 0.25 ? .flat : .frown
            }
        }

        private func describe(_ c: ScoopCustomer) -> String {
            let o = c.order
            let toppings = o.toppings.isEmpty ? "" : ", with " + o.toppings.map(\.rawValue).joined(separator: " and ")
            return "A \(c.kind.rawValue): a \(o.base?.rawValue ?? "") with \(o.scoops.map(\.rawValue).joined(separator: ", "))\(toppings)"
        }

        static func ease(_ t: Double, out: Bool) -> Double { out ? 1 - pow(1 - t, 3) : t * t }
    }

    // MARK: The treat being made, and who's making it

    private var hintText: String {
        if !hint.isEmpty { return hint }
        if !news.isEmpty { return news }
        if shift.build.base == nil { return "Cone or cup?" }
        if shift.build.scoops.isEmpty { return "Now the scoops" }
        return "Tap a customer to serve"
    }

    private var station: some View {
        GeometryReader { geo in
            let pad: CGFloat = 12
            VStack(spacing: 4) {
                Text(hintText)
                    .font(.subheadline.weight(hint.isEmpty && news.isEmpty ? .regular : .semibold))
                    .foregroundStyle(!hint.isEmpty ? Theme.warningInk : !news.isEmpty ? Theme.accent : Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .bottom, spacing: 0) {
                    let room = geo.size.height - 40
                    let crewWidth = max(0, min(geo.size.width * 0.42, room * 0.8))
                    ScoopCrewView(who: shift.worker, happy: mood == .happy, oops: mood == .oops, hops: hops, shakes: shakes)
                        .frame(width: crewWidth, height: crewWidth * 1.2)
                    ScoopTreatView(order: shift.build)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .keyframeAnimator(initialValue: 0.0, trigger: treatShake) { content, x in
                            content.offset(x: x * 6)
                        } keyframes: { _ in
                            KeyframeTrack {
                                LinearKeyframe(-1, duration: 0.05)
                                LinearKeyframe(1, duration: 0.1)
                                LinearKeyframe(0, duration: 0.05)
                            }
                        }
                }
            }
            .padding(pad)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    // MARK: The buttons

    private func pad(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.keys, id: \.0) { key, column, row, span in
                padButton(key, labelled: layout.bh >= 84)
                    .frame(width: CGFloat(span) * layout.bw + CGFloat(span - 1) * layout.pg, height: layout.bh)
                    .offset(x: CGFloat(column) * (layout.bw + layout.pg), y: CGFloat(row) * (layout.bh + layout.pg))
            }
        }
        .frame(width: layout.pad.width, height: layout.pad.height, alignment: .topLeading)
    }

    private func padButton(_ key: Key, labelled: Bool) -> some View {
        let build = shift.build
        let chosen: Bool
        let ready: Bool
        let picture: ScoopOrder
        let units: CGFloat
        let lift: CGFloat
        switch key {
        case .base(let b):
            chosen = build.base == b
            ready = true
            picture = ScoopOrder(base: b)
            units = b == .cone ? 5 : 4
            lift = 0.25
        case .flavour(let f):
            chosen = false
            ready = build.base != nil
            picture = ScoopOrder(scoops: [f])
            units = 3
            lift = 0.3
        case .topping(let t):
            chosen = build.toppings.contains(t)
            ready = !build.scoops.isEmpty
            picture = ScoopOrder(toppings: [t])
            units = 3.2
            lift = 0
        case .undo:
            chosen = false
            ready = true
            picture = ScoopOrder()
            units = 12
            lift = 0
        }
        return Button { tap(key) } label: {
            VStack(spacing: 2) {
                Group {
                    if key == .undo {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                    } else {
                        ScoopTreatView(order: picture, units: units, lift: lift)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(ready ? 1 : 0.4)
                if labelled {
                    Text(key.name).font(.caption.weight(.medium)).foregroundStyle(chosen ? Theme.accent : Theme.text).lineLimit(1)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(chosen ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous).stroke(Theme.accent, lineWidth: chosen ? 2 : 0))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(key.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Who works the shift: at the start, and once the shop closes

    private func chooser(side: Bool) -> some View {
        let over = shift.phase == .over
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
                    .frame(maxWidth: 220, maxHeight: 280)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(who == .pip ? "Pip the penguin" : "Lotl the axolotl")
            }
        }
        return Group {
            if side {
                HStack(spacing: 24) { words.frame(maxWidth: .infinity, alignment: .leading); cards.frame(maxWidth: 460) }
            } else {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)
                    words.frame(maxWidth: 520)
                    cards.frame(maxHeight: 300)
                    Spacer(minLength: 0)
                }
            }
        }
        .background(Theme.background)
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
