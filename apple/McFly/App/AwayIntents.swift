import AppIntents
import Foundation
import McFlyKit

/// Away mode from Shortcuts: an automation on leaving home runs "I'm Away",
/// one on arriving runs "I'm Home", so the display opens to Messages only
/// while you're out (`set_away`). They sign in from the app's saved session
/// and don't open the app, so they work from a locked phone.
struct ImAwayIntent: AppIntent {
    static let title: LocalizedStringResource = "I'm Away"
    static let description = IntentDescription("Tell McFly you're out of the house: the display opens to Messages for whoever's home.")

    @Parameter(title: "Note", description: "Shown on the display beside your name, such as \u{201C}At work\u{201D}.")
    var note: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await AwayIntents.set(true, note: note)
        return .result(dialog: "McFly knows you're out. The display opens to Messages.")
    }
}

struct ImHomeIntent: AppIntent {
    static let title: LocalizedStringResource = "I'm Home"
    static let description = IntentDescription("Turn McFly's away mode off: the display goes back to Home.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await AwayIntents.set(false, note: nil)
        return .result(dialog: "Welcome home. McFly's display is back to normal.")
    }
}

enum AwayIntents {
    static func set(_ away: Bool, note: String?) async throws -> AwayStatus {
        if Config.isDemo { return AwayStatus() }
        guard Config.isConfigured else { throw McFlyError.message(Config.unconfiguredMessage) }
        let client = McFlyClient(supabaseURL: Config.supabaseURL, anonKey: Config.supabaseAnonKey,
                                 authCallbackURL: Config.authCallbackURL)
        do {
            return try await client.messages.setAway(away, until: nil, note: note)
        } catch {
            throw McFlyError.message(McFlyError.describe(error))
        }
    }
}

struct McFlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ImAwayIntent(), phrases: ["I'm away in \(.applicationName)", "Turn on \(.applicationName) away mode"],
                    shortTitle: "I'm Away", systemImageName: "figure.walk.departure")
        AppShortcut(intent: ImHomeIntent(), phrases: ["I'm home in \(.applicationName)", "Turn off \(.applicationName) away mode"],
                    shortTitle: "I'm Home", systemImageName: "house")
    }
}
