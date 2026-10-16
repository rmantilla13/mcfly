import Foundation
import Testing
@testable import McFlyVoice

@Suite struct KokoroVoiceTests {
    @Test func splitsLongPhonemesAtTheMiddlePause() throws {
        let (first, second) = try #require(KokoroVoice.split("ðɪs ɪz wʌn, ænd ðɪs ɪz tˈu. ðˈɛn θɹˈi"))
        #expect(first == "ðɪs ɪz wʌn, ænd ðɪs ɪz tˈu.")
        #expect(second == "ðˈɛn θɹˈi")
        #expect(KokoroVoice.split("ɑ") == nil)
    }

    @Test(.enabled(if: KokoroVoice.resourcesURL != nil, "Run scripts/fetch-kokoro.sh first"))
    func speaksASentence() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("McFlyVoiceTests-\(KokoroVoice.revision)")
        let voice = try await KokoroVoice.load(cacheDirectory: cache)
        let samples = try await voice.synthesize("Boil water for one minute, then let it cool.")
        let seconds = Double(samples.count) / KokoroVoice.sampleRate
        #expect((1.5...6).contains(seconds))
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        #expect(rms > 0.01)
    }
}
