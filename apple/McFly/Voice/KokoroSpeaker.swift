import AVFoundation
import McFlyVoice

/// Plays McFly's Kokoro voice: text in, speech out, in order. Each piece is rendered
/// while the one before it plays, so sentences follow each other without gaps, and the
/// audio itself drives a `LevelMeter` so the glow moves with the voice. From Homestead's.
@MainActor
final class KokoroSpeaker {
    let meter: LevelMeter
    var speaker: KokoroVoice.Speaker = .heart
    private(set) var isSpeaking = false
    /// Called once everything queued has played (not after `stop()`).
    var onFinished: (@MainActor () -> Void)?
    /// Called each time one `speak` call's audio has played to the end.
    var onPartPlayed: (@MainActor () -> Void)?
    /// Called with text the built-in voice couldn't speak, so it can be spoken another way.
    var onFailure: (@MainActor (String) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroVoice.sampleRate, channels: 1)!
    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    /// Buffers handed to the player that haven't finished playing.
    private var scheduled = 0
    /// Bumped by `stop()`, so callbacks from before it are ignored.
    private var generation = 0

    init(meter: LevelMeter) {
        self.meter = meter
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.levelTap(meter: meter))
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !isSpeaking { BuiltInVoice.shared.beginUse() }
        isSpeaking = true
        queue.append(text)
        if worker == nil {
            worker = Task { await drain(generation) }
        }
    }

    func stop() {
        generation += 1
        queue.removeAll()
        worker?.cancel()
        worker = nil
        player.stop()
        scheduled = 0
        meter.reset()
        if isSpeaking { BuiltInVoice.shared.endUse() }
        isSpeaking = false
    }

    private func drain(_ current: Int) async {
        while current == generation, !queue.isEmpty {
            let text = queue.removeFirst()
            guard let voice = await BuiltInVoice.shared.voice() else {
                if current == generation { onFailure?(text) }
                continue
            }
            do {
                let samples = try await voice.synthesize(text, speaker: speaker)
                guard current == generation else { return }
                play(samples)
            } catch {
                if current == generation { onFailure?(text) }
            }
        }
        guard current == generation else { return }
        worker = nil
        finishIfDone()
    }

    private func play(_ samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        do {
            try startEngine()
        } catch {
            return
        }
        scheduled += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack,
                              completionHandler: Self.playedHandler(owner: self, generation: generation))
        if !player.isPlaying { player.play() }
    }

    private func played(_ playedGeneration: Int) {
        guard playedGeneration == generation else { return }
        scheduled = max(0, scheduled - 1)
        onPartPlayed?()
        finishIfDone()
    }

    private func finishIfDone() {
        guard isSpeaking, scheduled == 0, queue.isEmpty, worker == nil else { return }
        isSpeaking = false
        meter.reset()
        BuiltInVoice.shared.endUse()
        onFinished?()
    }

    private func startEngine() throws {
        guard !engine.isRunning else { return }
        #if os(iOS)
        // Voice mode already set up play-and-record; otherwise play like spoken audio, which
        // also sounds with the silent switch on.
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        }
        #endif
        engine.prepare()
        try engine.start()
    }

    // MARK: Audio-thread callbacks
    //
    // Built outside the main actor: AVFoundation calls them on its own threads, and a closure
    // that inherited main-actor isolation would trap there.

    nonisolated private static func playedHandler(owner: KokoroSpeaker, generation: Int)
        -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak owner] _ in
            Task { @MainActor in owner?.played(generation) }
        }
    }

    /// Voice energy overall and in three bands (low, mid, high), from the audio being played.
    nonisolated private static func levelTap(meter: LevelMeter) -> AVAudioNodeTapBlock {
        let filters = BandFilters()
        return { buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            meter.set(filters.levels(samples, count: Int(buffer.frameLength)))
        }
    }
}

/// One-pole filters splitting speech at about 300 Hz and 2 kHz (24 kHz audio). Used only
/// from the tap's thread.
private final class BandFilters: @unchecked Sendable {
    private var below300: Float = 0
    private var below2k: Float = 0

    func levels(_ samples: UnsafePointer<Float>, count: Int) -> LevelMeter.Levels {
        var total: Float = 0, low: Float = 0, mid: Float = 0, high: Float = 0
        for i in 0..<count {
            let x = samples[i]
            below300 += 0.075 * (x - below300)
            below2k += 0.41 * (x - below2k)
            total += x * x
            low += below300 * below300
            mid += (below2k - below300) * (below2k - below300)
            high += (x - below2k) * (x - below2k)
        }
        func scaled(_ energy: Float, _ gain: Float) -> Float { min(1, (energy / Float(count)).squareRoot() * gain) }
        return LevelMeter.Levels(level: scaled(total, 7), low: scaled(low, 9), mid: scaled(mid, 9), high: scaled(high, 14))
    }
}
