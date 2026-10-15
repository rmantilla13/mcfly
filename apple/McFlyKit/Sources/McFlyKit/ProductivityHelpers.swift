import Foundation

extension Project {
    /// The newest update the feed embedded, if any.
    public var lastUpdate: ProjectUpdate? { updates.first }
}

extension CalendarEvent {
    public func isOngoing(at now: Date = .now) -> Bool { startsAt <= now && endsAt > now }
}
