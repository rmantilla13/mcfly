import AVFoundation
import Accelerate
import CoreMedia
import Observation
import Speech
import os

/// Turns speech into text on this device and meters the microphone for the
/// voice glow. Apple's `SpeechAnalyzer` does the recognizing on iOS 26 and
/// macOS 26; older systems use `SFSpeechRecognizer`, on-device where the
/// device supports it. Nothing is recorded to disk.
@MainActor
@Observable
final class VoiceListener {
    enum Failure: LocalizedError {
        case microphoneDenied
        case speechDenied
        case unsupported
        case audio(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "Microphone access is off. Turn it on in Settings → Privacy & Security → Microphone → McFly."
            case .speechDenied:
                return "Speech recognition is off. Turn it on in Settings → Privacy & Security → Speech Recognition → McFly."
            case .unsupported:
                return "Speech recognition isn't available on this device or for this language."
            case .audio(let message):
                return "The microphone couldn't start: \(message)"
            }
        }
    }

    /// Which engine this system uses, for Settings → About.
    nonisolated static var engineDescription: String {
        if #available(iOS 26, macOS 26, *) { return "SpeechAnalyzer (on device)" }
        return "SFSpeechRecognizer"
    }

    /// The words recognition has settled on, and the still-changing words after them.
    private(set) var confirmedText = ""
    private(set) var pendingText = ""
    var transcript: String {
        [confirmedText, pendingText].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
    private(set) var isListening = false
    /// What start-up is waiting on, shown under "Getting ready" (e.g. the permission prompt).
    private(set) var startupStep: String?
    /// Whether the audio stays on the device (false only for a server-based SFSpeechRecognizer).
    private(set) var isOnDevice = true
    let meter = LevelMeter()

    private let audioEngine = AVAudioEngine()
    private var processor: TapProcessor?
    private var recognizer: (any SpeechRecognizing)?

    /// Starts listening. The microphone goes live first (`onLive`) and audio is kept while the
    /// speech model loads, so words spoken the moment listening starts aren't lost.
    /// `onSpeechEnded` fires after the speaker pauses, or after a long silence with no speech.
    func start(vocabulary: [String] = [],
               onLive: @escaping @MainActor () -> Void = {},
               onSpeechEnded: @escaping @MainActor () -> Void) async throws {
        guard !isListening else { return }
        startupStep = "Waiting for microphone permission. Look for a system prompt."
        defer { startupStep = nil }
        guard await AVAudioApplication.requestRecordPermission() else { throw Failure.microphoneDenied }

        startupStep = "Finding the speech model"
        let recognizer = try await Self.makeRecognizer()
        isOnDevice = recognizer.isOnDevice

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            if #available(iOS 26, *) {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            } else {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            }
            try session.setActive(true)
        } catch {
            throw Failure.audio(error.localizedDescription)
        }
        #endif

        confirmedText = ""
        pendingText = ""
        meter.reset()

        // 1. Microphone first, in its own format; audio is kept until the recognizer is ready.
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw Failure.audio("No microphone input is available.") }
        let processor = TapProcessor(meter: meter) {
            Task { @MainActor in onSpeechEnded() }
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat, block: Self.tapBlock(for: processor))
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.audio(error.localizedDescription)
        }
        self.processor = processor
        self.recognizer = recognizer
        isListening = true
        startupStep = "Starting recognition"
        onLive()

        // 2. The recognizer, then everything captured so far.
        do {
            let feeder = try await recognizer.start(
                inputFormat: inputFormat, vocabulary: vocabulary,
                onProgress: { [weak self] step in self?.startupStep = step },
                onResult: { [weak self] confirmed, pending in
                    self?.confirmedText = confirmed
                    self?.pendingText = pending
                })
            processor.attach(feeder)
        } catch {
            stopAudio()
            processor.finish()
            await recognizer.cancel()
            cleanUp()
            throw (error as? Failure) ?? Failure.audio(error.localizedDescription)
        }
    }

    /// Stops listening and returns everything heard, after the recognizer finalizes it.
    func finish() async -> String {
        guard isListening else { return transcript }
        stopAudio()
        processor?.finish()
        await recognizer?.finish()
        cleanUp()
        return transcript
    }

    /// Stops immediately, discarding what was heard.
    func cancel() async {
        guard isListening else { return }
        stopAudio()
        processor?.finish()
        await recognizer?.cancel()
        cleanUp()
        confirmedText = ""
        pendingText = ""
    }

    /// SpeechAnalyzer where the system has it and supports the language; else SFSpeechRecognizer.
    private static func makeRecognizer() async throws -> any SpeechRecognizing {
        if #available(iOS 26, macOS 26, *) {
            if let analyzer = await AnalyzerRecognizer.make() { return analyzer }
        }
        return try await LegacyRecognizer.make()
    }

    /// The tap runs on the audio engine's real-time thread. A closure written inside a
    /// main-actor method would be main-actor isolated and trap there, so build it here.
    nonisolated private static func tapBlock(for processor: TapProcessor) -> AVAudioNodeTapBlock {
        { buffer, _ in processor.process(buffer) }
    }

    private func stopAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        meter.reset()
    }

    private func cleanUp() {
        recognizer = nil
        processor = nil
        isListening = false
    }
}

// MARK: - Recognizers

/// One speech engine behind the listener. `start` returns the feeder the audio
/// thread calls with microphone buffers.
@MainActor
protocol SpeechRecognizing: AnyObject {
    var isOnDevice: Bool { get }
    func start(inputFormat: AVAudioFormat, vocabulary: [String],
               onProgress: @escaping @MainActor (String) -> Void,
               onResult: @escaping @MainActor (_ confirmed: String, _ pending: String) -> Void) async throws -> @Sendable (AVAudioPCMBuffer) -> Void
    /// Ends the input and waits for the final results.
    func finish() async
    func cancel() async
}

/// Apple's on-device `SpeechAnalyzer` with a `SpeechTranscriber` module (iOS 26, macOS 26).
@available(iOS 26, macOS 26, *)
@MainActor
final class AnalyzerRecognizer: SpeechRecognizing {
    let isOnDevice = true
    private let transcriber: SpeechTranscriber
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finalSegments: [String] = []
    /// Provisional text keyed by where its audio starts; a later result for the same span replaces it.
    private var volatileSegments: [(start: CMTime, text: String)] = []

    // Lookups that take a moment the first time; cached so voice mode opens instantly after.
    private static var cachedLocale: Locale?
    private static var cachedFormat: AVAudioFormat?

    private init(transcriber: SpeechTranscriber) {
        self.transcriber = transcriber
    }

    /// The transcriber for the person's language, or nil if unsupported.
    static func make() async -> AnalyzerRecognizer? {
        guard SpeechTranscriber.isAvailable else { return nil }
        if cachedLocale == nil {
            cachedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        }
        guard let locale = cachedLocale else { return nil }
        return AnalyzerRecognizer(transcriber: SpeechTranscriber(locale: locale, preset: .progressiveTranscription))
    }

    func start(inputFormat: AVAudioFormat, vocabulary: [String],
               onProgress: @escaping @MainActor (String) -> Void,
               onResult: @escaping @MainActor (String, String) -> Void) async throws -> @Sendable (AVAudioPCMBuffer) -> Void {
        // The model is often already on the device (the system or another app installed it)
        // without being reserved for McFly; asking for an installation request reserves it
        // and returns nil when there's nothing to download.
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            break
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                onProgress("Downloading Apple's speech model (one time)")
                try await request.downloadAndInstall()
            }
        default:
            throw VoiceListener.Failure.unsupported
        }
        let format: AVAudioFormat
        if let cached = Self.cachedFormat {
            format = cached
        } else if let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) {
            Self.cachedFormat = best
            format = best
        } else {
            throw VoiceListener.Failure.unsupported
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw VoiceListener.Failure.audio("Couldn't convert microphone audio.")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        finalSegments = []
        volatileSegments = []
        let transcriber = self.transcriber
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.receive(result, onResult: onResult)
                }
            } catch {
                // The stream ends with an error if analysis is cancelled; the transcript so far stands.
            }
        }
        if !vocabulary.isEmpty {
            // Symbols and agent names improve recognition of things like "NVDA".
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.continuation = continuation
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        let convert = BufferConverter(converter: converter, format: format)
        return { buffer in
            if let converted = convert.convert(buffer) { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
    }

    func finish() async {
        continuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        clear()
    }

    func cancel() async {
        continuation?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        clear()
    }

    private func receive(_ result: SpeechTranscriber.Result, onResult: @MainActor (String, String) -> Void) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespaces)
        let start = result.range.start
        if result.isFinal {
            if !text.isEmpty { finalSegments.append(text) }
            // Drop provisional text this final result now covers.
            let end = CMTimeRangeGetEnd(result.range)
            volatileSegments.removeAll { CMTimeCompare($0.start, end) < 0 }
        } else {
            // A newer provisional result replaces anything from the same point onward.
            volatileSegments.removeAll { CMTimeCompare($0.start, start) >= 0 }
            if !text.isEmpty { volatileSegments.append((start, text)) }
        }
        onResult(finalSegments.joined(separator: " "), volatileSegments.map(\.text).joined(separator: " "))
    }

    private func clear() {
        analyzer = nil
        continuation = nil
        resultsTask = nil
    }
}

/// `SFSpeechRecognizer` (iOS 17–25, macOS 14–25): on-device when the device
/// and language allow, else Apple's servers.
@MainActor
final class LegacyRecognizer: SpeechRecognizing {
    let isOnDevice: Bool
    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finished = false

    private init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
        isOnDevice = recognizer.supportsOnDeviceRecognition
    }

    static func make() async throws -> LegacyRecognizer {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            throw VoiceListener.Failure.unsupported
        }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        switch status {
        case .authorized: return LegacyRecognizer(recognizer: recognizer)
        case .denied, .restricted: throw VoiceListener.Failure.speechDenied
        default: throw VoiceListener.Failure.unsupported
        }
    }

    func start(inputFormat: AVAudioFormat, vocabulary: [String],
               onProgress: @escaping @MainActor (String) -> Void,
               onResult: @escaping @MainActor (String, String) -> Void) async throws -> @Sendable (AVAudioPCMBuffer) -> Void {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = isOnDevice
        if !vocabulary.isEmpty { request.contextualStrings = vocabulary }
        self.request = request
        finished = false
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text {
                    // Partial results settle only at the end, so until then every word is pending.
                    onResult(isFinal ? text : "", isFinal ? "" : text)
                }
                if isFinal || failed { self.finished = true }
            }
        }
        return { buffer in request.append(buffer) }
    }

    func finish() async {
        request?.endAudio()
        // The final result follows the end of audio; don't wait forever for it.
        for _ in 0..<30 where !finished {
            try? await Task.sleep(for: .milliseconds(100))
        }
        task?.cancel()
        clear()
    }

    func cancel() async {
        request?.endAudio()
        task?.cancel()
        clear()
    }

    private func clear() {
        request = nil
        task = nil
    }
}

/// Converts microphone buffers to the analyzer's format on the audio thread.
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let lock = NSLock()

    init(converter: AVAudioConverter, format: AVAudioFormat) {
        self.converter = converter
        self.format = format
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        // The converter calls this block synchronously on this thread: hand it the buffer once.
        let supplied = Flag()
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied.isSet {
                status.pointee = .noDataNow
                return nil
            }
            supplied.isSet = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    private final class Flag: @unchecked Sendable {
        var isSet = false
    }
}

// MARK: - Tap

/// Runs on the real-time audio thread: meters the voice for the glow, notices when the speaker
/// has stopped, and hands audio to the recognizer. Until the recognizer is ready, it keeps the
/// raw audio (up to a minute) and feeds it over once `attach` is called.
private final class TapProcessor: @unchecked Sendable {
    private let meter: LevelMeter
    private let onSpeechEnded: @Sendable () -> Void

    // Shared between the audio thread and `attach` / `finish`.
    private let lock = NSLock()
    private var feeder: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var backlog: [AVAudioPCMBuffer] = []
    private var finished = false

    // Only touched from the audio thread.
    private var lowState: Float = 0
    private var midState: Float = 0
    private var noiseFloor: Float = 0.01
    private var loudBuffers = 0
    private var speechStarted = false
    private var lastLoud = Date()
    private let started = Date()
    private var endedReported = false

    /// Pause after speech that ends the question, and how long to wait for any speech at all.
    private static let endPause: TimeInterval = 1.3
    private static let noSpeechTimeout: TimeInterval = 12
    private static let maxUtterance: TimeInterval = 45
    private static let maxBacklogFrames: AVAudioFramePosition = 48_000 * 60

    init(meter: LevelMeter, onSpeechEnded: @escaping @Sendable () -> Void) {
        self.meter = meter
        self.onSpeechEnded = onSpeechEnded
    }

    /// Connects the recognizer and feeds it everything captured so far.
    func attach(_ feeder: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.feeder = feeder
        for buffer in backlog { feeder(buffer) }
        backlog.removeAll()
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let done = finished
        lock.unlock()
        guard !done else { return }

        meterAndDetect(buffer)

        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if let feeder {
            feeder(buffer)
        } else if let copy = Self.copy(buffer) {
            let frames = backlog.reduce(AVAudioFramePosition(0)) { $0 + AVAudioFramePosition($1.frameLength) }
            if frames < Self.maxBacklogFrames { backlog.append(copy) }
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        finished = true
        feeder = nil
        backlog.removeAll()
    }

    private func meterAndDetect(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let rate = Float(buffer.format.sampleRate)

        // Three voice bands from one-pole filters: below ~300 Hz, 300–2000 Hz, above 2000 Hz.
        let aLow = 1 - exp(-2 * Float.pi * 300 / rate)
        let aMid = 1 - exp(-2 * Float.pi * 2000 / rate)
        var sumLow: Float = 0, sumMid: Float = 0, sumHigh: Float = 0
        for i in 0..<count {
            let x = samples[i]
            lowState += aLow * (x - lowState)
            midState += aMid * (x - midState)
            let mid = midState - lowState
            let high = x - midState
            sumLow += lowState * lowState
            sumMid += mid * mid
            sumHigh += high * high
        }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        let n = Float(count)

        // Gate below the room's noise floor, then scale into 0...1 for the glow.
        let gate = max(0.008, noiseFloor * 2.2)
        func shape(_ value: Float, gain: Float) -> Float { min(1, max(0, value - gate) * gain) }
        meter.set(.init(level: shape(rms, gain: 9),
                        low: shape((sumLow / n).squareRoot(), gain: 10),
                        mid: shape((sumMid / n).squareRoot(), gain: 14),
                        high: shape((sumHigh / n).squareRoot(), gain: 22)))

        // Track the noise floor slowly while quiet, so a loud room doesn't count as speech.
        let now = Date()
        if rms < gate {
            noiseFloor += (rms - noiseFloor) * 0.05
        }
        if rms > gate * 1.6 {
            loudBuffers += 1
            if loudBuffers >= 3 { speechStarted = true }
            lastLoud = now
        } else {
            loudBuffers = 0
        }

        let pausedAfterSpeech = speechStarted && now.timeIntervalSince(lastLoud) > Self.endPause
        let neverSpoke = !speechStarted && now.timeIntervalSince(started) > Self.noSpeechTimeout
        let tooLong = now.timeIntervalSince(started) > Self.maxUtterance
        if (pausedAfterSpeech || neverSpoke || tooLong) && !endedReported {
            endedReported = true
            onSpeechEnded()
        }
    }

    /// The tap reuses its buffers, so kept audio must be copied.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let destination = copy.floatChannelData else { return nil }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for channel in 0..<(buffer.format.isInterleaved ? 1 : channels) {
            let samples = buffer.format.isInterleaved ? frames * channels : frames
            destination[channel].update(from: source[channel], count: samples)
        }
        return copy
    }
}
