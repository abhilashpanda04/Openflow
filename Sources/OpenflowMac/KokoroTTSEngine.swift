import Foundation
import AVFoundation
import Combine
import FluidAudio

public final class KokoroTTSEngine: NSObject, TTSEngineProtocol, AVAudioPlayerDelegate, ObservableObject, @unchecked Sendable {
    public static let shared = KokoroTTSEngine()

    private var manager: KokoroAneManager?
    private var audioPlayer: AVAudioPlayer?
    private var isInitializing = false
    private var onCompletionCallback: (() -> Void)?
    private var onWordCallback: ((NSRange) -> Void)?
    private var wordTimer: Timer?

    @Published public var isModelDownloaded: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var statusMessage: String = ""

    public var playbackRate: Float = 1.0 // 0.5 to 2.0
    public var pitchMultiplier: Float = 1.0
    public var volume: Float = 1.0

    public var currentVoice: TTSVoice?

    public static var isModelLocallyCached: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let anePath = home.appendingPathComponent(".cache/fluidaudio/Models/kokoro-82m-coreml/ANE/af_heart.bin").path
        let g2pPath = home.appendingPathComponent(".cache/fluidaudio/Models/kokoro/G2PDecoder.mlmodelc").path
        return FileManager.default.fileExists(atPath: anePath) && FileManager.default.fileExists(atPath: g2pPath)
    }

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
        self.isModelDownloaded = Self.isModelLocallyCached
        if isModelDownloaded {
            self.statusMessage = "Ready on Apple Neural Engine"
        }
    }

    public func downloadModel() {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.15
        statusMessage = "Starting download from Hugging Face..."

        Task { [weak self] in
            guard let self = self else { return }
            do {
                await MainActor.run {
                    self.downloadProgress = 0.45
                    self.statusMessage = "Downloading Neural Engine weights (150 MB)..."
                }
                _ = try await self.ensureInitialized()
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadProgress = 1.0
                    self.isModelDownloaded = true
                    self.statusMessage = "Kokoro model ready on Apple Neural Engine"
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.statusMessage = "Download failed: \(error.localizedDescription)"
                }
            }
        }
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
                print(">>> Kokoro initialized successfully. Synthesizing...")
                let wavData = try await mgr.synthesize(text: sentence, voice: rawVoice, speed: speed)
                print(">>> Kokoro synthesized \(wavData.count) bytes")

                await MainActor.run {
                    do {
                        let player = try AVAudioPlayer(data: wavData)
                        player.delegate = self
                        player.volume = self.volume
                        player.prepareToPlay()
                        let started = player.play()
                        print(">>> Kokoro AVAudioPlayer started: \(started), duration: \(player.duration)")
                        self.audioPlayer = player

                        self.startWordProgressSimulation(sentence: sentence, duration: player.duration)
                    } catch {
                        print(">>> Kokoro AVAudioPlayer error: \(error)")
                        onCompletion()
                    }
                }
            } catch {
                print(">>> Kokoro synthesis error: \(error)")
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

    public var isLoadedInMemory: Bool {
        manager != nil
    }

    public func offload() {
        stop()
        manager = nil
        isInitializing = false
    }

    public func deleteModel() {
        offload()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let aneFolder = home.appendingPathComponent(".cache/fluidaudio/Models/kokoro-82m-coreml")
        let g2pFolder = home.appendingPathComponent(".cache/fluidaudio/Models/kokoro")
        try? FileManager.default.removeItem(at: aneFolder)
        try? FileManager.default.removeItem(at: g2pFolder)
        DispatchQueue.main.async {
            self.isModelDownloaded = false
            self.downloadProgress = 0.0
            self.statusMessage = "Model deleted. Click download to fetch."
        }
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
