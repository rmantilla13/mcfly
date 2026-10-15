import Foundation

// The anon key is designed to ship in client apps; row-level security does the
// protecting. A device or Mac build reads SupabaseURL and SupabaseAnonKey from
// Info.plist (Config/Local.xcconfig). Without them the app can still run in
// demo mode (`-McFlyDemo YES`) against the seed's data.
enum Config {
    static let unconfiguredMessage = "This build isn't connected to a Supabase project yet. Set SUPABASE_URL and SUPABASE_ANON_KEY in apple/Config/Local.xcconfig and build again."

    static let supabaseURL: URL = url(forInfoKey: "SupabaseURL") ?? URL(string: "https://YOUR-PROJECT.supabase.co")!
    static let supabaseAnonKey: String = string(forInfoKey: "SupabaseAnonKey") ?? "YOUR-ANON-KEY"

    /// `mcfly://auth-callback` finishes email links; `mcfly://pair?code=…` and
    /// `https://mcfly.bot/pair?code=…` open the pairing sheet. Both must match
    /// project.yml (CFBundleURLSchemes, the associated domain) and Supabase →
    /// Authentication → URL Configuration → Redirect URLs.
    static let urlScheme = "mcfly"
    static let authCallbackURL = URL(string: "\(urlScheme)://auth-callback")!

    static var isConfigured: Bool {
        let host = supabaseURL.host?.lowercased() ?? ""
        return !host.contains("your-project") && !supabaseAnonKey.isEmpty && supabaseAnonKey != "YOUR-ANON-KEY"
    }

    /// "1.0.0 (1)"
    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Demo mode: the seed's data, no backend. Edit the scheme's arguments or
    /// run `xcodebuild … -McFlyDemo YES`.
    static var isDemo: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-McFlyDemo"), i + 1 < arguments.count {
            return ["YES", "1", "true"].contains(arguments[i + 1])
        }
        return ProcessInfo.processInfo.environment["MCFLY_DEMO"] == "1"
    }

    private static func string(forInfoKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func url(forInfoKey key: String) -> URL? {
        guard let raw = string(forInfoKey: key), let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
