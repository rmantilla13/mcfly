import McFlyKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Messages: the household thread. What the people at home wrote on a
/// display sits on the left under their names; the person's replies sit on
/// the right, signed with what the household calls them, marked "Seen at
/// home" once a display has shown them. Read in full once, then polled every
/// few seconds while open; opening it marks home's messages read, which
/// clears the badge. A reply shows at once and stays, with Retry, if it
/// didn't go. With the box empty the mic records a voice note (up to 30 s;
/// ↑ sends it, ✕ drops it); a note plays with its ▶.
struct MessagesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showAway = false
    @State private var active = true
    @State private var recorder = VoiceNoteRecorder()
    @State private var player = VoiceNotePlayer()
    @FocusState private var composing: Bool

    private var store: MessagesStore { app.messages }

    var body: some View {
        let days = MessageThread.days(store.messages)
        let lastReply = store.messages.last { !$0.fromHome }?.id
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.away.isAway() {
                        AwayBanner(away: store.away) { showAway = true }
                            .padding(.bottom, 12)
                    }
                    if store.names.mine == nil, store.hasLoaded, !app.isDemo {
                        NamePrompt().padding(.bottom, 16)
                    }
                    if let message = store.errorMessage {
                        ErrorBanner(message: message) { Task { await store.refresh() } }
                            .padding(.bottom, 12)
                    }
                    if store.messages.isEmpty, store.pending.isEmpty {
                        EmptyThread(loaded: store.hasLoaded)
                    }
                    ForEach(days) { day in
                        Text(day.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 18)
                            .padding(.bottom, 8)
                        ForEach(Array(day.messages.enumerated()), id: \.element.id) { index, message in
                            let starts = MessageThread.startsRun(message, after: index > 0 ? day.messages[index - 1] : nil)
                            Bubble(message: message, startsRun: starts, status: message.id == lastReply ? MessageThread.replyStatus(message) : nil,
                                   playing: player.playingId == message.id) { play(message) }
                                .padding(.top, starts ? 10 : 3)
                                .id(message.id)
                        }
                    }
                    ForEach(store.pending) { item in
                        PendingBubble(item: item, signed: store.names.signed) {
                            Task { await store.retry(item.id) }
                        } onDiscard: {
                            store.discard(item.id)
                        }
                        .padding(.top, 3)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, Theme.page)
                .padding(.bottom, 12)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.last?.id) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
            .onChange(of: store.pending.count) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) {
                Composer(draft: $draft, composing: $composing, recorder: recorder, onSend: send,
                         onRecord: record, onCancelRecording: { recorder.cancel() })
            }
        }
        .screenBackground()
        .navigationTitle("Messages")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAway = true } label: {
                    Label(store.away.isAway() ? "Away" : "Away mode",
                          systemImage: store.away.isAway() ? "figure.walk.departure" : "house")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Label("Who writes", systemImage: "person.2") }
            }
        }
        .sheet(isPresented: $showAway) {
            NavigationStack { AwaySheet() }
                .environment(app)
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 520)
                #endif
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { MessageSettingsView() }
                .environment(app)
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 520)
                #endif
        }
        .onAppear { PushCenter.shared.showingMessages = true }
        .onDisappear { PushCenter.shared.showingMessages = false }
        .onChange(of: scenePhase) { _, phase in active = phase == .active }
        .task {
            // Every few seconds while it's open: what home wrote, and what it saw.
            await store.loadNames()
            while !Task.isCancelled {
                await store.refresh()
                if active {
                    await store.markRead()
                    app.updateBadge()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private static let bottom = "bottom"

    private func send() {
        if recorder.isRecording {
            sendRecording()
            return
        }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        Task { await store.send(text) }
    }

    private func record() {
        player.stop()
        recorder.onLimit = { sendRecording() }
        Task {
            do {
                try await recorder.start()
            } catch {
                app.report(error)
            }
        }
    }

    private func sendRecording() {
        guard let note = recorder.finish() else { return }
        Task { await store.sendVoiceNote(note.wav, ms: note.ms) }
    }

    private func play(_ message: Message) {
        if player.playingId == message.id {
            player.stop()
            return
        }
        Task {
            do {
                try player.play(try await store.audio(for: message), id: message.id)
            } catch {
                app.report(error)
            }
        }
    }
}

/// One message: home's on the left in the surface colour under the writer's
/// name, the person's on the right in the accent. A run shows the name and
/// time once.
private struct Bubble: View {
    let message: Message
    let startsRun: Bool
    var status: String?
    var playing = false
    var onPlay: () -> Void = {}

    var body: some View {
        let mine = !message.fromHome
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            if startsRun {
                Text("\(message.senderName) · \(Format.time(message.createdAt))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
            }
            VStack(alignment: .leading, spacing: 6) {
                if message.hasAudio {
                    VoiceNoteRow(label: message.audioLabel, playing: playing, mine: mine, onPlay: onPlay)
                }
                if !message.caption.isEmpty {
                    Text(message.caption)
                        .font(.body)
                        .foregroundStyle(mine ? Theme.accentInk : Theme.text)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(mine ? Theme.accent : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: 520, alignment: mine ? .trailing : .leading)
            if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(mine ? .leading : .trailing, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.senderName), \(Format.time(message.createdAt)): \(message.body)")
    }
}

/// A reply on its way, or one that didn't go: dimmed, then Retry.
private struct PendingBubble: View {
    let item: PendingMessage
    let signed: String
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(item.audioMs.map { Message.voiceNoteLabel(ms: $0) } ?? item.body)
                .font(.body)
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.accent.opacity(item.failure == nil ? 0.55 : 0.35),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if let failure = item.failure {
                HStack(spacing: 8) {
                    Text("Not sent: \(failure)")
                        .font(.caption2)
                        .foregroundStyle(Theme.down)
                        .multilineTextAlignment(.trailing)
                    Button("Retry", action: onRetry).font(.caption.weight(.semibold))
                    Button("Delete", role: .destructive, action: onDiscard).font(.caption)
                }
                .padding(.horizontal, 6)
            } else {
                Text("Sending…").font(.caption2).foregroundStyle(Theme.muted).padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
    }
}

private struct Composer: View {
    @Binding var draft: String
    var composing: FocusState<Bool>.Binding
    let recorder: VoiceNoteRecorder
    let onSend: () -> Void
    let onRecord: () -> Void
    let onCancelRecording: () -> Void

    var body: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let over = draft.count > Message.maxLength
        HStack(alignment: .bottom, spacing: 10) {
            if recorder.isRecording {
                // Recording: ✕ drops it, the time and the level, ↑ sends it.
                HStack(spacing: 12) {
                    Button(action: onCancelRecording) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 32).background(Theme.sunken, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Drop the voice note")
                    Circle().fill(Theme.down).frame(width: 10, height: 10)
                    Text(String(format: "0:%02d", Int(recorder.elapsed)))
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.text)
                    GeometryReader { geo in
                        Capsule().fill(Theme.sunken)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.accent).frame(width: geo.size.width * recorder.level)
                                    .animation(.linear(duration: 0.1), value: recorder.level)
                            }
                    }
                    .frame(height: 8)
                    Text("0:30").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                TextField("Message home", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .focused(composing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onSubmit(onSend)
                    #if os(macOS)
                    .textFieldStyle(.plain)
                    #endif
            }
            if empty, !recorder.isRecording {
                // Nothing typed: the mic, for a voice note.
                Button(action: onRecord) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record a voice note")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 44, height: 44)
                        .background(over && !recorder.isRecording ? Theme.muted.opacity(0.4) : Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(over && !recorder.isRecording)
                .accessibilityLabel(recorder.isRecording ? "Send the voice note" : "Send")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .overlay(alignment: .topTrailing) {
            if draft.count > Message.maxLength - 100 {
                Text("\(Message.maxLength - draft.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(over ? Theme.down : Theme.muted)
                    .offset(x: -64, y: -16)
            }
        }
        .padding(.horizontal, Theme.page)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct EmptyThread: View {
    let loaded: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text(loaded ? "No messages yet" : "Loading…")
                .font(.headline)
                .foregroundStyle(Theme.text)
            if loaded {
                Text("What the family writes on the display shows up here, and on this phone as a notification. Write to them below: it shows on the display at once.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// Until the person says what the household calls them, their replies are
/// from "Parent": a card at the top of the thread asks.
private struct NamePrompt: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What do they call you at home?")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("Your replies show this name on the display. Until then they're from \u{201C}Parent\u{201D}.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("Your name on the display", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .buttonStyle(.pill())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
        }
        .card()
    }

    private func save() {
        let value = name
        saving = true
        Task {
            do {
                try await app.messages.setMyName(value)
            } catch {
                app.report(error)
            }
            saving = false
        }
    }
}

/// Who writes, and the notifications: what the household calls the person,
/// the names on the display's "Who's writing?" buttons, and a test
/// notification to check the phone gets them.
struct MessageSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var mine = ""
    @State private var household: [String] = []
    @State private var newName = ""
    @State private var saving = false
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                TextField("Your name on the display", text: $mine)
            } header: {
                Text("You")
            } footer: {
                Text("Your replies are signed with this on the display: Dad, Mom, or what they call you.")
            }
            Section {
                ForEach(household, id: \.self) { name in
                    Text(name)
                }
                .onDelete { household.remove(atOffsets: $0) }
                .onMove { household.move(fromOffsets: $0, toOffset: $1) }
                if household.count < 8 {
                    HStack {
                        TextField("Add a name", text: $newName)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Who writes from the display")
            } footer: {
                Text("A button each on the display's Messages screen, so you know who wrote. With none, messages carry the display's name.")
            }
            Section {
                Button(testing ? "Sending…" : "Send a test notification") { test() }
                    .disabled(testing || app.isDemo)
                if let testResult {
                    Text(testResult).font(.footnote).foregroundStyle(Theme.muted)
                }
                #if os(iOS)
                Button("Notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                #endif
            } header: {
                Text("Notifications")
            } footer: {
                #if os(iOS)
                Text("A message from home arrives as a notification; Reply on it answers without opening McFly.")
                #else
                Text("On the Mac, a message from home shows as a notification while McFly is open.")
                #endif
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Who writes")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(saving)
            }
        }
        .onAppear {
            mine = app.messages.names.mine ?? ""
            household = app.messages.names.household
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !household.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        household.append(name)
        newName = ""
    }

    private func save() {
        add()
        saving = true
        Task {
            do {
                let store = app.messages
                if (store.names.mine ?? "") != mine.trimmingCharacters(in: .whitespaces) { try await store.setMyName(mine) }
                if store.names.household != household { try await store.setHouseholdNames(household) }
                dismiss()
            } catch {
                app.report(error)
            }
            saving = false
        }
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            do {
                testResult = try await app.messages.sendTestNotification()
            } catch {
                testResult = McFlyError.describe(error)
            }
            testing = false
        }
    }
}

/// Away mode is on: what the display does about it, until when, and the
/// way to change it.
private struct AwayBanner: View {
    let away: AwayStatus
    let onChange: () -> Void

    var body: some View {
        Button(action: onChange) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.departure")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(away.label() + (away.note.map { " · \($0)" } ?? ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("The display opens to Messages for the kids.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Text("Change").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Away mode: on until a time or until it's turned off, with a note the
/// display shows ("At work"); and how to have it switch itself.
struct AwaySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum Back: Hashable { case off, hours(Int), at }

    @State private var back: Back = .off
    @State private var at = Date.now.addingTimeInterval(3 * 3600)
    @State private var note = ""
    @State private var saving = false

    var body: some View {
        let away = app.messages.away
        Form {
            Section {
                Text("While you're away, the display opens to Messages whenever someone wakes it, and its screen saver says how to reach you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Section("Back") {
                Picker("Back", selection: $back) {
                    Text("When I turn it off").tag(Back.off)
                    Text("In 1 hour").tag(Back.hours(1))
                    Text("In 3 hours").tag(Back.hours(3))
                    Text("In 8 hours").tag(Back.hours(8))
                    Text("At a time…").tag(Back.at)
                }
                #if os(iOS)
                .pickerStyle(.inline)
                #endif
                .labelsHidden()
                if back == .at {
                    DatePicker("Back at", selection: $at, in: Date.now.addingTimeInterval(60)...Date.now.addingTimeInterval(14 * 86400))
                }
            }
            Section {
                TextField("At work, at the store…", text: $note)
            } header: {
                Text("Note")
            } footer: {
                Text("Shown on the display beside your name.")
            }
            Section {
                Button(away.isAway() ? "Update" : "I'm away") { save(true) }
                    .disabled(saving)
                if away.isAway() {
                    Button("I'm home", role: .destructive) { save(false) }
                        .disabled(saving)
                }
            } footer: {
                Text("To switch it by itself: Shortcuts → Automation → New Automation → Leave (your home) → McFly's \u{201C}I'm Away\u{201D}; and Arrive → \u{201C}I'm Home\u{201D}. Choose Run Immediately.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Away mode")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .onAppear {
            note = away.isAway() ? (away.note ?? "") : ""
            if away.isAway(), let until = away.until {
                back = .at
                at = until
            }
        }
    }

    private var until: Date? {
        switch back {
        case .off: return nil
        case .hours(let n): return Date.now.addingTimeInterval(Double(n) * 3600)
        case .at: return at
        }
    }

    private func save(_ on: Bool) {
        saving = true
        Task {
            do {
                try await app.messages.setAway(on, until: on ? until : nil, note: on ? note : nil)
                dismiss()
            } catch {
                app.report(error)
            }
            saving = false
        }
    }
}

/// Home's card for what home wrote that the person hasn't read: the newest
/// one and how many there are. A tap opens Messages.
struct MessagesCard: View {
    let latest: Message
    let unread: Int
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Theme.accent.opacity(Theme.palette.isDark ? 0.28 : 0.16))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(heading.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.muted)
                Text("\(latest.senderName): \(latest.body)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var heading: String {
        let count = unread == 1 ? "A message from home" : "\(unread) messages from home"
        return "\(count) · \(Format.relative(latest.createdAt, now: now))"
    }
}
