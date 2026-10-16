import Foundation

// Rows as PostgREST returns them, mirroring
// backend/supabase/migrations/20261014000001_core.sql. Keys are the column
// names; dates are timestamptz columns. A `date` column stays a "yyyy-MM-dd"
// string, as the server writes it.

public struct Agent: Codable, Identifiable, Hashable, Sendable {
    /// A label for icons and colors; any agent may push to any feed.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case grok, stocks, news, other

        /// The server only stores the four kinds, but a later one must not
        /// break decoding of the whole list.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .other
        }

        public var label: String {
            switch self {
            case .grok: return "Grok"
            case .stocks: return "Stocks"
            case .news: return "News"
            case .other: return "Other"
            }
        }

        public var systemImage: String {
            switch self {
            case .grok: return "sparkles"
            case .stocks: return "chart.line.uptrend.xyaxis"
            case .news: return "newspaper"
            case .other: return "cpu"
            }
        }
    }

    public let id: UUID
    public var name: String
    public var slug: String
    public var kind: Kind
    /// "#rrggbb"
    public var color: String
    public var createdAt: Date
    public var lastSeenAt: Date?
    public var revokedAt: Date?
    // Only admin_list_agents fills these.
    public var keyPrefix: String?
    public var keyCreatedAt: Date?
    public var pushes7d: Int?
    public var lastError: String?

    public var isRevoked: Bool { revokedAt != nil }

    public init(id: UUID, name: String, slug: String, kind: Kind, color: String, createdAt: Date,
                lastSeenAt: Date? = nil, revokedAt: Date? = nil, keyPrefix: String? = nil,
                keyCreatedAt: Date? = nil, pushes7d: Int? = nil, lastError: String? = nil) {
        self.id = id; self.name = name; self.slug = slug; self.kind = kind; self.color = color
        self.createdAt = createdAt; self.lastSeenAt = lastSeenAt; self.revokedAt = revokedAt
        self.keyPrefix = keyPrefix; self.keyCreatedAt = keyCreatedAt; self.pushes7d = pushes7d; self.lastError = lastError
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, kind, color
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
        case revokedAt = "revoked_at"
        case keyPrefix = "key_prefix"
        case keyCreatedAt = "key_created_at"
        case pushes7d = "pushes_7d"
        case lastError = "last_error"
    }
}

/// What `admin_create_agent` returns. The key is shown once and never stored.
public struct CreatedAgent: Codable, Hashable, Sendable {
    public let id: UUID
    public let slug: String
    public let key: String

    public init(id: UUID, slug: String, key: String) {
        self.id = id; self.slug = slug; self.key = key
    }
}

public struct Brief: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case hourly, daily, alert, update

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .update
        }

        public var label: String { rawValue.capitalized }
    }

    public let id: UUID
    public var agentId: UUID
    public var externalId: String?
    public var title: String
    /// Plain text: blank lines between paragraphs, `- ` bullets (see `BriefText`).
    public var body: String
    public var kind: Kind
    public var publishedAt: Date
    public var expiresAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, agentId: UUID, externalId: String? = nil, title: String, body: String, kind: Kind,
                publishedAt: Date, expiresAt: Date? = nil, createdAt: Date, updatedAt: Date) {
        self.id = id; self.agentId = agentId; self.externalId = externalId; self.title = title; self.body = body
        self.kind = kind; self.publishedAt = publishedAt; self.expiresAt = expiresAt
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, body, kind
        case agentId = "agent_id"
        case externalId = "external_id"
        case publishedAt = "published_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One push of one symbol. `quotes` keeps the history; the newest row per
/// symbol is the quote shown, with what its agent added in `data`.
public struct Quote: Codable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public var agentId: UUID
    public var symbol: String
    public var name: String?
    public var price: Double
    public var change: Double?
    public var changePct: Double?
    public var currency: String
    public var note: String?
    public var asOf: Date
    public var createdAt: Date
    /// The holding, signals and day's numbers (`Holdings`). The live history
    /// leaves it out; the newest row's comes from `quotes_latest`.
    public var data: QuoteData?

    public init(id: Int64, agentId: UUID, symbol: String, name: String? = nil, price: Double, change: Double? = nil,
                changePct: Double? = nil, currency: String = "USD", note: String? = nil, asOf: Date, createdAt: Date,
                data: QuoteData? = nil) {
        self.id = id; self.agentId = agentId; self.symbol = symbol; self.name = name; self.price = price
        self.change = change; self.changePct = changePct; self.currency = currency; self.note = note
        self.asOf = asOf; self.createdAt = createdAt; self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case id, symbol, name, price, change, currency, note, data
        case agentId = "agent_id"
        case changePct = "change_pct"
        case asOf = "as_of"
        case createdAt = "created_at"
    }
}

/// Every symbol seen, with the console's order and hidden flag.
public struct Symbol: Codable, Identifiable, Hashable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public var name: String?
    public var sortOrder: Int
    public var hidden: Bool
    public var updatedAt: Date?

    public init(symbol: String, name: String? = nil, sortOrder: Int = 1000, hidden: Bool = false, updatedAt: Date? = nil) {
        self.symbol = symbol; self.name = name; self.sortOrder = sortOrder; self.hidden = hidden; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case symbol, name, hidden
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
    }
}

/// A Daily Pulse report. Loaded with its items embedded (`news_items`).
public struct NewsReport: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var agentId: UUID
    public var slug: String
    /// "yyyy-MM-dd"
    public var reportDate: String
    /// As the agent wrote it, e.g. "Oct 14, 2026".
    public var displayDate: String?
    /// The item key of the top story.
    public var heroItem: String?
    public var publishedAt: Date
    public var createdAt: Date?
    public var items: [NewsItem]

    public init(id: UUID, agentId: UUID, slug: String, reportDate: String, displayDate: String? = nil,
                heroItem: String? = nil, publishedAt: Date, createdAt: Date? = nil, items: [NewsItem] = []) {
        self.id = id; self.agentId = agentId; self.slug = slug; self.reportDate = reportDate
        self.displayDate = displayDate; self.heroItem = heroItem; self.publishedAt = publishedAt
        self.createdAt = createdAt; self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case id, slug
        case agentId = "agent_id"
        case reportDate = "report_date"
        case displayDate = "display_date"
        case heroItem = "hero_item"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case items = "news_items"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        agentId = try c.decode(UUID.self, forKey: .agentId)
        slug = try c.decode(String.self, forKey: .slug)
        reportDate = try c.decode(String.self, forKey: .reportDate)
        displayDate = try c.decodeIfPresent(String.self, forKey: .displayDate)
        heroItem = try c.decodeIfPresent(String.self, forKey: .heroItem)
        publishedAt = try c.decode(Date.self, forKey: .publishedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        // A report row read without its embed still decodes; the items are sorted
        // the way the display shows them regardless of how they came back.
        items = (try c.decodeIfPresent([NewsItem].self, forKey: .items) ?? []).sorted {
            ($0.sectionOrder, $0.position, $0.itemKey) < ($1.sectionOrder, $1.position, $1.itemKey)
        }
    }

    /// The top story: the item the agent named, else the first one.
    public var hero: NewsItem? {
        if let heroItem, let item = items.first(where: { $0.itemKey == heroItem }) { return item }
        return items.first
    }

    /// Items grouped by section in section order.
    public var sections: [NewsSection] {
        var order: [String] = []
        var grouped: [String: NewsSection] = [:]
        for item in items {
            if grouped[item.sectionKey] == nil {
                order.append(item.sectionKey)
                grouped[item.sectionKey] = NewsSection(key: item.sectionKey, name: item.sectionName, order: item.sectionOrder, items: [])
            }
            grouped[item.sectionKey]?.items.append(item)
        }
        return order.compactMap { grouped[$0] }
    }

    /// Every story but the hero, in report order.
    public var headlines: [NewsItem] {
        let heroId = hero?.id
        return items.filter { $0.id != heroId }
    }
}

public struct NewsSection: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public var name: String
    public var order: Int
    public var items: [NewsItem]
}

public struct NewsItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var reportId: UUID
    public var sectionKey: String
    public var sectionName: String
    public var sectionOrder: Int
    public var itemKey: String
    public var position: Int
    public var headline: String
    public var takeaway: String
    public var url: String
    public var imageURL: String?
    /// Host without www, as the server computed it from `url`.
    public var sourceDomain: String?
    public var createdAt: Date?

    public init(id: UUID, reportId: UUID, sectionKey: String, sectionName: String, sectionOrder: Int, itemKey: String,
                position: Int, headline: String, takeaway: String, url: String, imageURL: String? = nil,
                sourceDomain: String? = nil, createdAt: Date? = nil) {
        self.id = id; self.reportId = reportId; self.sectionKey = sectionKey; self.sectionName = sectionName
        self.sectionOrder = sectionOrder; self.itemKey = itemKey; self.position = position; self.headline = headline
        self.takeaway = takeaway; self.url = url; self.imageURL = imageURL; self.sourceDomain = sourceDomain
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, position, headline, takeaway, url
        case reportId = "report_id"
        case sectionKey = "section_key"
        case sectionName = "section_name"
        case sectionOrder = "section_order"
        case itemKey = "item_key"
        case imageURL = "image_url"
        case sourceDomain = "source_domain"
        case createdAt = "created_at"
    }

    public var link: URL? { URL(string: url) }
    public var image: URL? { imageURL.flatMap(URL.init(string:)) }
    /// The source to show: the stored domain, else the link's host.
    public var source: String { sourceDomain ?? link?.host?.replacingOccurrences(of: "www.", with: "") ?? "" }
}

/// A paired display, as `admin_list_devices` returns it.
public struct Device: Codable, Identifiable, Hashable, Sendable {
    /// A display that checked in within this long counts as online (spec §1.6).
    public static let onlineWindow: TimeInterval = 15 * 60

    /// The part of the display's settings (`devices.settings`) the app reads.
    public struct Settings: Codable, Hashable, Sendable {
        /// The account's voice (`AccountVoice`): one of Kokoro's.
        public var voice: String?
        /// The screen savers' backdrop (`AccountBackdrop`): the mesh, or one of the skies.
        public var backdrop: String?
        /// What falls over it (`AccountWeather`): off, by the season, or one kind.
        public var weather: String?

        public init(voice: String? = nil, backdrop: String? = nil, weather: String? = nil) {
            self.voice = voice; self.backdrop = backdrop; self.weather = weather
        }
    }

    public let id: UUID
    public var userId: UUID?
    public var name: String
    public var lastSeenAt: Date?
    public var createdAt: Date
    public var settings: Settings?

    public init(id: UUID, userId: UUID? = nil, name: String, lastSeenAt: Date? = nil, createdAt: Date, settings: Settings? = nil) {
        self.id = id; self.userId = userId; self.name = name; self.lastSeenAt = lastSeenAt; self.createdAt = createdAt
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case id, name, settings
        case userId = "user_id"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
    }

    public func isOnline(at now: Date = .now) -> Bool {
        guard let lastSeenAt else { return false }
        return now.timeIntervalSince(lastSeenAt) < Self.onlineWindow
    }
}

/// The one `platform_settings` row, as `admin_get_settings` returns it (no id).
/// Named for the table: SwiftUI has a `Settings` scene of its own.
public struct PlatformSettings: Codable, Hashable, Sendable {
    public var displayName: String
    public var timezone: String
    public var briefsKeepDays: Int
    public var quotesKeepDays: Int
    public var newsKeepReports: Int
    public var assistantProvider: AssistantProvider
    public var metricsKeepDays: Int
    public var eventsKeepDays: Int
    public var updatedAt: Date?

    public init(displayName: String = "McFly", timezone: String = "America/Chicago", briefsKeepDays: Int = 30,
                quotesKeepDays: Int = 90, newsKeepReports: Int = 14, assistantProvider: AssistantProvider = .claude,
                metricsKeepDays: Int = 90, eventsKeepDays: Int = 60, updatedAt: Date? = nil) {
        self.displayName = displayName; self.timezone = timezone; self.briefsKeepDays = briefsKeepDays
        self.quotesKeepDays = quotesKeepDays; self.newsKeepReports = newsKeepReports
        self.assistantProvider = assistantProvider; self.metricsKeepDays = metricsKeepDays; self.eventsKeepDays = eventsKeepDays
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case timezone
        case displayName = "display_name"
        case briefsKeepDays = "briefs_keep_days"
        case quotesKeepDays = "quotes_keep_days"
        case newsKeepReports = "news_keep_reports"
        case assistantProvider = "assistant_provider"
        case metricsKeepDays = "metrics_keep_days"
        case eventsKeepDays = "events_keep_days"
        case updatedAt = "updated_at"
    }

    /// A backend without the productivity migration leaves the newer columns out.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "McFly"
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone) ?? "America/Chicago"
        briefsKeepDays = try c.decodeIfPresent(Int.self, forKey: .briefsKeepDays) ?? 30
        quotesKeepDays = try c.decodeIfPresent(Int.self, forKey: .quotesKeepDays) ?? 90
        newsKeepReports = try c.decodeIfPresent(Int.self, forKey: .newsKeepReports) ?? 14
        assistantProvider = try c.decodeIfPresent(AssistantProvider.self, forKey: .assistantProvider) ?? .claude
        metricsKeepDays = try c.decodeIfPresent(Int.self, forKey: .metricsKeepDays) ?? 90
        eventsKeepDays = try c.decodeIfPresent(Int.self, forKey: .eventsKeepDays) ?? 60
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
