import Foundation

/// Weather over the screen savers' backdrop, as the display's Settings →
/// Backdrop → Weather and the console's Customize set it
/// (`devices.settings.weather`): `off`, `season` (by the date and the
/// hemisphere where it is shown: snow in winter, petals in spring, fireflies
/// in summer, leaves in autumn), or one kind all year. Which kind, which
/// season and how many are the display's rules (DisplayController::weatherFor,
/// seasonFor, southernZone, weatherCount) and the console's (lib/weather.ts),
/// with the same cases in each one's tests. The app reads it as it reads the
/// backdrop (`AccountBackdrop`): from the first display that has one.
public enum AccountWeather {
    /// What `clean_device_settings` accepts.
    public static let settings = ["off", "season", "snow", "petals", "fireflies", "leaves"]
    /// What falls: every setting but off and season.
    public static let kinds = ["snow", "petals", "fireflies", "leaves"]
    public static let off = "off"

    /// The weather the account's displays show: the first display, oldest
    /// first, with a setting this build knows. Off with no display, or none
    /// with the key yet.
    public static func resolve(_ devices: [Device]) -> String {
        devices.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .lazy.compactMap { $0.settings?.weather }
            .first { settings.contains($0) } ?? off
    }

    // Meteorological seasons, whole months, as the north has them: December
    // to February is winter.
    static let north = ["winter", "winter", "spring", "spring", "spring", "summer",
                        "summer", "summer", "autumn", "autumn", "autumn", "winter"]

    /// The season in `month` (1–12), in the north or six months on in the south.
    public static func season(month: Int, south: Bool) -> String {
        let m = (month - 1 + 12) % 12
        return north[south ? (m + 6) % 12 : m]
    }

    // Time zones south of the equator: a whole region by prefix where every
    // zone in it is, one by one elsewhere. One missing gets the north's seasons.
    static let southPrefixes = ["Australia/", "Antarctica/", "America/Argentina/", "Chile/", "Brazil/"]
    static let southZones: Set<String> = [
        "NZ", "NZ-CHAT", "Pacific/Auckland", "Pacific/Chatham", "Pacific/Fiji", "Pacific/Noumea", "Pacific/Tongatapu",
        "Pacific/Apia", "Pacific/Efate", "Pacific/Norfolk", "Pacific/Tahiti", "Pacific/Easter", "Pacific/Rarotonga",
        "America/Santiago", "America/Punta_Arenas", "America/Montevideo", "America/Asuncion", "America/Sao_Paulo",
        "America/La_Paz", "America/Lima", "America/Recife", "America/Bahia", "America/Maceio", "America/Cuiaba",
        "America/Campo_Grande", "America/Porto_Velho", "America/Rio_Branco",
        "Atlantic/Stanley", "Atlantic/South_Georgia", "Atlantic/St_Helena",
        "Africa/Johannesburg", "Africa/Maputo", "Africa/Harare", "Africa/Lusaka", "Africa/Windhoek", "Africa/Gaborone",
        "Africa/Maseru", "Africa/Mbabane", "Africa/Blantyre", "Africa/Lubumbashi", "Africa/Luanda", "Africa/Dar_es_Salaam",
        "Indian/Antananarivo", "Indian/Mauritius", "Indian/Reunion", "Indian/Mayotte", "Indian/Comoro",
    ]

    /// Whether an IANA time zone is south of the equator.
    public static func southernZone(_ zone: String?) -> Bool {
        let tz = zone ?? ""
        return southZones.contains(tz) || southPrefixes.contains { tz.hasPrefix($0) }
    }

    /// What falls on `date` where `timeZone` is: a kind, or nil while off (or
    /// for a setting this build doesn't know).
    public static func kind(for setting: String, on date: Date = Date(), in timeZone: TimeZone = .current) -> String? {
        if setting == "season" {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            switch season(month: calendar.component(.month, from: date), south: southernZone(timeZone.identifier)) {
            case "winter": return "snow"
            case "spring": return "petals"
            case "summer": return "fireflies"
            default: return "leaves"
            }
        }
        return kinds.contains(setting) ? setting : nil
    }

    // How many: one per this many square points of screen, within bounds. A
    // phone gets a few; a big screen is not crowded, nor paying for a crowd.
    static let density: [String: (per: Double, min: Int, max: Int)] = [
        "snow": (26_000, 12, 44), "petals": (60_000, 6, 18), "leaves": (85_000, 5, 14), "fireflies": (65_000, 7, 20),
    ]

    /// How many of `kind` a screen `width` × `height` shows at once.
    public static func count(_ kind: String, width: Double, height: Double) -> Int {
        guard let d = density[kind] else { return 0 }
        let n = Int((max(0, width) * max(0, height) / d.per).rounded())
        return max(d.min, min(d.max, n))
    }
}

extension AdminService {
    /// The account's weather, read from the displays.
    public func accountWeather() async throws -> String {
        AccountWeather.resolve(try await listDevices())
    }
}
