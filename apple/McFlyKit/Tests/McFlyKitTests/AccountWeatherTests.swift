import XCTest
@testable import McFlyKit

/// Weather over the savers' backdrop, read from the displays (`AccountWeather`),
/// by the display's own cases (tst_display.cpp) and the console's (weather.test.mjs).
final class AccountWeatherTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    private func on(_ y: Int, _ m: Int, _ d: Int, in zone: String) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testTheWeatherIsTheOldestDisplaysThatHasOneElseOff() {
        XCTAssertEqual(AccountWeather.resolve([]), "off")
        let bare = Device(id: UUID(), name: "New", createdAt: older)
        let office = Device(id: UUID(), name: "Office", createdAt: newer, settings: .init(weather: "snow"))
        let kitchen = Device(id: UUID(), name: "Kitchen", createdAt: older.addingTimeInterval(1), settings: .init(weather: "season"))
        XCTAssertEqual(AccountWeather.resolve([bare]), "off", "a display without the key shows none")
        XCTAssertEqual(AccountWeather.resolve([office, bare]), "snow")
        XCTAssertEqual(AccountWeather.resolve([office, kitchen, bare]), "season")
        let odd = Device(id: UUID(), name: "Odd", createdAt: older, settings: .init(weather: "rain"))
        XCTAssertEqual(AccountWeather.resolve([odd, office]), "snow", "a setting this build doesn't know is skipped")
    }

    func testTheWeatherDecodesFromTheDisplaysSettings() throws {
        let json = #"""
        [{"id": "00000000-0000-0000-0000-0000000e0001", "name": "Display", "created_at": "2026-10-15T21:22:19+00:00",
          "settings": {"backdrop": "dawn", "weather": "fireflies", "darkMode": true}}]
        """#
        let devices = try JSONDecoder.mcfly.decode([Device].self, from: Data(json.utf8))
        XCTAssertEqual(devices[0].settings?.weather, "fireflies")
        XCTAssertEqual(AccountWeather.resolve(devices), "fireflies")
    }

    func testSeasonsAreWholeMonthsAndTheSouthHasTheNorthsSixMonthsOn() {
        XCTAssertEqual((1...12).map { AccountWeather.season(month: $0, south: false) },
                       ["winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter"])
        XCTAssertEqual(AccountWeather.season(month: 12, south: true), "summer")
        XCTAssertEqual(AccountWeather.season(month: 7, south: true), "winter")
        XCTAssertEqual(AccountWeather.season(month: 10, south: true), "spring")
        XCTAssertEqual(AccountWeather.season(month: 4, south: true), "autumn")
        for tz in ["Australia/Sydney", "Pacific/Auckland", "America/Argentina/Buenos_Aires", "America/Santiago",
                   "America/Sao_Paulo", "Africa/Johannesburg", "Antarctica/McMurdo"] {
            XCTAssertTrue(AccountWeather.southernZone(tz), tz)
        }
        for tz in ["America/Chicago", "Europe/London", "Asia/Tokyo", "Africa/Cairo", "America/Bogota", "UTC", ""] {
            XCTAssertFalse(AccountWeather.southernZone(tz), tz)
        }
    }

    func testBySeasonIsTheSeasonsWeatherWhereItIsShown() {
        func seasonal(_ y: Int, _ m: Int, _ d: Int, _ zone: String) -> String? {
            AccountWeather.kind(for: "season", on: on(y, m, d, in: zone), in: TimeZone(identifier: zone)!)
        }
        XCTAssertEqual(seasonal(2026, 12, 20, "America/Chicago"), "snow")
        XCTAssertEqual(seasonal(2026, 12, 20, "Australia/Sydney"), "fireflies")
        XCTAssertEqual(seasonal(2026, 4, 20, "America/Chicago"), "petals")
        XCTAssertEqual(seasonal(2026, 4, 20, "Australia/Sydney"), "leaves")
        XCTAssertEqual(seasonal(2026, 10, 16, "America/Chicago"), "leaves")
        for kind in AccountWeather.kinds { XCTAssertEqual(AccountWeather.kind(for: kind), kind) }
        XCTAssertNil(AccountWeather.kind(for: "off"))
        XCTAssertNil(AccountWeather.kind(for: "rain"))
    }

    func testASmallScreenGetsAFewAndABigOneIsNotCrowded() {
        for kind in AccountWeather.kinds {
            let phone = AccountWeather.count(kind, width: 390, height: 844)
            let laptop = AccountWeather.count(kind, width: 1440, height: 900)
            let huge = AccountWeather.count(kind, width: 5120, height: 2880)
            XCTAssertTrue(phone > 0 && phone <= laptop && laptop <= huge, kind)
            XCTAssertEqual(AccountWeather.count(kind, width: 0, height: 0), AccountWeather.count(kind, width: 1, height: 1))
            XCTAssertEqual(huge, AccountWeather.count(kind, width: 20_000, height: 20_000))
        }
        XCTAssertEqual(AccountWeather.kinds.map { AccountWeather.count($0, width: 1440, height: 900) }, [44, 18, 20, 14])
        XCTAssertEqual(AccountWeather.count("rain", width: 1440, height: 900), 0)
    }

    func testTheDemosDisplaysShowNone() async throws {
        let weather = try await DemoAdminService().accountWeather()
        XCTAssertEqual(weather, "off")
    }
}
