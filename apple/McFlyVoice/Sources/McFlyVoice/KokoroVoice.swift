import Foundation
import KokoroG2P
import KokoroPipeline
#if os(iOS)
import os
#endif

/// McFly's voice: Kokoro-82M (Apache-2.0) on Core ML, the voice the display and the web
/// speak with, here inside the app, so it needs no download or connection. Taken from
/// Homestead (github.com/rmantilla13/homestead), where it was built.
///
/// English only. Text should already be written for speech (McFlyKit's `SpokenText`):
/// this turns words into phonemes with a pronunciation lexicon (plus a small model for words
/// the lexicon lacks), then phonemes into 24 kHz audio.
public final class KokoroVoice: @unchecked Sendable {
    /// The voices bundled with the app.
    public enum Speaker: String, CaseIterable, Identifiable, Sendable {
        case heart = "af_heart"
        case bella = "af_bella"
        case michael = "am_michael"
        case fenrir = "am_fenrir"

        public var id: String { rawValue }
        public var name: String {
            switch self {
            case .heart: "Heart"
            case .bella: "Bella"
            case .michael: "Michael"
            case .fenrir: "Fenrir"
            }
        }
    }

    public static let sampleRate = Double(PipelineConstants.sampleRate)
    /// The model files' revision; part of the compiled-model cache's name, so updated
    /// models never reuse stale compiled copies.
    public static let revision = "9183566f"

    /// The bundled model files, if this build includes them (`McFlyVoice/scripts/fetch-kokoro.sh`).
    public static var resourcesURL: URL? {
        guard let url = Bundle.module.url(forResource: "Kokoro", withExtension: nil),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("coreml").path)
        else { return nil }
        return url
    }

    /// Longest phoneme run synthesized in one pass (at most about 8 seconds of speech);
    /// longer text is split at a pause.
    ///
    /// Short passes and few shapes keep memory flat. The GPU runtime keeps a compiled
    /// program and its buffers for every input shape the generator sees and lets them go
    /// only slowly, so a generator rounded to many lengths grew past 4 GB while reading one
    /// article aloud. So every pass fits the 10 s bucket and runs the generator at one of
    /// two lengths (reading the handbook stays near 0.6 GB); the rare pass that would still
    /// run longer is split again rather than cut off.
    static let maxTokens = 120
    /// Bucket sizes (seconds) for the F0 and decoder stages: the 15 s and 30 s buckets
    /// are never needed for passes this short, so their models are never opened.
    static let buckets = [3, 7, 10]
    /// The generator's two lengths (seconds). Nearly every pass fits the first.
    static let generatorSeconds: [Double] = [8, 10]
    /// Largest duration model used: `maxTokens` plus the start and end markers fit in 128.
    static let durationTokens = 128

    private let pipeline: KokoroPipeline
    private let frontend: KokoroEnglishFrontend
    private let vocab: [Character: Int32]
    private let voicesDirectory: URL
    /// Per-voice style tables, loaded on first use. Only touched on `queue`.
    private var tables: [Speaker: [Float]] = [:]
    /// Core ML work is synchronous and heavy; it runs here, one request at a time, off the
    /// Swift concurrency pool.
    private let queue = DispatchQueue(label: "McFly.KokoroVoice", qos: .userInitiated)

    /// Loads the voice. The first launch compiles the models into `cacheDirectory`, which
    /// takes several seconds; later launches reuse the compiled copies.
    public static func load(cacheDirectory: URL?) async throws -> KokoroVoice {
        guard let root = resourcesURL else { throw KokoroVoiceError.notBundled }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try KokoroVoice(root: root, cacheDirectory: cacheDirectory) })
            }
        }
    }

    private init(root: URL, cacheDirectory: URL?) throws {
        struct HnsfWeights: Decodable {
            let linear_weights: [Float]
            let linear_bias: Float
        }
        let hnsf = try JSONDecoder().decode(
            HnsfWeights.self, from: Data(contentsOf: root.appendingPathComponent("runtime/hnsf_weights.json")))
        pipeline = try KokoroPipeline(
            modelsDirectory: root.appendingPathComponent("coreml"),
            buckets: Self.buckets,
            linearWeights: hnsf.linear_weights,
            linearBias: hnsf.linear_bias,
            compiledModelCache: cacheDirectory,
            maxDurationTokenLength: Self.durationTokens,
            generatorSeconds: Self.generatorSeconds)
        frontend = try KokoroEnglishFrontend(assetsDirectory: root.appendingPathComponent("g2p"))
        vocab = try Self.loadVocab(root.appendingPathComponent("runtime/kokoro-vocab.json"))
        voicesDirectory = root.appendingPathComponent("voices")
    }

    /// `text` (a sentence or short paragraph) spoken by `speaker`, as 24 kHz mono samples.
    public func synthesize(_ text: String, speaker: Speaker = .heart, speed: Float = 1) async throws -> [Float] {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty else { throw KokoroVoiceError.nothingToSay }
        let phonemes = try await frontend.phonemes(for: words)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.render(phonemes, speaker: speaker, speed: speed) })
            }
        }
    }

    /// Loads the models for short sentences, so the first real answer starts quickly.
    public func prewarm() async throws {
        _ = try await synthesize("Ready.")
    }

    // MARK: Rendering (on `queue`)

    private func render(_ phonemes: String, speaker: Speaker, speed: Float) throws -> [Float] {
        let tokens = phonemes.compactMap { vocab[$0] }
        guard tokens.contains(where: { $0 != KokoroVocabulary.whitespaceTokenId }) else {
            throw KokoroVoiceError.nothingToSay
        }
        if tokens.count > Self.maxTokens, let halves = Self.split(phonemes) {
            return try render(halves, speaker: speaker, speed: speed)
        }
        let framed = [KokoroVocabulary.bosEosTokenId] + tokens + [KokoroVocabulary.bosEosTokenId]
        let length = PipelineConstants.durationTokenSizes.first { $0 >= framed.count } ?? framed.count
        let padding = max(0, length - framed.count)
        releaseGeneratorIfMemoryIsLow()
        do {
            let result = try pipeline.synthesize(
                inputIds: framed + Array(repeating: KokoroVocabulary.bosEosTokenId, count: padding),
                attentionMask: Array(repeating: 1, count: framed.count) + Array(repeating: 0, count: padding),
                refS: try style(for: speaker, phonemeCount: phonemes.utf16.count),
                speed: speed)
            return result.audio
        } catch let error where Self.isTooLong(error) {
            // Slow speech can run past the longest bucket: say it in two parts rather than
            // lose its end.
            guard let halves = Self.split(phonemes) else { throw error }
            return try render(halves, speaker: speaker, speed: speed)
        }
    }

    private func render(_ halves: (String, String), speaker: Speaker, speed: Float) throws -> [Float] {
        // A short pause where the text was split, as at a comma.
        let pause = [Float](repeating: 0, count: Int(Self.sampleRate * 0.12))
        return try render(halves.0, speaker: speaker, speed: speed) + pause + render(halves.1, speaker: speaker, speed: speed)
    }

    /// Whether synthesis failed only because the pass would last longer than the models allow.
    static func isTooLong(_ error: Error) -> Bool {
        switch error {
        case PipelineError.utteranceTooLong, PipelineError.inputTooLong, PipelineValidationError.wouldTruncate: true
        default: false
        }
    }

    /// Below this much headroom before iOS would end the app, the generator (most of the
    /// voice's GPU memory) is closed before the next pass and reopened from the compiled
    /// cache, which costs a fraction of a second. The Mac has no such limit.
    static let lowMemoryBytes = 400 * 1_048_576

    private func releaseGeneratorIfMemoryIsLow() {
        #if os(iOS)
        let available = os_proc_available_memory()   // 0 where there's no limit (Simulator)
        if available > 0, available < Self.lowMemoryBytes { pipeline.releaseGenerator() }
        #endif
    }

    /// The voice's style vector for an utterance of `phonemeCount` phonemes. Each voice file
    /// holds one 256-value row per utterance length.
    private func style(for speaker: Speaker, phonemeCount: Int) throws -> [Float] {
        let dimension = PipelineConstants.voiceEmbeddingDim
        let rows: [Float]
        if let cached = tables[speaker] {
            rows = cached
        } else {
            let data = try Data(contentsOf: voicesDirectory.appendingPathComponent("\(speaker.rawValue).bin"))
            guard !data.isEmpty, data.count % (dimension * 4) == 0 else { throw KokoroVoiceError.badVoiceFile(speaker.rawValue) }
            rows = data.withUnsafeBytes { raw in
                (0..<data.count / 4).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
            }
            tables[speaker] = rows
        }
        let row = max(0, min(rows.count / dimension - 1, phonemeCount - 1))
        return Array(rows[(row * dimension)..<((row + 1) * dimension)])
    }

    /// Splits a long phoneme string at the pause (sentence end, comma, then space) closest to
    /// its middle, or, for one very long word, at the middle itself.
    static func split(_ phonemes: String) -> (String, String)? {
        let characters = Array(phonemes)
        let middle = characters.count / 2
        for marks in [Set<Character>(".!?;:"), Set<Character>(",—…"), Set<Character>(" ")] {
            let candidates = characters.indices.filter { marks.contains(characters[$0]) && $0 > 0 && $0 < characters.count - 1 }
            if let best = candidates.min(by: { abs($0 - middle) < abs($1 - middle) }) {
                let first = String(characters[...best]).trimmingCharacters(in: .whitespaces)
                let second = String(characters[(best + 1)...]).trimmingCharacters(in: .whitespaces)
                if !first.isEmpty, !second.isEmpty { return (first, second) }
            }
        }
        guard characters.count >= 2 else { return nil }
        return (String(characters[..<middle]), String(characters[middle...]))
    }

    private static func loadVocab(_ url: URL) throws -> [Character: Int32] {
        struct File: Decodable { let vocab: [String: Int32] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        var table: [Character: Int32] = [:]
        for (symbol, id) in file.vocab where symbol.count == 1 {
            table[symbol.first!] = id
        }
        return table
    }

    /// 16-bit mono WAV of `samples`, for saving or sharing speech.
    public static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let rate = UInt32(sampleRate)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(rate); append(rate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(samples.count * 2))
        for sample in samples { append(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
        return data
    }
}

public enum KokoroVoiceError: Error, LocalizedError {
    case notBundled
    case nothingToSay
    case badVoiceFile(String)

    public var errorDescription: String? {
        switch self {
        case .notBundled: "The built-in voice isn't included in this build."
        case .nothingToSay: "There's nothing to say."
        case .badVoiceFile(let name): "The voice file \(name) is damaged."
        }
    }
}
