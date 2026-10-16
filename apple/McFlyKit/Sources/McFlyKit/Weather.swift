import Foundation

/// Today's weather where the phone is, from Open-Meteo (open-meteo.com: free, no
/// key, no account). No agent pushes weather to McFly, so the phone asks for it
/// itself, with its approximate location, for Home's weather tile.
public struct Weather: Equatable, Sendable {
    /// Now, in the unit asked for.
    public var temperature: Double
    public var high: Double
    public var low: Double
    /// WMO weather code (open-meteo.com/en/docs, "WMO Weather interpretation codes").
    public var code: Int
    public var isDay: Bool
    public var unit: Unit

    public enum Unit: String, Sendable {
        case celsius, fahrenheit
    }

    public init(temperature: Double, high: Double, low: Double, code: Int, isDay: Bool = true, unit: Unit = .fahrenheit) {
        self.temperature = temperature; self.high = high; self.low = low; self.code = code; self.isDay = isDay; self.unit = unit
    }

    /// The forecast request for a place: now, and today's high and low, in its own time zone.
    public static func url(latitude: Double, longitude: Double, unit: Unit) -> URL {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        // Two decimals (about a kilometre) is plenty for a forecast and says less about where the phone is.
        let round: (Double) -> String = { String(format: "%.2f", $0) }
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: round(latitude)),
            URLQueryItem(name: "longitude", value: round(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        return parts.url!
    }

    /// Decodes Open-Meteo's answer to `url(...)`.
    public static func decode(_ data: Data, unit: Unit) throws -> Weather {
        struct Answer: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let is_day: Int?
            }
            struct Daily: Decodable {
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let current: Current
            let daily: Daily
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        guard let high = answer.daily.temperature_2m_max.first, let low = answer.daily.temperature_2m_min.first else {
            throw McFlyError.message("The forecast had no high or low for today.")
        }
        return Weather(temperature: answer.current.temperature_2m, high: high, low: low,
                       code: answer.current.weather_code, isDay: (answer.current.is_day ?? 1) == 1, unit: unit)
    }

    /// Fahrenheit where the person's locale measures in US units, else Celsius.
    public static func unit(for locale: Locale = .current) -> Unit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// "Partly cloudy", for the WMO code.
    public var condition: String {
        switch code {
        case 0: return isDay ? "Clear" : "Clear night"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71, 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81: return "Showers"
        case 82: return "Heavy showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Thunderstorms, hail"
        default: return "—"
        }
    }

    /// An SF Symbol for the WMO code (multicolour where the app draws it so).
    public var systemImage: String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 67, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }

    /// "72°"
    public static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
}
