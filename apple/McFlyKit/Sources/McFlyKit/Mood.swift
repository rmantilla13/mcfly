import Foundation

/// The time of day the palette follows, picked the way the display picks it
/// (display/src/hardware/DisplayController.cpp, `updateNightMode`): night
/// from 9:30 pm to 6:30 am (the display's night-mode window), then morning
/// until 11, day until 5 pm and evening after.
public enum Mood: String, CaseIterable, Sendable {
    case morning, day, evening, night

    /// Night starts at 21:30 and ends at 06:30, in minutes after midnight.
    public static let nightStart = 21 * 60 + 30
    public static let nightEnd = 6 * 60 + 30

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 12
        let minutes = hour * 60 + (parts.minute ?? 0)
        if minutes >= Self.nightStart || minutes < Self.nightEnd {
            self = .night
        } else if hour < 11 {
            self = .morning
        } else if hour < 17 {
            self = .day
        } else {
            self = .evening
        }
    }

    /// The next moment the mood changes after `date`: 6:30, 11:00, 17:00 or 21:30.
    public static func nextChange(after date: Date, calendar: Calendar = .current) -> Date {
        let boundaries = [nightEnd, 11 * 60, 17 * 60, nightStart]
        let midnight = calendar.startOfDay(for: date)
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: midnight) else { continue }
            for minutes in boundaries {
                if let moment = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                   moment > date {
                    return moment
                }
            }
        }
        return date.addingTimeInterval(3600)
    }
}
