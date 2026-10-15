import McFlyKit
import SwiftUI

/// The Voice tab: start a spoken conversation, or ask by typing.
struct VoiceHubView: View {
    @Environment(AppModel.self) private var app
    @State private var showVoice = false
    @State private var showAsk = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Button {
                    showVoice = true
                } label: {
                    VoiceTile()
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Talk to McFly")

                Button {
                    showAsk = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask by typing").font(.headline).foregroundStyle(Theme.text)
                            Text("A written answer, with the same feeds behind it.")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                    }
                    .card()
                }
                .buttonStyle(PressableStyle())

                VStack(alignment: .leading, spacing: 8) {
                    Label("Everything spoken stays on this device", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("Speech is recognized and read aloud by Apple's on-device engines. Only the words you say go to McFly's assistant, grounded in your briefs, quotes and the day's Pulse report.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
            .padding(Theme.page)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Voice")
        .voiceCover(isPresented: $showVoice) {
            VoiceModeView()
                .environment(app)
        }
        .sheet(isPresented: $showAsk) {
            AskSheet()
                .environment(app)
        }
    }
}

/// The dark tile with the glow at its bottom edge, idling with life.
private struct VoiceTile: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(white: 0.105)
            VoiceGlow(meter: .ambient, kind: .input, cornerRadius: Theme.radius)
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .medium))
                Text("Talk to McFly")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Hands-free, with the day's feeds at hand")
                    .font(.system(.footnote, design: .rounded))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.bottom, 54)
            .padding(.top, 36)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

/// A typed conversation in `chat` mode, replies streamed word by word.
struct AskSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [AssistantTurn] = []
    @State private var draft = ""
    @State private var streaming = ""
    @State private var isReplying = false
    @State private var replyTask: Task<Void, Never>?
    /// Which model answers this chat. Starts from the platform's default.
    @State private var provider: AssistantProvider = .claude
    @FocusState private var focused: Bool

    private static let suggestions = ["What's in today's brief?", "How are my stocks doing?", "What's the top story?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if turns.isEmpty && !isReplying {
                                suggestionChips
                            }
                            ForEach(turns) { turn in
                                bubble(turn.text, mine: turn.role == .user)
                            }
                            if isReplying {
                                if streaming.isEmpty {
                                    TypingIndicator()
                                } else {
                                    bubble(streaming, mine: false)
                                }
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(Theme.page)
                    }
                    .onChange(of: streaming) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                    .onChange(of: turns.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
                composer
            }
            .screenBackground()
            .navigationTitle("Ask McFly")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { newChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
                        .disabled(turns.isEmpty && !isReplying)
                }
            }
        }
        .macOSFrame(width: 560, height: 680)
        .onAppear {
            focused = true
            provider = app.feeds.settings?.assistantProvider ?? .claude
        }
        .onDisappear { replyTask?.cancel() }
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
            ForEach(Self.suggestions, id: \.self) { text in
                Button {
                    draft = text
                    send()
                } label: {
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            Group {
                if mine {
                    Text(text).foregroundStyle(.white)
                } else {
                    MarkdownText(text: text).foregroundStyle(Theme.text)
                }
            }
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(mine ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Picker("Assistant", selection: $provider) {
                ForEach(AssistantProvider.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)
            .disabled(isReplying)
            .accessibilityLabel("Assistant model")
            composerRow
        }
        .padding(.horizontal, Theme.page)
        .padding(.vertical, 10)
        .background(Theme.background)
    }

    private var composerRow: some View {
        HStack(spacing: 10) {
            TextField("Ask about your briefs, markets or news", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .focused($focused)
                .onSubmit(send)
            Button {
                if isReplying { replyTask?.cancel() } else { send() }
            } label: {
                Image(systemName: isReplying ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!isReplying && draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func newChat() {
        replyTask?.cancel()
        turns = []
        streaming = ""
        isReplying = false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }
        draft = ""
        let history = turns
        turns.append(AssistantTurn(role: .user, text: text))
        isReplying = true
        streaming = ""
        replyTask = Task {
            var reply = ""
            do {
                try await app.answer(text, .chat, history, provider) { event in
                    switch event {
                    case .delta(let piece):
                        streaming += piece
                    case .done(let final):
                        reply = final.reply
                    case .error(let message):
                        reply = streaming.isEmpty ? message : streaming
                    }
                }
            } catch is CancellationError {
                reply = streaming
            } catch {
                reply = McFlyError.describe(error)
            }
            if !reply.isEmpty { turns.append(AssistantTurn(role: .assistant, text: reply)) }
            streaming = ""
            isReplying = false
        }
    }
}

/// Three bouncing dots while the first words are on their way.
struct TypingIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.muted)
                    .frame(width: 7, height: 7)
                    .offset(y: phase ? -3 : 3)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { phase = true }
    }
}
