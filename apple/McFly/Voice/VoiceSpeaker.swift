import AVFoundation
import McFlyVoice
import Observation
import os

/// Which voice reads answers: one of Kokoro's, the account's voice the display and the web
/// speak with too (`AccountVoice`, `AppModel.syncVoice`), or this device's own, which stays
/// here. Kept on the device under the web's key, Heart until the account says otherwise.
enum VoiceChoice: String, CaseIterable, Identifiable {
    case heart = "af_heart"
    case bella = "af_bella"
    case michael = "am_michael"
    case fenrir = "am_fenrir"
    case system

    static let key = "mcfly.voice"

    static var current: VoiceChoice {
        get { UserDefaults.standard.string(forKey: key).flatMap(VoiceChoice.init(rawValue:)) ?? .heart }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    var id: Self { self }

    var name: String {
        switch self {
        case .heart: return "Heart"
        case .bella: return "Bella"
        case .michael: return "Michael"
        case .fenrir: return "Fenrir"
        case .system: return "This device's voice"
        }
    }

    /// The Kokoro voice, or nil for the system's.
    var kokoro: KokoroVoice.Speaker? { KokoroVoice.Speaker(rawValue: rawValue) }
}

/// Reads answers aloud, sentence by sentence as they arrive, and drives a `LevelMeter`
/// so the glow follows the voice. Kokoro speaks when it's the chosen voice and this build
/// has it (`BuiltInVoice`); otherwise, or for a sentence Kokoro can't say (its models need
/// iOS 18 or macOS 15), the system's most natural voice does.
@MainActor
@Observable
final class VoiceSpeaker: NSObject {
    let meter = LevelMeter()
    private(set) var isSpeaking = false
    /// Called once everything queued has been spoken (not after `stop()`).
    var onFinished: (@MainActor () -> Void)?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let kokoro: KokoroSpeaker
    /// System utterances queued and not yet finished.
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private let voice = VoiceSpeaker.preferredVoice()
    @ObservationIgnored private let log = Logger(subsystem: "bot.mcfly", category: "voice")

    override init() {
        kokoro = KokoroSpeaker(meter: meter)
        super.init()
        synthesizer.delegate = self
        kokoro.onFinished = { [weak self] in self?.finishIfDone() }
        kokoro.onFailure = { [weak self] text in
            self?.log.info("Kokoro couldn't say a sentence; the system voice says it")
            self?.speakWithSystem(text)
        }
        kokoro.onPartPlayed = { [log] in log.info("Kokoro spoke a sentence") }
    }

    /// Loads Kokoro ahead of the first answer, if it's the voice that will speak.
    func prepare() {
        if VoiceChoice.current.kokoro != nil { BuiltInVoice.shared.prepare() }
    }

    func speak(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSpeaking = true
        if let speaker = VoiceChoice.current.kokoro, BuiltInVoice.isBundled {
            kokoro.speaker = speaker
            kokoro.speak(text)
        } else {
            speakWithSystem(text)
        }
    }

    func stop() {
        pending = 0
        isSpeaking = false
        kokoro.stop()
        synthesizer.stopSpeaking(at: .immediate)
        meter.reset()
    }

    private func speakWithSystem(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utterance.postUtteranceDelay = 0.12   // a natural breath between sentences
        pending += 1
        isSpeaking = true
        synthesizer.speak(utterance)
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
        finishIfDone()
    }

    private func finishIfDone() {
        guard isSpeaking, pending == 0, !kokoro.isSpeaking else { return }
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
