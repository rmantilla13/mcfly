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
                            Text("A full-screen answer to read, with the same feeds behind it.")
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
        .voiceCover(isPresented: $showAsk) {
            AskView()
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

/// Ask McFly, full screen: room for the assistant to answer properly (`read`
/// mode: longer answers with headings, lists and tables) and to take them in,
/// as the console's /ask does. Each question opens at the top of the page as
/// a heading and its answer is laid out below it as it streams in; the page
/// holds still while you read. Full screen on iPhone and iPad, a large sheet
/// on the Mac.
struct AskView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [AssistantTurn] = []
    @State private var draft = ""
    @State private var streaming = ""
    @State private var isReplying = false
    /// Why the last question got no answer, shown under it with Try again.
    @State private var failure: String?
    @State private var copied: Int?
    @State private var replyTask: Task<Void, Never>?
    /// New chat starts another; a reply still finishing from the old one is dropped.
    @State private var chat = UUID()
    /// Which model answers this chat. Starts from the platform's default.
    @State private var provider: AssistantProvider = .claude
    @FocusState private var focused: Bool

    /// Questions that want a full screen (the console's).
    private static let suggestions = [
        "Catch me up on everything today",
        "Compare my watchlist in a table",
        "Where does every project stand?",
        "What needs my attention this week?",
    ]

    /// A question and its answer; either can be missing (one stopped early).
    private struct Exchange: Identifiable {
        let id: Int
        var question: String?
        var answer: String?
    }

    private var exchanges: [Exchange] {
        var out: [Exchange] = []
        for turn in turns {
            if turn.role == .user {
                out.append(Exchange(id: out.count, question: turn.text))
            } else if let last = out.indices.last, out[last].answer == nil {
                out[last].answer = turn.text
            } else {
                out.append(Exchange(id: out.count, answer: turn.text))
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if turns.isEmpty {
                                welcome
                            } else {
                                // The newest exchange is at least a screen tall, so its question can sit at the top.
                                thread(lastMinHeight: viewport.size.height - 24)
                            }
                        }
                        .padding(.horizontal, Theme.page)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: turns.count) { old, new in
                        // A new question goes to the top of the page; its answer fills in below without moving it.
                        guard new > old, turns.last?.role == .user, let last = exchanges.last else { return }
                        withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(last.id, anchor: .top) }
                    }
                }
            }
            composer
        }
        .screenBackground()
        .macOSFrame(width: 760, height: 840)
        .onAppear {
            focused = true
            provider = app.feeds.settings?.assistantProvider ?? .claude
        }
        .onDisappear { replyTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 1) {
                Text("Ask McFly").font(.headline).foregroundStyle(Theme.text)
                Text("Answers from your feeds").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)

            Menu {
                Picker("Answers from", selection: $provider) {
                    ForEach(AssistantProvider.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(provider.label)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.surface, in: Capsule())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(isReplying)
            .accessibilityLabel("Answers from \(provider.label)")

            if !turns.isEmpty {
                Button(action: newChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("New chat")
            }
        }
        .padding(.horizontal, Theme.page - 4)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    // MARK: Before the first question

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            GradientTile(colors: Theme.palette.glow, rings: 1, seed: 5.1) { tile in
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "text.book.closed")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tile.strong)
                    Text("What would you like to know?")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(tile.ink)
                    Text("Ask for the whole picture. McFly answers from what's on your display, laid out to read: the headline first, then the detail.")
                        .font(.body)
                        .foregroundStyle(tile.inkMuted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)
            }
            Text("Try asking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(Self.suggestions, id: \.self) { text in
                    Button { send(text) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(text)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.muted)
                        }
                        .card(padding: 16, radius: Theme.radiusSm)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.vertical, 24)
    }

    // MARK: The thread

    private func thread(lastMinHeight: CGFloat) -> some View {
        let all = exchanges
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(all) { exchange in
                let last = exchange.id == all.last?.id
                exchangeView(exchange, last: last)
                    // Room above the question when it's scrolled to the top.
                    .padding(.top, 22)
                    .frame(maxWidth: .infinity, minHeight: last ? max(0, lastMinHeight) : nil, alignment: .topLeading)
                    .id(exchange.id)
            }
        }
        .padding(.bottom, 16)
    }

    private func exchangeView(_ exchange: Exchange, last: Bool) -> some View {
        let replying = last && isReplying
        let answer = exchange.answer ?? (replying ? streaming : "")
        return VStack(alignment: .leading, spacing: 18) {
            if exchange.id > 0 {
                Rectangle().fill(Theme.divider).frame(height: 1).padding(.bottom, 10)
            }
            if let question = exchange.question {
                Text(question)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if !answer.isEmpty {
                AnswerMarkdown(text: answer)
            } else if replying {
                ReadingIndicator()
            } else if !(last && failure != nil) {
                Text("Stopped before an answer.").font(.subheadline).foregroundStyle(Theme.muted)
            }
            if replying && !answer.isEmpty {
                StreamingBar()
            } else if !answer.isEmpty {
                Button {
                    Pasteboard.copy(answer)
                    copied = exchange.id
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        if copied == exchange.id { copied = nil }
                    }
                } label: {
                    Label(copied == exchange.id ? "Copied" : "Copy", systemImage: copied == exchange.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.pill(.neutral))
            }
            if last, let failure, !isReplying {
                failureCard(failure)
            }
        }
    }

    private func failureCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Try again", action: retry).buttonStyle(.pill(.soft))
        }
        .padding(14)
        .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
    }

    // MARK: Composer

    private var composer: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 8) {
            TextField(turns.isEmpty ? "Ask McFly anything" : "Ask a follow-up", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focused)
                .onSubmit { send(draft) }
                .padding(.vertical, 11)
                .padding(.leading, 16)
            Button {
                if isReplying { replyTask?.cancel() } else { send(draft) }
            } label: {
                Image(systemName: isReplying ? "stop.fill" : "arrow.up")
                    .font(.system(size: isReplying ? 14 : 16, weight: .bold))
                    .foregroundStyle(isReplying ? Theme.background : Theme.accentInk)
                    .frame(width: 40, height: 40)
                    .background(isReplying ? Theme.text : Theme.accent, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .opacity(!isReplying && empty ? 0.35 : 1)
            .disabled(!isReplying && empty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel(isReplying ? "Stop the answer" : "Ask")
        }
        .padding(4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        // The glow's colours under the composer while McFly is answering.
        .background(alignment: .bottom) {
            Capsule()
                .fill(LinearGradient(colors: Theme.glow, startPoint: .leading, endPoint: .trailing))
                .frame(height: 30)
                .padding(.horizontal, 36)
                .blur(radius: 20)
                .offset(y: 8)
                .opacity(isReplying ? 0.75 : 0)
                .animation(.easeInOut(duration: 0.5), value: isReplying)
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, Theme.page - 4)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: Asking

    private func newChat() {
        replyTask?.cancel()
        chat = UUID()
        turns = []
        streaming = ""
        failure = nil
        copied = nil
        isReplying = false
        focused = true
    }

    /// Asks the last question again, in its place.
    private func retry() {
        guard let question = turns.last(where: { $0.role == .user })?.text else { return }
        if turns.last?.role == .user { turns.removeLast() }
        send(question)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isReplying else { return }
        draft = ""
        failure = nil
        // The answer gets the screen.
        focused = false
        let history = turns
        let current = chat
        turns.append(AssistantTurn(role: .user, text: question))
        isReplying = true
        streaming = ""
        replyTask = Task {
            var reply = ""
            var problem: String?
            do {
                try await app.answer(question, .read, history, provider) { event in
                    switch event {
                    case .delta(let piece):
                        if chat == current { streaming += piece }
                    case .done(let final):
                        reply = final.reply
                    case .error(let message):
                        if streaming.isEmpty { problem = message } else { reply = streaming }
                    }
                }
            } catch {
                // Stopped: what arrived stays. Anything else, said under the question.
                reply = streaming
                if !Task.isCancelled && streaming.isEmpty { problem = McFlyError.describe(error) }
            }
            guard chat == current else { return }
            // Stopped part-way, it's marked: the next message is taken as a change to the question.
            if !reply.isEmpty { turns.append(AssistantTurn(role: .assistant, text: reply, interrupted: Task.isCancelled)) }
            failure = problem
            streaming = ""
            isReplying = false
        }
    }
}

/// A pulsing dot while the first words are on their way.
private struct ReadingIndicator: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 10, height: 10)
                .background {
                    Circle()
                        .fill(Theme.accent.opacity(0.45))
                        .scaleEffect(pulse ? 2.6 : 1)
                        .opacity(pulse ? 0 : 1)
                }
            Text("Reading your feeds…").font(.body).foregroundStyle(Theme.muted)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Under an answer that is still arriving.
private struct StreamingBar: View {
    @State private var dim = false

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: Theme.glow, startPoint: .leading, endPoint: .trailing))
            .frame(width: 44, height: 5)
            .opacity(dim ? 0.35 : 0.9)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true } }
            .accessibilityHidden(true)
    }
}
