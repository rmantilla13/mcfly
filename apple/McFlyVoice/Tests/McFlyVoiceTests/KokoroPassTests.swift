import CoreML
import Foundation
import Testing
@testable import McFlyVoice
@testable import KokoroPipeline

/// The voice's memory stays flat only while every pass fits a few fixed model shapes, and a
/// pass that doesn't fit must be split, never cut short.
@Suite struct KokoroPassTests {
    @Test func paddingNeverDropsRealFrames() throws {
        let source = try makeZeroArray3D(channels: 2, time: 5)
        #expect(try zeroPad3D(source: source, channels: 2, targetTime: 8).shape.last == 8)
        #expect(throws: PipelineValidationError.self) { try zeroPad3D(source: source, channels: 2, targetTime: 4) }
        // Bucket padding after the real frames may be cropped to a shorter length.
        #expect(try zeroPad3D(source: source, channels: 2, targetTime: 4, validTime: 3).shape.last == 4)
        #expect(throws: PipelineValidationError.self) { try zeroPad3D(source: source, channels: 2, targetTime: 4, validTime: 5) }
        #expect(throws: PipelineValidationError.self) {
            try zeroPad3D(sourceValues: Array(repeating: 1, count: 10), channels: 2, sourceTime: 5, targetTime: 4)
        }
    }

    @Test func generatorRunsAtTwoLengthsAtMost() throws {
        let lengths = KokoroVoice.generatorSeconds.map { Int($0 * PipelineConstants.f0FrameRate) }
        let accepted = 40...2400
        var used = Set<Int>()
        for frames in 1...800 {
            let length = try flexibleTimeAxis(realFrames: frames, accepted: accepted, granule: 40, lengths: lengths, stage: "generator")
            #expect(length >= frames)
            used.insert(length)
        }
        #expect(used == [640, 800])
        #expect(throws: PipelineError.self) {
            try flexibleTimeAxis(realFrames: 801, accepted: accepted, granule: 40, lengths: lengths, stage: "generator")
        }
        // Without a list, lengths round to the 0.5 s granule: one shape per half second.
        #expect(try flexibleTimeAxis(realFrames: 41, accepted: accepted, granule: 40, stage: "generator") == 80)
    }

    @Test func passesFitTheSmallModels() {
        // The longest pass plus its start and end markers fits the largest duration model
        // used, and the generator's longest length is the largest bucket.
        #expect(KokoroVoice.maxTokens + 2 <= KokoroVoice.durationTokens)
        #expect(KokoroVoice.generatorSeconds.count <= 2)
        #expect(KokoroVoice.generatorSeconds.max() == Double(KokoroVoice.buckets.max()!))
        #expect(!KokoroVoice.buckets.contains(15) && !KokoroVoice.buckets.contains(30))
    }

    @Test func tooLongPassesAreSplit() throws {
        #expect(KokoroVoice.isTooLong(PipelineError.utteranceTooLong(frames: 450, maxFrames: 400)))
        #expect(KokoroVoice.isTooLong(PipelineValidationError.wouldTruncate(operation: "zeroPad3D", sourceTime: 5, targetTime: 4)))
        #expect(!KokoroVoice.isTooLong(PipelineError.modelNotLoaded("generator")))
        // A single long word with no pause still splits.
        let (first, second) = try #require(KokoroVoice.split("ɑbɑbɑb"))
        #expect(first == "ɑbɑ" && second == "bɑb")
    }

    @Test(.enabled(if: KokoroVoice.resourcesURL != nil, "Run scripts/fetch-kokoro.sh first"))
    func slowSpeechKeepsItsEnd() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("McFlyVoiceTests-\(KokoroVoice.revision)")
        let voice = try await KokoroVoice.load(cacheDirectory: cache)
        // About 6.5 s at normal speed, so at half speed one pass would need 13 s: more than the
        // largest bucket. It must come out split, at full length, not cut off at 10 s.
        let text = "Press hard on the wound with both hands and keep pressing for ten full minutes without lifting to look."
        let normal = try await voice.synthesize(text)
        let slow = try await voice.synthesize(text, speed: 0.5)
        let ratio = Double(slow.count) / Double(normal.count)
        #expect(ratio > 1.6, "half speed came out \(ratio)× as long")
    }
}
