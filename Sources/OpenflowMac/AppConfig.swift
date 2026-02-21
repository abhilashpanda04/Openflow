// Copyright 2025 Abhilash Panda
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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

enum ModelName: String, CaseIterable {
    case fast06B = "Qwen/Qwen3-ASR-0.6B"
    case accurate17B = "Qwen/Qwen3-ASR-1.7B"

    var displayName: String {
        switch self {
        case .fast06B:
            return "Fast (0.6B) — Recommended"
        case .accurate17B:
            return "Higher Accuracy (1.7B)"
        }
    }

    var description: String {
        switch self {
        case .fast06B:
            return "Faster inference, lower memory usage. Best for most users."
        case .accurate17B:
            return "Better accuracy for challenging audio. Requires more VRAM/RAM."
        }
    }
}

enum UserSettingKey {
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
    let modelName: ModelName

    static let `default` = AppConfig(
        backendBaseURL: URL(string: "http://127.0.0.1:8001")!,
        requestTimeoutSeconds: 45,
        maxRetryCount: 2,
        retryBaseDelayMs: 250,
        autoCopyTranscript: true,
        outputMode: .activeApp,
        hotKey: .default,
        apiToken: nil,
        maxUploadBytes: 25 * 1024 * 1024,
        modelName: .fast06B
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

        return AppConfig(
            backendBaseURL: backendURL,
            requestTimeoutSeconds: timeout,
            maxRetryCount: retryCount,
            retryBaseDelayMs: retryDelay,
            autoCopyTranscript: outputMode.shouldCopyToClipboard,
            outputMode: outputMode,
            hotKey: hotKey,
            apiToken: token,
            maxUploadBytes: maxUploadBytes,
            modelName: modelName
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
