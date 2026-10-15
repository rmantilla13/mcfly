import Foundation
import Supabase

/// The 6-digit code a display shows, and the links that carry it:
/// `https://mcfly.bot/pair?code=123456` (a universal link, also the QR code
/// on the display) and `mcfly://pair?code=123456`.
public enum PairingCode {
    public static let length = 6
    public static let universalLinkHost = "mcfly.bot"

    /// Just the digits, at most six: what the server accepts.
    public static func normalize(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(length))
    }

    public static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(\.isNumber)
    }

    /// The code in a pairing link or QR payload, or nil when it isn't one.
    public static func code(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let isWeb = ["https", "http"].contains(components.scheme?.lowercased() ?? "")
            && components.host?.lowercased() == universalLinkHost
            && components.path.lowercased().hasPrefix("/pair")
        let isScheme = components.scheme?.lowercased() == "mcfly"
            && (components.host?.lowercased() == "pair" || components.path.lowercased().hasPrefix("/pair"))
        guard isWeb || isScheme else { return nil }
        guard let raw = components.queryItems?.first(where: { $0.name == "code" })?.value else { return nil }
        let code = normalize(raw)
        return isValid(code) ? code : nil
    }

    /// A QR code holds either a pairing link or the bare digits.
    public static func code(fromScanned payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let code = code(from: url) { return code }
        let code = normalize(trimmed)
        return trimmed.count == length && isValid(code) ? code : nil
    }

    /// The link a display's QR code should carry for this code.
    public static func link(for code: String) -> URL {
        URL(string: "https://\(universalLinkHost)/pair?code=\(code)")!
    }
}

/// `pair-device` `claim` (spec §2.2): binds the display showing `code` to
/// McFly. Needs an admin's JWT, which supabase-swift adds from the session.
public struct PairingClient: Sendable {
    private let functions: FunctionsClient

    public init(functions: FunctionsClient) {
        self.functions = functions
    }

    private struct ClaimBody: Encodable {
        var action = "claim"
        var code: String
        var name: String?
    }

    private struct ClaimResponse: Decodable { var deviceId: UUID }

    /// The new device's id. Throws the server's sentence (404 unknown or
    /// expired, 409 already used, 403 not an admin) as a `McFlyError`.
    public func claim(code: String, name: String?) async throws -> UUID {
        let clean = PairingCode.normalize(code)
        guard PairingCode.isValid(clean) else { throw McFlyError.message("Enter the 6 digits on the display.") }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ClaimBody(code: clean, name: trimmedName.flatMap { $0.isEmpty ? nil : $0 })
        do {
            let response: ClaimResponse = try await functions.invoke(
                "pair-device",
                options: FunctionInvokeOptions(body: body),
                decode: { data, _ in try JSONDecoder.mcfly.decode(ClaimResponse.self, from: data) })
            return response.deviceId
        } catch {
            throw McFlyError.message(McFlyError.describe(error))
        }
    }
}
