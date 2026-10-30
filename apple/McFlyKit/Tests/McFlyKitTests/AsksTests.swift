import Supabase
import XCTest
@testable import McFlyKit

/// The asks the server answers with, as a source the tests set.
private actor AskSource: FeedSource {
    let data: DemoData
    var asks: [Ask]

    init(data: DemoData, asks: [Ask]) {
        self.data = data
        self.asks = asks
    }

    func setAsks(_ asks: [Ask]) { self.asks = asks }

    func loadAgents() async throws -> [Agent] { data.agents }
    func loadBriefs(limit: Int) async throws -> [Brief] { [] }
    func loadQuotes(limit: Int) async throws -> [Quote] { [] }
    func loadSymbols() async throws -> [Symbol] { [] }
    func loadReports(limit: Int) async throws -> [NewsReport] { [] }
    func loadSettings() async throws -> PlatformSettings? { nil }
    func loadProjects(updatesPerProject: Int) async throws -> [Project] { [] }
    func loadMetrics(limit: Int) async throws -> [Metric] { [] }
    func loadMetricSettings() async throws -> [MetricSetting] { [] }
    func loadDashboards() async throws -> [Dashboard] { [] }
    func loadEvents(from: Date, to: Date) async throws -> [CalendarEvent] { [] }
    func loadAsks() async throws -> [Ask] { asks }
}

final class AsksTests: XCTestCase {
    func testDecodesARow() throws {
        let json = """
        [{"id": "a5c00000-0000-0000-0000-000000000009", "agent_id": "00000000-0000-0000-0000-00000000a001",
          "question": "Ship v2.3?", "detail": null, "choices": ["Ship it", "Hold"], "url": "https://example.com/pr/4",
          "expires_at": null, "created_at": "2026-10-29T18:00:00.123456+00:00"}]
        """
        let asks = try JSONDecoder.mcfly.decode([Ask].self, from: Data(json.utf8))
        XCTAssertEqual(asks.first?.choices, ["Ship it", "Hold"])
        XCTAssertEqual(asks.first?.link?.host(), "example.com")
        XCTAssertNil(asks.first?.expiresAt)
        XCTAssertTrue(asks.first?.isOpen(now: .now) ?? false)
    }

    /// The server takes any http(s) link; one Foundation can't read has no
    /// link, and the rest of the list still reads.
    func testALinkFoundationCantReadKeepsTheList() throws {
        let json = """
        [{"id": "a5c00000-0000-0000-0000-000000000009", "question": "Ship v2.3?", "choices": ["Ship it", "Hold"],
          "url": "https://example.com:8o80/", "created_at": "2026-10-29T18:00:00Z"},
         {"id": "a5c00000-0000-0000-0000-00000000000a", "question": "Which story?", "choices": ["A", "B"],
          "url": "https://example.com/pr/4", "created_at": "2026-10-29T18:01:00Z"}]
        """
        let asks = try JSONDecoder.mcfly.decode([Ask].self, from: Data(json.utf8))
        XCTAssertEqual(asks.map(\.question), ["Ship v2.3?", "Which story?"])
        XCTAssertEqual(asks[0].url, "https://example.com:8o80/")
        XCTAssertNil(asks[0].link)
        XCTAssertEqual(asks[1].link?.host(), "example.com")
    }

    func testAnsweredElsewhere() {
        XCTAssertEqual(Ask.answeredElsewhere("already answered: Hold"), "Hold")
        XCTAssertEqual(Ask.answeredElsewhere("Couldn't save: already answered: Ship it "), "Ship it")
        XCTAssertNil(Ask.answeredElsewhere("this question ran out"))
        // As the app shows it: describe() capitalises the server's sentence.
        let described = McFlyError.describe(PostgrestError(code: "P0001", message: "already answered: Hold"))
        XCTAssertEqual(described, "Already answered: Hold")
        XCTAssertEqual(Ask.answeredElsewhere(described), "Hold")
    }

    /// What each of answer_ask's refusals does to the card, from the error
    /// supabase-swift throws for it.
    func testAnswerFailures() {
        func failure(_ message: String) -> Ask.AnswerFailure {
            Ask.AnswerFailure(PostgrestError(code: "P0001", message: message))
        }
        XCTAssertEqual(failure("already answered: Ship it"), .answeredElsewhere("Ship it"))
        XCTAssertEqual(failure("the agent took this question back"), .closed)
        XCTAssertEqual(failure("this question ran out"), .closed)
        XCTAssertEqual(failure("the agent changed this question; look again"), .changed)
        // Refusals a fresh read clears, in the server's words.
        XCTAssertEqual(failure("answer with one of: Ship now, Wait"), .refused("answer with one of: Ship now, Wait"))
        XCTAssertEqual(failure("ask not found"), .refused("ask not found"))
        // A label that only mentions running out is still the server's list.
        XCTAssertEqual(failure("answer with one of: Ran out, Plenty"), .refused("answer with one of: Ran out, Plenty"))
        // Never reached the server.
        XCTAssertEqual(Ask.AnswerFailure(URLError(.notConnectedToInternet)), .unsent)
    }

    /// answer_ask's arguments: the question goes exactly as it came.
    func testAnswerSendsTheQuestionAsItCame() throws {
        let params = AnswerAskParams(ask: "a5c00000-0000-0000-0000-000000000009", choice: "Hold", question: "Ship  v2.3?\n")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: String])
        XCTAssertEqual(json, ["ask": "a5c00000-0000-0000-0000-000000000009", "choice": "Hold", "via": "app",
                              "question": "Ship  v2.3?\n"])
    }

    /// Run-out asks are filtered by the server, in UTC.
    func testTheQueryLeavesOutTheRunOut() {
        let now = Date(timeIntervalSince1970: 1_793_361_600)  // 2026-10-30 12:00 UTC
        XCTAssertEqual(SupabaseFeedSource.notRunOut(at: now), "expires_at.is.null,expires_at.gt.2026-10-30T12:00:00Z")
    }

    @MainActor
    func testOpenAsksHideTheRunOutAndTheAnsweredHere() async throws {
        let data = try DemoData.load()
        let now = Date()
        let older = Ask(question: "Older?", choices: ["Yes", "No"], createdAt: now.addingTimeInterval(-600))
        let ranOut = Ask(question: "Gone?", choices: ["Yes", "No"], expiresAt: now.addingTimeInterval(-1), createdAt: now.addingTimeInterval(-900))
        let newer = Ask(question: "Newer?", choices: ["A", "B"], expiresAt: now.addingTimeInterval(3600), createdAt: now.addingTimeInterval(-60))
        let source = AskSource(data: data, asks: [newer, ranOut, older])
        let feeds = FeedStore(source: source)
        await feeds.refresh()
        XCTAssertEqual(feeds.openAsks(now: now).map(\.question), ["Older?", "Newer?"], "oldest first, the run-out one left out")

        // Answered here: hidden while the server still lists it, and again
        // after a refresh that does; gone from the list once the server drops it.
        feeds.setAnsweredHere(older.id, true)
        XCTAssertEqual(feeds.openAsks(now: now).map(\.question), ["Newer?"])
        await feeds.refresh()
        XCTAssertEqual(feeds.openAsks(now: now).map(\.question), ["Newer?"])
        await source.setAsks([newer])
        await feeds.refresh()
        XCTAssertTrue(feeds.answeredHere.isEmpty)
        // Taken back (an undo, a failed send): shown again.
        feeds.setAnsweredHere(newer.id, true)
        feeds.setAnsweredHere(newer.id, false)
        XCTAssertEqual(feeds.openAsks(now: now).map(\.question), ["Newer?"])
    }

    @MainActor
    func testTheDemoAsksTwo() async throws {
        let feeds = FeedStore(source: try DemoFeedSource())
        await feeds.refresh()
        let asks = feeds.openAsks()
        XCTAssertEqual(asks.map(\.choices), [["Ship it", "Hold"], ["Chips", "Rates", "Launch"]])
        XCTAssertNotNil(asks.first?.agentId)
        let answered = try await DemoAdminService(data: DemoData.load()).answerAsk(asks[0].id, choice: "Hold",
                                                                                  question: asks[0].question)
        XCTAssertEqual(answered, "Hold")
    }
}
