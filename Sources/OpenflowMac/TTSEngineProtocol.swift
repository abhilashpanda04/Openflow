import Foundation

public struct TTSVoice: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: VoiceQuality
    public let gender: VoiceGender

    public enum VoiceQuality: String, Codable {
        case standard
        case enhanced
        case premium
    }

    public enum VoiceGender: String, Codable {
        case unspecified
        case female
        case male
    }

    public init(
        id: String,
        name: String,
        language: String,
        quality: VoiceQuality = .standard,
        gender: VoiceGender = .unspecified
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
        self.gender = gender
    }

    public var displayName: String {
        var badges: [String] = []
        if quality == .premium {
            badges.append("Premium")
        } else if quality == .enhanced {
            badges.append("Enhanced")
        }
        let badgeStr = badges.isEmpty ? "" : " (\(badges.joined(separator: ", ")))"
        return "\(name)\(badgeStr) [\(language)]"
    }
}

public protocol TTSEngineProtocol: AnyObject {
    var availableVoices: [TTSVoice] { get }
    var currentVoice: TTSVoice? { get set }
    var playbackRate: Float { get set } // 0.5 ... 2.0
    var pitchMultiplier: Float { get set } // 0.5 ... 1.5
    var volume: Float { get set } // 0.0 ... 1.0

    func speak(
        sentence: String,
        onWord: @escaping (NSRange) -> Void,
        onCompletion: @escaping () -> Void
    )
    func pause()
    func resume()
    func stop()
}
