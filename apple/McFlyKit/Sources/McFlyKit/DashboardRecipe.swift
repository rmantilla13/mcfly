import Foundation

/// Dashboards made in the app or the console, not pushed: a template to start
/// from and, for each part of the board, where it pulls from. The database
/// draws the parts into the six widgets every screen knows and keeps them
/// drawn (backend migration 20261016000010, `dashboard_part`); this is the
/// app's side of the recipe, the twin of the console's
/// admin/lib/dashboard-sources.ts, with the same templates and the same rules
/// for reading a part.
public struct DashboardPart: Hashable, Sendable, Identifiable {
    /// Where a part pulls from (`from`).
    public enum Kind: String, CaseIterable, Sendable {
        case quotes, metrics, projects, calendar, todos, news, brief, agents, note

        public var label: String {
            switch self {
            case .quotes: return "Markets"
            case .metrics: return "Metrics"
            case .projects: return "Projects"
            case .calendar: return "Calendar"
            case .todos: return "Todos"
            case .news: return "News"
            case .brief: return "Brief"
            case .agents: return "Agents"
            case .note: return "Note"
            }
        }

        public var summary: String {
            switch self {
            case .quotes: return "Prices and the day's move, for the symbols you pick."
            case .metrics: return "Numbers an agent reports, as tiles or a chart."
            case .projects: return "Progress and next steps."
            case .calendar: return "What's coming up, from the calendars you pick."
            case .todos: return "What's open, and reminders."
            case .news: return "Headlines from the newest Daily Pulse."
            case .brief: return "The newest brief, whole."
            case .agents: return "Whether each agent is still pushing."
            case .note: return "Words of your own."
            }
        }

        /// #rrggbb, the console's dot for the kind.
        public var color: String {
            switch self {
            case .quotes: return "#3DB37A"
            case .metrics: return "#F6B94A"
            case .projects: return "#5B7CF5"
            case .calendar: return "#14C2C2"
            case .todos: return "#E86A92"
            case .news: return "#E2725B"
            case .brief: return "#7A64E8"
            case .agents: return "#8F95A1"
            case .note: return "#A78BFA"
            }
        }

        public var systemImage: String {
            switch self {
            case .quotes: return "chart.line.uptrend.xyaxis"
            case .metrics: return "gauge.with.dots.needle.33percent"
            case .projects: return "hammer"
            case .calendar: return "calendar"
            case .todos: return "checklist"
            case .news: return "newspaper"
            case .brief: return "text.quote"
            case .agents: return "dot.radiowaves.left.and.right"
            case .note: return "note.text"
            }
        }
    }

    /// How a part draws: quotes and metrics as tiles or charts, projects as
    /// progress or one list.
    public enum Show: String, Sendable {
        case tiles, chart, progress, list
    }

    /// Which todos: both kinds, or one.
    public enum Todos: String, CaseIterable, Sendable {
        case all, todo, reminder
    }

    /// For the builder's lists; never sent.
    public var id = UUID()
    public var from: Kind
    public var symbols: [String] = []
    public var keys: [String] = []
    public var group: String?
    public var projects: [String] = []
    public var calendars: [String] = []
    public var agents: [String] = []
    public var show: Show = .tiles
    public var limit: Int?
    public var days = 7
    public var todos: Todos = .all
    public var section: String?
    public var briefKind: Brief.Kind?
    public var agent: String?
    public var hours = 24
    public var title: String?
    public var body = ""

    public init(_ from: Kind) {
        self.from = from
        show = from == .projects ? .progress : .tiles
        if from == .news { limit = 5 }
    }

    /// The choices the builder offers.
    public static let calendarDays = [1, 2, 3, 7, 14, 31]
    public static let agentHours = [1, 6, 24, 72, 168]
    public static let maxParts = 20

    /// The most a part's limit may be (the database clamps the same).
    public var maxLimit: Int { [.quotes, .metrics, .projects].contains(from) ? 12 : 20 }

    /// What the part shows when no limit is set (dashboard_part's defaults).
    public var defaultLimit: Int {
        switch from {
        case .quotes: return show == .chart ? 1 : 8
        case .metrics: return show == .chart ? 2 : 8
        case .projects: return 6
        case .news: return 5
        default: return 8
        }
    }

    // MARK: Reading

    /// The part as the database will take it, cleaned the way the console's
    /// `readPart` cleans: names deduplicated and capped at twenty, symbols in
    /// capitals, keys and ids in lower case, limits clamped, days and hours
    /// snapped to a choice, a note with no words dropped (nil).
    public func normalized() -> DashboardPart? {
        var p = self
        p.title = Self.words(title, 80)
        p.limit = limit.map { min(maxLimit, max(1, $0)) }
        switch from {
        case .quotes:
            p.symbols = Self.names(symbols.map { $0.uppercased() }).filter { $0.range(of: #"^[A-Z0-9.^=:-]{1,16}$"#, options: .regularExpression) != nil }
            p.show = show == .chart ? .chart : .tiles
        case .metrics:
            p.keys = Self.names(keys.map { $0.lowercased() })
            p.group = Self.words(group, 80)
            p.show = show == .chart ? .chart : .tiles
        case .projects:
            p.projects = Self.names(projects.map { $0.lowercased() }).filter(Self.isUUID)
            p.show = show == .list ? .list : .progress
        case .calendar:
            p.calendars = Self.names(calendars)
            p.days = Self.nearest(days, in: Self.calendarDays)
        case .todos:
            break
        case .news:
            p.section = Self.words(section, 32)
        case .brief:
            p.agent = agent.map { $0.lowercased() }.flatMap { Self.isUUID($0) ? $0 : nil }
        case .agents:
            p.agents = Self.names(agents.map { $0.lowercased() }).filter(Self.isUUID)
            p.hours = Self.nearest(hours, in: Self.agentHours)
        case .note:
            guard let words = Self.words(body, 2000) else { return nil }
            p.body = words
        }
        return p
    }

    /// A whole recipe: the parts that can be read, at most twenty.
    public static func normalized(_ parts: [DashboardPart]) -> [DashboardPart] {
        Array(parts.compactMap { $0.normalized() }.prefix(maxParts))
    }

    static func words(_ s: String?, _ max: Int) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return String(t.prefix(max))
    }

    static func names(_ list: [String]) -> [String] {
        var out: [String] = []
        for raw in list {
            let s = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            if !s.isEmpty, !out.contains(s) { out.append(s) }
            if out.count == 20 { break }
        }
        return out
    }

    static func isUUID(_ s: String) -> Bool {
        s.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The closest choice; a tie goes to the smaller.
    static func nearest(_ n: Int, in choices: [Int]) -> Int {
        let clamped = min(choices.last!, max(choices.first!, n))
        return choices.min { abs($0 - clamped) < abs($1 - clamped) } ?? choices[0]
    }
}

// MARK: Equality

extension DashboardPart {
    /// Two parts are the same when they pull the same way; `id` is only the
    /// builder's handle, so two reads of one stored board compare equal.
    public static func == (a: DashboardPart, b: DashboardPart) -> Bool {
        a.from == b.from && a.symbols == b.symbols && a.keys == b.keys && a.group == b.group && a.projects == b.projects
            && a.calendars == b.calendars && a.agents == b.agents && a.show == b.show && a.limit == b.limit && a.days == b.days
            && a.todos == b.todos && a.section == b.section && a.briefKind == b.briefKind && a.agent == b.agent && a.hours == b.hours
            && a.title == b.title && a.body == b.body
    }

    public func hash(into h: inout Hasher) {
        h.combine(from); h.combine(symbols); h.combine(keys); h.combine(group); h.combine(projects); h.combine(calendars)
        h.combine(agents); h.combine(show); h.combine(limit); h.combine(days); h.combine(todos); h.combine(section)
        h.combine(briefKind); h.combine(agent); h.combine(hours); h.combine(title); h.combine(body)
    }
}

// MARK: The wire shape

extension DashboardPart: Codable {
    enum CodingKeys: String, CodingKey {
        case from, symbols, keys, group, projects, calendars, agents, show, limit, days, kind, section, agent, hours, title, body
    }

    /// Lenient, like the console's reader: what can't be read is left at its
    /// default, and `normalized()` does the rest. An unknown `from` throws.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let kind = Kind(rawValue: try c.decode(String.self, forKey: .from)) else {
            throw DecodingError.dataCorruptedError(forKey: .from, in: c, debugDescription: "Not a kind of part")
        }
        self.init(kind)
        func strings(_ key: CodingKeys) -> [String] {
            ((try? c.decodeIfPresent([Lossy<String>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
        }
        func string(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        func int(_ key: CodingKeys) -> Int? { ((try? c.decodeIfPresent(LenientNumber.self, forKey: key)) ?? nil).map { Int($0.value.rounded()) } }
        symbols = strings(.symbols)
        keys = strings(.keys)
        projects = strings(.projects)
        calendars = strings(.calendars)
        agents = strings(.agents)
        group = string(.group)
        section = string(.section)
        agent = string(.agent)
        title = string(.title)
        body = string(.body) ?? ""
        limit = int(.limit)
        if let d = int(.days) { days = d }
        if let h = int(.hours) { hours = h }
        if let s = string(.show).flatMap(Show.init(rawValue:)) { show = s }
        let k = string(.kind)
        if kind == .todos { todos = k.flatMap(Todos.init(rawValue:)) ?? .all }
        if kind == .brief { briefKind = k.flatMap(Brief.Kind.init(rawValue:)) }
    }

    /// Only the fields the part's kind uses, the way the console sends them.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from.rawValue, forKey: .from)
        switch from {
        case .quotes:
            try c.encode(symbols, forKey: .symbols)
            try c.encode(show.rawValue, forKey: .show)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .metrics:
            try c.encode(keys, forKey: .keys)
            try c.encodeIfPresent(group, forKey: .group)
            try c.encode(show.rawValue, forKey: .show)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .projects:
            try c.encode(projects, forKey: .projects)
            try c.encode(show.rawValue, forKey: .show)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .calendar:
            try c.encode(calendars, forKey: .calendars)
            try c.encode(days, forKey: .days)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .todos:
            try c.encode(todos.rawValue, forKey: .kind)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .news:
            try c.encodeIfPresent(section, forKey: .section)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .brief:
            try c.encodeIfPresent(briefKind?.rawValue, forKey: .kind)
            try c.encodeIfPresent(agent, forKey: .agent)
        case .agents:
            try c.encode(agents, forKey: .agents)
            try c.encode(hours, forKey: .hours)
        case .note:
            try c.encode(body, forKey: .body)
        }
        try c.encodeIfPresent(title, forKey: .title)
    }

    /// The parts a stored recipe holds, any it can't read left out.
    static func lossy(from decoder: Decoder) -> [DashboardPart]? {
        guard let list = try? [Lossy<DashboardPart>](from: decoder) else { return nil }
        return list.compactMap(\.value)
    }
}

/// One element of a list, or nil when it isn't the type: a bad entry is
/// skipped rather than sinking the list.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

// MARK: Templates

/// A starting point: a title and its parts. An empty list of symbols, keys,
/// projects, calendars or agents means "all of them", so a template works
/// before anything is picked.
public struct DashboardTemplate: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let summary: String
    public let color: String
    public let title: String
    public let subtitle: String?
    let make: @Sendable () -> [DashboardPart]

    /// A fresh copy of the template's parts, for the builder to change.
    public var parts: [DashboardPart] { make() }

    public static func find(_ id: String?) -> DashboardTemplate? { all.first { $0.id == id } }

    /// The console's templates (admin/lib/dashboard-sources.ts), same ids.
    public static let all: [DashboardTemplate] = [
        .init(id: "today", label: "Today", summary: "The day's calendar, what's open, the morning brief and your symbols.",
              color: "#F2A33A", title: "Today", subtitle: nil) {
            [part(.calendar) { $0.days = 1 }, part(.todos) { $0.limit = 6 }, part(.quotes) { $0.limit = 4 }, part(.brief) { $0.briefKind = .daily }]
        },
        .init(id: "markets", label: "Markets", summary: "A chart for the symbol that matters, tiles for the rest.",
              color: "#3DB37A", title: "Markets", subtitle: "The last 30 days") {
            [part(.quotes) { $0.show = .chart; $0.limit = 1 }, part(.quotes) { $0.limit = 8 }]
        },
        .init(id: "numbers", label: "Numbers", summary: "The metrics you pick as tiles, with charts for the first two.",
              color: "#F6B94A", title: "Numbers", subtitle: nil) {
            [part(.metrics) { $0.limit = 8 }, part(.metrics) { $0.show = .chart; $0.limit = 2 }]
        },
        .init(id: "projects", label: "Projects", summary: "Every active project's progress, and what's next on each.",
              color: "#5B7CF5", title: "Projects", subtitle: nil) {
            [part(.projects), part(.projects) { $0.show = .list; $0.title = "Next steps" }]
        },
        .init(id: "week", label: "Week ahead", summary: "Seven days of calendar, with todos and reminders beside them.",
              color: "#14C2C2", title: "Week ahead", subtitle: nil) {
            [part(.calendar) { $0.limit = 12 }, part(.todos) { $0.todos = .todo; $0.limit = 8 }, part(.todos) { $0.todos = .reminder; $0.limit = 6 }]
        },
        .init(id: "health", label: "Agent health", summary: "Which agents are pushing, which went quiet, and which failed.",
              color: "#8F95A1", title: "Agent health", subtitle: "Quiet after a day") {
            [part(.agents)]
        },
        .init(id: "reading", label: "Reading", summary: "The newest brief and the day's headlines.",
              color: "#E2725B", title: "Reading", subtitle: nil) {
            [part(.brief), part(.news) { $0.limit = 6 }]
        },
        .init(id: "blank", label: "Blank", summary: "Start from a note and add what you want.",
              color: "#A78BFA", title: "My board", subtitle: nil) {
            [part(.note) { $0.title = "Note"; $0.body = "Add parts below: markets, metrics, projects, the calendar…" }]
        },
    ]

    private static func part(_ kind: DashboardPart.Kind, _ set: (inout DashboardPart) -> Void = { _ in }) -> DashboardPart {
        var p = DashboardPart(kind)
        set(&p)
        return p
    }
}

// MARK: What a part can pull from

/// `admin_dashboard_sources()`: the names the builder's pickers offer.
public struct DashboardSourceOptions: Decodable, Sendable, Equatable {
    public struct SymbolOption: Decodable, Sendable, Equatable { public var symbol: String; public var name: String?; public var hidden: Bool? }
    public struct MetricOption: Decodable, Sendable, Equatable { public var key: String; public var label: String; public var group: String?; public var unit: String?; public var hidden: Bool? }
    public struct ProjectOption: Decodable, Sendable, Equatable {
        public var id: String; public var name: String; public var status: String
        public var agentName: String?
        enum CodingKeys: String, CodingKey { case id, name, status, agentName = "agent_name" }
    }
    public struct SectionOption: Decodable, Sendable, Equatable { public var key: String; public var name: String }
    public struct AgentOption: Decodable, Sendable, Equatable {
        public var id: String; public var name: String; public var color: String?
        public var hasKey: Bool?
        enum CodingKeys: String, CodingKey { case id, name, color, hasKey = "has_key" }
    }

    public var symbols: [SymbolOption] = []
    public var metrics: [MetricOption] = []
    public var projects: [ProjectOption] = []
    public var calendars: [String] = []
    public var newsSections: [SectionOption] = []
    public var agents: [AgentOption] = []
    public var timezone: String = "UTC"

    enum CodingKeys: String, CodingKey {
        case symbols, metrics, projects, calendars, agents, timezone
        case newsSections = "news_sections"
    }

    public init() {}

    public init(symbols: [SymbolOption], metrics: [MetricOption], projects: [ProjectOption], calendars: [String],
                newsSections: [SectionOption], agents: [AgentOption], timezone: String) {
        self.symbols = symbols; self.metrics = metrics; self.projects = projects; self.calendars = calendars
        self.newsSections = newsSections; self.agents = agents; self.timezone = timezone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list<T: Decodable>(_ key: CodingKeys) -> [T] { ((try? c.decodeIfPresent([Lossy<T>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? [] }
        symbols = list(.symbols)
        metrics = list(.metrics)
        projects = list(.projects)
        calendars = list(.calendars)
        newsSections = list(.newsSections)
        agents = list(.agents)
        timezone = ((try? c.decodeIfPresent(String.self, forKey: .timezone)) ?? nil) ?? "UTC"
    }
}

// MARK: Saying what a part shows

extension DashboardPart {
    public static func daysLabel(_ days: Int) -> String {
        days == 1 ? "today" : days == 2 ? "today and tomorrow" : "the next \(days) days"
    }

    public static func hoursLabel(_ hours: Int) -> String {
        if hours % 24 == 0 { return hours == 24 ? "a day" : "\(hours / 24) days" }
        return hours == 1 ? "an hour" : "\(hours) hours"
    }

    /// One line on where the part pulls from: "AAPL, NVDA as tiles", "Work,
    /// the next 7 days". The console's `describePart`, word for word.
    public func describe(_ options: DashboardSourceOptions = .init()) -> String {
        func listed(_ picked: [String], _ label: (String) -> String, all: String, max: Int = 3) -> String {
            if picked.isEmpty { return all }
            let shown = picked.prefix(max).map(label).joined(separator: ", ")
            return picked.count > max ? "\(shown) and \(picked.count - max) more" : shown
        }
        let most = limit.map { ", up to \($0)" } ?? ""
        switch from {
        case .quotes:
            return "\(listed(symbols, { $0 }, all: "Every symbol")) as \(show == .chart ? "charts" : "tiles")\(most)"
        case .metrics:
            let all = group.map { "Every \($0) metric" } ?? "Every metric"
            let label = { (k: String) in options.metrics.first { $0.key == k }?.label ?? k }
            return "\(listed(keys, label, all: all)) as \(show == .chart ? "charts" : "tiles")\(most)"
        case .projects:
            let label = { (id: String) in options.projects.first { $0.id == id }?.name ?? "a project" }
            return "\(listed(projects, label, all: "Active projects")), \(show == .list ? "as a list" : "their progress")"
        case .calendar:
            return "\(listed(calendars, { $0 }, all: "Every calendar")), \(Self.daysLabel(days))"
        case .todos:
            return todos == .reminder ? "Reminders" : todos == .todo ? "Open todos" : "Open todos and reminders"
        case .news:
            let name = section.map { s in options.newsSections.first { $0.key == s }?.name ?? s }
            return "\(name.map { "\($0) headlines" } ?? "The top headlines")\(most)"
        case .brief:
            let from = agent.flatMap { a in options.agents.first { $0.id == a }?.name }
            return "The newest \(briefKind.map { "\($0.rawValue) " } ?? "")brief\(from.map { " from \($0)" } ?? "")"
        case .agents:
            let label = { (id: String) in options.agents.first { $0.id == id }?.name ?? "an agent" }
            return "\(listed(agents, label, all: "Every agent with a key")), quiet after \(Self.hoursLabel(hours))"
        case .note:
            return title.map { "A note: \($0)" } ?? "A note"
        }
    }
}
