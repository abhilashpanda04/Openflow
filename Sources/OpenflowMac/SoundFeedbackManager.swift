import AppKit
import Foundation

// MARK: - Feedback Sound Cue
public enum FeedbackSoundCue {
    case start
    case finish
    case cancel
}

// MARK: - Sound Feedback Manager
public final class SoundFeedbackManager {
    public static let shared = SoundFeedbackManager()

    private let siriSoundsPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri"

    public var isSoundEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: UserSettingKey.playFeedbackSounds) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: UserSettingKey.playFeedbackSounds)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserSettingKey.playFeedbackSounds)
        }
    }

    public init() {}

    public func play(_ cue: FeedbackSoundCue) {
        guard isSoundEnabled else { return }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let sound = self.soundForCue(cue)
            sound?.play()
        }
    }

    func soundForCue(_ cue: FeedbackSoundCue) -> NSSound? {
        let (filename, fallbackName): (String, String) = {
            switch cue {
            case .start:
                return ("jbl_begin.caf", "Pop")
            case .finish:
                return ("jbl_confirm.caf", "Bottle")
            case .cancel:
                return ("jbl_cancel.caf", "Tink")
            }
        }()

        let fullPath = "\(siriSoundsPath)/\(filename)"
        if FileManager.default.fileExists(atPath: fullPath),
           let sound = NSSound(contentsOfFile: fullPath, byReference: true) {
            return sound
        }

        return NSSound(named: fallbackName)
    }
}
