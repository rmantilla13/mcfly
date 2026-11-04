import Foundation
import Observation
import Supabase

/// A message in the household thread (the messages table, migration
/// 20261103000010): written on a display by someone at home, or the person's
/// reply from the app or the console. The server says who wrote it; the
/// app only reads the thread and sends its own replies (`send_message`).
public struct Message: Codable, Identifiable, Hashable, Sendable {
    public enum Sender: String, Codable, Sendable {
        /// Someone at home, on a display.
        case display
        /// The person, in the app or on the console.
        case person
    }

    public var id: UUID
    public var sender: Sender
    /// One of the names listed for the displays, the display's own name, or
    /// what the household calls the person.
    public var senderName: String
    public var body: String
    public var deviceId: UUID?
    public var via: String
    public var createdAt: Date
    public var updatedAt: Date
    /// When the other side read it: the person (a message from home), a display (a reply).
    public var readAt: Date?
    /// A message from home: when Apple took its notification, or why it didn't go.
    public var notifiedAt: Date?
    public var notifyError: String?

    enum CodingKeys: String, CodingKey {
        case id, body, via
        case sender = "sender_kind"
        case senderName = "sender_name"
        case deviceId = "device_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case readAt = "read_at"
        case notifiedAt = "notified_at"
        case notifyError = "notify_error"
    }

    public init(id: UUID = UUID(), sender: Sender, senderName: String, body: String, deviceId: UUID? = nil,
                via: String? = nil, createdAt: Date, updatedAt: Date? = nil, readAt: Date? = nil,
                notifiedAt: Date? = nil, notifyError: String? = nil) {
        self.id = id
        self.sender = sender
        self.senderName = senderName
        self.body = body
        self.deviceId = deviceId
        self.via = via ?? (sender == .display ? "display" : "app")
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.readAt = readAt
        self.notifiedAt = notifiedAt
        self.notifyError = notifyError
    }

    public var fromHome: Bool { sender == .display }

    /// The columns every screen reads.
    public static let columns = "id,sender_kind,sender_name,body,device_id,via,created_at,updated_at,read_at,notified_at,notify_error"
    /// What a message may hold, as send_message checks it.
    public static let maxLength = 500
}

/// Who writes: the names listed for the displays' "Who's writing?" buttons,
/// and what the household calls the signed-in person (nil until they say).
public struct MessageNames: Equatable, Sendable {
    public var household: [String]
    public var mine: String?

    public init(household: [String] = [], mine: String? = nil) {
        self.household = household
        self.mine = mine
    }

    /// What the person's replies say, as send_message signs them.
    public var signed: String { mine ?? "Parent" }
}

/// Away mode (platform_settings.away_*, migration 20261104000010): the
/// person is out of the house, so the displays wake to Messages. Away from
/// `since` until `until` (nil: until it's turned off), decided on each screen
/// against the clock, so it ends on time without a write.
public struct AwayStatus: Codable, Equatable, Sendable {
    public var since: Date?
    public var until: Date?
    public var note: String?
    /// What the household calls the person who set it.
    public var name: String?

    enum CodingKeys: String, CodingKey {
        case since = "away_since"
        case until = "away_until"
        case note = "away_note"
        case name = "away_name"
    }

    public init(since: Date? = nil, until: Date? = nil, note: String? = nil, name: String? = nil) {
        self.since = since
        self.until = until
        self.note = note
        self.name = name
    }

    public func isAway(now: Date = .now) -> Bool {
        since != nil && (until.map { $0 > now } ?? true)
    }

    /// For the person: "Away until 6:00 PM", "Away until Thursday 9:00 AM", "Away".
    public func label(now: Date = .now, calendar: Calendar = .current) -> String {
        guard isAway(now: now) else { return "Home" }
        guard let until else { return "Away" }
        let time = until.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(until, inSameDayAs: now) { return "Away until \(time)" }
        return "Away until \(until.formatted(.dateTime.weekday(.wide))) \(time)"
    }
}

/// A day of the thread, for its heading: "Today", "Yesterday", the weekday
/// within a week, else the date.
public struct MessageDay: Identifiable, Equatable, Sendable {
    public var day: Date
    public var title: String
    public var messages: [Message]
    public var id: Date { day }
}

public enum MessageThread {
    /// The thread by day, oldest first, as it reads top to bottom.
    public static func days(_ messages: [Message], now: Date = .now, calendar: Calendar = .current) -> [MessageDay] {
        var out: [MessageDay] = []
        for m in messages.sorted(by: order) {
            let day = calendar.startOfDay(for: m.createdAt)
            if out.last?.day == day {
                out[out.count - 1].messages.append(m)
            } else {
                out.append(MessageDay(day: day, title: title(for: day, now: now, calendar: calendar), messages: [m]))
            }
        }
        return out
    }

    static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let today = calendar.startOfDay(for: now)
        if let days = calendar.dateComponents([.day], from: day, to: today).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return sameYear ? day.formatted(.dateTime.month(.abbreviated).day()) : day.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Whether a message starts a run: the first, a different writer from the
    /// one before, or ten minutes or more after it. A run shows its writer's
    /// name once.
    public static func startsRun(_ message: Message, after previous: Message?) -> Bool {
        guard let previous else { return true }
        return previous.sender != message.sender || previous.senderName != message.senderName
            || message.createdAt.timeIntervalSince(previous.createdAt) >= 600
    }

    /// The thread's order: when written, then id, so two at once never swap.
    public static func order(_ a: Message, _ b: Message) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
    }

    /// Under the person's newest reply: whether home has seen it.
    public static func replyStatus(_ message: Message) -> String {
        message.readAt == nil ? "Sent" : "Seen at home"
    }
}

/// Where the thread comes from: PostgREST and the RPCs with the person's JWT,
/// or the demo.
public protocol MessageService: Sendable {
    /// The newest `limit` messages, any order.
    func loadMessages(limit: Int) async throws -> [Message]
    /// Every message sent, read or notified after `since`, at most `limit`.
    func loadChanges(since: Date, limit: Int) async throws -> [Message]
    /// The person's reply (`send_message`, via the app), as stored.
    func send(_ body: String) async throws -> Message
    /// Marks home's messages read up to `upTo` (`read_messages`; nil: all).
    func markRead(upTo: UUID?) async throws
    func names() async throws -> MessageNames
    /// Away mode as the displays see it.
    func away() async throws -> AwayStatus
    /// Away mode on (until a time, or until it's turned off) or off (`set_away`).
    func setAway(_ away: Bool, until: Date?, note: String?) async throws -> AwayStatus
    /// What the household calls the person (`set_message_name`); nil clears it.
    func setMyName(_ name: String?) async throws -> String?
    /// Who writes from the displays (`admin_set_message_names`), as kept.
    func setHouseholdNames(_ names: [String]) async throws -> [String]
    /// This install's notification token (`register_push_token`).
    func registerPushToken(_ token: String, environment: String, bundleId: String, platform: String) async throws
    func unregisterPushToken(_ token: String) async throws
    /// A test notification on each of the person's phones (`notify`, `test`): what happened, in a sentence.
    func sendTestNotification() async throws -> String
}

public struct SupabaseMessageService: MessageService {
    let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func loadMessages(limit: Int) async throws -> [Message] {
        try decode(await client.from("messages").select(Message.columns)
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(limit)
            .execute().data)
    }

    public func loadChanges(since: Date, limit: Int) async throws -> [Message] {
        try decode(await client.from("messages").select(Message.columns)
            .gt("updated_at", value: Self.iso.string(from: since))
            .order("updated_at")
            .limit(limit)
            .execute().data)
    }

    public func send(_ body: String) async throws -> Message {
        try decode(await client.rpc("send_message", params: ["body": body, "via": "app"]).execute().data)
    }

    public func markRead(upTo: UUID?) async throws {
        struct Params: Encodable { var up_to: String? }
        try await client.rpc("read_messages", params: Params(up_to: upTo?.lowercased)).execute()
    }

    public func names() async throws -> MessageNames {
        struct Settings: Decodable { var message_names: [String]? }
        struct Profile: Decodable { var message_name: String? }
        let settings: [Settings] = try decode(await client.from("platform_settings").select("message_names").limit(1).execute().data)
        var mine: String?
        if let user = client.auth.currentUser?.id {
            let profiles: [Profile] = try decode(await client.from("profiles").select("message_name")
                .eq("id", value: user.lowercased).limit(1).execute().data)
            mine = profiles.first?.message_name
        }
        return MessageNames(household: settings.first?.message_names ?? [], mine: mine)
    }

    public func setMyName(_ name: String?) async throws -> String? {
        struct Params: Encodable { var name: String? }
        let data = try await client.rpc("set_message_name", params: Params(name: name)).execute().data
        return try? JSONDecoder.mcfly.decode(String?.self, from: data)
    }

    public func setHouseholdNames(_ names: [String]) async throws -> [String] {
        try decode(await client.rpc("admin_set_message_names", params: ["names": names]).execute().data)
    }

    public func away() async throws -> AwayStatus {
        let rows: [AwayStatus] = try decode(await client.from("platform_settings")
            .select("away_since,away_until,away_note,away_name").limit(1).execute().data)
        return rows.first ?? AwayStatus()
    }

    public func setAway(_ away: Bool, until: Date?, note: String?) async throws -> AwayStatus {
        struct Params: Encodable {
            var away: Bool
            var until: String?
            var note: String?
        }
        struct Answer: Decodable {
            var since: Date?
            var until: Date?
            var note: String?
            var name: String?
        }
        let params = Params(away: away, until: until.map { Self.iso.string(from: $0) }, note: note)
        let answer: Answer = try decode(await client.rpc("set_away", params: params).execute().data)
        return AwayStatus(since: answer.since, until: answer.until, note: answer.note, name: answer.name)
    }

    public func registerPushToken(_ token: String, environment: String, bundleId: String, platform: String) async throws {
        try await client.rpc("register_push_token", params: ["token": token, "environment": environment,
                                                             "bundle_id": bundleId, "platform": platform]).execute()
    }

    public func unregisterPushToken(_ token: String) async throws {
        try await client.rpc("unregister_push_token", params: ["token": token]).execute()
    }

    public func sendTestNotification() async throws -> String {
        struct Body: Encodable { var action = "test" }
        struct Answer: Decodable {
            struct Result: Decodable { var outcome: String; var message: String? }
            var ok: Bool
            var results: [Result]
        }
        let answer: Answer = try await client.functions.invoke("notify", options: FunctionInvokeOptions(body: Body()))
        let sent = answer.results.filter { $0.outcome == "sent" }.count
        if sent == answer.results.count {
            return sent == 1 ? "Sent. It should be on this phone now." : "Sent to \(sent) phones."
        }
        let why = answer.results.compactMap(\.message).first ?? "Apple didn't take it"
        return sent > 0 ? "Sent to \(sent) of \(answer.results.count) phones. \(why.sentenceCased)." : "\(why.sentenceCased)."
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder.mcfly.decode(T.self, from: data)
    }
}

/// A reply on its way from here: shown at once, under the thread, until the
/// server has it, or with why it didn't go.
public struct PendingMessage: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var body: String
    public var createdAt: Date
    public var failure: String?
}

/// The household thread as the app shows it: read in full once, then only
/// what changed (a new message, one read or notified), every few seconds
/// while the thread is open. The person's replies go through `send`.
@MainActor
@Observable
public final class MessagesStore {
    /// Oldest first, at most `limit`.
    public private(set) var messages: [Message] = []
    public private(set) var pending: [PendingMessage] = []
    public private(set) var names = MessageNames()
    public private(set) var loadedAt: Date?
    public var errorMessage: String?

    /// How many are kept, and how far back each poll looks again, so a
    /// message written in a transaction that committed late isn't missed.
    public static let limit = 200
    public static let overlap: TimeInterval = 30

    private let service: MessageService
    @ObservationIgnored private var cursor: Date?
    @ObservationIgnored private var refreshing = false

    public init(service: MessageService) {
        self.service = service
    }

    public var hasLoaded: Bool { loadedAt != nil }
    /// From home and not read yet.
    public var unread: [Message] { messages.filter { $0.fromHome && $0.readAt == nil } }
    public var unreadCount: Int { unread.count }
    /// The newest message from home, for Home's card.
    public var latestFromHome: Message? { messages.last(where: \.fromHome) }

    /// Reads the thread (the first time) or what changed since. Returns the
    /// messages from home seen for the first time, oldest first: none on the
    /// first read, since nothing there is news.
    @discardableResult
    public func refresh() async -> [Message] {
        if refreshing { return [] }
        refreshing = true
        defer { refreshing = false }
        do {
            if let cursor {
                let known = Set(messages.map(\.id))
                let changes = try await service.loadChanges(since: cursor.addingTimeInterval(-Self.overlap), limit: Self.limit)
                merge(changes)
                errorMessage = nil
                loadedAt = .now
                return changes.filter { $0.fromHome && !known.contains($0.id) }.sorted(by: MessageThread.order)
            }
            let rows = try await service.loadMessages(limit: Self.limit)
            messages = []
            merge(rows)
            // An empty thread: from here on, every message is a change.
            if cursor == nil { cursor = Date(timeIntervalSince1970: 0) }
            errorMessage = nil
            loadedAt = .now
        } catch {
            if !(error is CancellationError) { errorMessage = McFlyError.describe(error) }
        }
        return []
    }

    /// Rows in: a known one is replaced when the server's copy is newer, the
    /// thread kept in order and to `limit`, newest kept.
    public func merge(_ rows: [Message]) {
        guard !rows.isEmpty else { return }
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for row in rows {
            if let known = byId[row.id] {
                if known.updatedAt > row.updatedAt { continue }
                // Read here and not yet on the server: the same copy again keeps it read.
                if known.updatedAt == row.updatedAt, known.readAt != nil, row.readAt == nil { continue }
            }
            byId[row.id] = row
        }
        var all = byId.values.sorted(by: MessageThread.order)
        if all.count > Self.limit { all.removeFirst(all.count - Self.limit) }
        messages = all
        let newest = rows.map(\.updatedAt).max()
        if let newest, cursor.map({ newest > $0 }) ?? true { cursor = newest }
    }

    /// Sends a reply: it shows at once and joins the thread once the server
    /// has it. Blank does nothing. Returns whether it went.
    @discardableResult
    public func send(_ text: String) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        let item = PendingMessage(body: body, createdAt: .now)
        pending.append(item)
        return await deliver(item)
    }

    /// A reply that didn't go, tried again.
    public func retry(_ id: UUID) async {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].failure = nil
        _ = await deliver(pending[index])
    }

    public func discard(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    private func deliver(_ item: PendingMessage) async -> Bool {
        do {
            let sent = try await service.send(item.body)
            pending.removeAll { $0.id == item.id }
            merge([sent])
            return true
        } catch {
            if let index = pending.firstIndex(where: { $0.id == item.id }) {
                pending[index].failure = McFlyError.describe(error)
            }
            return false
        }
    }

    /// The thread was seen: home's messages are marked read, here at once.
    public func markRead() async {
        guard let newest = unread.last else { return }
        let now = Date.now
        messages = messages.map { m in
            var m = m
            if m.fromHome, m.readAt == nil, !MessageThread.order(newest, m) { m.readAt = now }
            return m
        }
        do {
            try await service.markRead(upTo: newest.id)
        } catch {
            errorMessage = McFlyError.describe(error)
        }
    }

    /// Away mode, as last read or set here.
    public private(set) var away = AwayStatus()

    public func loadNames() async {
        if let names = try? await service.names() { self.names = names }
        if let away = try? await service.away() { self.away = away }
    }

    public func setMyName(_ name: String?) async throws {
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        names.mine = try await service.setMyName(cleaned?.isEmpty == false ? cleaned : nil)
    }

    public func setAway(_ on: Bool, until: Date? = nil, note: String? = nil) async throws {
        let cleaned = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        away = try await service.setAway(on, until: until, note: cleaned?.isEmpty == false ? cleaned : nil)
    }

    public func setHouseholdNames(_ list: [String]) async throws {
        names.household = try await service.setHouseholdNames(list)
    }

    public func registerPushToken(_ token: String, environment: String, bundleId: String, platform: String) async throws {
        try await service.registerPushToken(token, environment: environment, bundleId: bundleId, platform: platform)
    }

    public func unregisterPushToken(_ token: String) async {
        try? await service.unregisterPushToken(token)
    }

    public func sendTestNotification() async throws -> String {
        try await service.sendTestNotification()
    }

    /// Signed out: nothing of the thread stays.
    public func reset() {
        messages = []
        pending = []
        names = MessageNames()
        away = AwayStatus()
        loadedAt = nil
        cursor = nil
        errorMessage = nil
    }
}

/// The demo's thread: a few messages from home today, and a reply from home
/// a few seconds after each of the person's, so the thread moves.
public actor DemoMessageService: MessageService {
    private var messages: [Message]
    private var names: MessageNames
    private var echoes: [Message] = []

    public init(now: Date = .now) {
        let at = { (minutes: Double) in now.addingTimeInterval(-minutes * 60) }
        messages = [
            Message(sender: .display, senderName: "Mia", body: "I'm home from school!", createdAt: at(185), readAt: at(180), notifiedAt: at(185)),
            Message(sender: .person, senderName: "Parent", body: "Yay! Snack is in the fridge. Homework first 🙂", createdAt: at(178), readAt: at(176)),
            Message(sender: .display, senderName: "Leo", body: "Can Sam come over to play?", createdAt: at(24), notifiedAt: at(24)),
            Message(sender: .display, senderName: "Mia", body: "When are you coming home?", createdAt: at(6), notifiedAt: at(6)),
        ]
        names = MessageNames(household: ["Mia", "Leo"], mine: nil)
    }

    public func loadMessages(limit: Int) async throws -> [Message] { Array(messages.suffix(limit)) }

    public func loadChanges(since: Date, limit: Int) async throws -> [Message] {
        let due = echoes.filter { $0.createdAt <= .now }
        echoes.removeAll { $0.createdAt <= .now }
        messages += due
        return Array(messages.filter { $0.updatedAt > since }.suffix(limit))
    }

    public func send(_ body: String) async throws -> Message {
        try await Task.sleep(for: .milliseconds(350))
        let m = Message(sender: .person, senderName: names.signed, body: body, createdAt: .now)
        messages.append(m)
        let reply = ["Okay! ❤️", "Got it", "👍", "Love you too!"].randomElement() ?? "Okay!"
        let at = Date.now.addingTimeInterval(4)
        echoes.append(Message(sender: .display, senderName: names.household.first ?? "Kitchen", body: reply, createdAt: at, notifiedAt: at))
        return m
    }

    public func markRead(upTo: UUID?) async throws {
        let until = upTo.flatMap { id in messages.first { $0.id == id }?.createdAt } ?? .distantFuture
        let now = Date.now
        messages = messages.map { m in
            var m = m
            if m.fromHome, m.readAt == nil, m.createdAt <= until {
                m.readAt = now
                m.updatedAt = now
            }
            return m
        }
    }

    public func names() async throws -> MessageNames { names }

    private var awayNow = AwayStatus()
    public func away() async throws -> AwayStatus { awayNow }
    public func setAway(_ away: Bool, until: Date?, note: String?) async throws -> AwayStatus {
        awayNow = away ? AwayStatus(since: awayNow.since ?? .now, until: until, note: note, name: names.signed) : AwayStatus()
        return awayNow
    }

    public func setMyName(_ name: String?) async throws -> String? {
        names.mine = name
        return name
    }

    public func setHouseholdNames(_ list: [String]) async throws -> [String] {
        names.household = list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return names.household
    }

    public func registerPushToken(_ token: String, environment: String, bundleId: String, platform: String) async throws {}
    public func unregisterPushToken(_ token: String) async throws {}
    public func sendTestNotification() async throws -> String { "The demo sends no notifications." }
}
