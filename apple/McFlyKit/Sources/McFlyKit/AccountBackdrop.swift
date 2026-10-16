import Foundation

/// The screen savers' backdrop, as the display's Settings → Backdrop and the
/// console's Customize set it (`devices.settings.backdrop`): `mesh`, the moving
/// gradient with an aurora over it at night, or one of five skies, each a shader
/// of its own (display/qml/components/Backdrop.qml; the app's `Backdrop` draws
/// the same ones). The app reads it the way it reads the voice (`AccountVoice`):
/// from the first display that has one. A display without the key shows the
/// mesh, so the app does too.
public enum AccountBackdrop {
    /// What `clean_device_settings` accepts.
    public static let styles = ["mesh", "arc", "ribbons", "dawn", "silk", "pillars"]
    /// What every display showed before there was a choice.
    public static let mesh = "mesh"
    /// The skies: every style but the mesh.
    public static let skies = ["arc", "ribbons", "dawn", "silk", "pillars"]

    /// The backdrop the account's displays show: the first display, oldest first
    /// (as `admin_list_devices` orders them), with a style this build knows. The
    /// mesh with no display, or none with the key yet.
    public static func resolve(_ devices: [Device]) -> String {
        devices.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .lazy.compactMap { $0.settings?.backdrop }
            .first { styles.contains($0) } ?? mesh
    }
}

extension AdminService {
    /// The account's backdrop, read from the displays.
    public func accountBackdrop() async throws -> String {
        AccountBackdrop.resolve(try await listDevices())
    }
}
