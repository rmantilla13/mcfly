import Foundation

/// One row of today: a Pulse report, a brief, a project update or an event.
public struct TimelineItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case news, brief, alert, project, event
    }

    /// What a tap opens.
    public enum Target: Hashable, Sendable {
        case report(UUID)
        case brief(UUID)
        case project(UUID)
        case event(UUID)
    }

    /// Where the row sits against the clock. Only timed events have one.
    public enum RowState: Sendable {
        case none, past, now, next
    }

    public let id: String
    public let kind: Kind
    public let start: Date
    public let end: Date
    public let allDay: Bool
    /// "3:30", or "All day".
    public let time: String
    /// "pm"; empty for all-day rows and on a 24-hour clock.
    public let ampm: String
    /// The kicker: source and kind ("Grok · Daily"), the project, the calendar.
    public let label: String
    public let title: String
    public let detail: String
    /// "#rrggbb": the agent's, the project status's or the event's.
    public let color: String
    public let imageURL: URL?
    /// The row's symbol; a project row shows its update's kind.
    public let systemImage: String
    public let target: Target
}

/// Today, as one stream: what arrived and what is planned, in time order.
/// The phone's twin of the display's timeline (display/src/models/FeedStore.cpp,
/// `rebuildTimeline`) and the web's (admin/lib/today.ts): the same rows, the
/// same order and the same past / now / next rules. Pure, so the tests can
/// check it against the web's cases.
public enum Timeline {
    /// The display's status colours (FeedStore.cpp, `statusColor`).
    public static func statusColor(_ status: Project.Status) -> String {
        switch status {
        case .blocked: return "#F07F5A"
        case .paused: return "#F6B94A"
        case .planned: return "#7C8CF8"
        case .done: return "#8F95A1"
        case .active: return "#3DB37A"
        }
    }

    public static let defaultColor = "#5B7CF5"

    public static func build(briefs: [Brief], reports: [NewsReport], projects: [Project], events: [CalendarEvent],
                             agents: [Agent], now: Date, calendar: Calendar = .current,
                             locale: Locale = .current) -> [TimelineItem] {
        let clock = Clock(calendar: calendar, locale: locale)
        let today = calendar.startOfDay(for: now)
        let todayKey = dayKey(now, calendar: calendar)
        let byId = Dictionary(agents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func onToday(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: now) }

        var rows: [TimelineItem] = []
        func add(_ id: String, _ kind: TimelineItem.Kind, start: Date, end: Date? = nil, allDay: Bool = false,
                 label: String, title: String, detail: String, color: String, imageURL: URL? = nil,
                 systemImage: String, target: TimelineItem.Target) {
            let face = allDay ? (time: "All day", ampm: "") : clock.parts(start)
            rows.append(TimelineItem(id: id, kind: kind, start: start, end: end ?? start, allDay: allDay,
                                     time: face.time, ampm: face.ampm, label: label, title: title, detail: detail,
                                     color: color, imageURL: imageURL, systemImage: systemImage, target: target))
        }

        // Today's reports, every source: the top story, and how many more.
        for report in reports where report.reportDate == todayKey {
            guard let hero = report.hero else { continue }
            let others = report.items.filter { $0.itemKey != hero.itemKey }.prefix(2).map(\.headline)
            let more = report.items.count - 1 - others.count
            var detail = others.joined(separator: " · ")
            if more > 0 { detail += " · \(more) more" }
            let name = byId[report.agentId]?.name ?? ""
            let source = name.isEmpty ? "Daily Pulse" : name
            // Written last night for today, it opens the day.
            let at = onToday(report.publishedAt) ? report.publishedAt : today
            add("news:\(report.id)", .news, start: at,
                label: "\(source) · \(report.items.count == 1 ? "1 story" : "\(report.items.count) stories")",
                title: hero.headline, detail: detail, color: byId[report.agentId]?.color ?? defaultColor,
                imageURL: hero.image, systemImage: "newspaper", target: .report(report.id))
        }

        for brief in briefs where onToday(brief.publishedAt) {
            let agent = byId[brief.agentId]
            let name = agent?.name ?? ""
            add("brief:\(brief.id)", brief.kind == .alert ? .alert : .brief, start: brief.publishedAt,
                label: name.isEmpty ? brief.kind.label : "\(name) · \(brief.kind.label)",
                title: brief.title, detail: summary(brief.body), color: agent?.color ?? defaultColor,
                systemImage: brief.kind == .alert ? "exclamationmark.circle" : "text.alignleft", target: .brief(brief.id))
        }

        for project in projects {
            for update in project.updates where onToday(update.happenedAt) {
                add("project:\(project.id):\(update.id)", .project, start: update.happenedAt,
                    label: project.name, title: update.text,
                    detail: project.progress.map { "\($0)% done" } ?? project.status.label,
                    color: statusColor(project.status), systemImage: update.kind.systemImage,
                    target: .project(project.id))
            }
        }

        for event in events where onToday(event.startsAt) {
            rows.append(eventRow(event, clock: clock, agents: byId))
        }
        return sorted(rows)
    }

    /// Tomorrow's events as rows: the preview Home shows under today's last row.
    public static func tomorrow(events: [CalendarEvent], agents: [Agent], now: Date, calendar: Calendar = .current,
                                locale: Locale = .current) -> [TimelineItem] {
        guard let next = calendar.date(byAdding: .day, value: 1, to: now) else { return [] }
        let clock = Clock(calendar: calendar, locale: locale)
        let byId = Dictionary(agents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return sorted(events.filter { calendar.isDate($0.startsAt, inSameDayAs: next) }.map { eventRow($0, clock: clock, agents: byId) })
    }

    /// Tomorrow's weekday ("Friday"), for that preview's heading.
    public static func tomorrowLabel(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let next = calendar.date(byAdding: .day, value: 1, to: now) else { return "" }
        return next.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
    }

    /// An event's row: the calendar over the title, the hours and the place under it.
    private static func eventRow(_ event: CalendarEvent, clock: Clock, agents: [UUID: Agent]) -> TimelineItem {
        let range = event.allDay ? event.calendar : "\(clock.label(event.startsAt)) – \(clock.label(event.endsAt))"
        let place = event.location.flatMap { $0.isEmpty ? nil : $0 }
        let face = event.allDay ? (time: "All day", ampm: "") : clock.parts(event.startsAt)
        return TimelineItem(id: "event:\(event.id)", kind: .event, start: event.startsAt, end: max(event.endsAt, event.startsAt),
                            allDay: event.allDay, time: face.time, ampm: face.ampm, label: event.calendar, title: event.title,
                            detail: place.map { event.allDay ? range : "\(range) · \($0)" } ?? range,
                            color: event.color ?? agents[event.agentId]?.color ?? defaultColor,
                            imageURL: nil, systemImage: "calendar", target: .event(event.id))
    }

    /// All-day first, then by start; ties keep the order they were added in.
    private static func sorted(_ rows: [TimelineItem]) -> [TimelineItem] {
        rows.enumerated()
            .sorted { a, b in
                if a.element.allDay != b.element.allDay { return a.element.allDay }
                if a.element.start != b.element.start { return a.element.start < b.element.start }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    // MARK: Where "now" is

    /// The first timed event still to start.
    public static func nextIndex(_ items: [TimelineItem], now: Date) -> Int? {
        items.firstIndex { $0.kind == .event && !$0.allDay && $0.start > now }
    }

    public static func state(at index: Int, in items: [TimelineItem], now: Date) -> TimelineItem.RowState {
        let item = items[index]
        guard item.kind == .event, !item.allDay else { return .none }
        if item.start <= now && item.end > now { return .now }
        if item.end <= now { return .past }
        return index == nextIndex(items, now: now) ? .next : .none
    }

    /// The row to bring into view: the first event not yet over, else the newest row.
    public static func focusIndex(_ items: [TimelineItem], now: Date) -> Int? {
        items.firstIndex { $0.kind == .event && !$0.allDay && $0.end >= now } ?? (items.isEmpty ? nil : items.count - 1)
    }

    /// The event on now, else the next one (today or later), skipping all-day ones.
    public static func upNext(_ events: [CalendarEvent], now: Date) -> CalendarEvent? {
        events.sorted { $0.startsAt < $1.startsAt }.first { !$0.allDay && $0.endsAt > now }
    }

    /// "now", "in 18 min" ("in 18 minutes" when `long`), "in 2 h", "in 2 h 5 min".
    public static func untilLabel(_ date: Date, now: Date, long: Bool = false) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
        if minutes < 1 { return "now" }
        if minutes < 60 { return long ? "in \(minutes) minutes" : "in \(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
    }

    /// "Good morning", with the display's name unless it is still "McFly".
    public static func greeting(now: Date, calendar: Calendar = .current, name: String? = nil) -> String {
        let hour = calendar.component(.hour, from: now)
        let part = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        guard let name, !name.isEmpty, name != "McFly" else { return part }
        return "\(part), \(name)"
    }

    /// "yyyy-MM-dd" in the calendar's time zone, as `report_date` is written.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A brief's first paragraph on one line, as the display's cards show it.
    static func summary(_ body: String) -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = text.range(of: "\n\n").map { String(text[..<$0.lowerBound]) } ?? text
        return first.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Clock faces: "3:30" over "pm" on a 12-hour clock, "15:30" alone on a 24-hour one.
    public struct Clock {
        private let time: DateFormatter
        private let period: DateFormatter?

        public init(calendar: Calendar = .current, locale: Locale = .current) {
            let twelveHour = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a").contains("a")
            time = DateFormatter()
            time.locale = locale
            time.calendar = calendar
            time.timeZone = calendar.timeZone
            time.dateFormat = twelveHour ? "h:mm" : "HH:mm"
            if twelveHour {
                let period = DateFormatter()
                period.locale = locale
                period.calendar = calendar
                period.timeZone = calendar.timeZone
                period.dateFormat = "a"
                self.period = period
            } else {
                period = nil
            }
        }

        public func parts(_ date: Date) -> (time: String, ampm: String) {
            (time.string(from: date), period?.string(from: date).lowercased() ?? "")
        }

        /// "9:30 am", or "09:30".
        public func label(_ date: Date) -> String {
            let face = parts(date)
            return face.ampm.isEmpty ? face.time : "\(face.time) \(face.ampm)"
        }
    }
}
