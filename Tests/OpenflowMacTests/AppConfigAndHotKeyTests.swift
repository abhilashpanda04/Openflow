import Carbon
import Darwin
import XCTest
@testable import OpenflowMac

final class TranscriptOutputModeTests: XCTestCase {
    func testParseAcceptsKnownValuesAndAliases() {
        XCTAssertEqual(TranscriptOutputMode.parse("clipboard"), .clipboard)
        XCTAssertEqual(TranscriptOutputMode.parse("active-app"), .activeApp)
        XCTAssertEqual(TranscriptOutputMode.parse("active_app"), .activeApp)
        XCTAssertEqual(TranscriptOutputMode.parse("activeapp"), .activeApp)
        XCTAssertEqual(TranscriptOutputMode.parse("focused-app"), .activeApp)
        XCTAssertEqual(TranscriptOutputMode.parse("both"), .both)
        XCTAssertEqual(TranscriptOutputMode.parse("none"), TranscriptOutputMode.none)
    }

    func testParseRejectsEmptyAndUnknownValues() {
        XCTAssertNil(TranscriptOutputMode.parse(nil))
        XCTAssertNil(TranscriptOutputMode.parse(""))
        XCTAssertNil(TranscriptOutputMode.parse("   "))
        XCTAssertNil(TranscriptOutputMode.parse("invalid"))
    }

    func testComputedPropertiesAndDisplayNames() {
        XCTAssertTrue(TranscriptOutputMode.clipboard.shouldCopyToClipboard)
        XCTAssertFalse(TranscriptOutputMode.clipboard.shouldPasteToActiveApp)
        XCTAssertEqual(TranscriptOutputMode.clipboard.displayName, "Clipboard")

        XCTAssertFalse(TranscriptOutputMode.activeApp.shouldCopyToClipboard)
        XCTAssertTrue(TranscriptOutputMode.activeApp.shouldPasteToActiveApp)
        XCTAssertEqual(TranscriptOutputMode.activeApp.displayName, "Active App")

        XCTAssertTrue(TranscriptOutputMode.both.shouldCopyToClipboard)
        XCTAssertTrue(TranscriptOutputMode.both.shouldPasteToActiveApp)
        XCTAssertEqual(TranscriptOutputMode.both.displayName, "Clipboard + Active App")

        XCTAssertFalse(TranscriptOutputMode.none.shouldCopyToClipboard)
        XCTAssertFalse(TranscriptOutputMode.none.shouldPasteToActiveApp)
        XCTAssertEqual(TranscriptOutputMode.none.displayName, "None")
    }
}

final class ASREngineTypeTests: XCTestCase {
    func testParseEngineTypes() {
        XCTAssertEqual(ASREngineType.parse("local-coreml"), .localCoreML)
        XCTAssertEqual(ASREngineType.parse("coreml"), .localCoreML)
        XCTAssertEqual(ASREngineType.parse("whisperkit"), .localCoreML)
        XCTAssertEqual(ASREngineType.parse("apple-speech"), .appleSpeech)
        XCTAssertEqual(ASREngineType.parse("siri"), .appleSpeech)
        XCTAssertEqual(ASREngineType.parse("speech"), .appleSpeech)
        XCTAssertEqual(ASREngineType.parse("remote-server"), .remoteServer)
        XCTAssertEqual(ASREngineType.parse("http"), .remoteServer)
        XCTAssertNil(ASREngineType.parse("invalid"))
    }

    func testEngineTypeDisplayNames() {
        XCTAssertEqual(ASREngineType.localCoreML.displayName, "Native CoreML (WhisperKit)")
        XCTAssertEqual(ASREngineType.appleSpeech.displayName, "Apple Speech (macOS Built-in / Offline)")
        XCTAssertEqual(ASREngineType.remoteServer.displayName, "Remote Server (HTTP Backend)")
    }
}

final class WhisperModelChoiceTests: XCTestCase {
    func testModelChoices() {
        XCTAssertEqual(WhisperModelChoice.tiny.rawValue, "openai_whisper-tiny")
        XCTAssertEqual(WhisperModelChoice.base.rawValue, "openai_whisper-base")
        XCTAssertEqual(WhisperModelChoice.parakeetTDT110M.rawValue, "nvidia_parakeet-tdt-110m")
        XCTAssertEqual(WhisperModelChoice.qwenAudio06B.rawValue, "qwen_qwen3-asr-0.6b")

        // MB Size and Language counts
        XCTAssertEqual(WhisperModelChoice.parakeetTDT110M.sizeMB, 110)
        XCTAssertEqual(WhisperModelChoice.parakeetTDT110M.languageCount, 1)
        XCTAssertEqual(WhisperModelChoice.qwenAudio06B.sizeMB, 640)
        XCTAssertEqual(WhisperModelChoice.qwenAudio06B.languageCount, 10)
        XCTAssertEqual(WhisperModelChoice.tiny.sizeMB, 75)
        XCTAssertEqual(WhisperModelChoice.tiny.languageCount, 99)
        XCTAssertEqual(WhisperModelChoice.base.sizeMB, 140)
        XCTAssertEqual(WhisperModelChoice.base.languageCount, 99)

        XCTAssertFalse(WhisperModelChoice.tiny.displayName.isEmpty)
        XCTAssertFalse(WhisperModelChoice.base.displayName.isEmpty)
    }
}

final class ModelNameTests: XCTestCase {
    func testModelMetadata() {
        XCTAssertTrue(ModelName.fast06B.displayName.contains("0.6B"))
        XCTAssertTrue(ModelName.accurate17B.displayName.contains("1.7B"))
        XCTAssertEqual(ModelName.fast06B.sizeMB, 640)
        XCTAssertEqual(ModelName.fast06B.languageCount, 10)
        XCTAssertEqual(ModelName.parakeet110M.sizeMB, 110)
        XCTAssertEqual(ModelName.parakeet110M.languageCount, 1)
        XCTAssertFalse(ModelName.fast06B.description.isEmpty)
        XCTAssertFalse(ModelName.accurate17B.description.isEmpty)
    }
}

final class HotKeyConfigurationTests: XCTestCase {
    func testParseAlphaShortcut() {
        let config = HotKeyConfiguration.parse("cmd+shift+a")
        XCTAssertEqual(config.keyCode, UInt32(kVK_ANSI_A))
        XCTAssertEqual(config.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(config.displayText, "Cmd+Shift+A")
    }

    func testParseSpecialKeyWithSynonyms() {
        let config = HotKeyConfiguration.parse("command+alt+enter")
        XCTAssertEqual(config.keyCode, UInt32(kVK_Return))
        XCTAssertEqual(config.modifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(config.displayText, "Cmd+Option+Return")
    }

    func testParseNormalizesWhitespaceAndOrdering() {
        let config = HotKeyConfiguration.parse("  ctrl + option + space ")
        XCTAssertEqual(config.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(config.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(config.displayText, "Option+Ctrl+Space")
    }

    func testParseFallsBackToDefaultForInvalidOrIncompleteInput() {
        XCTAssertEqual(HotKeyConfiguration.parse(nil).displayText, HotKeyConfiguration.default.displayText)
        XCTAssertEqual(HotKeyConfiguration.parse("a").displayText, HotKeyConfiguration.default.displayText)
        XCTAssertEqual(HotKeyConfiguration.parse("cmd+shift+f13").displayText, HotKeyConfiguration.default.displayText)
        XCTAssertEqual(HotKeyConfiguration.parse("cmd+shift").displayText, HotKeyConfiguration.default.displayText)
    }
}

final class AppConfigLoadTests: XCTestCase {
    private let envKeys = [
        "OPENFLOW_BACKEND_URL",
        "OPENFLOW_TIMEOUT_SECONDS",
        "OPENFLOW_RETRY_COUNT",
        "OPENFLOW_RETRY_BASE_DELAY_MS",
        "OPENFLOW_AUTO_COPY",
        "OPENFLOW_OUTPUT_MODE",
        "OPENFLOW_HOTKEY",
        "OPENFLOW_API_TOKEN",
        "OPENFLOW_MAX_UPLOAD_BYTES",
        "OPENFLOW_MODEL_NAME",
        "OPENFLOW_ENGINE_TYPE",
        "OPENFLOW_LOCAL_WHISPER_MODEL",
    ]

    private let userDefaultKeys = [
        UserSettingKey.backendBaseURL,
        UserSettingKey.timeoutSeconds,
        UserSettingKey.retryCount,
        UserSettingKey.retryBaseDelayMs,
        UserSettingKey.autoCopy,
        UserSettingKey.outputMode,
        UserSettingKey.hotkey,
        UserSettingKey.apiToken,
        UserSettingKey.maxUploadBytes,
        UserSettingKey.modelName,
        UserSettingKey.engineType,
        UserSettingKey.localWhisperModel,
    ]

    private var originalEnvironment: [String: String?] = [:]

    override func setUp() {
        super.setUp()
        snapshotAndClearEnvironment()
        clearUserDefaults()
    }

    override func tearDown() {
        restoreEnvironment()
        clearUserDefaults()
        super.tearDown()
    }

    func testLoadUsesDefaultValuesWhenNoOverridesArePresent() {
        let config = AppConfig.load()
        XCTAssertEqual(config.backendBaseURL, AppConfig.default.backendBaseURL)
        XCTAssertEqual(config.requestTimeoutSeconds, AppConfig.default.requestTimeoutSeconds)
        XCTAssertEqual(config.maxRetryCount, AppConfig.default.maxRetryCount)
        XCTAssertEqual(config.retryBaseDelayMs, AppConfig.default.retryBaseDelayMs)
        XCTAssertEqual(config.outputMode, AppConfig.default.outputMode)
        XCTAssertEqual(config.autoCopyTranscript, config.outputMode.shouldCopyToClipboard)
        XCTAssertEqual(config.hotKey.displayText, AppConfig.default.hotKey.displayText)
        XCTAssertNil(config.apiToken)
        XCTAssertEqual(config.maxUploadBytes, AppConfig.default.maxUploadBytes)
        XCTAssertEqual(config.modelName, AppConfig.default.modelName)
        XCTAssertEqual(config.engineType, AppConfig.default.engineType)
        XCTAssertEqual(config.localWhisperModel, AppConfig.default.localWhisperModel)
    }

    func testLoadPrefersEnvironmentValuesOverUserDefaults() {
        UserDefaults.standard.set("http://defaults.local:8111", forKey: UserSettingKey.backendBaseURL)
        UserDefaults.standard.set("30", forKey: UserSettingKey.timeoutSeconds)
        UserDefaults.standard.set("1", forKey: UserSettingKey.retryCount)
        UserDefaults.standard.set("300", forKey: UserSettingKey.retryBaseDelayMs)
        UserDefaults.standard.set("none", forKey: UserSettingKey.outputMode)
        UserDefaults.standard.set("cmd+shift+z", forKey: UserSettingKey.hotkey)
        UserDefaults.standard.set("defaults-token", forKey: UserSettingKey.apiToken)
        UserDefaults.standard.set("8192", forKey: UserSettingKey.maxUploadBytes)
        UserDefaults.standard.set(ModelName.fast06B.rawValue, forKey: UserSettingKey.modelName)
        UserDefaults.standard.set(ASREngineType.localCoreML.rawValue, forKey: UserSettingKey.engineType)
        UserDefaults.standard.set(WhisperModelChoice.tiny.rawValue, forKey: UserSettingKey.localWhisperModel)

        setEnv("OPENFLOW_BACKEND_URL", "http://env.local:8001")
        setEnv("OPENFLOW_TIMEOUT_SECONDS", "15")
        setEnv("OPENFLOW_RETRY_COUNT", "3")
        setEnv("OPENFLOW_RETRY_BASE_DELAY_MS", "500")
        setEnv("OPENFLOW_OUTPUT_MODE", "both")
        setEnv("OPENFLOW_HOTKEY", "cmd+option+return")
        setEnv("OPENFLOW_API_TOKEN", "  env-token  ")
        setEnv("OPENFLOW_MAX_UPLOAD_BYTES", "4096")
        setEnv("OPENFLOW_MODEL_NAME", ModelName.accurate17B.rawValue)
        setEnv("OPENFLOW_ENGINE_TYPE", "remote-server")
        setEnv("OPENFLOW_LOCAL_WHISPER_MODEL", WhisperModelChoice.small.rawValue)

        let config = AppConfig.load()
        XCTAssertEqual(config.backendBaseURL, URL(string: "http://env.local:8001"))
        XCTAssertEqual(config.requestTimeoutSeconds, 15)
        XCTAssertEqual(config.maxRetryCount, 3)
        XCTAssertEqual(config.retryBaseDelayMs, 500)
        XCTAssertEqual(config.outputMode, .both)
        XCTAssertTrue(config.autoCopyTranscript)
        XCTAssertEqual(config.hotKey.displayText, "Cmd+Option+Return")
        XCTAssertEqual(config.apiToken, "env-token")
        XCTAssertEqual(config.maxUploadBytes, 4096)
        XCTAssertEqual(config.modelName, .accurate17B)
        XCTAssertEqual(config.engineType, .remoteServer)
        XCTAssertEqual(config.localWhisperModel, .small)
    }

    func testLoadFallsBackWhenNumericValuesAreInvalid() {
        setEnv("OPENFLOW_TIMEOUT_SECONDS", "-1")
        setEnv("OPENFLOW_RETRY_COUNT", "-4")
        setEnv("OPENFLOW_RETRY_BASE_DELAY_MS", "5")
        setEnv("OPENFLOW_MAX_UPLOAD_BYTES", "0")

        let config = AppConfig.load()
        XCTAssertEqual(config.requestTimeoutSeconds, AppConfig.default.requestTimeoutSeconds)
        XCTAssertEqual(config.maxRetryCount, AppConfig.default.maxRetryCount)
        XCTAssertEqual(config.retryBaseDelayMs, AppConfig.default.retryBaseDelayMs)
        XCTAssertEqual(config.maxUploadBytes, AppConfig.default.maxUploadBytes)
    }

    func testLoadUsesLegacyAutoCopyWhenOutputModeIsMissing() {
        setEnv("OPENFLOW_AUTO_COPY", "yes")
        XCTAssertEqual(AppConfig.load().outputMode, .clipboard)

        setEnv("OPENFLOW_AUTO_COPY", "off")
        XCTAssertEqual(AppConfig.load().outputMode, .none)
    }

    func testLoadIgnoresBlankTokenValue() {
        setEnv("OPENFLOW_API_TOKEN", "   ")
        XCTAssertNil(AppConfig.load().apiToken)
    }

    private func snapshotAndClearEnvironment() {
        for key in envKeys {
            if let value = getenv(key) {
                originalEnvironment[key] = String(cString: value)
            } else {
                originalEnvironment[key] = nil
            }
            unsetenv(key)
        }
    }

    private func restoreEnvironment() {
        for key in envKeys {
            setEnv(key, originalEnvironment[key] ?? nil)
        }
        originalEnvironment.removeAll()
    }

    private func setEnv(_ key: String, _ value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }

    private func clearUserDefaults() {
        for key in userDefaultKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

final class AppThemeTests: XCTestCase {
    func testAppThemeParsing() {
        XCTAssertEqual(AppTheme.parse("light"), .light)
        XCTAssertEqual(AppTheme.parse("white"), .light)
        XCTAssertEqual(AppTheme.parse("LIGHT"), .light)

        XCTAssertEqual(AppTheme.parse("dark"), .dark)
        XCTAssertEqual(AppTheme.parse("black"), .dark)
        XCTAssertEqual(AppTheme.parse("DARK"), .dark)

        XCTAssertEqual(AppTheme.parse("system"), .system)
        XCTAssertEqual(AppTheme.parse("auto"), .system)
        XCTAssertNil(AppTheme.parse("invalid"))
        XCTAssertNil(AppTheme.parse(nil))
    }

    func testAppThemeDisplayProperties() {
        XCTAssertEqual(AppTheme.light.displayName, "Light (White)")
        XCTAssertEqual(AppTheme.light.iconName, "sun.max.fill")

        XCTAssertEqual(AppTheme.dark.displayName, "Dark")
        XCTAssertEqual(AppTheme.dark.iconName, "moon.stars.fill")

        XCTAssertEqual(AppTheme.system.displayName, "System (Auto)")
        XCTAssertEqual(AppTheme.system.iconName, "circle.lefthalf.filled")
    }

    func testThemeManagerToggleAndSet() {
        let manager = AppThemeManager.shared
        let originalTheme = manager.theme

        defer {
            manager.setTheme(originalTheme)
        }

        manager.setTheme(.light)
        XCTAssertEqual(manager.theme, .light)
        XCTAssertFalse(manager.isDark)
        XCTAssertEqual(manager.colorScheme, .light)

        manager.setTheme(.dark)
        XCTAssertEqual(manager.theme, .dark)
        XCTAssertTrue(manager.isDark)
        XCTAssertEqual(manager.colorScheme, .dark)

        manager.setTheme(.system)
        XCTAssertEqual(manager.theme, .system)
        XCTAssertNil(manager.colorScheme)

        // Toggle from dark goes to light
        manager.setTheme(.dark)
        manager.toggleTheme()
        XCTAssertEqual(manager.theme, .light)

        // Toggle from light goes to dark
        manager.toggleTheme()
        XCTAssertEqual(manager.theme, .dark)
    }
}

final class OverlayPlacementTests: XCTestCase {
    func testOverlayPlacementParsingAndLabels() {
        XCTAssertEqual(OverlayPlacement.parse("top"), .top)
        XCTAssertEqual(OverlayPlacement.parse("Top"), .top)
        XCTAssertEqual(OverlayPlacement.parse("bottom"), .bottom)
        XCTAssertEqual(OverlayPlacement.parse("Bottom"), .bottom)
        XCTAssertNil(OverlayPlacement.parse("invalid"))
        XCTAssertNil(OverlayPlacement.parse(nil))

        XCTAssertEqual(OverlayPlacement.top.icon, "arrow.up.to.line")
        XCTAssertEqual(OverlayPlacement.bottom.icon, "arrow.down.to.line")
        XCTAssertTrue(OverlayPlacement.top.displayName.contains("Top"))
        XCTAssertTrue(OverlayPlacement.bottom.displayName.contains("Bottom"))
    }
}
