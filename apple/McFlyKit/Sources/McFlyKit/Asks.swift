import Foundation

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
    public var url: URL?
    public var expiresAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, question, detail, choices, url
        case agentId = "agent_id"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    public init(id: UUID = UUID(), agentId: UUID? = nil, question: String, detail: String? = nil, choices: [String],
                url: URL? = nil, expiresAt: Date? = nil, createdAt: Date) {
        self.id = id
        self.agentId = agentId
        self.question = question
        self.detail = detail
        self.choices = choices
        self.url = url
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

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
                choices: ["Ship it", "Hold"], url: URL(string: "https://github.com/rmantilla13/mcfly/pull/40"),
                expiresAt: now.addingTimeInterval(6 * 3600), createdAt: now.addingTimeInterval(-95 * 60)),
            Ask(id: UUID(uuidString: "a5c00000-0000-0000-0000-000000000002")!, agentId: news?.id,
                question: "Which story leads tomorrow's Pulse?", choices: ["Chips", "Rates", "Launch"],
                createdAt: now.addingTimeInterval(-12 * 60)),
        ]
    }

    /// The choice another screen got in first, from answer_ask's refusal
    /// ("already answered: Hold"), or nil for any other error.
    public static func answeredElsewhere(_ message: String) -> String? {
        guard let range = message.range(of: "already answered: ") else { return nil }
        let rest = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}
