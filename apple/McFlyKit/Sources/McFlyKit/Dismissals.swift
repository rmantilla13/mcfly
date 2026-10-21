import Foundation

/// A callout someone dismissed (the dismissals table, migration
/// 20261021000070): an insight's id, lower-cased (`blocked:<project id>`,
/// `metric:<key>`, …), and when it runs out. Nil means when the project
/// changes, which the server sees to. The display, the console and this app
/// hide an id while it has a dismissal that hasn't run out.
public struct Dismissal: Codable, Hashable, Sendable {
    public var key: String
    public var hideUntil: Date?

    enum CodingKeys: String, CodingKey {
        case key
        case hideUntil = "hide_until"
    }

    public init(key: String, hideUntil: Date? = nil) {
        self.key = key
        self.hideUntil = hideUntil
    }

    /// Whether this one hides `id` (any case) at `now`.
    public func hides(_ id: String, now: Date) -> Bool {
        key == id.lowercased() && (hideUntil.map { $0 > now } ?? true)
    }
}
