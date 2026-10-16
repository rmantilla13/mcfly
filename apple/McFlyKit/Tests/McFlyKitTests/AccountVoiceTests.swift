import XCTest
@testable import McFlyKit

/// One voice for the account, read from and written to the displays (`AccountVoice`).
final class AccountVoiceTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    func testTheAccountVoiceIsTheOldestDisplaysThatHasOne() {
        XCTAssertNil(AccountVoice.resolve([]))
        let bare = Device(id: UUID(), name: "New", createdAt: older)
        let office = Device(id: UUID(), name: "Office", createdAt: newer, settings: .init(voice: "am_fenrir"))
        let kitchen = Device(id: UUID(), name: "Kitchen", createdAt: older.addingTimeInterval(1), settings: .init(voice: "af_bella"))
        XCTAssertNil(AccountVoice.resolve([bare]))
        XCTAssertEqual(AccountVoice.resolve([office, bare]), "am_fenrir")
        XCTAssertEqual(AccountVoice.resolve([office, kitchen, bare]), "af_bella")
        let odd = Device(id: UUID(), name: "Odd", createdAt: older, settings: .init(voice: "system"))
        XCTAssertEqual(AccountVoice.resolve([odd, office]), "am_fenrir", "a voice that isn't Kokoro's is skipped")
    }

    func testThisDevicesVoiceStaysAndKokoroFollows() {
        XCTAssertEqual(AccountVoice.follow(local: "system", account: "af_bella"), "system")
        XCTAssertEqual(AccountVoice.follow(local: "af_heart", account: "af_bella"), "af_bella")
        XCTAssertEqual(AccountVoice.follow(local: "am_fenrir", account: nil), "am_fenrir")
    }

    func testTheVoiceDecodesFromTheDisplaysSettings() throws {
        let json = #"""
        [{"id": "00000000-0000-0000-0000-0000000e0001", "user_id": null, "name": "Display",
          "last_seen_at": null, "created_at": "2026-10-15T21:22:19.544927+00:00",
          "settings": {"voice": "am_michael", "darkMode": true, "idleSeconds": 120}},
         {"id": "00000000-0000-0000-0000-0000000e0002", "name": "Older server",
          "created_at": "2026-10-16T09:00:00+00:00"}]
        """#
        let devices = try JSONDecoder.mcfly.decode([Device].self, from: Data(json.utf8))
        XCTAssertEqual(devices[0].settings?.voice, "am_michael")
        XCTAssertNil(devices[1].settings)
        XCTAssertEqual(AccountVoice.resolve(devices), "am_michael")
    }

    func testAPickGoesToEveryDisplay() async throws {
        let admin = try DemoAdminService()
        let before = try await admin.listDevices()
        XCTAssertGreaterThan(before.count, 1)
        let held = try await admin.setAccountVoice("am_fenrir")
        XCTAssertEqual(held, before.count)
        let after = try await admin.listDevices()
        XCTAssertEqual(after.map { $0.settings?.voice }, Array(repeating: "am_fenrir", count: before.count))
        let voice = try await admin.accountVoice()
        XCTAssertEqual(voice, "am_fenrir")
        do {
            try await admin.setAccountVoice(AccountVoice.system)
            XCTFail("this device's voice is never sent")
        } catch {}
    }
}
