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

enum UserSettingKey {
    static let backendBaseURL = "quickasr.backend_base_url"
    static let timeoutSeconds = "quickasr.timeout_seconds"
    static let retryCount = "quickasr.retry_count"
    static let retryBaseDelayMs = "quickasr.retry_base_delay_ms"
    static let outputMode = "quickasr.output_mode"
    static let autoCopy = "quickasr.auto_copy"
    static let hotkey = "quickasr.hotkey"
    static let apiToken = "quickasr.api_token"
    static let maxUploadBytes = "quickasr.max_upload_bytes"
}

struct AppConfig {
    let backendBaseURL: URL
    let requestTimeoutSeconds: TimeInterval
    let maxRetryCount: Int
    let retryBaseDelayMs: Int
    let autoCopyTranscript: Bool
    let outputMode: TranscriptOutputMode
    let hotKey: HotKeyConfiguration
    let apiToken: String?
    let maxUploadBytes: Int

    static let `default` = AppConfig(
        backendBaseURL: URL(string: "http://127.0.0.1:8001")!,
        requestTimeoutSeconds: 45,
        maxRetryCount: 2,
        retryBaseDelayMs: 250,
        autoCopyTranscript: true,
        outputMode: .activeApp,
        hotKey: .default,
        apiToken: nil,
        maxUploadBytes: 25 * 1024 * 1024
    )

    static func load() -> AppConfig {
        let environment = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard

        let backendRaw = environment["QUICKASR_BACKEND_URL"]
            ?? defaults.string(forKey: UserSettingKey.backendBaseURL)
        let backendURL = URL(string: backendRaw ?? "") ?? AppConfig.default.backendBaseURL

        let timeoutRaw = environment["QUICKASR_TIMEOUT_SECONDS"]
            ?? defaults.string(forKey: UserSettingKey.timeoutSeconds)
        let timeout = Double(timeoutRaw ?? "")
            .flatMap { $0 > 0 ? $0 : nil } ?? AppConfig.default.requestTimeoutSeconds

        let retryCountRaw = environment["QUICKASR_RETRY_COUNT"]
            ?? defaults.string(forKey: UserSettingKey.retryCount)
        let retryCount = Int(retryCountRaw ?? "")
            .flatMap { $0 >= 0 ? $0 : nil } ?? AppConfig.default.maxRetryCount

        let retryDelayRaw = environment["QUICKASR_RETRY_BASE_DELAY_MS"]
            ?? defaults.string(forKey: UserSettingKey.retryBaseDelayMs)
        let retryDelay = Int(retryDelayRaw ?? "")
            .flatMap { $0 >= 25 ? $0 : nil } ?? AppConfig.default.retryBaseDelayMs

        let legacyAutoCopyRaw = environment["QUICKASR_AUTO_COPY"]
            ?? defaults.string(forKey: UserSettingKey.autoCopy)
        let autoCopy = parseBool(legacyAutoCopyRaw, fallback: AppConfig.default.autoCopyTranscript)

        let outputMode: TranscriptOutputMode
        if let explicitOutputMode = TranscriptOutputMode.parse(environment["QUICKASR_OUTPUT_MODE"]) {
            outputMode = explicitOutputMode
        } else if let persistedMode = TranscriptOutputMode.parse(defaults.string(forKey: UserSettingKey.outputMode)) {
            outputMode = persistedMode
        } else if environment["QUICKASR_AUTO_COPY"] != nil {
            outputMode = autoCopy ? .clipboard : .none
        } else if defaults.string(forKey: UserSettingKey.autoCopy) != nil {
            outputMode = autoCopy ? .clipboard : .none
        } else {
            outputMode = AppConfig.default.outputMode
        }

        let hotkeyRaw = environment["QUICKASR_HOTKEY"]
            ?? defaults.string(forKey: UserSettingKey.hotkey)
        let hotKey = HotKeyConfiguration.parse(hotkeyRaw)

        let tokenRaw = environment["QUICKASR_API_TOKEN"]
            ?? defaults.string(forKey: UserSettingKey.apiToken)
        let tokenValue = tokenRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenValue?.isEmpty == false ? tokenValue : nil

        let maxUploadRaw = environment["QUICKASR_MAX_UPLOAD_BYTES"]
            ?? defaults.string(forKey: UserSettingKey.maxUploadBytes)
        let maxUploadBytes = Int(maxUploadRaw ?? "")
            .flatMap { $0 > 0 ? $0 : nil } ?? AppConfig.default.maxUploadBytes

        return AppConfig(
            backendBaseURL: backendURL,
            requestTimeoutSeconds: timeout,
            maxRetryCount: retryCount,
            retryBaseDelayMs: retryDelay,
            autoCopyTranscript: outputMode.shouldCopyToClipboard,
            outputMode: outputMode,
            hotKey: hotKey,
            apiToken: token,
            maxUploadBytes: maxUploadBytes
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
}
