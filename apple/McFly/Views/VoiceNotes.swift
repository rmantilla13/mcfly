import AVFoundation
import McFlyKit
import Observation
import SwiftUI

/// Records a voice note for home: 16 kHz mono 16-bit WAV, as the display
/// records them and plays them, for at most 30 seconds (then it stops
/// itself and `onLimit` sends it).
@MainActor
@Observable
final class VoiceNoteRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// 0…1, from the recorder's meter.
    private(set) var level: Double = 0
    @ObservationIgnored var onLimit: (() -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcfly-voice-note.wav")

    func start() async throws {
        guard !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw McFlyError.message("McFly needs the microphone for voice notes: allow it in Settings.")
        }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        #endif
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: VoiceNoteAudio.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: Double(Message.maxVoiceNoteMs) / 1000) else {
            throw McFlyError.message("Couldn't start recording.")
        }
        self.recorder = recorder
        isRecording = true
        elapsed = 0
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let recorder = self.recorder else { return }
                if !recorder.isRecording {
                    // The 30 s ran out.
                    self.onLimit?()
                    return
                }
                recorder.updateMeters()
                let db = Double(recorder.averagePower(forChannel: 0))
                self.level = max(0, min(1, (db + 60) / 60))
                self.elapsed = recorder.currentTime
            }
        }
    }

    /// Stops and gives the WAV and its length; nil when there's nothing to send.
    func finish() -> (wav: Data, ms: Int)? {
        guard let recorder else { return nil }
        let measured = Int(recorder.currentTime * 1000)
        recorder.stop()
        reset()
        guard let wav = try? Data(contentsOf: url), !wav.isEmpty else { return nil }
        try? FileManager.default.removeItem(at: url)
        let ms = VoiceNoteAudio.milliseconds(of: wav) ?? measured
        return (wav, min(ms, Message.maxVoiceNoteMs))
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        reset()
    }

    private func reset() {
        ticker?.cancel()
        ticker = nil
        recorder = nil
        isRecording = false
        level = 0
    }
}

/// Plays voice notes, one at a time.
@MainActor
@Observable
final class VoiceNotePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var playingId: UUID?
    @ObservationIgnored private var player: AVAudioPlayer?

    func play(_ wav: Data, id: UUID) throws {
        stop()
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
        let player = try AVAudioPlayer(data: wav)
        player.delegate = self
        player.play()
        self.player = player
        playingId = id
    }

    func stop() {
        player?.stop()
        player = nil
        playingId = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.stop() }
        }
    }
}

/// A voice note in a bubble: ▶ (■ while it plays) and how long it is.
struct VoiceNoteRow: View {
    let label: String
    let playing: Bool
    let mine: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background((mine ? Color.white.opacity(0.22) : Theme.accentSoft), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Voice note").font(.subheadline.weight(.semibold))
                    Text(label).font(.caption.monospacedDigit()).opacity(0.8)
                }
            }
            .foregroundStyle(mine ? Theme.accentInk : Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "Stop the voice note" : "Play the voice note, \(label)")
    }
}
