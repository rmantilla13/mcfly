import XCTest
@testable import McFlyKit

final class ArticleTests: XCTestCase {
    private func decode(_ json: String) throws -> NewsArticle {
        try JSONDecoder.mcfly.decode(NewsArticle.self, from: Data(json.utf8))
    }

    func testDecodesTheFunctionsArticle() throws {
        let article = try decode("""
        {"item_id": "0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61", "status": "ready", "title": "Rates hold",
         "byline": "Pat Writer", "site_name": "The Paper", "published_at": "2026-10-20T14:30:00.000Z",
         "lead_image": "https://cdn.test/lead.jpg", "word_count": 690,
         "blocks": [
           {"type": "p", "text": "First."},
           {"type": "h", "text": "Why"},
           {"type": "quote", "text": "We held.", "cite": "X"},
           {"type": "list", "items": ["a", "b"], "ordered": true},
           {"type": "image", "url": "https://cdn.test/1.jpg", "caption": "Chart"},
           {"type": "video", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "provider": "youtube",
            "poster": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"},
           {"type": "table", "rows": []},
           {"type": "image", "url": "javascript:alert(1)"},
           {"type": "list", "items": []}
         ],
         "summary": "The bank held.", "points": ["One", "Two"], "summary_model": "claude-sonnet-5-5",
         "summary_tried_at": "2026-10-21T08:00:00+00:00", "fetched_at": "2026-10-21T08:00:00+00:00",
         "illustration": "0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61.jpg",
         "illustration_url": "https://x.supabase.co/storage/v1/object/sign/news-illustrations/a.jpg?token=t"}
        """)
        XCTAssertEqual(article.status, .ready)
        XCTAssertEqual(article.siteName, "The Paper")
        XCTAssertEqual(article.publishedAt, ISO8601Dates.parse("2026-10-20T14:30:00Z"))
        XCTAssertEqual(article.leadImage, URL(string: "https://cdn.test/lead.jpg"))
        XCTAssertEqual(article.blocks.count, 6, "unknown and unusable blocks are left out")
        XCTAssertEqual(article.blocks[3], .list(["a", "b"], ordered: true))
        XCTAssert(article.blocks[5] == .video(.init(url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!, provider: .youtube,
                                                 poster: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"))))
        XCTAssertEqual(article.media.count, 2)
        XCTAssert(article.hasFullStory)
        XCTAssertEqual(article.readingTime, "3 min read")
        XCTAssertEqual(article.points, ["One", "Two"])
        XCTAssertEqual(article.illustration?.host, "x.supabase.co")
        XCTAssertFalse(article.pending)
        XCTAssertNil(article.working)
    }

    func testPendingSaysWhatIsOnItsWay() throws {
        var article = try decode("""
        {"item_id": "0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61", "status": "unavailable", "blocks": [], "pending": true}
        """)
        XCTAssertTrue(article.pending)
        XCTAssertEqual(article.working, "Summarizing the story…")
        article.summary = "Grok read it."
        XCTAssertEqual(article.working, "Grok is drawing a picture of it…")
    }

    func testAPageWithNothingStillDecodes() throws {
        let article = try decode("""
        {"item_id": "0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61", "status": "unavailable", "title": null, "byline": null,
         "site_name": null, "published_at": null, "lead_image": null, "blocks": [], "word_count": 0,
         "summary": null, "points": [], "summary_model": null, "fetched_at": "2026-10-21T08:00:00+00:00"}
        """)
        XCTAssertEqual(article.status, .unavailable)
        XCTAssert(!article.hasFullStory)
        XCTAssertEqual(article.readingTime, nil)
        XCTAssertEqual(article.summary, nil)
        XCTAssertNil(article.illustration)
    }

    func testAnUnknownStatusOrBadDateIsNotFatal() throws {
        let article = try decode("""
        {"item_id": "0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61", "status": "archived", "published_at": "yesterday",
         "blocks": [{"type": "p", "text": "Teaser."}]}
        """)
        XCTAssertEqual(article.status, .unavailable)
        XCTAssertEqual(article.publishedAt, nil)
        XCTAssertEqual(article.blocks, [.paragraph("Teaser.")])
    }

    func testTheDemoArticleCarriesTheStory() {
        let item = NewsItem(id: UUID(), reportId: UUID(), sectionKey: "ai", sectionName: "AI", sectionOrder: 0, itemKey: "x",
                            position: 0, headline: "A headline", takeaway: "The takeaway.", url: "https://paper.test/a",
                            imageURL: "https://cdn.test/a.jpg")
        let article = NewsArticle.demo(for: item)
        XCTAssertEqual(article.summary, "The takeaway.")
        XCTAssertEqual(article.leadImage, URL(string: "https://cdn.test/a.jpg"))
        XCTAssert(article.hasFullStory)
        XCTAssertEqual(article.media.count, 1)
    }
}
