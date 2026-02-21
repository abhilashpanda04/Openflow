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

import AppKit
import Carbon
import Foundation
import XCTest
@testable import OpenflowMac

private enum AppDelegateMockError: Error {
    case missingStub
}

private final class AppDelegateMockURLProtocol: URLProtocol {
    struct Stub {
        let response: HTTPURLResponse?
        let data: Data?
        let error: Error?
    }

    private static let lock = NSLock()
    private static var stubs: [Stub] = []

    static func configure(stubs: [Stub]) {
        lock.lock()
        defer { lock.unlock() }
        self.stubs = stubs
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "mock.openflow.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stub: Stub?
        Self.lock.lock()
        if Self.stubs.isEmpty {
            stub = nil
        } else {
            stub = Self.stubs.removeFirst()
        }
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: AppDelegateMockError.missingStub)
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let response = stub.response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = stub.data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags = []) -> NSEvent {
    let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    cgEvent.flags = flags
    return NSEvent(cgEvent: cgEvent)!
}

private func makeHealthStub(modelLoaded: Bool) -> AppDelegateMockURLProtocol.Stub {
    let url = URL(string: "http://mock.openflow.local/health")!
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let body = """
    {"status":"ok","model_loaded":\(modelLoaded ? "true" : "false"),"model_name":"Qwen","auth_enabled":false}
    """
    return AppDelegateMockURLProtocol.Stub(response: response, data: Data(body.utf8), error: nil)
}

private func makeHealthErrorStub() -> AppDelegateMockURLProtocol.Stub {
    AppDelegateMockURLProtocol.Stub(response: nil, data: nil, error: URLError(.cannotConnectToHost))
}

private func makeMockHealthClient(stubs: [AppDelegateMockURLProtocol.Stub]) -> ASRClient {
    AppDelegateMockURLProtocol.configure(stubs: stubs)
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [AppDelegateMockURLProtocol.self]
    sessionConfig.timeoutIntervalForRequest = 1
    sessionConfig.timeoutIntervalForResource = 1
    let session = URLSession(configuration: sessionConfig)
    return ASRClient(
        config: ASRClientConfiguration(
            baseURL: URL(string: "http://mock.openflow.local")!,
            timeoutSeconds: 1,
            retryCount: 0,
            retryBaseDelayMs: 1,
            apiToken: nil,
            maxUploadBytes: 1024 * 1024
        ),
        session: session
    )
}

final class GlobalHotKeyCaptureTests: XCTestCase {
    func testCaptureBuildsStorageAndDisplayValue() {
        let event = makeKeyEvent(
            keyCode: CGKeyCode(kVK_ANSI_A),
            flags: [.maskCommand, .maskShift]
        )

        let captured = HotKeyConfiguration.capture(from: event)
        XCTAssertEqual(captured?.storageValue, "cmd+shift+a")
        XCTAssertEqual(captured?.configuration.displayText, "Cmd+Shift+A")
        XCTAssertEqual(captured?.configuration.keyCode, UInt32(kVK_ANSI_A))
    }

    func testCaptureRejectsEventsWithoutModifiers() {
        let event = makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_A))
        XCTAssertNil(HotKeyConfiguration.capture(from: event))
    }

    func testCaptureRejectsUnsupportedKeys() {
        let event = makeKeyEvent(keyCode: CGKeyCode(kVK_F13), flags: [.maskCommand])
        XCTAssertNil(HotKeyConfiguration.capture(from: event))
    }
}

final class SettingsViewBehaviorTests: XCTestCase {
    private let userDefaultKeys = [
        UserSettingKey.backendBaseURL,
        UserSettingKey.timeoutSeconds,
        UserSettingKey.retryCount,
        UserSettingKey.retryBaseDelayMs,
        UserSettingKey.hotkey,
        UserSettingKey.apiToken,
        UserSettingKey.maxUploadBytes,
        UserSettingKey.outputMode,
        UserSettingKey.modelName,
    ]

    override func setUp() {
        super.setUp()
        clearUserDefaults()
    }

    override func tearDown() {
        clearUserDefaults()
        super.tearDown()
    }

    func testSavePostsNotificationAndPersistsConfiguredDefaults() {
        var view = SettingsView()
        _ = view.body

        let note = expectation(forNotification: .quickASRSettingsDidChange, object: nil)
        view._test_save()
        wait(for: [note], timeout: 1.0)

        XCTAssertEqual(UserDefaults.standard.string(forKey: UserSettingKey.backendBaseURL), "http://127.0.0.1:8001")
        XCTAssertEqual(UserDefaults.standard.string(forKey: UserSettingKey.timeoutSeconds), "45")
        XCTAssertEqual(UserDefaults.standard.string(forKey: UserSettingKey.retryCount), "2")
        XCTAssertEqual(UserDefaults.standard.string(forKey: UserSettingKey.retryBaseDelayMs), "250")
        XCTAssertEqual(UserDefaults.standard.string(forKey: UserSettingKey.hotkey), "cmd+shift+space")
        XCTAssertEqual(UserDefaults.standard.string(forKey: UserSettingKey.outputMode), TranscriptOutputMode.activeApp.rawValue)
    }

    func testBodyAndHelpersExecuteWithoutCrashing() {
        var view = SettingsView()
        _ = view.body
        view._test_restoreDefaults()
        view._test_toggleHotkeyCapture()
        let escape = makeKeyEvent(keyCode: CGKeyCode(kVK_Escape))
        _ = view._test_handleHotkeyCapture(escape)
        let event = makeKeyEvent(
            keyCode: CGKeyCode(kVK_Return),
            flags: [.maskCommand, .maskAlternate]
        )
        _ = view._test_handleHotkeyCapture(event)
        view._test_stopHotkeyCapture()
        XCTAssertNotNil(UserDefaults.standard)
    }

    private func clearUserDefaults() {
        for key in userDefaultKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

final class ControllerIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testBackendSetupDialogShowsProgressFailureReadyAndActions() {
        let controller = BackendSetupDialogController()
        var invoked: [String] = []
        controller.onRetry = { invoked.append("retry") }
        controller.onOpenSettings = { invoked.append("settings") }
        controller.onViewLogs = { invoked.append("logs") }
        controller.onStartRecording = { invoked.append("record") }
        controller.onAbort = { invoked.append("abort") }

        controller.showProgress(
            status: "Checking backend runtime",
            detail: "Looking for runtime...",
            percent: 33.2,
            elapsed: "Elapsed: 5s",
            allowClose: false
        )
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller._test_statusText(), "Checking backend runtime")
        XCTAssertEqual(controller._test_elapsedText(), "Elapsed: 5s")
        XCTAssertEqual(controller._test_percentText(), "33%")
        XCTAssertEqual(controller._test_progressValue(), 33.2, accuracy: 0.2)

        controller.updateProgress(
            status: "Loading model",
            detail: "Warmup in progress",
            percent: 79.7,
            elapsed: "Elapsed: 12s",
            allowClose: false
        )
        XCTAssertEqual(controller._test_statusText(), "Loading model")
        XCTAssertEqual(controller._test_percentText(), "80%")

        controller.showFailure(status: "Backend setup failed", detail: "Download error", percent: 64)
        XCTAssertEqual(controller._test_statusText(), "Backend setup failed")
        XCTAssertEqual(controller._test_detailText(), "Download error")

        controller.showReady(detail: "Speech engine ready", startRecordingEnabled: true)
        XCTAssertEqual(controller._test_statusText(), "Speech engine is ready")
        XCTAssertEqual(controller._test_percentText(), "100%")
        controller.focus()

        controller._test_triggerRetry()
        controller._test_triggerOpenSettings()
        controller._test_triggerViewLogs()
        controller._test_triggerStartRecording()
        controller._test_triggerAbort()
        XCTAssertEqual(invoked, ["retry", "settings", "logs", "record", "abort"])

        controller.hide()
        XCTAssertFalse(controller.isVisible)
    }

    func testTranscriptPanelRecordingAndTranscriptDisplayFlow() {
        let controller = TranscriptPanelController()

        controller.showRecording()
        XCTAssertTrue(controller._test_isRecordingPanelVisible())
        XCTAssertEqual(controller._test_recordingTitleText(), "Recording")

        controller.showTranscribing()
        XCTAssertEqual(controller._test_recordingTitleText(), "Transcribing")

        controller.showWarming(queuedRecording: true)
        XCTAssertEqual(controller._test_recordingTitleText(), "Preparing speech engine")
        XCTAssertTrue(controller._test_recordingSubtitleText().contains("automatically"))

        controller.showWarming(queuedRecording: false, subtitle: "Custom subtitle")
        XCTAssertEqual(controller._test_recordingSubtitleText(), "Custom subtitle")

        controller.show(transcript: "hello world", language: "en", activateApp: false)
        XCTAssertTrue(controller._test_isTranscriptPanelVisible())
        XCTAssertFalse(controller._test_isRecordingPanelVisible())
        XCTAssertEqual(controller._test_transcriptText(), "hello world")
        XCTAssertEqual(controller._test_languageText(), "Language: en")

        NSPasteboard.general.clearContents()
        controller._test_triggerCopyTranscript()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello world")

        controller.dismissRecordingOverlay()
        XCTAssertFalse(controller._test_isRecordingPanelVisible())
    }

    func testSettingsWindowShowCreatesWindowOnce() {
        let controller = SettingsWindowController()
        XCTAssertFalse(controller._test_windowExists())
        controller.show()
        XCTAssertTrue(controller._test_windowExists())
        controller.show()
        XCTAssertTrue(controller._test_windowExists())
    }
}

final class AppDelegateHelperLogicTests: XCTestCase {
    private let agreementKey = UserSettingKey.backendSetupAgreementAccepted

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        UserDefaults.standard.removeObject(forKey: agreementKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: agreementKey)
        super.tearDown()
    }

    func testParserAndLabelHelpers() {
        let delegate = AppDelegate()
        delegate._test_setConfig(
            AppConfig(
                backendBaseURL: URL(string: "http://127.0.0.1:8001")!,
                requestTimeoutSeconds: 5,
                maxRetryCount: 1,
                retryBaseDelayMs: 10,
                autoCopyTranscript: false,
                outputMode: .both,
                hotKey: .default,
                apiToken: nil,
                maxUploadBytes: 1000,
                modelName: .fast06B
            )
        )

        XCTAssertEqual(delegate._test_menuBarTitle("idle"), "Q")
        XCTAssertEqual(delegate._test_menuBarSymbolName("recording"), "mic.fill")
        XCTAssertEqual(delegate._test_startBackendMenuTitle(), "Start Backend")
        XCTAssertEqual(delegate._test_outputModeLabel(), "clipboard + active app")
        XCTAssertTrue(delegate._test_isManagedLocalBackendURL())
        XCTAssertFalse(delegate._test_canUseUserNotifications())
        XCTAssertEqual(delegate._test_extractPercentage("load 145%"), 100)
        XCTAssertEqual(delegate._test_extractPercentage("load 45%"), 45)
        XCTAssertNil(delegate._test_extractPercentage("no percent"))
        XCTAssertEqual(delegate._test_extractFraction("4 / 8") ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(delegate._test_extractFraction("10/5") ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertNil(delegate._test_extractFraction("0 / 0"))
        XCTAssertEqual(delegate._test_sanitizeTranscriptText("  hello  "), "hello")
        XCTAssertEqual(delegate._test_sanitizeTranscriptText("ASRTranscription(text='')"), "")
        XCTAssertFalse(delegate._test_shouldAutoShowTranscriptPanel())
    }

    func testWarmupAndBackendOutputHandling() {
        let delegate = AppDelegate()
        delegate._test_setBackendSetupPhase("checkingRuntime")
        delegate._test_setBackendSetupProgress(20)
        delegate._test_handleBackendOutputLine("Fetching model files 3 / 10")
        XCTAssertEqual(delegate._test_backendSetupPhase(), "checkingRuntime")
        XCTAssertGreaterThanOrEqual(delegate._test_backendSetupProgress(), 45)
        XCTAssertTrue(delegate._test_latestBackendOutputDetail().contains("Fetching"))

        delegate._test_setBackendSetupPhase("warmingModel")
        delegate._test_handleBackendOutputLine("Loading checkpoint shards 37%")
        XCTAssertGreaterThanOrEqual(delegate._test_backendSetupProgress(), 72)

        delegate._test_handleBackendOutputLine("Model loaded successfully")
        XCTAssertGreaterThanOrEqual(delegate._test_backendSetupProgress(), 95)

        delegate._test_setRecentBackendOutputLines(["line 1", "line 2"])
        delegate._test_setQueuedRecordingIntent(true)
        delegate._test_setBackendDownloadDetected(true)
        let detail = delegate._test_warmingDetailMessage(elapsedSeconds: 95)
        XCTAssertTrue(detail.contains("Downloading speech model files"))
        XCTAssertTrue(detail.contains("line 2"))
        XCTAssertTrue(detail.contains("automatically"))

        let floor = delegate._test_warmingProgressFloor(elapsedSeconds: 30, timeoutSeconds: 180)
        XCTAssertGreaterThan(floor, 60)
    }

    func testSetupLifecycleAndStateTransitions() {
        let delegate = AppDelegate()
        delegate._test_updateSetupProgress(
            phase: "launchingBackend",
            progress: 30,
            status: "launching",
            detail: "booting"
        )
        delegate._test_updateSetupProgress(
            phase: "launchingBackend",
            progress: 10,
            status: "ignored",
            detail: "ignored"
        )
        XCTAssertGreaterThanOrEqual(delegate._test_backendSetupProgress(), 30)

        delegate._test_showSetupFailure(reason: "boom")
        XCTAssertEqual(delegate._test_backendSetupPhase(), "failed")

        delegate._test_resetSetupProgress()
        XCTAssertEqual(delegate._test_backendSetupPhase(), "idle")
        XCTAssertEqual(delegate._test_backendSetupProgress(), 0)

        delegate._test_transitionBackendState("ready")
        XCTAssertEqual(delegate._test_backendStatusLine(), "Backend: healthy")
        XCTAssertFalse(delegate._test_canRetryBackend())

        delegate._test_transitionBackendState("failed")
        XCTAssertEqual(delegate._test_backendStatusLine(), "Backend: needs attention")
        XCTAssertTrue(delegate._test_canRetryBackend())

        delegate._test_transitionBackendState("notStarted")
        XCTAssertTrue(delegate._test_canStartBackend())
        XCTAssertEqual(delegate._test_backendStatusLine(), "Backend: not started")
    }

    func testBackendProcessExitAndAbortPaths() {
        let delegate = AppDelegate()
        delegate._test_transitionBackendState("ready")
        delegate._test_handleBackendProcessExit(status: 9)
        XCTAssertEqual(delegate._test_backendStartupState(), "failed")

        delegate._test_setBackendSetupPhase("warmingModel")
        delegate._test_abortBackendSetup()
        XCTAssertEqual(delegate._test_backendSetupPhase(), "failed")
        XCTAssertEqual(delegate._test_backendStartupState(), "notStarted")
        XCTAssertEqual(delegate._test_backendNoticeText(), "Backend setup aborted by user.")
    }
}

final class AppDelegateLifecycleIntegrationTests: XCTestCase {
    private let launchGuideKey = UserSettingKey.launchGuideShown

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        UserDefaults.standard.set(true, forKey: launchGuideKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: launchGuideKey)
        super.tearDown()
    }

    func testApplicationLifecycleRunsWithoutInteractiveUI() {
        let delegate = AppDelegate()
        delegate._test_applicationDidFinishLaunching()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        delegate._test_settingsDidChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        delegate._test_applicationWillTerminate()
        XCTAssertNotNil(delegate)
    }

    func testActionAndClipboardPathsExecute() {
        let delegate = AppDelegate()
        delegate._test_setConfig(
            AppConfig(
                backendBaseURL: URL(string: "http://127.0.0.1:8001")!,
                requestTimeoutSeconds: 1,
                maxRetryCount: 0,
                retryBaseDelayMs: 1,
                autoCopyTranscript: true,
                outputMode: .clipboard,
                hotKey: .default,
                apiToken: nil,
                maxUploadBytes: 1024 * 1024,
                modelName: .fast06B
            )
        )

        delegate._test_setupStatusItem()
        delegate._test_transitionRecordingState("idle")
        delegate._test_transitionRecordingState("recording")
        delegate._test_transitionRecordingState("transcribing")
        _ = delegate._test_currentMenuBarSymbolName()
        delegate._test_configureBackendSetupDialogActions()
        delegate._test_setBackendNotice("notice")
        delegate._test_setBackendNotice(nil)
        delegate._test_copyToClipboard("openflow-copy")
        delegate._test_deliverTranscript("openflow-transcript")
        delegate._test_showLastTranscript()
        delegate._test_openSettingsAction()
        delegate._test_requestNotificationAuthorizationIfNeeded()
        delegate._test_notifyBackendReady()
        delegate._test_presentReadyFallbackNotification()
        delegate._test_openBackendLogs()
        delegate._test_stopBackendAction()
        delegate._test_applicationWillTerminate()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "openflow-transcript")
    }
}

final class AppDelegateAdvancedFlowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        UserDefaults.standard.set(true, forKey: UserSettingKey.backendSetupAgreementAccepted)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserSettingKey.backendSetupAgreementAccepted)
        super.tearDown()
    }

    func testRefreshLiveBackendHealthTransitionsDegradedUnreachableReady() {
        let delegate = AppDelegate()
        delegate._test_setConfig(
            AppConfig(
                backendBaseURL: URL(string: "http://127.0.0.1:8001")!,
                requestTimeoutSeconds: 1,
                maxRetryCount: 0,
                retryBaseDelayMs: 1,
                autoCopyTranscript: false,
                outputMode: .none,
                hotKey: .default,
                apiToken: nil,
                maxUploadBytes: 1024 * 1024,
                modelName: .fast06B
            )
        )
        delegate._test_setASRClient(
            makeMockHealthClient(
                stubs: [
                    makeHealthStub(modelLoaded: false),
                    makeHealthErrorStub(),
                    makeHealthStub(modelLoaded: true),
                ]
            )
        )

        delegate._test_refreshLiveBackendHealth()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(delegate._test_backendStartupState(), "degraded")

        delegate._test_refreshLiveBackendHealth()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(delegate._test_backendStartupState(), "notStarted")
        XCTAssertEqual(delegate._test_backendNoticeText(), "Backend is unreachable. Check URL or start backend.")

        delegate._test_refreshLiveBackendHealth()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(delegate._test_backendStartupState(), "ready")
    }

    func testStartBackendFlowExternalTimeoutTransitionsToFailure() {
        let delegate = AppDelegate()
        delegate._test_setConfig(
            AppConfig(
                backendBaseURL: URL(string: "http://example.com:8001")!,
                requestTimeoutSeconds: 1,
                maxRetryCount: 0,
                retryBaseDelayMs: 1,
                autoCopyTranscript: false,
                outputMode: .none,
                hotKey: .default,
                apiToken: nil,
                maxUploadBytes: 1024 * 1024,
                modelName: .fast06B
            )
        )
        delegate._test_setASRClient(
            makeMockHealthClient(
                stubs: [
                    makeHealthStub(modelLoaded: false),
                    makeHealthStub(modelLoaded: false),
                ]
            )
        )
        delegate._test_startBackendFlow(userRequestedRecording: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        delegate._test_setBackendSetupTimeoutSeconds(1)
        delegate._test_setBackendWarmupStartedAt(Date().addingTimeInterval(-120))

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && delegate._test_backendStartupState() != "failed" {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertEqual(delegate._test_backendStartupState(), "failed")
        XCTAssertEqual(delegate._test_backendStatusLine(), "Backend: needs attention")
    }

    func testStartBackendFlowEarlyReturnBranches() {
        let delegate = AppDelegate()
        delegate._test_setConfig(
            AppConfig(
                backendBaseURL: URL(string: "http://127.0.0.1:8001")!,
                requestTimeoutSeconds: 1,
                maxRetryCount: 0,
                retryBaseDelayMs: 1,
                autoCopyTranscript: false,
                outputMode: .none,
                hotKey: .default,
                apiToken: nil,
                maxUploadBytes: 1024 * 1024,
                modelName: .fast06B
            )
        )
        delegate._test_setASRClient(makeMockHealthClient(stubs: [makeHealthStub(modelLoaded: true)]))
        delegate._test_markBackendReady(triggerQueuedRecording: false, notifyUser: false)
        delegate._test_startBackendFlow(userRequestedRecording: false)
        XCTAssertEqual(delegate._test_backendStartupState(), "ready")
        XCTAssertTrue(delegate._test_isBackendReady())

        delegate._test_transitionBackendState("starting")
        delegate._test_startBackendFlow(userRequestedRecording: false)
        XCTAssertEqual(delegate._test_backendStartupState(), "starting")

        delegate._test_transitionBackendState("warming")
        delegate._test_startBackendFlow(userRequestedRecording: false)
        XCTAssertEqual(delegate._test_backendStartupState(), "warming")
    }

    func testActionMethodsAndNotificationHelpersExecute() {
        let delegate = AppDelegate()
        delegate._test_setConfig(
            AppConfig(
                backendBaseURL: URL(string: "http://example.com:8001")!,
                requestTimeoutSeconds: 1,
                maxRetryCount: 0,
                retryBaseDelayMs: 1,
                autoCopyTranscript: false,
                outputMode: .both,
                hotKey: .default,
                apiToken: nil,
                maxUploadBytes: 1024 * 1024,
                modelName: .fast06B
            )
        )
        delegate._test_setASRClient(
            makeMockHealthClient(stubs: Array(repeating: makeHealthStub(modelLoaded: false), count: 20))
        )

        delegate._test_refreshBackendStatusAction()
        delegate._test_startBackendAction()
        delegate._test_retryBackendAction()
        delegate._test_toggleRecordingFromHotKey()
        delegate._test_toggleRecordingMenuAction()
        delegate._test_toggleRecording()
        delegate._test_startRecording()
        delegate._test_stopRecordingAndTranscribe()
        delegate._test_showSetupProgressAction()
        delegate._test_openSettingsAction()
        delegate._test_showLastTranscript()
        delegate._test_requestNotificationAuthorizationIfNeeded()
        delegate._test_notifyBackendReady()
        delegate._test_deliverReadyLocalNotification()
        delegate._test_presentReadyFallbackNotification()
        _ = delegate._test_presentBackendSetupAgreementDialog()
        delegate._test_captureOutputTargetApplication()
        delegate._test_setOutputTargetApplicationToCurrentApp()
        delegate._test_deliverTranscript("integration transcript")
        delegate._test_pasteToCapturedApplication("direct paste")
        _ = delegate._test_sendPasteShortcut()
        delegate._test_showError("test error")
        delegate._test_showInfo("test info")
        delegate._test_openBackendLogs()

        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        delegate._test_stopBackendForCleanup()
        delegate._test_applicationWillTerminate()
        XCTAssertTrue(true)
    }
}

final class AppDelegateBackendFlowIntegrationTests: XCTestCase {
    private var originalDirectoryPath = ""
    private var originalPathEnv: String?
    private var temporaryRoots: [URL] = []

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        originalDirectoryPath = FileManager.default.currentDirectoryPath
        originalPathEnv = ProcessInfo.processInfo.environment["PATH"]
        UserDefaults.standard.set(true, forKey: UserSettingKey.backendSetupAgreementAccepted)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserSettingKey.backendSetupAgreementAccepted)
        _ = FileManager.default.changeCurrentDirectoryPath(originalDirectoryPath)
        if let originalPathEnv {
            setenv("PATH", originalPathEnv, 1)
        } else {
            unsetenv("PATH")
        }

        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        super.tearDown()
    }

    func testStartBackendFlowTransitionsToReady() throws {
        let root = try makeFakeBackendWorkspace()
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(root.path))
        setenv("PATH", "", 1)

        let delegate = AppDelegate()
        delegate._test_setConfig(
            AppConfig(
                backendBaseURL: URL(string: "http://127.0.0.1:8001")!,
                requestTimeoutSeconds: 1,
                maxRetryCount: 0,
                retryBaseDelayMs: 1,
                autoCopyTranscript: false,
                outputMode: .none,
                hotKey: .default,
                apiToken: nil,
                maxUploadBytes: 1024 * 1024,
                modelName: .fast06B
            )
        )
        delegate._test_setASRClient(
            makeMockHealthClient(
                stubs: [
                    makeHealthStub(modelLoaded: false),
                    makeHealthStub(modelLoaded: true),
                ]
            )
        )

        delegate._test_startBackendFlow(userRequestedRecording: false)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && delegate._test_backendStartupState() != "ready" {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(delegate._test_backendStartupState(), "ready")
        XCTAssertEqual(delegate._test_backendStatusLine(), "Backend: healthy")
        delegate._test_stopBackendForCleanup()
    }

    private func makeFakeBackendWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openflow-appdelegate-\(UUID().uuidString)", isDirectory: true)
        let backendDirectory = root.appendingPathComponent("backend", isDirectory: true)
        let binDirectory = backendDirectory.appendingPathComponent(".venv/bin", isDirectory: true)

        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let serverScript = backendDirectory.appendingPathComponent("qwen_server.py")
        try "print('placeholder')\n".write(to: serverScript, atomically: true, encoding: .utf8)

        let fakePython = binDirectory.appendingPathComponent("python")
        let launcher = """
        #!/bin/sh
        echo backend-ready
        /bin/sleep 5
        exit 0
        """
        try launcher.write(to: fakePython, atomically: true, encoding: .utf8)
        let status = chmod(fakePython.path, 0o755)
        if status != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        temporaryRoots.append(root)
        return root
    }
}
