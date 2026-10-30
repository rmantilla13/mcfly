import XCTest
@testable import McFlyKit

final class SSEParserTests: XCTestCase {
    func testBlankLineCompletesAnEvent() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed(line: "event: delta"))
        XCTAssertNil(parser.feed(line: "data: {\"text\":\"Hi\"}"))
        XCTAssertEqual(parser.feed(line: ""), SSEParser.Event(name: "delta", data: "{\"text\":\"Hi\"}"))
        // The next event starts clean.
        XCTAssertNil(parser.feed(line: "data: x"))
        XCTAssertEqual(parser.feed(line: ""), SSEParser.Event(name: "message", data: "x"))
    }

    func testMultiLineDataAndComments() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed(line: ": keep-alive"))
        XCTAssertNil(parser.feed(line: "event: done"))
        XCTAssertNil(parser.feed(line: "data: {\"reply\":"))
        XCTAssertNil(parser.feed(line: "data: \"ok\"}"))
        XCTAssertNil(parser.feed(line: "id: 3"))
        XCTAssertEqual(parser.feed(line: ""), SSEParser.Event(name: "done", data: "{\"reply\":\n\"ok\"}"))
    }

    func testBlankLineWithoutDataIsNothing() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed(line: ""))
        XCTAssertNil(parser.feed(line: "event: delta"))
        XCTAssertNil(parser.feed(line: ""))
    }

    func testFinishFlushesATrailingEvent() {
        var parser = SSEParser()
        _ = parser.feed(line: "event: delta")
        _ = parser.feed(line: "data:{\"text\":\"no space after colon\"}")
        XCTAssertEqual(parser.finish(), SSEParser.Event(name: "delta", data: "{\"text\":\"no space after colon\"}"))
        XCTAssertNil(parser.finish())
    }

    func testDecodesTheSpecEvents() {
        XCTAssertEqual(AssistantClient.decode(.init(name: "delta", data: "{\"text\":\"Hel\"}")), .delta("Hel"))
        XCTAssertEqual(AssistantClient.decode(.init(name: "done", data: "{\"reply\":\"Hello.\",\"model\":\"claude-sonnet-5-5\"}")),
                       .done(AssistantReply(reply: "Hello.", model: "claude-sonnet-5-5")))
        XCTAssertEqual(AssistantClient.decode(.init(name: "error", data: "{\"message\":\"busy\"}")), .error("busy"))
        XCTAssertNil(AssistantClient.decode(.init(name: "thread", data: "{}")))
        // A done the app can't read is reported, not dropped silently.
        if case .error? = AssistantClient.decode(.init(name: "done", data: "{")) {} else {
            XCTFail("expected an error event for an unreadable done")
        }
    }

    func testTurnsEncodeAsTheSpecShape() throws {
        let data = try JSONEncoder().encode([AssistantTurn(role: .user, text: "hi"), AssistantTurn(role: .assistant, text: "hello")])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])
        XCTAssertEqual(json, [["role": "user", "text": "hi"], ["role": "assistant", "text": "hello"]])
    }

    /// `suggested` goes only when the app wrote the question; a typed or
    /// spoken one sends the body older apps did.
    func testASuggestedQuestionSaysSo() async throws {
        let client = AssistantClient(supabaseURL: URL(string: "https://example.supabase.co")!, anonKey: "anon") { "token" }
        func body(suggested: Bool) async throws -> [String: Any] {
            let request = try await client.makeRequest("What's blocking McFly?", mode: .read, history: [], provider: nil,
                                                       suggested: suggested, streaming: true)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        }
        let chip = try await body(suggested: true)
        XCTAssertEqual(chip["suggested"] as? Bool, true)
        XCTAssertEqual(chip["message"] as? String, "What's blocking McFly?")
        let typed = try await body(suggested: false)
        XCTAssertNil(typed["suggested"])
        XCTAssertEqual(Set(typed.keys), ["message", "mode", "stream", "history"])
    }

    func testAnAnswerCutShortSaysSo() throws {
        let data = try JSONEncoder().encode(AssistantTurn(role: .assistant, text: "Saturday you have", interrupted: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["interrupted"] as? Bool, true)
        let back = try JSONDecoder().decode(AssistantTurn.self, from: data)
        XCTAssertTrue(back.interrupted)
        XCTAssertFalse(try JSONDecoder().decode(AssistantTurn.self, from: Data(#"{"role":"user","text":"hi"}"#.utf8)).interrupted)
    }
}
