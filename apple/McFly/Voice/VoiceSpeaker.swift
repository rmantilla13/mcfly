import AVFoundation
import Observation

/// Reads answers aloud with the system voice, sentence by sentence as they
/// arrive, and drives a `LevelMeter` so the glow follows the voice.
@MainActor
@Observable
final class VoiceSpeaker: NSObject {
    let meter = LevelMeter()
    private(set) var isSpeaking = false
    /// Called once everything queued has been spoken (not after `stop()`).
    var onFinished: (@MainActor () -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// Utterances queued and not yet finished.
    private var pending = 0
    private let voice = VoiceSpeaker.preferredVoice()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utterance.postUtteranceDelay = 0.12   // a natural breath between sentences
        pending += 1
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        pending = 0
        isSpeaking = false
        synthesizer.stopSpeaking(at: .immediate)
        meter.reset()
    }

    /// The most natural voice installed for the person's language: premium,
    /// then enhanced, then whatever the system offers.
    nonisolated static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String(language.prefix(2))
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
            var score = voice.language == language ? 10 : 0
            switch voice.quality {
            case .premium: score += 3
            case .enhanced: score += 2
            default: break
            }
            return score
        }
        return candidates.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: language)
    }

    fileprivate func wordSpoken(length: Int) {
        meter.pulse(0.35 + min(0.65, Float(length) / 10))
    }

    fileprivate func utteranceFinished() {
        guard pending > 0 else { return }
        pending -= 1
        guard pending == 0, isSpeaking else { return }
        isSpeaking = false
        onFinished?()
    }
}

extension VoiceSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let length = characterRange.length
        Task { @MainActor in self.wordSpoken(length: length) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceFinished() }
    }
}
