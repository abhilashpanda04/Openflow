import Foundation
import AVFoundation

public final class NativeTTSEngine: NSObject, TTSEngineProtocol, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    public var playbackRate: Float = 1.0 // 0.5 to 2.0
    public var pitchMultiplier: Float = 1.0 // 0.5 to 1.5
    public var volume: Float = 1.0 // 0.0 to 1.0

    public var currentVoice: TTSVoice?

    private var onWordCallback: ((NSRange) -> Void)?
    private var onCompletionCallback: (() -> Void)?

    public override init() {
        super.init()
        synthesizer.delegate = self
        selectDefaultVoice()
    }

    public var availableVoices: [TTSVoice] {
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"

        return systemVoices.map { voice in
            let quality: TTSVoice.VoiceQuality
            switch voice.quality {
            case .premium:
                quality = .premium
            case .enhanced:
                quality = .enhanced
            default:
                quality = .standard
            }

            let gender: TTSVoice.VoiceGender
            switch voice.gender {
            case .female:
                gender = .female
            case .male:
                gender = .male
            default:
                gender = .unspecified
            }

            return TTSVoice(
                id: voice.identifier,
                name: voice.name,
                language: voice.language,
                quality: quality,
                gender: gender
            )
        }.sorted { (v1, v2) -> Bool in
            let v1MatchesLang = v1.language.hasPrefix(currentLanguage)
            let v2MatchesLang = v2.language.hasPrefix(currentLanguage)
            if v1MatchesLang != v2MatchesLang {
                return v1MatchesLang
            }
            if v1.quality != v2.quality {
                return v1.quality.rawValue > v2.quality.rawValue
            }
            return v1.name < v2.name
        }
    }

    private func selectDefaultVoice() {
        let voices = availableVoices
        // Prefer enhanced or premium voice matching system language
        if let preferred = voices.first(where: { $0.quality == .premium }) ??
                           voices.first(where: { $0.quality == .enhanced }) ??
                           voices.first {
            currentVoice = preferred
        }
    }

    public func speak(
        sentence: String,
        onWord: @escaping (NSRange) -> Void,
        onCompletion: @escaping () -> Void
    ) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        self.onWordCallback = onWord
        self.onCompletionCallback = onCompletion

        let utterance = AVSpeechUtterance(string: sentence)
        
        // Map rate
        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        let mappedRate = min(max(baseRate * playbackRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.rate = mappedRate
        utterance.pitchMultiplier = min(max(pitchMultiplier, 0.5), 1.5)
        utterance.volume = min(max(volume, 0.0), 1.0)

        if let voiceId = currentVoice?.id, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: Locale.current.identifier) {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    public func pause() {
        if synthesizer.isSpeaking && !synthesizer.isPaused {
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }

    public func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }

    public func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        onWordCallback = nil
        onCompletionCallback = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.onWordCallback?(characterRange)
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            let callback = self?.onCompletionCallback
            self?.onCompletionCallback = nil
            self?.onWordCallback = nil
            callback?()
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.onCompletionCallback = nil
            self?.onWordCallback = nil
        }
    }
}
