import XCTest
@testable import McFlyKit

/// The screen savers' backdrop, read from the displays (`AccountBackdrop`).
final class AccountBackdropTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    func testTheBackdropIsTheOldestDisplaysThatHasOneElseTheMesh() {
        XCTAssertEqual(AccountBackdrop.resolve([]), "mesh")
        let bare = Device(id: UUID(), name: "New", createdAt: older)
        let office = Device(id: UUID(), name: "Office", createdAt: newer, settings: .init(backdrop: "silk"))
        let kitchen = Device(id: UUID(), name: "Kitchen", createdAt: older.addingTimeInterval(1), settings: .init(backdrop: "ribbons"))
        XCTAssertEqual(AccountBackdrop.resolve([bare]), "mesh", "a display without the key shows the mesh")
        XCTAssertEqual(AccountBackdrop.resolve([office, bare]), "silk")
        XCTAssertEqual(AccountBackdrop.resolve([office, kitchen, bare]), "ribbons")
        let odd = Device(id: UUID(), name: "Odd", createdAt: older, settings: .init(backdrop: "plaid"))
        XCTAssertEqual(AccountBackdrop.resolve([odd, office]), "silk", "a style this build doesn't know is skipped")
        XCTAssertEqual(AccountBackdrop.styles, [AccountBackdrop.mesh] + AccountBackdrop.skies)
    }

    func testTheBackdropDecodesFromTheDisplaysSettings() throws {
        let json = #"""
        [{"id": "00000000-0000-0000-0000-0000000e0001", "user_id": null, "name": "Display",
          "last_seen_at": null, "created_at": "2026-10-15T21:22:19.544927+00:00",
          "settings": {"voice": "am_michael", "backdrop": "dawn", "darkMode": true, "idleSeconds": 120}},
         {"id": "00000000-0000-0000-0000-0000000e0002", "name": "Older display",
          "created_at": "2026-10-16T09:00:00+00:00", "settings": {"voice": "af_heart"}}]
        """#
        let devices = try JSONDecoder.mcfly.decode([Device].self, from: Data(json.utf8))
        XCTAssertEqual(devices[0].settings?.backdrop, "dawn", "the keys the app doesn't read are passed over")
        XCTAssertNil(devices[1].settings?.backdrop, "a display from before the setting has no key")
        XCTAssertEqual(AccountBackdrop.resolve(devices), "dawn")
        XCTAssertEqual(AccountBackdrop.resolve([devices[1]]), "mesh")
    }

    func testTheDemosDisplaysShowTheMesh() async throws {
        let admin = try DemoAdminService()
        let backdrop = try await admin.accountBackdrop()
        XCTAssertEqual(backdrop, "mesh")
    }
}
