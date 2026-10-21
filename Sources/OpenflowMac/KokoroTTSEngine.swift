import Foundation
import AVFoundation
import FluidAudio

public final class KokoroTTSEngine: NSObject, TTSEngineProtocol, AVAudioPlayerDelegate, @unchecked Sendable {
    public static let shared = KokoroTTSEngine()

    private var manager: KokoroAneManager?
    private var audioPlayer: AVAudioPlayer?
    private var isInitializing = false
    private var onCompletionCallback: (() -> Void)?
    private var onWordCallback: ((NSRange) -> Void)?
    private var wordTimer: Timer?

    public var playbackRate: Float = 1.0 // 0.5 to 2.0
    public var pitchMultiplier: Float = 1.0
    public var volume: Float = 1.0

    public var currentVoice: TTSVoice?

    public static let curatedKokoroVoices: [TTSVoice] = [
        TTSVoice(id: "kokoro:af_heart", name: "Heart (Narrator)", language: "en-US", quality: .premium, gender: .female),
        TTSVoice(id: "kokoro:af_bella", name: "Bella (Warm & Expressive)", language: "en-US", quality: .premium, gender: .female),
        TTSVoice(id: "kokoro:af_sarah", name: "Sarah (Soft & Natural)", language: "en-US", quality: .premium, gender: .female),
        TTSVoice(id: "kokoro:af_sky", name: "Sky (Bright & Clear)", language: "en-US", quality: .premium, gender: .female),
        TTSVoice(id: "kokoro:af_nicole", name: "Nicole (Energetic)", language: "en-US", quality: .premium, gender: .female),
        TTSVoice(id: "kokoro:am_adam", name: "Adam (Deep Storyteller)", language: "en-US", quality: .premium, gender: .male),
        TTSVoice(id: "kokoro:am_michael", name: "Michael (Conversational)", language: "en-US", quality: .premium, gender: .male),
        TTSVoice(id: "kokoro:am_echo", name: "Echo (Smooth & Calm)", language: "en-US", quality: .premium, gender: .male),
        TTSVoice(id: "kokoro:am_eric", name: "Eric (Warm Baritone)", language: "en-US", quality: .premium, gender: .male),
        TTSVoice(id: "kokoro:bf_emma", name: "Emma (British Classic)", language: "en-GB", quality: .premium, gender: .female),
        TTSVoice(id: "kokoro:bf_isabella", name: "Isabella (British Poetic)", language: "en-GB", quality: .premium, gender: .female),
        TTSVoice(id: "kokoro:bf_alice", name: "Alice (British Expressive)", language: "en-GB", quality: .premium, gender: .female),
        TTSVoice(id: "kokoro:bm_george", name: "George (British Warm)", language: "en-GB", quality: .premium, gender: .male),
        TTSVoice(id: "kokoro:bm_lewis", name: "Lewis (British Storyteller)", language: "en-GB", quality: .premium, gender: .male),
        TTSVoice(id: "kokoro:bm_daniel", name: "Daniel (British Deep)", language: "en-GB", quality: .premium, gender: .male)
    ]

    public override init() {
        super.init()
        self.currentVoice = Self.curatedKokoroVoices.first
    }

    public var availableVoices: [TTSVoice] {
        Self.curatedKokoroVoices
    }

    private func ensureInitialized() async throws -> KokoroAneManager {
        if let mgr = manager {
            return mgr
        }
        let voiceId = rawVoiceName(from: currentVoice?.id ?? "af_heart")
        let mgr = KokoroAneManager(defaultVoice: voiceId)
        try await mgr.initialize()
        self.manager = mgr
        return mgr
    }

    private func rawVoiceName(from identifier: String) -> String {
        if identifier.hasPrefix("kokoro:") {
            return String(identifier.dropFirst("kokoro:".count))
        }
        return identifier
    }

    public func speak(
        sentence: String,
        onWord: @escaping (NSRange) -> Void,
        onCompletion: @escaping () -> Void
    ) {
        stop()

        self.onWordCallback = onWord
        self.onCompletionCallback = onCompletion

        let rawVoice = rawVoiceName(from: currentVoice?.id ?? "af_heart")
        let speed = min(max(playbackRate, 0.5), 2.0)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let mgr = try await self.ensureInitialized()
                let wavData = try await mgr.synthesize(text: sentence, voice: rawVoice, speed: speed)

                await MainActor.run {
                    do {
                        let player = try AVAudioPlayer(data: wavData)
                        player.delegate = self
                        player.volume = self.volume
                        player.prepareToPlay()
                        player.play()
                        self.audioPlayer = player

                        self.startWordProgressSimulation(sentence: sentence, duration: player.duration)
                    } catch {
                        onCompletion()
                    }
                }
            } catch {
                await MainActor.run {
                    onCompletion()
                }
            }
        }
    }

    private func startWordProgressSimulation(sentence: String, duration: TimeInterval) {
        stopWordProgressSimulation()
        guard duration > 0.1 else { return }

        let words = sentence.split(separator: " ")
        guard !words.isEmpty else { return }

        let interval = duration / Double(words.count)
        var wordIndex = 0

        wordTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self, wordIndex < words.count else {
                timer.invalidate()
                return
            }
            let word = String(words[wordIndex])
            if let range = sentence.range(of: word) {
                let nsRange = NSRange(range, in: sentence)
                self.onWordCallback?(nsRange)
            }
            wordIndex += 1
        }
    }

    private func stopWordProgressSimulation() {
        wordTimer?.invalidate()
        wordTimer = nil
    }

    public func pause() {
        audioPlayer?.pause()
        wordTimer?.invalidate()
    }

    public func resume() {
        audioPlayer?.play()
    }

    public func stop() {
        stopWordProgressSimulation()
        audioPlayer?.stop()
        audioPlayer = nil
        onCompletionCallback = nil
        onWordCallback = nil
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopWordProgressSimulation()
        DispatchQueue.main.async { [weak self] in
            let callback = self?.onCompletionCallback
            self?.onCompletionCallback = nil
            self?.onWordCallback = nil
            callback?()
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        stopWordProgressSimulation()
        DispatchQueue.main.async { [weak self] in
            let callback = self?.onCompletionCallback
            self?.onCompletionCallback = nil
            self?.onWordCallback = nil
            callback?()
        }
    }
}
