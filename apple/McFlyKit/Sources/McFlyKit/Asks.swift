import Foundation
import Supabase

/// A question an agent is waiting on (the asks table, migration
/// 20261029000010): two to four choices, the first the main one. The person
/// answers it on any screen (`answer_ask`), or by asking McFly; the agent
/// reads the answer back. The feeds read only the open ones.
public struct Ask: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var agentId: UUID?
    public var question: String
    public var detail: String?
    public var choices: [String]
    /// As the agent sent it: the server takes any http(s) link, some of which
    /// Foundation can't parse, and one of those mustn't fail the whole list.
    public var url: String?
    public var expiresAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, question, detail, choices, url
        case agentId = "agent_id"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    public init(id: UUID = UUID(), agentId: UUID? = nil, question: String, detail: String? = nil, choices: [String],
                url: String? = nil, expiresAt: Date? = nil, createdAt: Date) {
        self.id = id
        self.agentId = agentId
        self.question = question
        self.detail = detail
        self.choices = choices
        self.url = url
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    /// The link to open, when Foundation can read it.
    public var link: URL? { url.flatMap(URL.init(string:)) }

    /// Still waiting at `now`: it hasn't run out.
    public func isOpen(now: Date) -> Bool {
        expiresAt.map { $0 > now } ?? true
    }

    /// The questions the demo asks, as if just asked: the display's two
    /// (display/resources/demo/feed.json), from whichever agents fit.
    public static func demo(agents: [Agent], now: Date = .now) -> [Ask] {
        let code = agents.first { $0.kind == .other } ?? agents.first
        let news = agents.first { $0.kind == .news } ?? agents.first
        return [
            Ask(id: UUID(uuidString: "a5c00000-0000-0000-0000-000000000001")!, agentId: code?.id,
                question: "Ship McFly v2.3 to TestFlight?", detail: "CI is green on main and the release notes are in the PR.",
                choices: ["Ship it", "Hold"], url: "https://github.com/rmantilla13/mcfly/pull/40",
                expiresAt: now.addingTimeInterval(6 * 3600), createdAt: now.addingTimeInterval(-95 * 60)),
            Ask(id: UUID(uuidString: "a5c00000-0000-0000-0000-000000000002")!, agentId: news?.id,
                question: "Which story leads tomorrow's Pulse?", choices: ["Chips", "Rates", "Launch"],
                createdAt: now.addingTimeInterval(-12 * 60)),
        ]
    }

    /// The choice another screen got in first, from answer_ask's refusal
    /// ("already answered: Hold"), or nil for any other error. Any case:
    /// `McFlyError.describe` capitalises the server's sentence.
    public static func answeredElsewhere(_ message: String) -> String? {
        guard let range = message.range(of: "already answered: ", options: .caseInsensitive) else { return nil }
        let rest = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// Why an answer didn't go, from what `answer_ask` threw: what the card
    /// should do next.
    public enum AnswerFailure: Equatable, Sendable {
        /// Another screen got in first, with this choice: the card stays gone.
        case answeredElsewhere(String)
        /// The agent took it back, or it ran out: the card stays gone.
        case closed
        /// The agent changed the question since it was read: the card comes
        /// back as it is now.
        case changed
        /// The server turned it down for another reason (a choice the agent
        /// has since replaced, an ask that's gone), in its own words: the
        /// card comes back as the server has it now.
        case refused(String)
        /// It never reached the server (offline, say): the card comes back as it was.
        case unsent

        public init(_ error: Error) {
            let message = McFlyError.describe(error)
            if let first = Ask.answeredElsewhere(message) {
                self = .answeredElsewhere(first)
            } else if message.range(of: "changed this question", options: .caseInsensitive) != nil {
                self = .changed
            } else if message.range(of: "took this question back", options: .caseInsensitive) != nil
                        || message.range(of: "this question ran out", options: .caseInsensitive) != nil {
                self = .closed
            } else if let refusal = error as? PostgrestError {
                self = .refused(refusal.message)
            } else {
                self = .unsent
            }
        }
    }
}
