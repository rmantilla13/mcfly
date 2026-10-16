import Foundation

/// McFly speaks with one voice on the Pi, the web and here: one of Kokoro's, kept in
/// the displays' settings (`devices.settings.voice`), which the Pi already syncs both
/// ways. The app reads it from `admin_list_devices` and writes a pick to every display,
/// so a voice picked anywhere is the voice everywhere. "This device's voice" (the
/// system's) is the one local choice: it stays on the device and is never sent. The
/// web follows the same rule (admin/lib/account-voice.ts).
public enum AccountVoice {
    /// Kokoro's voices, as `clean_device_settings` accepts them.
    public static let kokoro = ["af_heart", "af_bella", "am_michael", "am_fenrir"]
    /// This device's own voice.
    public static let system = "system"

    /// The account's voice: the first display, oldest first (as `admin_list_devices`
    /// orders them), that has one. Nil with no display, or none with a voice yet.
    public static func resolve(_ devices: [Device]) -> String? {
        devices.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .lazy.compactMap { $0.settings?.voice }
            .first { kokoro.contains($0) }
    }

    /// What this device speaks with: its own voice stays; a Kokoro voice follows the
    /// account once it's known.
    public static func follow(local: String, account: String?) -> String {
        guard local != system, let account else { return local }
        return account
    }
}

extension AdminService {
    /// The account's voice, read from the displays.
    public func accountVoice() async throws -> String? {
        AccountVoice.resolve(try await listDevices())
    }

    /// A Kokoro voice picked here goes to every display; the Pi and the web follow it.
    /// Returns how many displays hold it (0: no display yet, the app keeps it to itself).
    @discardableResult
    public func setAccountVoice(_ voice: String) async throws -> Int {
        guard AccountVoice.kokoro.contains(voice) else { throw McFlyError.message("That isn't one of McFly's voices.") }
        let devices = try await listDevices()
        for device in devices { try await setVoice(voice, on: device.id) }
        return devices.count
    }
}
