import Foundation

/// The demo's twin of the database's drawing (`dashboard_part`,
/// `dashboard_widgets`): a made board's parts drawn from the demo feeds into
/// widgets. A real account never runs this; the database draws made boards
/// and keeps them drawn. Same rules and words as the database (and the
/// console's lib/dashboard-draw.ts), so the demo shows what a real board would.
public enum DashboardDrawing {
    /// The feeds as the drawing reads them. The demo has no todos and no push
    /// log: todos draw as nothing open, and an agent's last push is its
    /// `lastSeenAt`.
    public struct Feeds: Sendable {
        public var quotes: [Quote]
        public var symbols: [Symbol]
        public var metrics: [Metric]
        public var metricSettings: [MetricSetting]
        public var projects: [Project]
        public var events: [CalendarEvent]
        public var briefs: [Brief]
        public var reports: [NewsReport]
        public var agents: [Agent]
        public var timeZone: TimeZone

        public init(_ data: DemoData) {
            quotes = data.quotes; symbols = data.symbols; metrics = data.metrics; metricSettings = data.metricSettings
            projects = data.projects; events = data.events; briefs = data.briefs; reports = data.reports; agents = data.agents
            timeZone = TimeZone(identifier: data.settings.timezone) ?? .current
        }
    }

    /// A made board's widgets: every part in order, at most 40, never none.
    public static func draw(_ parts: [DashboardPart], from feeds: Feeds, now: Date = .now) -> [DashboardWidget] {
        let out = parts.flatMap { draw($0, feeds, now) }
        return out.isEmpty ? [.text(title: nil, body: "Nothing to show yet.")] : Array(out.prefix(40))
    }

    /// "Today 9:30 AM", "Tomorrow", "Tue Oct 20 2:00 PM": `dashboard_when`'s words.
    public static func when(_ date: Date, allDay: Bool, in zone: TimeZone, now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let english = Locale(identifier: "en_US_POSIX")
        func format(_ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = english
            f.timeZone = zone
            f.dateFormat = pattern
            return f.string(from: date)
        }
        let day = days == 0 ? "Today" : days == 1 ? "Tomorrow" : days == -1 ? "Yesterday" : format("EEE MMM d")
        return allDay ? day : "\(day) \(format("h:mm a"))"
    }

    private static func waiting(_ title: String?, _ body: String) -> [DashboardWidget] {
        [.text(title: title, body: body)]
    }

    private static func newest<T>(_ rows: [T], at: (T) -> Date, id: (T) -> Int64) -> T? {
        rows.max { (at($0), id($0)) < (at($1), id($1)) }
    }

    private static func draw(_ part: DashboardPart, _ d: Feeds, _ now: Date) -> [DashboardWidget] {
        let heading = part.title.flatMap { DashboardPart.words($0, 80) }
        let limit = part.limit ?? part.defaultLimit
        switch part.from {
        case .quotes:
            let picked = part.symbols.isEmpty
                ? d.symbols.filter { !$0.hidden }.sorted { ($0.sortOrder, $0.symbol) < ($1.sortOrder, $1.symbol) }.map(\.symbol)
                : part.symbols
            var out: [DashboardWidget] = []
            for symbol in picked {
                let rows = d.quotes.filter { $0.symbol == symbol }
                guard let q = newest(rows, at: \.asOf, id: \.id) else { continue }
                if part.show == .chart {
                    let since = now.addingTimeInterval(-30 * 86_400)
                    let points = rows.filter { $0.asOf > since }.sorted { ($0.asOf, $0.id) > ($1.asOf, $1.id) }.prefix(120).reversed().map(\.price)
                    out.append(.chart(label: q.name.map { "\($0) (\(q.symbol))" } ?? q.symbol, points: Array(points), unit: q.currency))
                } else {
                    out.append(.metric(label: q.symbol, value: q.price, unit: q.currency, delta: q.change, deltaPct: q.changePct))
                }
                if out.count == limit { break }
            }
            return out.isEmpty ? waiting(heading ?? "Markets", part.symbols.isEmpty ? "No quotes yet." : "No quotes yet for \(part.symbols.joined(separator: ", ")).") : out
        case .metrics:
            let picked = part.keys.isEmpty
                ? d.metricSettings.filter { !$0.hidden && (part.group == nil || $0.groupName == part.group) }
                    .sorted { ($0.sortOrder, $0.key) < ($1.sortOrder, $1.key) }.map(\.key)
                : part.keys
            var out: [DashboardWidget] = []
            for key in picked {
                let rows = d.metrics.filter { $0.key == key }
                guard let m = newest(rows, at: \.asOf, id: \.id) else { continue }
                let label = d.metricSettings.first { $0.key == key }?.label ?? m.label ?? key
                if part.show == .chart {
                    let points = rows.sorted { ($0.asOf, $0.id) > ($1.asOf, $1.id) }.prefix(120).reversed().map(\.value)
                    out.append(.chart(label: label, points: Array(points), unit: m.unit))
                } else {
                    out.append(.metric(label: label, value: m.value, unit: m.unit, delta: m.delta, deltaPct: m.deltaPct))
                }
                if out.count == limit { break }
            }
            return out.isEmpty ? waiting(heading ?? part.group ?? "Metrics", "No numbers yet.") : out
        case .projects:
            let shown = (part.projects.isEmpty
                ? d.projects.filter { $0.status == .active || $0.status == .blocked }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
                : part.projects.compactMap { id in d.projects.first { $0.id.lowercased == id } }).prefix(limit)
            if shown.isEmpty { return waiting(heading ?? "Projects", "No projects yet.") }
            if part.show == .list {
                return [.list(title: heading ?? "Projects", items: shown.map { p in p.name + (p.nextStep.map { " · \($0)" } ?? "") })]
            }
            return shown.map { p in
                if let progress = p.progress {
                    return .progress(label: p.name, value: Double(progress), max: 100, unit: "%")
                }
                let state: DashboardWidget.State = p.status == .blocked ? .warn : p.status == .paused ? .unknown : .ok
                let detail = p.nextStep ?? (p.summary.isEmpty ? nil : p.summary)
                return .status(label: p.name, state: state, detail: detail.map { String($0.prefix(300)) })
            }
        case .calendar:
            let title = heading ?? (part.days == 1 ? "Today" : part.days == 2 ? "Today and tomorrow" : "Next \(part.days) days")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = d.timeZone
            let end = calendar.date(byAdding: .day, value: part.days, to: calendar.startOfDay(for: now)) ?? now
            let items = d.events
                .filter { $0.endsAt > now && $0.startsAt < end && (part.calendars.isEmpty || part.calendars.contains($0.calendar)) }
                .sorted { ($0.startsAt, $0.title) < ($1.startsAt, $1.title) }
                .prefix(limit)
                .map { "\(when($0.startsAt, allDay: $0.allDay, in: d.timeZone, now: now)) · \($0.title)" }
            return items.isEmpty ? waiting(title, "Nothing on the calendar.") : [.list(title: title, items: Array(items))]
        case .todos:
            return waiting(heading ?? (part.todos == .reminder ? "Reminders" : "To do"), part.todos == .reminder ? "No reminders set." : "Nothing open.")
        case .news:
            guard let report = d.reports.max(by: { ($0.reportDate, $0.publishedAt) < ($1.reportDate, $1.publishedAt) }) else {
                return waiting(heading ?? "Headlines", "No headlines yet.")
            }
            let rows = report.items.filter { part.section == nil || $0.sectionKey == part.section }
                .sorted { ($0.sectionOrder, $0.position) < ($1.sectionOrder, $1.position) }.prefix(limit)
            if rows.isEmpty { return waiting(heading ?? "Headlines", "No headlines yet.") }
            let sectionName = rows.map(\.sectionName).min() ?? "Headlines"
            return [.list(title: heading ?? (part.section == nil ? "Headlines" : sectionName), items: rows.map(\.headline))]
        case .brief:
            let brief = d.briefs
                .filter { ($0.expiresAt.map { $0 > now } ?? true) && (part.briefKind == nil || $0.kind == part.briefKind) && (part.agent == nil || $0.agentId.lowercased == part.agent) }
                .max { $0.publishedAt < $1.publishedAt }
            guard let brief else { return waiting(heading ?? "Brief", "No brief yet.") }
            return [.text(title: String((heading ?? brief.title).prefix(80)), body: String(brief.body.prefix(2000)))]
        case .agents:
            let quiet = now.addingTimeInterval(-Double(part.hours) * 3600)
            let picked = part.agents.isEmpty
                ? d.agents.filter { !$0.isRevoked && $0.keyPrefix != nil }.sorted { $0.name < $1.name }
                : part.agents.compactMap { id in d.agents.first { $0.id.lowercased == id } }
            let out: [DashboardWidget] = picked.prefix(12).map { a in
                guard let last = a.lastSeenAt else { return .status(label: a.name, state: .unknown, detail: "No pushes yet") }
                let at = when(last, allDay: false, in: d.timeZone, now: now)
                return last < quiet ? .status(label: a.name, state: .warn, detail: "Quiet since \(at)")
                    : .status(label: a.name, state: .ok, detail: "Last push \(at)")
            }
            return out.isEmpty ? waiting(heading ?? "Agents", "No agents yet.") : out
        case .note:
            let body = DashboardPart.words(part.body, 2000) ?? " "
            return [.text(title: heading, body: body)]
        }
    }
}
