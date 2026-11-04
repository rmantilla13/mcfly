import XCTest
@testable import McFlyKit

/// The thread the server answers with, as the tests set it.
private actor FakeMessages: MessageService {
    var rows: [Message] = []
    var failSend: String?
    var readUpTo: [UUID?] = []
    var sinceAsked: [Date] = []

    func set(_ rows: [Message]) { self.rows = rows }
    func add(_ row: Message) { rows.append(row) }
    func failSends(_ why: String?) { failSend = why }

    func loadMessages(limit: Int) async throws -> [Message] { Array(rows.suffix(limit).reversed()) }
    func loadChanges(since: Date, limit: Int) async throws -> [Message] {
        sinceAsked.append(since)
        return rows.filter { $0.updatedAt > since }.sorted { $0.updatedAt < $1.updatedAt }
    }
    func send(_ body: String) async throws -> Message {
        if let failSend { throw McFlyError.message(failSend) }
        let m = Message(sender: .person, senderName: "Dad", body: body, createdAt: .now)
        rows.append(m)
        return m
    }
    func markRead(upTo: UUID?) async throws { readUpTo.append(upTo) }
    func names() async throws -> MessageNames { MessageNames(household: ["Mia"], mine: "Dad") }
    func away() async throws -> AwayStatus { AwayStatus() }
    var uploads = 0
    var failNextVoiceSend = false
    func failNextVoice() { failNextVoiceSend = true }
    func uploadVoiceNote(_ wav: Data) async throws -> String {
        uploads += 1
        return "ad000000-0000-0000-0000-000000000001/\(UUID().lowercased).wav"
    }
    func sendVoiceNote(path: String, ms: Int) async throws -> Message {
        if failNextVoiceSend {
            failNextVoiceSend = false
            throw McFlyError.message("Try again.")
        }
        let m = Message(sender: .person, senderName: "Dad", body: Message.voiceNoteLabel(ms: ms), createdAt: .now, audioPath: path, audioMs: ms)
        rows.append(m)
        return m
    }
    func voiceNote(_ path: String) async throws -> Data { Data("downloaded".utf8) }
    func setAway(_ away: Bool, until: Date?, note: String?) async throws -> AwayStatus {
        away ? AwayStatus(since: .now, until: until, note: note, name: "Dad") : AwayStatus()
    }
    func setMyName(_ name: String?) async throws -> String? { name }
    func setHouseholdNames(_ names: [String]) async throws -> [String] { names }
    func registerPushToken(_ token: String, environment: String, bundleId: String, platform: String) async throws {}
    func unregisterPushToken(_ token: String) async throws {}
    func sendTestNotification() async throws -> String { "ok" }
}

@MainActor
final class MessagesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func home(_ body: String, _ minutes: Double, name: String = "Mia", read: Bool = false) -> Message {
        let at = t0.addingTimeInterval(minutes * 60)
        return Message(sender: .display, senderName: name, body: body, createdAt: at, readAt: read ? at : nil)
    }

    func testDecodesARow() throws {
        let json = """
        {"id": "6d000000-0000-0000-0000-000000000001", "sender_kind": "display", "sender_name": "Mia",
         "body": "I'm home!", "device_id": "00000000-0000-0000-0000-00000000d001", "via": "display",
         "created_at": "2026-11-03T20:11:07.123456+00:00", "updated_at": "2026-11-03T20:11:08+00:00",
         "read_at": null, "notified_at": "2026-11-03T20:11:08.5+00:00", "notify_error": null, "author": "x"}
        """
        let m = try JSONDecoder.mcfly.decode(Message.self, from: Data(json.utf8))
        XCTAssertTrue(m.fromHome)
        XCTAssertEqual(m.senderName, "Mia")
        XCTAssertNotNil(m.notifiedAt)
        XCTAssertNil(m.readAt)
        XCTAssertGreaterThan(m.updatedAt, m.createdAt)
    }

    func testDaysAndRuns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = t0
        let messages = [
            home("today later", 0),
            home("yesterday", -24 * 60),
            home("today", -5),
            home("last week", -10 * 24 * 60),
        ]
        let days = MessageThread.days(messages, now: now, calendar: calendar)
        // 2:00 am in Chicago: five minutes before is still today.
        XCTAssertEqual(days.count, 3)
        XCTAssertNotEqual(days.first?.title, "Today", "ten days back: its date")
        XCTAssertEqual(days.last?.title, "Today")
        XCTAssertEqual(days.last?.messages.map(\.body), ["today", "today later"], "oldest first")
        XCTAssertEqual(days[days.count - 2].title, "Yesterday")

        let a = home("a", 0)
        XCTAssertTrue(MessageThread.startsRun(a, after: nil))
        XCTAssertFalse(MessageThread.startsRun(home("b", 2), after: a), "same writer, soon after")
        XCTAssertTrue(MessageThread.startsRun(home("b", 2, name: "Leo"), after: a), "someone else")
        XCTAssertTrue(MessageThread.startsRun(home("b", 11), after: a), "ten minutes on")
        let reply = Message(sender: .person, senderName: "Mia", body: "x", createdAt: t0.addingTimeInterval(60))
        XCTAssertTrue(MessageThread.startsRun(reply, after: a), "the other side, whatever the name")
    }

    func testMergeKeepsTheNewestCopyInOrder() {
        let store = MessagesStore(service: FakeMessages())
        var first = home("hi", 0)
        let second = home("there", 1)
        store.merge([second, first])
        XCTAssertEqual(store.messages.map(\.body), ["hi", "there"])
        var older = first
        older.updatedAt = first.updatedAt.addingTimeInterval(-60)
        older.body = "stale"
        store.merge([older])
        XCTAssertEqual(store.messages.first?.body, "hi", "an older copy doesn't win")
        first.readAt = t0.addingTimeInterval(120)
        first.updatedAt = t0.addingTimeInterval(120)
        store.merge([first])
        XCTAssertNotNil(store.messages.first?.readAt, "a newer one does")
        XCTAssertEqual(store.messages.count, 2)

        store.merge((0 ..< MessagesStore.limit + 5).map { home("m\($0)", Double(10 + $0)) })
        XCTAssertEqual(store.messages.count, MessagesStore.limit)
        XCTAssertEqual(store.messages.last?.body, "m\(MessagesStore.limit + 4)", "the newest kept")
    }

    func testRefreshReadsOnceThenOnlyChangesWithAnOverlap() async {
        let service = FakeMessages()
        await service.set([home("old", 0, read: true), home("unread", 1)])
        let store = MessagesStore(service: service)
        let firstNews = await store.refresh()
        XCTAssertEqual(firstNews, [], "nothing on the first read is news")
        XCTAssertEqual(store.unreadCount, 1)

        let fresh = home("new", 5)
        await service.add(fresh)
        let news = await store.refresh()
        XCTAssertEqual(news.map(\.body), ["new"])
        XCTAssertEqual(store.messages.map(\.body), ["old", "unread", "new"])
        let asked = await service.sinceAsked
        XCTAssertEqual(asked.first, t0.addingTimeInterval(60 - MessagesStore.overlap), "the newest seen, less the overlap")

        let again = await store.refresh()
        XCTAssertEqual(again, [], "seen already: not news again")
    }

    func testAnEmptyThreadStillPollsForTheFirstMessage() async {
        let service = FakeMessages()
        let store = MessagesStore(service: service)
        await store.refresh()
        XCTAssertTrue(store.hasLoaded)
        await service.add(home("first ever", 0))
        let news = await store.refresh()
        XCTAssertEqual(news.map(\.body), ["first ever"])
    }

    func testSendingShowsAtOnceAndKeepsAFailure() async {
        let service = FakeMessages()
        let store = MessagesStore(service: service)
        let went = await store.send("  On my way  ")
        XCTAssertTrue(went)
        XCTAssertEqual(store.messages.last?.body, "On my way")
        XCTAssertEqual(store.pending, [])
        let blank = await store.send("   ")
        XCTAssertFalse(blank)

        await service.failSends("McFly couldn't be reached.")
        let failed = await store.send("Dinner at 6")
        XCTAssertFalse(failed)
        XCTAssertEqual(store.pending.first?.failure, "McFly couldn't be reached.")
        await service.failSends(nil)
        await store.retry(store.pending[0].id)
        XCTAssertEqual(store.pending, [])
        XCTAssertEqual(store.messages.last?.body, "Dinner at 6")
    }

    func testMarkReadMarksHereAtOnceAndTellsTheServer() async {
        let service = FakeMessages()
        await service.set([home("a", 0), home("b", 1)])
        let store = MessagesStore(service: service)
        await store.refresh()
        XCTAssertEqual(store.unreadCount, 2)
        await store.markRead()
        XCTAssertEqual(store.unreadCount, 0)
        let asked = await service.readUpTo
        XCTAssertEqual(asked, [store.messages.last?.id])
        await store.markRead()
        let again = await service.readUpTo
        XCTAssertEqual(again.count, 1, "nothing unread: nothing sent")
        // The server's copy, from before it heard, comes back in the overlap: still read.
        await store.refresh()
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testAwayModeEndsOnItsOwn() async throws {
        let json = """
        [{"away_since": "2026-11-04T14:00:00Z", "away_until": null, "away_note": "At work", "away_name": "Dad"}]
        """
        let decoded = try JSONDecoder.mcfly.decode([AwayStatus].self, from: Data(json.utf8))
        XCTAssertTrue(decoded[0].isAway(now: t0))
        XCTAssertEqual(decoded[0].label(now: t0), "Away")
        var away = AwayStatus(since: t0, until: t0.addingTimeInterval(3600), name: "Dad")
        XCTAssertTrue(away.isAway(now: t0.addingTimeInterval(3599)))
        XCTAssertFalse(away.isAway(now: t0.addingTimeInterval(3600)), "ends at its time, with no write")
        XCTAssertEqual(away.label(now: t0.addingTimeInterval(4000)), "Home")
        away.since = nil
        XCTAssertFalse(away.isAway(now: t0))
        XCTAssertFalse(AwayStatus().isAway())

        let store = MessagesStore(service: FakeMessages())
        try await store.setAway(true, until: nil, note: "  At work ")
        XCTAssertTrue(store.away.isAway())
        XCTAssertEqual(store.away.note, "At work")
        try await store.setAway(false)
        XCTAssertFalse(store.away.isAway())
    }

    func testVoiceNotesUploadOnceThenSend() async throws {
        XCTAssertEqual(Message.voiceNoteLabel(ms: 12345), "🎤 Voice note · 0:12", "as send_message writes it")
        XCTAssertEqual(Message.voiceNoteLabel(ms: 65000), "🎤 Voice note · 1:05")
        let note = Message(sender: .display, senderName: "Mia", body: Message.voiceNoteLabel(ms: 4000), createdAt: t0,
                           audioPath: "x/y.wav", audioMs: 4000)
        XCTAssertTrue(note.hasAudio)
        XCTAssertEqual(note.caption, "", "the server's own words aren't a caption")
        XCTAssertEqual(note.audioLabel, "0:04")
        var captioned = note
        captioned.body = "Listen!"
        XCTAssertEqual(captioned.caption, "Listen!")

        let service = FakeMessages()
        let store = MessagesStore(service: service)
        let wav = VoiceNoteAudio.wav(VoiceNoteAudio.tone(seconds: 3))
        XCTAssertEqual(VoiceNoteAudio.milliseconds(of: wav), 3000)
        await service.failNextVoice()
        let first = await store.sendVoiceNote(wav, ms: 3000)
        XCTAssertFalse(first)
        XCTAssertEqual(store.pending.first?.failure, "Try again.")
        XCTAssertNotNil(store.pending.first?.audioPath, "uploaded before the send failed")
        await store.retry(store.pending[0].id)
        XCTAssertEqual(store.pending, [])
        let uploads = await service.uploads
        XCTAssertEqual(uploads, 1, "a retry doesn't upload again")
        let sent = try XCTUnwrap(store.messages.last)
        XCTAssertEqual(sent.audioMs, 3000)
        let played = try await store.audio(for: sent)
        XCTAssertEqual(played, wav, "our own note plays from here")
        let tooShort = await store.sendVoiceNote(wav, ms: 100)
        XCTAssertFalse(tooShort)
    }

    func testTheDemoAnswersBack() async throws {
        let demo = DemoMessageService()
        let store = MessagesStore(service: demo)
        await store.refresh()
        XCTAssertGreaterThan(store.unreadCount, 0)
        XCTAssertEqual(store.latestFromHome?.senderName, "Mia")
        await store.send("Be home at 6")
        XCTAssertEqual(store.messages.last?.body, "Be home at 6")
        XCTAssertEqual(store.messages.last?.senderName, "Parent")
        XCTAssertEqual(MessageNames(mine: "Dad").signed, "Dad")
        XCTAssertEqual(MessageThread.replyStatus(store.messages.last!), "Sent")
    }
}
