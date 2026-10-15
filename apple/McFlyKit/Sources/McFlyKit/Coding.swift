import Foundation

// PostgREST writes timestamptz as ISO 8601 with microseconds and an offset
// ("2026-10-14T20:11:07.123456+00:00"); the seed and the demo file write
// whole seconds. Foundation's `.iso8601` strategy reads only one of those,
// so this one tries both.
extension JSONDecoder {
    public static let mcfly: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601Dates.parse(raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(raw)"))
        }
        return decoder
    }()
}

extension JSONEncoder {
    public static let mcfly: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

public enum ISO8601Dates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dayOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public static func parse(_ raw: String) -> Date? {
        // Postgres writes "+00" for UTC in some paths; ISO 8601 wants "+00:00".
        var text = raw
        if let range = text.range(of: #"[+-]\d\d$"#, options: .regularExpression) {
            text += ":00"
            _ = range
        }
        return fractional.date(from: text) ?? whole.date(from: text) ?? dayOnly.date(from: text)
    }
}
