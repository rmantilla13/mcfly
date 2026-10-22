import Foundation

/// How full one day is, from its timed events: where two or more run at once
/// (conflicts), which follow each other with no room between (back to back,
/// five minutes or less), the run of events with the most booked time (the
/// busiest stretch), and how booked each quarter hour's surroundings are,
/// for drawing. All-day events take no time here; one that runs over
/// midnight counts only for its part of the day.
public struct DayLoad: Sendable {
    public enum Kind: Sendable, Equatable {
        case clear, backToBack, conflict
    }

    /// A stretch of the day.
    public struct Span: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// The day's start, which `heat` counts quarter hours from.
    public let dayStart: Date
    /// Where two or more events run at once, in order.
    public let conflicts: [Span]
    /// The events that overlap another, and those that sit back to back with one.
    public let conflicting: Set<UUID>
    public let backToBack: Set<UUID>
    /// How many links there are between back-to-back events (three in a row is two).
    public let backToBackCount: Int
    /// The run of events (15 minutes or less between them) with the most
    /// booked time, when that is an hour or more of two events or more: one
    /// long event alone isn't a busy stretch.
    public let busiest: Span?
    /// For each quarter hour of the day (96), how much of the two hours
    /// around it is booked, 0 to 1.
    public let heat: [Double]

    /// Within this, one event's end and the next one's start are back to back.
    public static let backToBackGap: TimeInterval = 5 * 60
    static let slot: TimeInterval = 15 * 60
    static let window = 8 // quarter hours: the two hours heat looks at
    static let stretchGap: TimeInterval = 15 * 60
    static let busiestFloor: TimeInterval = 60 * 60

    public init(events: [CalendarEvent], day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        dayStart = start
        // Each timed event's part of this day, by start then end.
        let timed: [(id: UUID, start: Date, end: Date)] = events
            .filter { !$0.allDay }
            .compactMap { e in
                let s = max(e.startsAt, start), f = min(e.endsAt, end)
                return f > s ? (e.id, s, f) : nil
            }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }

        // Conflicts: walk in start order, keeping the furthest end so far and
        // who reaches it; anything starting before it overlaps.
        var overlaps: [Span] = []
        var conflicting = Set<UUID>()
        var reach: (end: Date, id: UUID)?
        for e in timed {
            if let r = reach, e.start < r.end {
                overlaps.append(Span(start: e.start, end: min(e.end, r.end)))
                conflicting.insert(e.id)
                conflicting.insert(r.id)
            }
            if reach == nil || e.end > reach!.end { reach = (e.end, e.id) }
        }
        conflicts = Self.merge(overlaps)
        self.conflicting = conflicting

        // Back to back: the next event starts at, or up to five minutes
        // after, the latest end so far.
        var linked = Set<UUID>()
        var links = 0
        reach = nil
        for e in timed {
            if let r = reach, e.start >= r.end, e.start.timeIntervalSince(r.end) <= Self.backToBackGap {
                linked.insert(e.id)
                linked.insert(r.id)
                links += 1
            }
            if reach == nil || e.end > reach!.end { reach = (e.end, e.id) }
        }
        backToBack = linked
        backToBackCount = links

        // Booked quarter hours (any event, overlaps counted once), then the
        // booked share of the two hours around each.
        var booked = [Double](repeating: 0, count: 96)
        for e in timed {
            let first = Int(e.start.timeIntervalSince(start) / Self.slot)
            let last = Int((e.end.timeIntervalSince(start) / Self.slot).rounded(.up))
            for i in max(0, first)..<min(96, last) {
                let slotStart = start.addingTimeInterval(Double(i) * Self.slot)
                let covered = min(e.end, slotStart.addingTimeInterval(Self.slot)).timeIntervalSince(max(e.start, slotStart))
                booked[i] = max(booked[i], covered / Self.slot)
            }
        }
        // Overlapping events in one slot count once, at the larger share:
        // close enough for a strip, and never more than the slot.
        heat = (0..<96).map { i in
            let from = max(0, i - Self.window / 2), to = min(96, i + Self.window / 2)
            return booked[from..<to].reduce(0, +) / Double(Self.window)
        }
        // Stretches: events joined while the next starts within 15 minutes
        // of the latest end, each with its booked time (overlaps once). The
        // busiest is the one with the most, the earlier on a tie.
        var stretches: [(span: Span, booked: TimeInterval, count: Int)] = []
        for e in timed {
            if let last = stretches.last, e.start.timeIntervalSince(last.span.end) <= Self.stretchGap {
                let added = max(0, e.end.timeIntervalSince(max(e.start, last.span.end)))
                stretches[stretches.count - 1] = (Span(start: last.span.start, end: max(last.span.end, e.end)), last.booked + added, last.count + 1)
            } else {
                stretches.append((Span(start: e.start, end: e.end), e.end.timeIntervalSince(e.start), 1))
            }
        }
        let top = stretches.filter { $0.count >= 2 }.reduce(nil as (span: Span, booked: TimeInterval, count: Int)?) { best, s in
            s.booked > (best?.booked ?? 0) ? s : best
        }
        busiest = top.flatMap { $0.booked >= Self.busiestFloor ? $0.span : nil }
    }

    /// The day's events, by what they run into.
    public func kind(of event: CalendarEvent) -> Kind {
        if conflicting.contains(event.id) { return .conflict }
        if backToBack.contains(event.id) { return .backToBack }
        return .clear
    }

    /// How many separate stretches overlap.
    public var conflictCount: Int { conflicts.count }

    /// Overlaps that touch or cross, joined.
    static func merge(_ spans: [Span]) -> [Span] {
        var out: [Span] = []
        for s in spans.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, s.start <= last.end {
                out[out.count - 1] = Span(start: last.start, end: max(last.end, s.end))
            } else {
                out.append(s)
            }
        }
        return out
    }
}
