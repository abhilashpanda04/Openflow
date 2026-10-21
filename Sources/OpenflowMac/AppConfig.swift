import Foundation

enum TranscriptOutputMode: String, CaseIterable {
    case clipboard
    case activeApp = "active-app"
    case both
    case none

    var shouldCopyToClipboard: Bool {
        self == .clipboard || self == .both
    }

    var shouldPasteToActiveApp: Bool {
        self == .activeApp || self == .both
    }

    var displayName: String {
        switch self {
        case .clipboard:
            return "Clipboard"
        case .activeApp:
            return "Active App"
        case .both:
            return "Clipboard + Active App"
        case .none:
            return "None"
        }
    }

    static func parse(_ rawValue: String?) -> TranscriptOutputMode? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else {
            return nil
        }

        switch value {
        case "clipboard":
            return .clipboard
        case "active-app", "active_app", "activeapp", "focused-app", "focused_app":
            return .activeApp
        case "both":
            return .both
        case "none":
            return TranscriptOutputMode.none
        default:
            return nil
        }
    }
}

enum ASREngineType: String, CaseIterable {
    case localCoreML = "local-coreml"
    case appleSpeech = "apple-speech"
    case remoteServer = "remote-server"

    var displayName: String {
        switch self {
        case .localCoreML:
            return "Native CoreML (WhisperKit)"
        case .appleSpeech:
            return "Apple Speech (macOS Built-in / Offline)"
        case .remoteServer:
            return "Remote Server (HTTP Backend)"
        }
    }

    static func parse(_ rawValue: String?) -> ASREngineType? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else {
            return nil
        }
        switch value {
        case "local-coreml", "local_coreml", "local", "whisperkit", "coreml":
            return .localCoreML
        case "apple-speech", "apple_speech", "apple", "siri", "speech":
            return .appleSpeech
        case "remote-server", "remote_server", "remote", "server", "http":
            return .remoteServer
        default:
            return nil
        }
    }
}

public enum ModelFamily: String, CaseIterable, Identifiable {
    case all = "All"
    case parakeet = "Parakeet (Mac)"
    case qwen = "Qwen"
    case whisper = "Whisper"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .all: return "sparkles"
        case .parakeet: return "bolt.shield.fill"
        case .qwen: return "brain.head.profile"
        case .whisper: return "waveform"
        }
    }
}

public enum WhisperModelChoice: String, CaseIterable, Identifiable {
    // Parakeet Family (Mac Optimized)
    case parakeetTDT110M = "nvidia_parakeet-tdt-110m"
    case parakeetTDT06B = "nvidia_parakeet-tdt-0.6b"
    case parakeetCTC06B = "nvidia_parakeet-ctc-0.6b-multi"
    case parakeetRNNT11B = "nvidia_parakeet-rnnt-1.1b"

    // Qwen Family (Multilingual)
    case qwenAudio06B = "qwen_qwen3-asr-0.6b"
    case qwenAudio17B = "qwen_qwen3-asr-1.7b"

    // Whisper Family
    case tiny = "openai_whisper-tiny"
    case tinyEn = "openai_whisper-tiny.en"
    case base = "openai_whisper-base"
    case baseEn = "openai_whisper-base.en"
    case small = "openai_whisper-small"
    case smallEn = "openai_whisper-small.en"
    case distilLargeV3 = "distil-whisper_distil-large-v3"

    public var id: String { rawValue }

    public var sizeMB: Int {
        switch self {
        case .tiny, .tinyEn: return 75
        case .parakeetTDT110M: return 110
        case .base, .baseEn: return 140
        case .small, .smallEn: return 460
        case .parakeetTDT06B, .parakeetCTC06B: return 620
        case .qwenAudio06B: return 640
        case .distilLargeV3: return 756
        case .parakeetRNNT11B: return 1100
        case .qwenAudio17B: return 1700
        }
    }

    public var formattedSize: String {
        if sizeMB >= 1000 {
            let gb = Double(sizeMB) / 1000.0
            return "\(sizeMB) MB (~" + String(format: "%.1f", gb) + " GB)"
        } else {
            return "\(sizeMB) MB"
        }
    }

    public var languageCount: Int {
        switch self {
        case .tinyEn, .baseEn, .smallEn, .parakeetTDT110M, .parakeetTDT06B, .parakeetRNNT11B:
            return 1
        case .qwenAudio06B:
            return 10
        case .qwenAudio17B:
            return 15
        case .parakeetCTC06B:
            return 25
        case .tiny, .base, .small, .distilLargeV3:
            return 99
        }
    }

    public var languageSummary: String {
        switch self {
        case .tinyEn, .baseEn, .smallEn, .parakeetTDT110M, .parakeetTDT06B, .parakeetRNNT11B:
            return "1 Language (English)"
        case .qwenAudio06B:
            return "10 Languages (EN, ZH, JA, KO, FR...)"
        case .qwenAudio17B:
            return "15 Languages (Multilingual)"
        case .parakeetCTC06B:
            return "25 Languages (Multilingual)"
        case .tiny, .base, .small, .distilLargeV3:
            return "99 Languages (Multilingual)"
        }
    }

    public var family: ModelFamily {
        switch self {
        case .parakeetTDT110M, .parakeetTDT06B, .parakeetCTC06B, .parakeetRNNT11B:
            return .parakeet
        case .qwenAudio06B, .qwenAudio17B:
            return .qwen
        case .tiny, .tinyEn, .base, .baseEn, .small, .smallEn, .distilLargeV3:
            return .whisper
        }
    }

    public var macSuitability: String {
        switch self {
        case .parakeetTDT110M:
            return "FastConformer for Mac • ~0.3s ultra-fast latency"
        case .parakeetTDT06B:
            return "NeMo TDT Conformer • High English accuracy on Apple Silicon"
        case .parakeetCTC06B:
            return "Multilingual Conformer • 25 languages for Apple Silicon"
        case .parakeetRNNT11B:
            return "Studio-grade ASR • Highest accuracy on Apple M-series"
        case .qwenAudio06B:
            return "Qwen-Audio compact weights • 10 Asian & Western languages"
        case .qwenAudio17B:
            return "Qwen-Audio 1.7B • Enhanced technical & code vocabulary"
        case .tiny, .tinyEn:
            return "Ultra-lightweight ~75MB • Instant zero-lag transcription"
        case .base, .baseEn:
            return "Recommended default • Fast & robust on Apple Silicon"
        case .small, .smallEn:
            return "High precision • Great for noisy environments"
        case .distilLargeV3:
            return "Flagship accuracy • Benchmark SOTA on Apple Neural Engine"
        }
    }

    public var displayName: String {
        switch self {
        case .parakeetTDT110M:
            return "Parakeet-TDT 110M (FastConformer) [\(formattedSize) • \(languageSummary)]"
        case .parakeetTDT06B:
            return "Parakeet-TDT 0.6B (NeMo) [\(formattedSize) • \(languageSummary)]"
        case .parakeetCTC06B:
            return "Parakeet-CTC 0.6B Multilingual [\(formattedSize) • \(languageSummary)]"
        case .parakeetRNNT11B:
            return "Parakeet-RNNT 1.1B Pro [\(formattedSize) • \(languageSummary)]"
        case .qwenAudio06B:
            return "Qwen3-ASR 0.6B [\(formattedSize) • \(languageSummary)]"
        case .qwenAudio17B:
            return "Qwen3-ASR 1.7B [\(formattedSize) • \(languageSummary)]"
        case .tiny:
            return "Tiny (Multilingual) [\(formattedSize) • \(languageSummary)]"
        case .tinyEn:
            return "Tiny English [\(formattedSize) • \(languageSummary)]"
        case .base:
            return "Base (Multilingual) — Recommended [\(formattedSize) • \(languageSummary)]"
        case .baseEn:
            return "Base English — Recommended [\(formattedSize) • \(languageSummary)]"
        case .small:
            return "Small (Multilingual) [\(formattedSize) • \(languageSummary)]"
        case .smallEn:
            return "Small English [\(formattedSize) • \(languageSummary)]"
        case .distilLargeV3:
            return "Distil Large V3 [\(formattedSize) • \(languageSummary)]"
        }
    }

    public var shortTitle: String {
        switch self {
        case .parakeetTDT110M: return "Parakeet 110M"
        case .parakeetTDT06B: return "Parakeet 0.6B"
        case .parakeetCTC06B: return "Parakeet CTC Multi"
        case .parakeetRNNT11B: return "Parakeet 1.1B"
        case .qwenAudio06B: return "Qwen3-ASR 0.6B"
        case .qwenAudio17B: return "Qwen3-ASR 1.7B"
        case .tiny: return "Tiny Multi"
        case .tinyEn: return "Tiny English"
        case .base: return "Base Multi"
        case .baseEn: return "Base English"
        case .small: return "Small Multi"
        case .smallEn: return "Small English"
        case .distilLargeV3: return "Distil Large V3"
        }
    }

    public var shortDetail: String {
        return "\(formattedSize) • \(languageCount) lang"
    }
}

public enum ModelName: String, CaseIterable, Identifiable {
    // Qwen Family
    case fast06B = "Qwen/Qwen3-ASR-0.6B"
    case accurate17B = "Qwen/Qwen3-ASR-1.7B"

    // Parakeet Family (Mac Optimized)
    case parakeet110M = "nvidia/parakeet-tdt-110m"
    case parakeet06B = "nvidia/parakeet-tdt-0.6b"
    case parakeetCtc06B = "nvidia/parakeet-ctc-0.6b-multi"
    case parakeet11B = "nvidia/parakeet-rnnt-1.1b"

    public var id: String { rawValue }

    public var sizeMB: Int {
        switch self {
        case .parakeet110M: return 110
        case .parakeet06B, .parakeetCtc06B: return 620
        case .fast06B: return 640
        case .parakeet11B: return 1100
        case .accurate17B: return 1700
        }
    }

    public var formattedSize: String {
        if sizeMB >= 1000 {
            let gb = Double(sizeMB) / 1000.0
            return "\(sizeMB) MB (~" + String(format: "%.1f", gb) + " GB)"
        } else {
            return "\(sizeMB) MB"
        }
    }

    public var languageCount: Int {
        switch self {
        case .parakeet110M, .parakeet06B, .parakeet11B:
            return 1
        case .fast06B:
            return 10
        case .accurate17B:
            return 15
        case .parakeetCtc06B:
            return 25
        }
    }

    public var languageSummary: String {
        switch self {
        case .parakeet110M, .parakeet06B, .parakeet11B:
            return "1 Language (English)"
        case .fast06B:
            return "10 Languages (EN, ZH, JA, KO, FR...)"
        case .accurate17B:
            return "15 Languages (Multilingual)"
        case .parakeetCtc06B:
            return "25 Languages (Multilingual)"
        }
    }

    public var family: ModelFamily {
        switch self {
        case .fast06B, .accurate17B:
            return .qwen
        case .parakeet110M, .parakeet06B, .parakeetCtc06B, .parakeet11B:
            return .parakeet
        }
    }

    public var displayName: String {
        switch self {
        case .fast06B:
            return "Qwen3-ASR (0.6B) [\(formattedSize) • \(languageSummary)]"
        case .accurate17B:
            return "Qwen3-ASR (1.7B) [\(formattedSize) • \(languageSummary)]"
        case .parakeet110M:
            return "Parakeet-TDT 110M [\(formattedSize) • \(languageSummary)]"
        case .parakeet06B:
            return "Parakeet-TDT 0.6B [\(formattedSize) • \(languageSummary)]"
        case .parakeetCtc06B:
            return "Parakeet-CTC 0.6B Multi [\(formattedSize) • \(languageSummary)]"
        case .parakeet11B:
            return "Parakeet-RNNT 1.1B [\(formattedSize) • \(languageSummary)]"
        }
    }

    public var description: String {
        switch self {
        case .fast06B:
            return "\(formattedSize) • \(languageSummary). Fast inference, lower memory footprint."
        case .accurate17B:
            return "\(formattedSize) • \(languageSummary). Higher accuracy for complex & technical audio."
        case .parakeet110M:
            return "\(formattedSize) • \(languageSummary). NVIDIA FastConformer optimized for Mac Apple Silicon."
        case .parakeet06B:
            return "\(formattedSize) • \(languageSummary). NeMo TDT architecture with superior word error rate."
        case .parakeetCtc06B:
            return "\(formattedSize) • \(languageSummary). 25-language European & Asian multilingual Conformer."
        case .parakeet11B:
            return "\(formattedSize) • \(languageSummary). Flagship 1.1B Conformer for studio-grade transcription."
        }
    }
}

enum UserSettingKey {
    static let engineType = "openflow.engine_type"
    static let localWhisperModel = "openflow.local_whisper_model"
    static let backendBaseURL = "openflow.backend_base_url"
    static let timeoutSeconds = "openflow.timeout_seconds"
    static let retryCount = "openflow.retry_count"
    static let retryBaseDelayMs = "openflow.retry_base_delay_ms"
    static let outputMode = "openflow.output_mode"
    static let autoCopy = "openflow.auto_copy"
    static let hotkey = "openflow.hotkey"
    static let apiToken = "openflow.api_token"
    static let maxUploadBytes = "openflow.max_upload_bytes"
    static let backendSetupAgreementAccepted = "openflow.backend_setup_agreement_accepted"
    static let launchGuideShown = "openflow.launch_guide_shown"
    static let modelName = "openflow.model_name"
    static let addTrailingSpace = "openflow.add_trailing_space"
    static let capitalizeSentences = "openflow.capitalize_sentences"
    static let writeNumbersAsDigits = "openflow.write_numbers_as_digits"
    static let useSymbolsAndOrdinals = "openflow.use_symbols_and_ordinals"
    static let spokenEmoji = "openflow.spoken_emoji"
    static let paragraphBreaks = "openflow.paragraph_breaks"
    static let spokenPunctuation = "openflow.spoken_punctuation"
    static let maxRecordingDuration = "openflow.max_recording_duration"
    static let skipSilenceBeforeTranscribing = "openflow.skip_silence_before_transcribing"
    static let silenceSensitivity = "openflow.silence_sensitivity"
    static let stopAfterSilence = "openflow.stop_after_silence"
    static let appTheme = "openflow.app_theme"
    static let overlayPlacement = "openflow.overlay_placement"
    static let playFeedbackSounds = "openflow.play_feedback_sounds"
}

// MARK: - Overlay Placement

extension Notification.Name {
    public static let openflowOverlayPlacementDidChange = Notification.Name("openflow.overlay_placement_did_change")
}

public enum OverlayPlacement: String, CaseIterable, Identifiable, Codable {
    case top = "Top"
    case bottom = "Bottom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .top: return "Top (Below Notch)"
        case .bottom: return "Bottom (Above Dock)"
        }
    }

    public var icon: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .bottom: return "arrow.down.to.line"
        }
    }

    public static func parse(_ raw: String?) -> OverlayPlacement? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return OverlayPlacement(rawValue: raw)
            ?? OverlayPlacement.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame })
    }
}

// MARK: - App Theme

public enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System (Auto)"
        case .light: return "Light (White)"
        case .dark: return "Dark"
        }
    }

    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    public static func parse(_ value: String?) -> AppTheme? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !v.isEmpty else { return nil }
        if v == "light" || v == "white" { return .light }
        if v == "dark" || v == "black" { return .dark }
        if v == "system" || v == "auto" { return .system }
        return AppTheme.allCases.first { $0.rawValue.lowercased() == v }
    }
}

// MARK: - Silence Sensitivity

public enum SilenceSensitivity: String, CaseIterable, Identifiable, Codable {
    case low = "Low (-30 dB)"
    case medium = "Medium (-38 dB)"
    case high = "High (-46 dB)"

    public var id: String { rawValue }

    public var thresholdDb: Float {
        switch self {
        case .low: return -30.0
        case .medium: return -38.0
        case .high: return -46.0
        }
    }

    public var shortLabel: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    public static func parse(_ value: String?) -> SilenceSensitivity? {
        guard let value = value?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }
        if value.contains("low") || value == "-30" { return .low }
        if value.contains("high") || value == "-46" { return .high }
        if value.contains("medium") || value == "-38" { return .medium }
        return SilenceSensitivity.allCases.first { $0.rawValue.lowercased() == value }
    }
}

// MARK: - Stop After Silence Choice

public enum StopAfterSilenceChoice: String, CaseIterable, Identifiable, Codable {
    case off = "Off"
    case oneSecond = "1.0s"
    case oneAndHalfSeconds = "1.5s"
    case twoSeconds = "2.0s"
    case threeSeconds = "3.0s"
    case fiveSeconds = "5.0s"

    public var id: String { rawValue }

    public var durationSeconds: Double {
        switch self {
        case .off: return 0.0
        case .oneSecond: return 1.0
        case .oneAndHalfSeconds: return 1.5
        case .twoSeconds: return 2.0
        case .threeSeconds: return 3.0
        case .fiveSeconds: return 5.0
        }
    }

    public static func parse(_ value: String?) -> StopAfterSilenceChoice? {
        guard let value = value?.trimmingCharacters(in: .whitespaces) else { return nil }
        if value == "0" || value == "0.0" || value.lowercased() == "off" { return .off }
        if value == "1" || value == "1.0" || value == "1.0s" { return .oneSecond }
        if value == "1.5" || value == "1.5s" { return .oneAndHalfSeconds }
        if value == "2" || value == "2.0" || value == "2.0s" { return .twoSeconds }
        if value == "3" || value == "3.0" || value == "3.0s" { return .threeSeconds }
        if value == "5" || value == "5.0" || value == "5.0s" { return .fiveSeconds }
        return StopAfterSilenceChoice.allCases.first { $0.rawValue == value }
    }
}

// MARK: - Max Recording Duration Choice

public enum MaxRecordingDurationChoice: String, CaseIterable, Identifiable, Codable {
    case off = "Unlimited"
    case thirtySeconds = "30s"
    case oneMinute = "1m"
    case twoMinutes = "2m"
    case fiveMinutes = "5m"
    case tenMinutes = "10m"

    public var id: String { rawValue }

    public var durationSeconds: Double {
        switch self {
        case .off: return 0.0
        case .thirtySeconds: return 30.0
        case .oneMinute: return 60.0
        case .twoMinutes: return 120.0
        case .fiveMinutes: return 300.0
        case .tenMinutes: return 600.0
        }
    }

    public var displayLabel: String {
        switch self {
        case .off: return "Unlimited"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        }
    }

    public static func parse(_ value: String?) -> MaxRecordingDurationChoice? {
        guard let value = value?.trimmingCharacters(in: .whitespaces) else { return nil }
        if value == "0" || value == "0.0" || value.lowercased() == "unlimited" || value.lowercased() == "off" { return .off }
        if value == "30" || value == "30s" || value == "30 seconds" { return .thirtySeconds }
        if value == "60" || value == "1m" || value == "1 minute" { return .oneMinute }
        if value == "120" || value == "2m" || value == "2 minutes" { return .twoMinutes }
        if value == "300" || value == "5m" || value == "5 minutes" { return .fiveMinutes }
        if value == "600" || value == "10m" || value == "10 minutes" { return .tenMinutes }
        return MaxRecordingDurationChoice.allCases.first { $0.rawValue == value }
    }
}

// MARK: - Recording Silence Config

public struct RecordingSilenceConfig: Equatable {
    public var maxRecordingDuration: MaxRecordingDurationChoice
    public var skipSilenceBeforeTranscribing: Bool
    public var silenceSensitivity: SilenceSensitivity
    public var stopAfterSilence: StopAfterSilenceChoice

    public init(
        maxRecordingDuration: MaxRecordingDurationChoice = .twoMinutes,
        skipSilenceBeforeTranscribing: Bool = true,
        silenceSensitivity: SilenceSensitivity = .medium,
        stopAfterSilence: StopAfterSilenceChoice = .twoSeconds
    ) {
        self.maxRecordingDuration = maxRecordingDuration
        self.skipSilenceBeforeTranscribing = skipSilenceBeforeTranscribing
        self.silenceSensitivity = silenceSensitivity
        self.stopAfterSilence = stopAfterSilence
    }
}

struct AppConfig {
    let engineType: ASREngineType
    let localWhisperModel: WhisperModelChoice
    let backendBaseURL: URL
    let requestTimeoutSeconds: TimeInterval
    let maxRetryCount: Int
    let retryBaseDelayMs: Int
    let autoCopyTranscript: Bool
    let outputMode: TranscriptOutputMode
    let hotKey: HotKeyConfiguration
    let apiToken: String?
    let maxUploadBytes: Int
    let modelName: ModelName
    let typedText: TypedTextConfig
    let recordingSilence: RecordingSilenceConfig
    let theme: AppTheme
    let overlayPlacement: OverlayPlacement

    init(
        engineType: ASREngineType = .remoteServer,
        localWhisperModel: WhisperModelChoice = .tiny,
        backendBaseURL: URL = URL(string: "http://127.0.0.1:8001")!,
        requestTimeoutSeconds: TimeInterval = 45,
        maxRetryCount: Int = 2,
        retryBaseDelayMs: Int = 250,
        autoCopyTranscript: Bool = true,
        outputMode: TranscriptOutputMode = .activeApp,
        hotKey: HotKeyConfiguration = .default,
        apiToken: String? = nil,
        maxUploadBytes: Int = 25 * 1024 * 1024,
        modelName: ModelName = .fast06B,
        typedText: TypedTextConfig = TypedTextConfig(),
        recordingSilence: RecordingSilenceConfig = RecordingSilenceConfig(),
        theme: AppTheme = .dark,
        overlayPlacement: OverlayPlacement = .top
    ) {
        self.engineType = engineType
        self.localWhisperModel = localWhisperModel
        self.backendBaseURL = backendBaseURL
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.maxRetryCount = maxRetryCount
        self.retryBaseDelayMs = retryBaseDelayMs
        self.autoCopyTranscript = autoCopyTranscript
        self.outputMode = outputMode
        self.hotKey = hotKey
        self.apiToken = apiToken
        self.maxUploadBytes = maxUploadBytes
        self.modelName = modelName
        self.typedText = typedText
        self.recordingSilence = recordingSilence
        self.theme = theme
        self.overlayPlacement = overlayPlacement
    }

    static let `default` = AppConfig(
        engineType: .localCoreML,
        localWhisperModel: .tiny,
        backendBaseURL: URL(string: "http://127.0.0.1:8001")!,
        requestTimeoutSeconds: 45,
        maxRetryCount: 2,
        retryBaseDelayMs: 250,
        autoCopyTranscript: true,
        outputMode: .activeApp,
        hotKey: .default,
        apiToken: nil,
        maxUploadBytes: 25 * 1024 * 1024,
        modelName: .fast06B,
        typedText: TypedTextConfig(),
        recordingSilence: RecordingSilenceConfig(),
        theme: .dark,
        overlayPlacement: .top
    )

    static func load() -> AppConfig {
        let environment = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard

        let backendRaw = envValue(environment, "BACKEND_URL")
            ?? defaults.string(forKey: UserSettingKey.backendBaseURL)
        let backendURL = URL(string: backendRaw ?? "") ?? AppConfig.default.backendBaseURL

        let timeoutRaw = envValue(environment, "TIMEOUT_SECONDS")
            ?? defaults.string(forKey: UserSettingKey.timeoutSeconds)
        let timeout = Double(timeoutRaw ?? "")
            .flatMap { $0 > 0 ? $0 : nil } ?? AppConfig.default.requestTimeoutSeconds

        let retryCountRaw = envValue(environment, "RETRY_COUNT")
            ?? defaults.string(forKey: UserSettingKey.retryCount)
        let retryCount = Int(retryCountRaw ?? "")
            .flatMap { $0 >= 0 ? $0 : nil } ?? AppConfig.default.maxRetryCount

        let retryDelayRaw = envValue(environment, "RETRY_BASE_DELAY_MS")
            ?? defaults.string(forKey: UserSettingKey.retryBaseDelayMs)
        let retryDelay = Int(retryDelayRaw ?? "")
            .flatMap { $0 >= 25 ? $0 : nil } ?? AppConfig.default.retryBaseDelayMs

        let legacyAutoCopyRaw = envValue(environment, "AUTO_COPY")
            ?? defaults.string(forKey: UserSettingKey.autoCopy)
        let autoCopy = parseBool(legacyAutoCopyRaw, fallback: AppConfig.default.autoCopyTranscript)

        let outputMode: TranscriptOutputMode
        if let explicitOutputMode = TranscriptOutputMode.parse(envValue(environment, "OUTPUT_MODE")) {
            outputMode = explicitOutputMode
        } else if let persistedMode = TranscriptOutputMode.parse(defaults.string(forKey: UserSettingKey.outputMode)) {
            outputMode = persistedMode
        } else if envValue(environment, "AUTO_COPY") != nil {
            outputMode = autoCopy ? .clipboard : .none
        } else if defaults.string(forKey: UserSettingKey.autoCopy) != nil {
            outputMode = autoCopy ? .clipboard : .none
        } else {
            outputMode = AppConfig.default.outputMode
        }

        let hotkeyRaw = envValue(environment, "HOTKEY")
            ?? defaults.string(forKey: UserSettingKey.hotkey)
        let hotKey = HotKeyConfiguration.parse(hotkeyRaw)

        let tokenRaw = envValue(environment, "API_TOKEN")
            ?? defaults.string(forKey: UserSettingKey.apiToken)
        let tokenValue = tokenRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenValue?.isEmpty == false ? tokenValue : nil

        let maxUploadRaw = envValue(environment, "MAX_UPLOAD_BYTES")
            ?? defaults.string(forKey: UserSettingKey.maxUploadBytes)
        let maxUploadBytes = Int(maxUploadRaw ?? "")
            .flatMap { $0 > 0 ? $0 : nil } ?? AppConfig.default.maxUploadBytes

        let modelName: ModelName
        if let modelRaw = envValue(environment, "MODEL_NAME"),
           let envModel = ModelName(rawValue: modelRaw) {
            modelName = envModel
        } else if let persistedModelRaw = defaults.string(forKey: UserSettingKey.modelName),
                  let persistedModel = ModelName(rawValue: persistedModelRaw) {
            modelName = persistedModel
        } else {
            modelName = AppConfig.default.modelName
        }

        let engineType: ASREngineType
        if let envEngine = ASREngineType.parse(envValue(environment, "ENGINE_TYPE")) {
            engineType = envEngine
        } else if let persistedEngine = ASREngineType.parse(defaults.string(forKey: UserSettingKey.engineType)) {
            engineType = persistedEngine
        } else {
            engineType = AppConfig.default.engineType
        }

        let localWhisperModel: WhisperModelChoice
        if let envWhisperModel = envValue(environment, "LOCAL_WHISPER_MODEL").flatMap({ WhisperModelChoice(rawValue: $0) }) {
            localWhisperModel = envWhisperModel
        } else if let persistedWhisperModel = defaults.string(forKey: UserSettingKey.localWhisperModel).flatMap({ WhisperModelChoice(rawValue: $0) }) {
            localWhisperModel = persistedWhisperModel
        } else {
            localWhisperModel = AppConfig.default.localWhisperModel
        }

        let addTrailingSpace = defaults.object(forKey: UserSettingKey.addTrailingSpace) != nil
            ? defaults.bool(forKey: UserSettingKey.addTrailingSpace)
            : true
        let capitalizeSentences = defaults.object(forKey: UserSettingKey.capitalizeSentences) != nil
            ? defaults.bool(forKey: UserSettingKey.capitalizeSentences)
            : true
        let writeNumbersAsDigits = defaults.bool(forKey: UserSettingKey.writeNumbersAsDigits)
        let useSymbolsAndOrdinals = defaults.bool(forKey: UserSettingKey.useSymbolsAndOrdinals)
        let spokenEmoji = defaults.bool(forKey: UserSettingKey.spokenEmoji)
        let paragraphBreaks = defaults.object(forKey: UserSettingKey.paragraphBreaks) != nil
            ? defaults.bool(forKey: UserSettingKey.paragraphBreaks)
            : true
        let spokenPunctuation = defaults.object(forKey: UserSettingKey.spokenPunctuation) != nil
            ? defaults.bool(forKey: UserSettingKey.spokenPunctuation)
            : true

        let typedText = TypedTextConfig(
            addTrailingSpace: addTrailingSpace,
            capitalizeSentences: capitalizeSentences,
            writeNumbersAsDigits: writeNumbersAsDigits,
            useSymbolsAndOrdinals: useSymbolsAndOrdinals,
            spokenEmoji: spokenEmoji,
            paragraphBreaks: paragraphBreaks,
            spokenPunctuation: spokenPunctuation
        )

        let maxRecordingDuration = MaxRecordingDurationChoice.parse(defaults.string(forKey: UserSettingKey.maxRecordingDuration))
            ?? .twoMinutes
        let skipSilence = defaults.object(forKey: UserSettingKey.skipSilenceBeforeTranscribing) != nil
            ? defaults.bool(forKey: UserSettingKey.skipSilenceBeforeTranscribing)
            : true
        let silenceSensitivity = SilenceSensitivity.parse(defaults.string(forKey: UserSettingKey.silenceSensitivity))
            ?? .medium
        let stopAfterSilence = StopAfterSilenceChoice.parse(defaults.string(forKey: UserSettingKey.stopAfterSilence))
            ?? .twoSeconds

        let recordingSilence = RecordingSilenceConfig(
            maxRecordingDuration: maxRecordingDuration,
            skipSilenceBeforeTranscribing: skipSilence,
            silenceSensitivity: silenceSensitivity,
            stopAfterSilence: stopAfterSilence
        )

        let themeRaw = envValue(environment, "THEME")
            ?? defaults.string(forKey: UserSettingKey.appTheme)
        let theme = AppTheme.parse(themeRaw) ?? AppConfig.default.theme

        let overlayPlacementRaw = envValue(environment, "OVERLAY_PLACEMENT")
            ?? defaults.string(forKey: UserSettingKey.overlayPlacement)
        let overlayPlacement = OverlayPlacement.parse(overlayPlacementRaw) ?? AppConfig.default.overlayPlacement

        return AppConfig(
            engineType: engineType,
            localWhisperModel: localWhisperModel,
            backendBaseURL: backendURL,
            requestTimeoutSeconds: timeout,
            maxRetryCount: retryCount,
            retryBaseDelayMs: retryDelay,
            autoCopyTranscript: outputMode.shouldCopyToClipboard,
            outputMode: outputMode,
            hotKey: hotKey,
            apiToken: token,
            maxUploadBytes: maxUploadBytes,
            modelName: modelName,
            typedText: typedText,
            recordingSilence: recordingSilence,
            theme: theme,
            overlayPlacement: overlayPlacement
        )
    }

    private static func parseBool(_ value: String?, fallback: Bool) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return fallback
        }

        switch value {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return fallback
        }
    }

    private static func envValue(_ environment: [String: String], _ keySuffix: String) -> String? {
        environment["OPENFLOW_\(keySuffix)"]
    }
}
