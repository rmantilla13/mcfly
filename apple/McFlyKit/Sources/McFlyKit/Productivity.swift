import Foundation

// The productivity feeds (backend/supabase/migrations/20261014000003_productivity.sql):
// projects with their updates, metrics with their console settings, agent-built
// dashboards, and calendar events.

// MARK: Projects

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case code, task, launch, other

        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
        }

        public var systemImage: String {
            switch self {
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .task: return "checklist"
            case .launch: return "paperplane"
            case .other: return "folder"
            }
        }
    }

    public enum Status: String, Codable, CaseIterable, Sendable {
        /// Planned: lined up, not started; listed as "Up next".
        case planned, active, blocked, paused, done

        public init(from decoder: Decoder) throws {
            self = Status(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .active
        }

        public var label: String { rawValue.capitalized }

        /// Sort rank by how much a project needs a look: blocked first, then
        /// the rest in flight, what's up next, and done last.
        public var attention: Int {
            switch self {
            case .blocked: return 0
            case .active: return 1
            case .paused: return 2
            case .planned: return 3
            case .done: return 4
            }
        }

        /// The list's name for the status's group: "Up next" for planned.
        public var groupLabel: String { self == .planned ? "Up next" : label }

        /// Blocked, active or paused: started and not finished.
        public var inFlight: Bool { self != .planned && self != .done }
    }

    public let id: UUID
    public var agentId: UUID
    /// The agent's own id; a re-push updates the project in place.
    public var key: String
    public var name: String
    public var kind: Kind
    public var status: Status
    /// 0–100, when the agent reports one.
    public var progress: Int?
    public var summary: String
    public var nextStep: String?
    public var link: String?
    public var color: String?
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    /// Newest first (embedded as `project_updates`).
    public var updates: [ProjectUpdate]
    /// The steps the agent lays out, in order (migration 20261021000050);
    /// empty when it sends none, or from a database without them.
    public var stages: [String]
    /// The stage it is in, one of `stages`; nil before the first.
    public var stage: String?
    /// When it reached that stage.
    public var stageSince: Date?

    public init(id: UUID, agentId: UUID, key: String, name: String, kind: Kind = .other, status: Status = .active,
                progress: Int? = nil, summary: String = "", nextStep: String? = nil, link: String? = nil, color: String? = nil,
                sortOrder: Int = 1000, createdAt: Date, updatedAt: Date, updates: [ProjectUpdate] = [],
                stages: [String] = [], stage: String? = nil, stageSince: Date? = nil) {
        self.id = id; self.agentId = agentId; self.key = key; self.name = name; self.kind = kind; self.status = status
        self.progress = progress; self.summary = summary; self.nextStep = nextStep; self.link = link; self.color = color
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.updates = updates.sorted { ($0.happenedAt, $0.id) > ($1.happenedAt, $1.id) }
        self.stages = stages; self.stage = stage; self.stageSince = stageSince
    }

    enum CodingKeys: String, CodingKey {
        case id, key, name, kind, status, progress, summary, link, color, stages, stage
        case agentId = "agent_id"
        case nextStep = "next_step"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case updates = "project_updates"
        case stageSince = "stage_since"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  agentId: try c.decode(UUID.self, forKey: .agentId),
                  key: try c.decode(String.self, forKey: .key),
                  name: try c.decode(String.self, forKey: .name),
                  kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .other,
                  status: try c.decodeIfPresent(Status.self, forKey: .status) ?? .active,
                  progress: try c.decodeIfPresent(Int.self, forKey: .progress),
                  summary: try c.decodeIfPresent(String.self, forKey: .summary) ?? "",
                  nextStep: try c.decodeIfPresent(String.self, forKey: .nextStep),
                  link: try c.decodeIfPresent(String.self, forKey: .link),
                  color: try c.decodeIfPresent(String.self, forKey: .color),
                  sortOrder: try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 1000,
                  createdAt: try c.decode(Date.self, forKey: .createdAt),
                  updatedAt: try c.decode(Date.self, forKey: .updatedAt),
                  updates: try c.decodeIfPresent([ProjectUpdate].self, forKey: .updates) ?? [],
                  stages: try c.decodeIfPresent([String].self, forKey: .stages) ?? [],
                  stage: try c.decodeIfPresent(String.self, forKey: .stage),
                  stageSince: try c.decodeIfPresent(Date.self, forKey: .stageSince))
    }

    public var latestUpdate: ProjectUpdate? { updates.first }
    public var url: URL? { link.flatMap(URL.init(string:)) }
}

public struct ProjectUpdate: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case note, commit, pr, ci, deploy, alert, done

        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .note
        }

        public var label: String {
            switch self {
            case .pr: return "PR"
            case .ci: return "CI"
            default: return rawValue.capitalized
            }
        }

        public var systemImage: String {
            switch self {
            case .note: return "text.bubble"
            case .commit: return "arrow.triangle.branch"
            case .pr: return "arrow.triangle.pull"
            case .ci: return "checkmark.seal"
            case .deploy: return "shippingbox"
            case .alert: return "exclamationmark.triangle"
            case .done: return "checkmark.circle"
            }
        }
    }

    public let id: Int64
    /// Nil for rows from `admin_project_updates`, which names no project.
    public var projectId: UUID?
    public var kind: Kind
    public var text: String
    public var url: String?
    public var happenedAt: Date
    public var createdAt: Date?

    public init(id: Int64, projectId: UUID? = nil, kind: Kind = .note, text: String, url: String? = nil, happenedAt: Date, createdAt: Date? = nil) {
        self.id = id; self.projectId = projectId; self.kind = kind; self.text = text; self.url = url
        self.happenedAt = happenedAt; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, text, url
        case projectId = "project_id"
        case happenedAt = "happened_at"
        case createdAt = "created_at"
    }

    public var link: URL? { url.flatMap(URL.init(string:)) }
}

// MARK: Metrics

/// One push of one metric. `metrics` keeps the history; the newest row per key is the value shown.
public struct Metric: Codable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public var agentId: UUID
    public var key: String
    public var label: String?
    public var value: Double
    public var unit: String?
    public var delta: Double?
    public var deltaPct: Double?
    public var note: String?
    public var asOf: Date
    public var createdAt: Date

    public init(id: Int64, agentId: UUID, key: String, label: String? = nil, value: Double, unit: String? = nil,
                delta: Double? = nil, deltaPct: Double? = nil, note: String? = nil, asOf: Date, createdAt: Date) {
        self.id = id; self.agentId = agentId; self.key = key; self.label = label; self.value = value; self.unit = unit
        self.delta = delta; self.deltaPct = deltaPct; self.note = note; self.asOf = asOf; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, key, label, value, unit, delta, note
        case agentId = "agent_id"
        case deltaPct = "delta_pct"
        case asOf = "as_of"
        case createdAt = "created_at"
    }
}

/// The console's label, group, order and hidden flag for a metric key.
public struct MetricSetting: Codable, Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public var label: String?
    public var groupName: String?
    public var sortOrder: Int
    public var hidden: Bool
    public var updatedAt: Date?

    public init(key: String, label: String? = nil, groupName: String? = nil, sortOrder: Int = 1000, hidden: Bool = false, updatedAt: Date? = nil) {
        self.key = key; self.label = label; self.groupName = groupName; self.sortOrder = sortOrder; self.hidden = hidden; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case key, label, hidden
        case groupName = "group_name"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
    }
}

/// One metric's history, newest first, with the console's label, group and order.
public struct MetricSeries: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public var label: String
    public var group: String?
    public var history: [Metric]
    public var sortOrder: Int

    public var latest: Metric { history[0] }
    /// Oldest to newest, for a sparkline.
    public var values: [Double] { history.reversed().map(\.value) }

    /// Groups the history by key, newest first within each, visible keys only,
    /// in `sort_order, key` order. A key without a settings row sorts at 1000.
    public static func group(_ metrics: [Metric], settings: [MetricSetting]) -> [MetricSeries] {
        let known = Dictionary(settings.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var byKey: [String: [Metric]] = [:]
        for metric in metrics { byKey[metric.key, default: []].append(metric) }
        return byKey.compactMap { key, rows -> MetricSeries? in
            if let setting = known[key], setting.hidden { return nil }
            let history = rows.sorted { ($0.asOf, $0.id) > ($1.asOf, $1.id) }
            guard let newest = history.first else { return nil }
            let label = known[key]?.label ?? history.first { $0.label != nil }?.label ?? key
            return MetricSeries(key: key, label: label, group: known[key]?.groupName, history: history,
                                sortOrder: known[key]?.sortOrder ?? 1000)
                .withLatest(newest)
        }
        .sorted { ($0.sortOrder, $0.key) < ($1.sortOrder, $1.key) }
    }

    /// Series grouped by their console group, in first-seen order; ungrouped ones last.
    public static func sections(_ series: [MetricSeries]) -> [(name: String?, series: [MetricSeries])] {
        var order: [String] = []
        var grouped: [String: [MetricSeries]] = [:]
        var ungrouped: [MetricSeries] = []
        for s in series {
            guard let group = s.group else {
                ungrouped.append(s)
                continue
            }
            if grouped[group] == nil { order.append(group) }
            grouped[group, default: []].append(s)
        }
        var out: [(name: String?, series: [MetricSeries])] = order.map { ($0, grouped[$0] ?? []) }
        if !ungrouped.isEmpty { out.append((nil, ungrouped)) }
        return out
    }

    /// `sections`, as named groups.
    public static func grouped(_ series: [MetricSeries]) -> [MetricGroup] {
        sections(series).map { MetricGroup(name: $0.name, series: $0.series) }
    }

    private func withLatest(_ metric: Metric) -> MetricSeries { self }
}

/// Metrics that share a console group (`metric_settings.group_name`); nil is the ungrouped rest.
public struct MetricGroup: Identifiable, Hashable, Sendable {
    public var id: String { name ?? "" }
    public let name: String?
    public var series: [MetricSeries]
    /// The heading: the console's group, or "Other" for metrics without one.
    public var title: String { name ?? "Other" }

    public init(name: String?, series: [MetricSeries]) {
        self.name = name
        self.series = series
    }
}

// MARK: Dashboards

/// A dashboard: a title and up to 40 widgets of six kinds, laid out by an
/// agent, or made in the app or the console from a recipe (`sources`) that the
/// database draws into the widgets.
public struct Dashboard: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var agentId: UUID
    public var key: String
    public var title: String
    public var subtitle: String?
    public var widgets: [DashboardWidget]
    public var sortOrder: Int
    public var hidden: Bool
    public var createdAt: Date?
    public var updatedAt: Date?
    /// A made board's template (`DashboardTemplate`), when it started from one.
    public var template: String?
    /// A made board's parts; nil when an agent lays the board out.
    public var sources: [DashboardPart]?
    public var isMade: Bool { sources != nil }

    public init(id: UUID, agentId: UUID, key: String, title: String, subtitle: String? = nil, widgets: [DashboardWidget],
                sortOrder: Int = 1000, hidden: Bool = false, createdAt: Date? = nil, updatedAt: Date? = nil,
                template: String? = nil, sources: [DashboardPart]? = nil) {
        self.id = id; self.agentId = agentId; self.key = key; self.title = title; self.subtitle = subtitle
        self.widgets = widgets; self.sortOrder = sortOrder; self.hidden = hidden; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.template = template; self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case id, key, title, subtitle, widgets, hidden, template, sources
        case agentId = "agent_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        agentId = try c.decode(UUID.self, forKey: .agentId)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        widgets = (try c.decodeIfPresent([LenientWidget].self, forKey: .widgets) ?? []).map(\.widget)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 1000
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        template = (try? c.decodeIfPresent(String.self, forKey: .template)) ?? nil
        if c.contains(.sources), (try? c.decodeNil(forKey: .sources)) == false, let nested = try? c.superDecoder(forKey: .sources) {
            sources = DashboardPart.lossy(from: nested)
        }
    }
}

/// `DashboardWidget`, by the shorter name the tests use.
public typealias Widget = DashboardWidget

/// One widget from a dashboard's `widgets` array. The server checks only the
/// `type`, so every field is read leniently: a number may arrive as a string,
/// and a missing label is an empty one.
public enum DashboardWidget: Hashable, Sendable {
    public enum State: String, Sendable {
        case ok, warn, error, unknown
    }

    case metric(label: String, value: Double, unit: String?, delta: Double?, deltaPct: Double?)
    case status(label: String, state: State, detail: String?)
    case progress(label: String, value: Double, max: Double, unit: String?)
    case list(title: String?, items: [String])
    case text(title: String?, body: String)
    case chart(label: String?, points: [Double], unit: String?)
    /// A type this version of the app doesn't know; shown as a placeholder.
    case unknown(type: String)

    public var typeName: String {
        switch self {
        case .metric: return "metric"
        case .status: return "status"
        case .progress: return "progress"
        case .list: return "list"
        case .text: return "text"
        case .chart: return "chart"
        case .unknown(let type): return type
        }
    }
}

extension DashboardWidget: Decodable {
    enum CodingKeys: String, CodingKey {
        case type, label, title, value, unit, delta, deltaPct = "delta_pct", state, detail, max, items, body, points
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try c.decodeIfPresent(String.self, forKey: .type) ?? "").lowercased()
        let label = try c.decodeIfPresent(String.self, forKey: .label) ?? c.decodeIfPresent(String.self, forKey: .title) ?? ""
        let title = try c.decodeIfPresent(String.self, forKey: .title) ?? c.decodeIfPresent(String.self, forKey: .label)
        let unit = try c.decodeIfPresent(String.self, forKey: .unit).flatMap { $0.isEmpty ? nil : $0 }
        switch type {
        case "metric":
            // A metric without a value reads as zero rather than sinking the dashboard.
            self = .metric(label: label, value: try c.decodeIfPresent(LenientNumber.self, forKey: .value)?.value ?? 0, unit: unit,
                           delta: try c.decodeIfPresent(LenientNumber.self, forKey: .delta)?.value,
                           deltaPct: try c.decodeIfPresent(LenientNumber.self, forKey: .deltaPct)?.value)
        case "status":
            let raw = (try c.decodeIfPresent(String.self, forKey: .state) ?? "").lowercased()
            let state: State
            switch raw {
            case "ok", "good", "up", "green", "pass", "passing": state = .ok
            case "warn", "warning", "degraded", "yellow", "amber": state = .warn
            case "error", "down", "fail", "failed", "failing", "red", "critical": state = .error
            default: state = .unknown
            }
            self = .status(label: label, state: state, detail: try c.decodeIfPresent(String.self, forKey: .detail))
        case "progress":
            let max = try c.decodeIfPresent(LenientNumber.self, forKey: .max)?.value ?? 100
            self = .progress(label: label, value: try c.decodeIfPresent(LenientNumber.self, forKey: .value)?.value ?? 0,
                             max: max > 0 ? max : 100, unit: unit)
        case "list":
            self = .list(title: title, items: try c.decodeIfPresent([LenientString].self, forKey: .items)?.map(\.value) ?? [])
        case "text":
            self = .text(title: title, body: try c.decodeIfPresent(String.self, forKey: .body) ?? "")
        case "chart":
            self = .chart(label: title, points: try c.decodeIfPresent([LenientNumber].self, forKey: .points)?.map(\.value) ?? [], unit: unit)
        default:
            self = .unknown(type: type.isEmpty ? "?" : type)
        }
    }
}

/// A `widgets` entry: a widget, or `.unknown` when it isn't even an object.
struct LenientWidget: Decodable {
    let widget: DashboardWidget

    init(from decoder: Decoder) throws {
        if let widget = try? DashboardWidget(from: decoder) {
            self.widget = widget
        } else {
            self.widget = .unknown(type: "")
        }
    }
}

extension DashboardWidget: Encodable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .metric(let label, let value, let unit, let delta, let deltaPct):
            try c.encode(label, forKey: .label)
            try c.encode(value, forKey: .value)
            try c.encodeIfPresent(unit, forKey: .unit)
            try c.encodeIfPresent(delta, forKey: .delta)
            try c.encodeIfPresent(deltaPct, forKey: .deltaPct)
        case .status(let label, let state, let detail):
            try c.encode(label, forKey: .label)
            try c.encode(state.rawValue, forKey: .state)
            try c.encodeIfPresent(detail, forKey: .detail)
        case .progress(let label, let value, let max, let unit):
            try c.encode(label, forKey: .label)
            try c.encode(value, forKey: .value)
            try c.encode(max, forKey: .max)
            try c.encodeIfPresent(unit, forKey: .unit)
        case .list(let title, let items):
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(items, forKey: .items)
        case .text(let title, let body):
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(body, forKey: .body)
        case .chart(let label, let points, let unit):
            try c.encodeIfPresent(label, forKey: .label)
            try c.encode(points, forKey: .points)
            try c.encodeIfPresent(unit, forKey: .unit)
        case .unknown:
            break
        }
    }
}

/// A number an agent may have written as a number or as a string.
struct LenientNumber: Decodable, Hashable {
    let value: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let number = try? c.decode(Double.self) {
            value = number
        } else if let text = try? c.decode(String.self), let number = Double(text.replacingOccurrences(of: ",", with: "")) {
            value = number
        } else if let flag = try? c.decode(Bool.self) {
            value = flag ? 1 : 0
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a number")
        }
    }
}

/// A list item an agent may have written as a string, a number, or `{ text }`.
struct LenientString: Decodable, Hashable {
    let value: String

    private enum Keys: String, CodingKey { case text, title, label }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if let text = try? c.decode(String.self) {
                value = text
                return
            }
            if let number = try? c.decode(Double.self) {
                value = number.formatted()
                return
            }
        }
        let c = try decoder.container(keyedBy: Keys.self)
        value = try c.decodeIfPresent(String.self, forKey: .text)
            ?? c.decodeIfPresent(String.self, forKey: .title)
            ?? c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

// MARK: Events

public struct CalendarEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var agentId: UUID
    public var calendar: String
    public var externalId: String
    public var title: String
    public var description: String?
    public var location: String?
    public var startsAt: Date
    public var endsAt: Date
    public var allDay: Bool
    public var color: String?
    public var url: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID, agentId: UUID, calendar: String = "Calendar", externalId: String, title: String, description: String? = nil,
                location: String? = nil, startsAt: Date, endsAt: Date, allDay: Bool = false, color: String? = nil, url: String? = nil,
                createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id; self.agentId = agentId; self.calendar = calendar; self.externalId = externalId; self.title = title
        self.description = description; self.location = location; self.startsAt = startsAt; self.endsAt = endsAt
        self.allDay = allDay; self.color = color; self.url = url; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, calendar, title, description, location, color, url
        case agentId = "agent_id"
        case externalId = "external_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public var link: URL? { url.flatMap(URL.init(string:)) }

    /// Whether any of the event falls on `day` (multi-day events are on each day they span).
    public func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return startsAt < end && endsAt > start
    }

    /// "All day", or "2:30 – 2:45 PM".
    public func timeLabel(on day: Date? = nil, calendar: Calendar = .current) -> String {
        if allDay { return "All day" }
        if let day, !calendar.isDate(startsAt, inSameDayAs: day), !calendar.isDate(endsAt, inSameDayAs: day) { return "All day" }
        let start = startsAt.formatted(date: .omitted, time: .shortened)
        let end = endsAt.formatted(date: .omitted, time: .shortened)
        return start == end ? start : "\(start) – \(end)"
    }
}

/// Day and week groupings for the calendar screens.
public enum EventDays {
    /// `count` days from `start`, each with the events on it (all-day and multi-day first, then by start).
    public static func days(_ events: [CalendarEvent], from start: Date, count: Int, calendar: Calendar = .current) -> [(day: Date, events: [CalendarEvent])] {
        let first = calendar.startOfDay(for: start)
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let onDay = events.filter { $0.occurs(on: day, calendar: calendar) }
                .sorted { a, b in
                    let aAll = a.allDay || !calendar.isDate(a.startsAt, inSameDayAs: day)
                    let bAll = b.allDay || !calendar.isDate(b.startsAt, inSameDayAs: day)
                    if aAll != bAll { return aAll }
                    return (a.startsAt, a.title) < (b.startsAt, b.title)
                }
            return (day, onDay)
        }
    }

    /// Only the days that have something on them, in order.
    public static func agenda(_ events: [CalendarEvent], from start: Date, count: Int, calendar: Calendar = .current) -> [(day: Date, events: [CalendarEvent])] {
        days(events, from: start, count: count, calendar: calendar).filter { !$0.events.isEmpty }
    }

    /// The first day of the week containing `date` (the calendar's own first weekday).
    public static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// Events that start after `now`, soonest first.
    public static func upcoming(_ events: [CalendarEvent], after now: Date, limit: Int) -> [CalendarEvent] {
        Array(events.filter { $0.endsAt > now }.sorted { $0.startsAt < $1.startsAt }.prefix(limit))
    }
}

// MARK: Settings

public enum AssistantProvider: String, Codable, CaseIterable, Sendable {
    case claude, grok

    public init(from decoder: Decoder) throws {
        self = AssistantProvider(rawValue: try decoder.singleValueContainer().decode(String.self).lowercased()) ?? .claude
    }

    public var label: String {
        switch self {
        case .claude: return "Claude"
        case .grok: return "Grok"
        }
    }
}

extension Format {
    /// A metric's value with its unit: "$4,280", "99.98%", "212 ms", "1.24M".
    public static func metric(_ value: Double, unit: String?) -> String {
        if let unit, unit.count == 3, unit.uppercased() == unit, unit.allSatisfy(\.isLetter) {
            return value.formatted(.currency(code: unit).precision(.fractionLength(value.rounded() == value ? 0 : 2)))
        }
        let number: String
        if abs(value) >= 100_000 {
            number = value.formatted(.number.notation(.compactName).precision(.fractionLength(0...2)))
        } else if value.rounded() == value {
            number = value.formatted(.number.precision(.fractionLength(0)))
        } else {
            number = value.formatted(.number.precision(.fractionLength(0...2)))
        }
        guard let unit, !unit.isEmpty else { return number }
        return unit == "%" ? number + "%" : number + " " + unit
    }

    /// "+46", "−18 ms", "+12.5%": whichever of the two the agent sent.
    public static func metricDelta(_ delta: Double?, pct: Double?, unit: String?) -> String {
        if let pct { return signed(pct, fractionDigits: pct.rounded() == pct ? 0 : 1) + "%" }
        if let delta {
            let text = signed(delta, fractionDigits: delta.rounded() == delta ? 0 : 2)
            guard let unit, !unit.isEmpty, unit != "%" else { return text + (unit == "%" ? "%" : "") }
            return unit.count == 3 && unit.uppercased() == unit ? text : text + " " + unit
        }
        return ""
    }
}
