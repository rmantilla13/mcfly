import Foundation
import McFlyKit
import Observation

/// The hands-free loop: listen → (pause ends the question) → think → speak → listen again.
/// Answers come from the `assistant` function in `quick` mode, with the last turns as history,
/// and are spoken sentence by sentence as they stream.
@MainActor
@Observable
final class VoiceSession {
    enum Phase: Equatable {
        case idle
        case starting
        case listening
        case thinking
        case speaking
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// What the person is saying (live) or said.
    private(set) var heard = ""
    /// The current answer, as it streams.
    private(set) var answer = ""
    /// The conversation so far, passed back as `history` (the server keeps the last 10).
    private(set) var history: [AssistantTurn] = []
    var handsFree = true

    let listener = VoiceListener()
    let speaker = VoiceSpeaker()
    private let answerer: Answerer
    private let vocabulary: [String]
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    /// The question being answered, until its turns are in `history`.
    @ObservationIgnored private var pendingQuestion: String?
    /// Streamed text not yet cut into a sentence and spoken.
    @ObservationIgnored private var unspoken = ""
    @ObservationIgnored private var answerComplete = false

    init(answerer: @escaping Answerer, vocabulary: [String] = []) {
        self.answerer = answerer
        self.vocabulary = vocabulary
        speaker.onFinished = { [weak self] in self?.speechFinished() }
        // The voice loads while the question is asked, not after it.
        speaker.prepare()
    }

    /// The meter the glow should follow right now.
    var activeMeter: LevelMeter { phase == .speaking ? speaker.meter : listener.meter }

    /// For display: settled words, and words recognition is still working on (shown dimmer).
    var liveConfirmed: String { phase == .listening ? listener.confirmedText : heard }
    var livePending: String { phase == .listening ? listener.pendingText : "" }

    func listen() async {
        keepCutShort()
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        await listener.cancel()
        heard = ""
        answer = ""
        phase = .starting
        do {
            try await listener.start(vocabulary: vocabulary, onLive: { [weak self] in
                self?.phase = .listening
            }, onSpeechEnded: { [weak self] in
                Task { await self?.questionEnded() }
            })
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Ends the question now (the person tapped instead of pausing).
    func doneTalking() {
        Task { await questionEnded() }
    }

    /// Stops the answer being spoken and listens again.
    func interrupt() {
        keepCutShort()
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        Task { await listen() }
    }

    func end() {
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        Task { await listener.cancel() }
        phase = .idle
    }

    private func questionEnded() async {
        guard phase == .listening else { return }
        let text = await listener.finish()
        heard = text
        guard !text.isEmpty else {
            // Nothing understood: stay ready rather than sending an empty question.
            phase = .idle
            return
        }
        answer = ""
        unspoken = ""
        answerComplete = false
        phase = .thinking
        pendingQuestion = text
        let priorTurns = history
        replyTask = Task { await ask(text, history: priorTurns) }
    }

    /// The person cut in before the answer was done (or while it was still being read
    /// out): keep the question and what had arrived, marked as cut short, so what they
    /// say next is taken as a change to it rather than a new topic.
    private func keepCutShort() {
        if let question = pendingQuestion {
            pendingQuestion = nil
            var turns = history + [AssistantTurn(role: .user, text: question)]
            if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                turns.append(AssistantTurn(role: .assistant, text: answer, interrupted: true))
            }
            history = Array(turns.suffix(AssistantClient.historyLimit))
        } else if speaker.isSpeaking, let last = history.indices.last, history[last].role == .assistant {
            history[last].interrupted = true
        }
    }

    private func ask(_ text: String, history prior: [AssistantTurn]) async {
        var finalReply = ""
        do {
            try await answerer(text, .quick, prior, nil) { [weak self] event in
                guard let self else { return }
                switch event {
                case .delta(let piece):
                    answer += piece
                    unspoken += piece
                    speakReady(final: false)
                case .done(let reply):
                    // The server's reply replaces what streamed (a refusal, say); what was
                    // already spoken stays spoken.
                    finalReply = reply.reply
                    if answer.isEmpty { unspoken = reply.reply }
                    answer = reply.reply
                    speakReady(final: true)
                case .error(let message):
                    if answer.isEmpty {
                        answer = message
                        unspoken = message
                    }
                    speakReady(final: true)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            let message = McFlyError.describe(error)
            answer = message
            unspoken = message
            speakReady(final: true)
        }
        guard !Task.isCancelled else { return }
        pendingQuestion = nil
        history = Array((prior + [AssistantTurn(role: .user, text: text),
                                  AssistantTurn(role: .assistant, text: finalReply.isEmpty ? answer : finalReply)])
            .suffix(AssistantClient.historyLimit))
        answerComplete = true
        if !speaker.isSpeaking { speechFinished() }
    }

    /// Speaks every whole sentence waiting in `unspoken`.
    private func speakReady(final: Bool) {
        let (sentences, rest) = SpokenText.split(unspoken, final: final)
        unspoken = rest
        for sentence in sentences {
            let plain = SpokenText.plain(sentence)
            guard !plain.isEmpty else { continue }
            speaker.speak(plain)
            phase = .speaking
        }
    }

    private func speechFinished() {
        guard answerComplete else { return }
        if handsFree {
            Task { await listen() }
        } else {
            phase = .idle
        }
    }
}
