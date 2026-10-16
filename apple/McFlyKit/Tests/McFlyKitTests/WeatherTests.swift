import XCTest
@testable import McFlyKit

/// Home's weather tile: the Open-Meteo request and answer, and how a code reads.
final class WeatherTests: XCTestCase {
    func testTheRequestAsksForNowAndTodayAtAboutAKilometre() throws {
        let url = Weather.url(latitude: 30.267153, longitude: -97.743057, unit: .fahrenheit)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertEqual(items["latitude"], "30.27")
        XCTAssertEqual(items["longitude"], "-97.74")
        XCTAssertEqual(items["temperature_unit"], "fahrenheit")
        XCTAssertEqual(items["forecast_days"], "1")
        XCTAssertEqual(items["current"], "temperature_2m,weather_code,is_day")
    }

    func testDecodesOpenMeteo() throws {
        let json = """
        {"latitude":30.27,"longitude":-97.74,"timezone":"America/Chicago",
         "current":{"time":"2026-10-15T17:00","interval":900,"temperature_2m":72.4,"weather_code":2,"is_day":1},
         "daily":{"time":["2026-10-15"],"temperature_2m_max":[78.1],"temperature_2m_min":[60.6]}}
        """
        let weather = try Weather.decode(Data(json.utf8), unit: .fahrenheit)
        XCTAssertEqual(weather, Weather(temperature: 72.4, high: 78.1, low: 60.6, code: 2, isDay: true, unit: .fahrenheit))
        XCTAssertEqual(weather.condition, "Partly cloudy")
        XCTAssertEqual(weather.systemImage, "cloud.sun.fill")
        XCTAssertEqual(Weather.degrees(weather.temperature), "72°")
        XCTAssertEqual(Weather.degrees(60.6), "61°")
    }

    func testAnAnswerWithoutTodayIsAnError() {
        let json = #"{"current":{"temperature_2m":10,"weather_code":0},"daily":{"temperature_2m_max":[],"temperature_2m_min":[]}}"#
        XCTAssertThrowsError(try Weather.decode(Data(json.utf8), unit: .celsius))
    }

    func testCodesReadAsWeather() {
        XCTAssertEqual(Weather(temperature: 0, high: 0, low: 0, code: 0, isDay: false).systemImage, "moon.stars.fill")
        XCTAssertEqual(Weather(temperature: 0, high: 0, low: 0, code: 95).condition, "Thunderstorms")
        XCTAssertEqual(Weather(temperature: 0, high: 0, low: 0, code: 65).systemImage, "cloud.heavyrain.fill")
        XCTAssertEqual(Weather(temperature: 0, high: 0, low: 0, code: 42).condition, "—")
        XCTAssertEqual(Weather.unit(for: Locale(identifier: "en_US")), .fahrenheit)
        XCTAssertEqual(Weather.unit(for: Locale(identifier: "en_GB")), .celsius)
    }
}
