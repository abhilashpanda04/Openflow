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

final class ModelNameTests: XCTestCase {
    func testModelMetadata() {
        XCTAssertEqual(ModelName.fast06B.displayName, "Fast (0.6B) — Recommended")
        XCTAssertEqual(ModelName.accurate17B.displayName, "Higher Accuracy (1.7B)")
        XCTAssertEqual(
            ModelName.fast06B.description,
            "Faster inference, lower memory usage. Best for most users."
        )
        XCTAssertEqual(
            ModelName.accurate17B.description,
            "Better accuracy for challenging audio. Requires more VRAM/RAM."
        )
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

        setEnv("OPENFLOW_BACKEND_URL", "http://env.local:8001")
        setEnv("OPENFLOW_TIMEOUT_SECONDS", "15")
        setEnv("OPENFLOW_RETRY_COUNT", "3")
        setEnv("OPENFLOW_RETRY_BASE_DELAY_MS", "500")
        setEnv("OPENFLOW_OUTPUT_MODE", "both")
        setEnv("OPENFLOW_HOTKEY", "cmd+option+return")
        setEnv("OPENFLOW_API_TOKEN", "  env-token  ")
        setEnv("OPENFLOW_MAX_UPLOAD_BYTES", "4096")
        setEnv("OPENFLOW_MODEL_NAME", ModelName.accurate17B.rawValue)

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
