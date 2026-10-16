import Foundation
import McFlyVoice
import os
#if canImport(UIKit)
import UIKit
#endif

/// Owns McFly's Kokoro voice (see `KokoroVoice`): loads it when speech is first needed,
/// shares it between voice mode and Settings' sample, and lets it go when memory runs low.
/// From Homestead's.
@MainActor
final class BuiltInVoice {
    static let shared = BuiltInVoice()

    /// Whether this build includes the voice files (`McFlyVoice/scripts/fetch-kokoro.sh`).
    nonisolated static var isBundled: Bool { KokoroVoice.resourcesURL != nil }

    private var loading: Task<KokoroVoice?, Never>?
    /// Speakers currently playing; the voice is never released under them.
    private var inUse = 0
    private let log = Logger(subsystem: "bot.mcfly", category: "voice")

    /// Compiled models live here between launches; the first launch fills it (several seconds).
    nonisolated private static var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Kokoro-\(KokoroVoice.revision)", isDirectory: true)
    }

    private init() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BuiltInVoice.shared.releaseIfIdle() }
        }
        #endif
    }

    /// The loaded voice, loading it first if needed; nil if it isn't bundled or won't load
    /// here (the models need iOS 18 or macOS 15).
    func voice() async -> KokoroVoice? {
        if loading == nil {
            loading = Task.detached(priority: .userInitiated) { [log] in
                do {
                    let voice = try await KokoroVoice.load(cacheDirectory: Self.cacheDirectory)
                    try await voice.prewarm()
                    log.info("Kokoro voice ready")
                    return voice
                } catch {
                    log.error("Kokoro voice unavailable: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        }
        return await loading?.value
    }

    /// Starts loading now, so the first answer doesn't wait for the models to compile
    /// (several seconds the first time after an install, then a moment).
    func prepare() {
        guard Self.isBundled, loading == nil else { return }
        Task { _ = await voice() }
    }

    func beginUse() { inUse += 1 }
    func endUse() { inUse = max(0, inUse - 1) }

    /// Frees the models (a few hundred MB) when nothing is speaking; they reload on demand.
    func releaseIfIdle() {
        guard inUse == 0, let current = loading else { return }
        // Only drop a finished load; one in progress is about to be used.
        Task {
            _ = await current.value
            if inUse == 0, loading == current { loading = nil }
        }
    }
}
