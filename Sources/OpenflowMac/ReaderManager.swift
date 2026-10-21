import Foundation
import Combine
import AppKit

public enum ReaderPlaybackState: String, Equatable {
    case idle
    case playing
    case paused
    case stopped
}

public enum TTSEngineKind: String, CaseIterable, Identifiable, Codable {
    case kokoro = "Kokoro-82M AI Studio"
    case appleNative = "Apple Neural / Siri"

    public var id: String { rawValue }
}

public final class ReaderManager: ObservableObject {
    public static let shared = ReaderManager()

    private var nativeEngine: TTSEngineProtocol
    private var kokoroEngine: TTSEngineProtocol

    @Published public var engineKind: TTSEngineKind = .kokoro {
        didSet {
            let oldRate = playbackRate
            stop()
            engine.playbackRate = oldRate
            self.currentVoice = engine.currentVoice
        }
    }

    public var engine: TTSEngineProtocol {
        switch engineKind {
        case .kokoro:
            return kokoroEngine
        case .appleNative:
            return nativeEngine
        }
    }

    @Published public var state: ReaderPlaybackState = .idle
    @Published public var isSynthesizing: Bool = false
    @Published public var sentences: [TextSentence] = []
    @Published public var currentSentenceIndex: Int = 0
    @Published public var currentWordRange: NSRange? = nil
    @Published public var playbackRate: Float = 1.0 {
        didSet {
            engine.playbackRate = playbackRate
        }
    }
    @Published public var currentVoice: TTSVoice? {
        didSet {
            engine.currentVoice = currentVoice
        }
    }
    @Published public var fullText: String = ""

    public init(engine: TTSEngineProtocol? = nil) {
        if let custom = engine {
            self.nativeEngine = custom
            self.kokoroEngine = custom
        } else {
            self.nativeEngine = NativeTTSEngine()
            self.kokoroEngine = KokoroTTSEngine.shared
        }
        self.currentVoice = self.engine.currentVoice
        self.playbackRate = self.engine.playbackRate
    }

    public var currentSentence: TextSentence? {
        guard currentSentenceIndex >= 0 && currentSentenceIndex < sentences.count else { return nil }
        return sentences[currentSentenceIndex]
    }

    public var progress: Double {
        guard !sentences.isEmpty else { return 0.0 }
        return Double(currentSentenceIndex + 1) / Double(sentences.count)
    }

    public var availableVoices: [TTSVoice] {
        engine.availableVoices
    }

    // MARK: - Actions

    public func startReading(text: String, startIndex: Int = 0) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()

        self.fullText = text
        self.sentences = TextChunker.splitIntoSentences(text)
        guard !sentences.isEmpty else { return }

        let targetIndex = min(max(startIndex, 0), sentences.count - 1)
        playSentence(index: targetIndex)
    }

    public func readClipboard() {
        if let clipboardText = NSPasteboard.general.string(forType: .string) {
            startReading(text: clipboardText)
        }
    }

    public func playSentence(index: Int) {
        guard index >= 0 && index < sentences.count else {
            stop()
            return
        }

        currentSentenceIndex = index
        state = .playing
        isSynthesizing = true
        currentWordRange = nil

        let sentence = sentences[index]
        engine.speak(sentence: sentence.text, onWord: { [weak self] range in
            guard let self = self, self.state == .playing else { return }
            self.isSynthesizing = false
            self.currentWordRange = range
        }, onCompletion: { [weak self] in
            guard let self = self, self.state == .playing else { return }
            self.isSynthesizing = false
            if self.currentSentenceIndex + 1 < self.sentences.count {
                self.playSentence(index: self.currentSentenceIndex + 1)
            } else {
                self.state = .idle
                self.currentWordRange = nil
            }
        })
    }

    public func pause() {
        guard state == .playing else { return }
        engine.pause()
        state = .paused
    }

    public func resume() {
        if state == .paused {
            engine.resume()
            state = .playing
        } else if state == .idle || state == .stopped {
            if !sentences.isEmpty {
                playSentence(index: currentSentenceIndex)
            }
        }
    }

    public func togglePlayPause() {
        if state == .playing {
            pause()
        } else {
            resume()
        }
    }

    public func stop() {
        engine.stop()
        state = .stopped
        isSynthesizing = false
        currentWordRange = nil
    }

    public func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
    }

    public func setVoice(_ voice: TTSVoice) {
        self.currentVoice = voice
    }

    public func skipForward() {
        guard !sentences.isEmpty else { return }
        let nextIndex = min(currentSentenceIndex + 1, sentences.count - 1)
        if nextIndex != currentSentenceIndex {
            playSentence(index: nextIndex)
        }
    }

    public func skipBackward() {
        guard !sentences.isEmpty else { return }
        let prevIndex = max(currentSentenceIndex - 1, 0)
        playSentence(index: prevIndex)
    }

    public func seek(to index: Int) {
        guard !sentences.isEmpty else { return }
        let target = min(max(index, 0), sentences.count - 1)
        playSentence(index: target)
    }
}
