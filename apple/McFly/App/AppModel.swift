import Foundation
import McFlyKit
import Observation

/// Streams an answer: the `assistant` function in the real app, canned text in
/// demo mode. Events arrive on the main actor, `done` or `error` last.
typealias Answerer = @MainActor (_ message: String, _ mode: AssistantClient.Mode, _ history: [AssistantTurn],
                                 _ provider: AssistantProvider?,
                                 _ onEvent: @escaping @MainActor @Sendable (AssistantEvent) -> Void) async throws -> Void

/// App-wide state: who is signed in, whether they're the admin, the feeds,
/// and the links the app was opened with. Screens read from here and call the
/// services for everything else.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        case signedOut
        /// Signed in, but `is_platform_admin` said no.
        case notAdmin
        case ready
        /// A saved account that can't be checked right now (offline).
        case unreachable
    }

    private(set) var phase: Phase = .loading
    var errorMessage: String?
    let feeds: FeedStore
    let admin: any AdminService
    let isDemo: Bool
    /// A pairing code from a link or QR code, waiting for the pairing sheet.
    var pendingPairCode: String?
    /// Set once a sign-in link has been emailed, so the screen can say so.
    var magicLinkSentTo: String?
    /// The voice answers are read in: the account's (`AccountVoice`), kept on this
    /// device so the first answer needn't wait for the server, or this device's own.
    private(set) var voice = VoiceChoice.current
    @ObservationIgnored private var voicePicks = 0
    @ObservationIgnored private var voiceSaving: Task<Void, Never>?
    /// The screen savers' backdrop (`AccountBackdrop`), read from the displays: the
    /// mesh, or one of the skies Ambient draws (`Backdrop`). A build pinned to one
    /// (`-McFlyBackdrop`, for screenshots) keeps it.
    private(set) var backdrop = Config.pinnedBackdrop ?? AccountBackdrop.mesh

    private let client: McFlyClient?
    private let pairingClient: PairingClient?

    init() {
        if Config.isDemo {
            isDemo = true
            client = nil
            pairingClient = nil
            // The demo file is part of the app; if it's unreadable the build is broken, not the network.
            let demo = try! DemoData.load().rebased()
            feeds = FeedStore(source: DemoFeedSource(data: demo))
            admin = DemoAdminService(data: demo)
        } else {
            isDemo = false
            let client = McFlyClient(supabaseURL: Config.supabaseURL, anonKey: Config.supabaseAnonKey,
                                     authCallbackURL: Config.authCallbackURL)
            self.client = client
            pairingClient = client.pairing
            feeds = FeedStore(source: client.feeds)
            admin = client.admin
        }
    }

    var email: String? { isDemo ? "demo@mcfly.bot" : client?.currentEmail }

    // MARK: Lifecycle

    func start() async {
        if isDemo {
            phase = .ready
            await feeds.refresh()
            return
        }
        guard let client, Config.isConfigured else {
            errorMessage = Config.unconfiguredMessage
            phase = .signedOut
            return
        }
        for await state in client.sessionStates {
            switch state {
            case .signedIn:
                await checkAdmin()
            case .signedOut:
                phase = .signedOut
            case .unreachable:
                errorMessage = "McFly couldn't be reached. Check your connection and try again."
                phase = .unreachable
            }
        }
    }

    /// RLS lets an admin read every feed; anyone else gets an explanation.
    func checkAdmin() async {
        do {
            if try await admin.isPlatformAdmin() {
                phase = .ready
                async let voiceSynced: Void = syncVoice()
                async let backdropSynced: Void = syncBackdrop()
                await feeds.refresh()
                await voiceSynced
                await backdropSynced
            } else {
                phase = .notAdmin
            }
        } catch {
            errorMessage = McFlyError.describe(error)
            phase = .unreachable
        }
    }

    // MARK: Auth

    func signIn(email: String, password: String) async {
        guard let client else { return }
        do {
            try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch {
            report(error)
        }
    }

    /// True when the email went out.
    func sendMagicLink(email: String) async -> Bool {
        guard let client else { return false }
        let address = email.trimmingCharacters(in: .whitespaces)
        do {
            try await client.sendMagicLink(email: address)
            magicLinkSentTo = address
            return true
        } catch {
            report(error)
            return false
        }
    }

    func signOut() async {
        guard !isDemo else { return }
        await client?.signOut()
        magicLinkSentTo = nil
    }

    // MARK: Links

    /// `mcfly://auth-callback…` finishes an email link; a pairing link
    /// (`https://mcfly.bot/pair?code=…` or `mcfly://pair?code=…`) opens the
    /// pairing sheet with the code filled in.
    func handleOpenURL(_ url: URL) {
        if let code = PairingCode.code(from: url) {
            pendingPairCode = code
            return
        }
        guard let client, client.isAuthCallback(url) else { return }
        Task {
            do {
                try await client.handleAuthCallback(url)
            } catch {
                report(error)
            }
        }
    }

    // MARK: Voice

    /// Catches up with the account's voice, picked on the display or the web, say.
    /// This device's own voice stays; with no display, the choice here is all there is.
    func syncVoice() async {
        let pick = voicePicks
        await voiceSaving?.value
        guard let account = try? await admin.accountVoice(), pick == voicePicks else { return }
        setVoice(VoiceChoice(rawValue: AccountVoice.follow(local: voice.rawValue, account: account)) ?? voice)
    }

    /// A voice picked here. A Kokoro voice goes to every display, so the display and
    /// the web speak with it too; this device's own voice stays on this device.
    func chooseVoice(_ choice: VoiceChoice) {
        voicePicks += 1
        setVoice(choice)
        guard choice.kokoro != nil else { return }
        let admin = admin
        voiceSaving = Task {
            do {
                try await admin.setAccountVoice(choice.rawValue)
            } catch {
                report(error)
            }
        }
    }

    private func setVoice(_ choice: VoiceChoice) {
        guard choice != voice else { return }
        voice = choice
        VoiceChoice.current = choice
    }

    // MARK: Backdrop

    /// Catches up with the displays' backdrop, picked on the display or the web
    /// (`AccountBackdrop`): the admin check asks, and Ambient as it opens.
    func syncBackdrop() async {
        guard Config.pinnedBackdrop == nil, let account = try? await admin.accountBackdrop() else { return }
        backdrop = account
    }

    // MARK: Services

    /// Claims a display's code (`pair-device` `claim`). Demo: a pretend device.
    func pairDisplay(code: String, name: String?) async throws -> UUID {
        if let pairingClient { return try await pairingClient.claim(code: code, name: name) }
        guard PairingCode.isValid(PairingCode.normalize(code)) else { throw McFlyError.message("Enter the 6 digits on the display.") }
        try await Task.sleep(for: .milliseconds(600))
        return UUID()
    }

    /// The assistant, streamed. Demo mode answers from the loaded feeds.
    var answer: Answerer {
        if let client {
            let assistant = client.assistant
            // The sheet's own choice first, else the platform setting, so the request says
            // so even before the server rereads it.
            let fallback = feeds.settings?.assistantProvider
            return { message, mode, history, provider, onEvent in
                try await assistant.stream(message, mode: mode, history: history, provider: provider ?? fallback, onEvent: onEvent)
            }
        }
        let feeds = feeds
        return { message, mode, _, provider, onEvent in
            let reply = mode == .read ? Self.demoReadReply(to: message, feeds: feeds, provider: provider)
                : Self.demoReply(to: message, mode: mode, feeds: feeds, provider: provider)
            for word in reply.split(separator: " ", omittingEmptySubsequences: false) {
                try await Task.sleep(for: .milliseconds(45))
                onEvent(.delta(String(word) + " "))
            }
            onEvent(.done(AssistantReply(reply: reply, model: "demo")))
        }
    }

    private static func demoReply(to message: String, mode: AssistantClient.Mode, feeds: FeedStore,
                                  provider: AssistantProvider?) -> String {
        let lower = message.lowercased()
        let signoff = provider == .grok ? " (Grok, in the demo.)" : ""
        if lower.contains("project"), let project = feeds.projectsByAttention.first {
            return "\(project.name) is \(project.status.label.lowercased())" + (project.nextStep.map { "; next: \($0)" } ?? "") + "." + signoff
        }
        if lower.contains("calendar") || lower.contains("event") || lower.contains("next up"),
           let event = feeds.upcomingEvents(limit: 1).first {
            return "Next up is \(event.title), \(Format.dayLabel(event.startsAt).lowercased()) at \(Format.time(event.startsAt))." + signoff
        }
        if let series = feeds.series.first(where: { lower.contains($0.symbol.lowercased()) || lower.contains($0.displayName.lowercased()) }) {
            let q = series.latest
            return "\(series.displayName) is at \(Format.price(q.price, currency: q.currency)), \(Format.change(q.change, pct: q.changePct)) today." + (q.note.map { " " + $0 } ?? "")
        }
        if lower.contains("news") || lower.contains("headline"), let story = feeds.latestReport?.hero {
            return "The top story is \(story.headline). \(story.takeaway)"
        }
        if let brief = feeds.latestBrief {
            let summary = BriefText.summary(brief.body)
            return mode == .quick ? "From \(brief.title): \(summary)" : "Here's the latest brief, \(brief.title).\n\n\(brief.body)"
        }
        return "This is the demo. Connect a Supabase project to talk to the real McFly."
    }

    /// The full-screen Ask's answer in the demo, shaped as the real one is
    /// (the assistant's `brief` and `layout` skills, docs/ASSISTANT.md): the
    /// answer in a line, the figures as tiles, what needs you first as tagged
    /// items, a table only where it is narrow, the brief's point as a quote.
    /// Asked for a table, it draws the projects as a wide one with a sentence
    /// in each row, as answers did before the skills: on a phone each row
    /// becomes a card.
    private static func demoReadReply(to message: String, feeds: FeedStore, provider: AssistantProvider?) -> String {
        if message.lowercased().contains("table") {
            let rows = feeds.projectsByAttention.prefix(6).map { p in
                "| \(p.name) | \(p.status.label) | \(p.nextStep ?? (p.summary.isEmpty ? "Nothing planned yet" : p.summary)) |"
            }
            return (["Every open project, side by side.", "### Waiting on action", "| Project | Status | What's needed |", "|:--|:--|:--|"]
                + rows + ["", "This is the demo. Connect a Supabase project to ask the real McFly."]).joined(separator: "\n")
        }
        var lead = "Here's where everything stands" + (provider == .grok ? " (Grok, in the demo)." : ".")
        let blocked = feeds.blockedProjects
        if let first = blocked.first { lead += " **\(first.name)** is blocked and needs you first." }
        var parts = [lead]

        let projects = feeds.projectsByAttention
        let events = feeds.upcomingEvents(limit: 3)
        var stats = ["```stats", "Projects | \(projects.count)"]
        stats.append("Blocked | \(blocked.count) | " + (blocked.isEmpty ? "up" : "down"))
        if !events.isEmpty { stats.append("Coming up | \(events.count) | watch") }
        if !feeds.series.isEmpty { stats.append("Watchlist | \(feeds.series.count)") }
        stats.append("```")
        parts.append(stats.joined(separator: "\n"))

        if !blocked.isEmpty {
            parts.append("### Needs you")
            parts.append(blocked.prefix(5).map { p in
                "- [Blocked] **\(p.name)**" + (p.nextStep.map { " — \($0)" } ?? "")
            }.joined(separator: "\n"))
        }
        if !events.isEmpty {
            parts.append("### Coming up")
            // The tag is the day in a word, as the skill asks; the time follows the name.
            parts.append(events.map { e in
                let day = Calendar.current.isDateInToday(e.startsAt) ? "Today"
                    : Calendar.current.isDateInTomorrow(e.startsAt) ? "Tomorrow"
                    : e.startsAt.formatted(.dateTime.weekday(.abbreviated))
                return "- [\(day)] **\(e.title)** — \(Format.time(e.startsAt))"
            }.joined(separator: "\n"))
        }
        let series = feeds.series.prefix(5)
        if !series.isEmpty {
            parts.append("### Markets")
            parts.append((["| Symbol | Price | Today |", "|:--|--:|--:|"] + series.map { s in
                let q = s.latest
                return "| **\(s.symbol)** | \(Format.price(q.price, currency: q.currency)) | \(Format.change(q.change, pct: q.changePct)) |"
            }).joined(separator: "\n"))
        }
        let moving = projects.filter { $0.status != .blocked }.prefix(4)
        if !moving.isEmpty {
            parts.append("### Projects")
            parts.append(moving.map { p in
                "- [\(p.status.label)] **\(p.name)**" + (p.nextStep.map { " — \($0)" } ?? "")
            }.joined(separator: "\n"))
        }
        if let brief = feeds.latestBrief {
            parts.append("### From the latest brief")
            parts.append("> " + BriefText.summary(brief.body))
        }
        parts.append("This is the demo. Connect a Supabase project to ask the real McFly.")
        return parts.joined(separator: "\n\n")
    }

    func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        errorMessage = McFlyError.describe(error)
    }
}
