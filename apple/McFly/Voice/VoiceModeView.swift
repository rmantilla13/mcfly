import McFlyKit
import SwiftUI

/// Full-screen voice conversation, styled after libraries.dev's voice-glow mobile host:
/// a dark surface, the live transcript centered, the glow rising from the bottom edge, and
/// translucent controls. Recognition and speech run on this device; the answer comes from
/// McFly's assistant.
struct VoiceModeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var session: VoiceSession?

    private static let surface = Color(white: 0.105)
    #if os(iOS)
    private static let cornerRadius: CGFloat = 55   // follows the iPhone's screen corners
    #else
    private static let cornerRadius: CGFloat = 18
    #endif

    var body: some View {
        ZStack {
            Self.surface.ignoresSafeArea()

            if let session {
                VoiceGlow(meter: session.activeMeter,
                          processing: session.phase == .thinking || session.phase == .starting,
                          kind: .screen, cornerRadius: Self.cornerRadius)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    statusChip(session)
                        .padding(.top, 14)
                    content(session)
                    controls(session)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 34)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .macOSFrame(width: 560, height: 720)
        .task {
            guard session == nil else { return }
            // Symbols and agent names, so "NVDA" is heard as NVDA.
            let vocabulary = app.feeds.series.flatMap { [$0.symbol, $0.displayName] } + app.feeds.agents.map(\.name)
            let session = VoiceSession(answerer: app.answer, vocabulary: Array(Set(vocabulary)))
            self.session = session
            await session.listen()
        }
        .onAppear {
            // Hands-free means not touching the phone, so it mustn't lock mid-conversation.
            ScreenAwake.hold("voice-mode")
        }
        .onDisappear {
            session?.end()
            ScreenAwake.release("voice-mode")
        }
        .onChange(of: session?.phase) { _, phase in
            guard let phase else { return }
            AccessibilityNotification.Announcement(Self.status(for: phase)).post()
        }
    }

    // MARK: Pieces

    private func statusChip(_ session: VoiceSession) -> some View {
        HStack(spacing: 6) {
            if session.listener.isOnDevice {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
            }
            Text(Self.status(for: session.phase))
        }
        .font(.system(.footnote, design: .rounded, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.07)))
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.status(for: session.phase))\(session.listener.isOnDevice ? ", on this device" : "")")
    }

    @ViewBuilder
    private func content(_ session: VoiceSession) -> some View {
        if session.answer.isEmpty {
            // Listening or thinking: the transcript, centered and large, just above the glow.
            VStack(spacing: 16) {
                Spacer()
                transcript(session)
                if session.phase == .starting, let step = session.listener.startupStep {
                    Text(step)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                if case .failed(let message) = session.phase {
                    failure(message)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 560)
        } else {
            // Answering: what was asked, then the answer, scrolling above the glow.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(session.heard)
                            .font(.system(.title3, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        MarkdownText(text: session.answer)
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .id("answer")
                        Color.clear.frame(height: 120)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 24)
                    .frame(maxWidth: 600, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .onChange(of: session.answer) { proxy.scrollTo("answer", anchor: .bottom) }
            }
        }
    }

    private func transcript(_ session: VoiceSession) -> some View {
        let confirmed = session.liveConfirmed
        let pending = session.livePending
        let empty = confirmed.isEmpty && pending.isEmpty
        var text = AttributedString(empty ? Self.prompt(for: session.phase) : confirmed)
        text.foregroundColor = .white.opacity(empty ? 0.38 : 0.82)
        if !pending.isEmpty {
            var tail = AttributedString((confirmed.isEmpty ? "" : " ") + pending)
            tail.foregroundColor = .white.opacity(0.42)   // still being recognized
            text += tail
        }
        return Text(text)
            .font(.system(size: 26, weight: .regular, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.15), value: confirmed + pending)
    }

    private func controls(_ session: VoiceSession) -> some View {
        HStack(spacing: 14) {
            modeMenu(session)
            Spacer()
            circleButton(icon: micIcon(session.phase), label: micLabel(session.phase),
                         highlighted: session.phase == .listening) {
                micAction(session)
            }
            .disabled(session.phase == .thinking || session.phase == .starting)
            .keyboardShortcut(.space, modifiers: [])
            circleButton(icon: "xmark", label: "Close voice mode", highlighted: false) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: 560)
    }

    private func modeMenu(_ session: VoiceSession) -> some View {
        @Bindable var session = session
        return Menu {
            Picker("Listening", selection: $session.handsFree) {
                Label("Hands-free (auto)", systemImage: "repeat").tag(true)
                Label("Tap to talk", systemImage: "hand.tap").tag(false)
            }
        } label: {
            HStack(spacing: 6) {
                Text(session.handsFree ? "Hands-free" : "Tap to talk")
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Capsule().fill(.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Mode: \(session.handsFree ? "hands-free" : "tap to talk")")
    }

    private func circleButton(icon: String, label: String, highlighted: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 52, height: 52)
                .background(Circle().fill(.white.opacity(highlighted ? 0.18 : 0.08)))
                .overlay(Circle().strokeBorder(.white.opacity(highlighted ? 0.3 : 0.08)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private func failure(_ message: String) -> some View {
        Text(message)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
        if message.contains("Settings") {
            Button("Open Settings") { openSettings() }
                .buttonStyle(.pill(.soft))
        }
    }

    // MARK: State text

    static func status(for phase: VoiceSession.Phase) -> String {
        switch phase {
        case .idle: return "Ready"
        case .starting: return "Getting ready"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .failed: return "Voice unavailable"
        }
    }

    private static func prompt(for phase: VoiceSession.Phase) -> String {
        switch phase {
        case .listening, .starting: return "Ask about your briefs, markets or news…"
        case .idle: return "Tap the mic to ask something"
        default: return ""
        }
    }

    private func micIcon(_ phase: VoiceSession.Phase) -> String {
        switch phase {
        case .listening: return "mic.fill"
        case .speaking: return "hand.raised.fill"
        default: return "mic"
        }
    }

    private func micLabel(_ phase: VoiceSession.Phase) -> String {
        switch phase {
        case .listening: return "Done talking"
        case .speaking: return "Interrupt and ask"
        case .thinking, .starting: return "Please wait"
        default: return "Talk"
        }
    }

    private func micAction(_ session: VoiceSession) {
        switch session.phase {
        case .listening: session.doneTalking()
        case .speaking: session.interrupt()
        default: Task { await session.listen() }
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { openURL(url) }
        #endif
    }
}
