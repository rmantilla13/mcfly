import Foundation
import Supabase

/// A news story read in full: the `article` function's answer, kept server-side
/// in `news_articles` (PLATFORM_SPEC §2.6). Its text, pictures and videos are
/// blocks in page order; `summary` and `points` are the assistant's, and
/// `illustration` is a picture Grok drew of the story (a signed link).
public struct NewsArticle: Decodable, Hashable, Sendable {
    public enum Status: String, Decodable, Sendable {
        /// The page's own text.
        case ready
        /// Only what the page says about itself: a paywall's teaser, a video.
        case partial
        /// Nothing usable: the takeaway and the link stand in.
        case unavailable
    }

    public enum Block: Hashable, Sendable {
        case paragraph(String)
        case heading(String)
        case quote(String, cite: String?)
        case list([String], ordered: Bool)
        case image(URL, caption: String?)
        case video(Video)

        public var isMedia: Bool {
            switch self {
            case .image, .video: return true
            default: return false
            }
        }
    }

    public struct Video: Hashable, Sendable {
        public enum Provider: String, Sendable { case youtube, vimeo, file }
        public var url: URL
        public var provider: Provider
        public var poster: URL?
        public var caption: String?

        public init(url: URL, provider: Provider, poster: URL? = nil, caption: String? = nil) {
            self.url = url; self.provider = provider; self.poster = poster; self.caption = caption
        }

        public var label: String {
            switch provider {
            case .youtube: return "YouTube"
            case .vimeo: return "Vimeo"
            case .file: return "Video"
            }
        }
    }

    public var itemId: UUID
    public var status: Status
    public var title: String?
    public var byline: String?
    public var siteName: String?
    public var publishedAt: Date?
    public var leadImage: URL?
    public var blocks: [Block]
    public var wordCount: Int
    public var summary: String?
    public var points: [String]
    public var summaryModel: String?
    public var illustration: URL?
    /// A summary or picture is still being made: ask again in a moment.
    public var pending: Bool

    public init(itemId: UUID, status: Status, title: String? = nil, byline: String? = nil, siteName: String? = nil,
                publishedAt: Date? = nil, leadImage: URL? = nil, blocks: [Block] = [], wordCount: Int = 0,
                summary: String? = nil, points: [String] = [], summaryModel: String? = nil, illustration: URL? = nil, pending: Bool = false) {
        self.itemId = itemId; self.status = status; self.title = title; self.byline = byline; self.siteName = siteName
        self.publishedAt = publishedAt; self.leadImage = leadImage; self.blocks = blocks; self.wordCount = wordCount
        self.summary = summary; self.points = points; self.summaryModel = summaryModel; self.illustration = illustration
        self.pending = pending
    }

    enum CodingKeys: String, CodingKey {
        case status, title, byline, blocks, summary, points
        case itemId = "item_id"
        case siteName = "site_name"
        case publishedAt = "published_at"
        case leadImage = "lead_image"
        case wordCount = "word_count"
        case summaryModel = "summary_model"
        case illustration = "illustration_url"
        case pending
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try c.decode(UUID.self, forKey: .itemId)
        status = (try? c.decode(Status.self, forKey: .status)) ?? .unavailable
        title = try c.decodeIfPresent(String.self, forKey: .title)
        byline = try c.decodeIfPresent(String.self, forKey: .byline)
        siteName = try c.decodeIfPresent(String.self, forKey: .siteName)
        publishedAt = try? c.decodeIfPresent(Date.self, forKey: .publishedAt)
        leadImage = (try? c.decodeIfPresent(String.self, forKey: .leadImage)).flatMap(Self.webURL)
        // A block this version doesn't know (or can't read) is left out, not fatal.
        blocks = ((try? c.decodeIfPresent([RawBlock].self, forKey: .blocks)) ?? []).compactMap(\.block)
        wordCount = (try? c.decodeIfPresent(Int.self, forKey: .wordCount)) ?? 0
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        points = (try? c.decodeIfPresent([String].self, forKey: .points)) ?? []
        summaryModel = try c.decodeIfPresent(String.self, forKey: .summaryModel)
        illustration = (try? c.decodeIfPresent(String.self, forKey: .illustration)).flatMap(Self.webURL)
        pending = (try? c.decodeIfPresent(Bool.self, forKey: .pending)) ?? false
    }

    /// What is still on its way, while `pending`.
    public var working: String? {
        guard pending else { return nil }
        if summary == nil { return "Summarizing the story…" }
        if illustration == nil { return "Grok is drawing a picture of it…" }
        return nil
    }

    /// The pictures and videos, in page order.
    public var media: [Block] { blocks.filter(\.isMedia) }

    /// Whether there's more to read than the summary: the page's own text.
    public var hasFullStory: Bool { status == .ready && blocks.contains { !$0.isMedia } }

    /// "4 min read", at 230 words a minute.
    public var readingTime: String? {
        guard status == .ready, wordCount > 0 else { return nil }
        return "\(max(1, Int((Double(wordCount) / 230).rounded()))) min read"
    }

    static func webURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// One block as the function writes it: `{ type, text?, items?, url?, ... }`.
    private struct RawBlock: Decodable {
        var type: String
        var text: String?
        var cite: String?
        var items: [String]?
        var ordered: Bool?
        var url: String?
        var caption: String?
        var provider: String?
        var poster: String?

        var block: Block? {
            switch type {
            case "p": return text.map(Block.paragraph)
            case "h": return text.map(Block.heading)
            case "quote": return text.map { Block.quote($0, cite: cite) }
            case "list": return items.flatMap { $0.isEmpty ? nil : Block.list($0, ordered: ordered ?? false) }
            case "image": return url.flatMap(NewsArticle.webURL).map { Block.image($0, caption: caption) }
            case "video":
                guard let url = url.flatMap(NewsArticle.webURL) else { return nil }
                return .video(Video(url: url, provider: provider.flatMap(Video.Provider.init(rawValue:)) ?? .file,
                                    poster: poster.flatMap(NewsArticle.webURL), caption: caption))
            default: return nil
            }
        }
    }
}

/// Reads a story in full; the app's model hands one to the story view.
public typealias ArticleReader = @Sendable (NewsItem) async throws -> NewsArticle

/// Calls the `article` edge function as the signed-in person.
public struct ArticleClient: Sendable {
    private let functions: FunctionsClient

    public init(functions: FunctionsClient) {
        self.functions = functions
    }

    private struct Body: Encodable {
        var item_id: UUID
    }

    private struct Response: Decodable {
        var article: NewsArticle
    }

    /// The story's article. The first open of a story fetches and summarizes
    /// it (a few seconds); later ones are the kept copy. Throws the server's
    /// sentence as a `McFlyError`.
    public func article(for itemId: UUID) async throws -> NewsArticle {
        do {
            let response: Response = try await functions.invoke(
                "article",
                options: FunctionInvokeOptions(body: Body(item_id: itemId)),
                decode: { data, _ in try JSONDecoder.mcfly.decode(Response.self, from: data) })
            return response.article
        } catch {
            throw McFlyError.message(McFlyError.describe(error))
        }
    }
}

extension NewsArticle {
    /// The demo's article for a story: its takeaway as the summary, a few
    /// paragraphs around it, and its picture.
    public static func demo(for item: NewsItem) -> NewsArticle {
        let takeaway = item.takeaway.isEmpty ? item.headline : item.takeaway
        var blocks: [Block] = [
            .paragraph("\(item.headline). \(takeaway)"),
            .paragraph("This is the demo, so the article is made up from the story itself. Connected to a McFly backend, this page shows the article from \(item.source.isEmpty ? "its source" : item.source): its own words, pictures and videos."),
            .heading("What it means"),
            .paragraph(takeaway),
            .quote("The full story and a summary appear here when a story is opened.", cite: nil),
            .list(["The summary comes first", "Full story shows the article's text", "Pictures and videos stay in place"], ordered: false),
        ]
        if let image = item.image { blocks.insert(.image(image, caption: item.sectionName), at: 2) }
        return NewsArticle(itemId: item.id, status: .ready, title: item.headline, siteName: item.source,
                           leadImage: item.image, blocks: blocks, wordCount: 180,
                           summary: takeaway,
                           points: ["\(item.sectionName): \(item.headline)", "Read on \(item.source.isEmpty ? "the source" : item.source)"],
                           summaryModel: "demo")
    }
}
