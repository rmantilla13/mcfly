import Foundation

/// Labels shared by the screens, so a price or a time reads the same everywhere.
public enum Format {
    public static func price(_ value: Double, currency: String = "USD") -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    /// "+2.78 (+1.13%)", "−3.10 (−1.62%)", or "" when nothing is known.
    public static func change(_ change: Double?, pct: Double?) -> String {
        var parts: [String] = []
        if let change { parts.append(signed(change, fractionDigits: 2)) }
        if let pct { parts.append("(\(signed(pct, fractionDigits: 2))%)") }
        return parts.joined(separator: " ")
    }

    /// "+1.13%" / "−1.62%".
    public static func percent(_ pct: Double?) -> String {
        guard let pct else { return "" }
        return signed(pct, fractionDigits: 2) + "%"
    }

    public static func signed(_ value: Double, fractionDigits: Int) -> String {
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(fractionDigits)))
        if value > 0 { return "+" + magnitude }
        if value < 0 { return "−" + magnitude }
        return magnitude
    }

    /// "Just now", "20 min ago", "3 hr ago", or the date for anything older than a day.
    public static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) hr ago" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400)) d ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Today", "Yesterday", else "Tuesday, Oct 14".
    public static func dayLabel(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Never", "Online", or when a display last checked in.
    public static func lastSeen(_ device: Device, now: Date = .now) -> String {
        guard let seen = device.lastSeenAt else { return "Never seen" }
        if device.isOnline(at: now) { return "Online" }
        return "Last seen " + relative(seen, now: now).lowercased()
    }
}
