import AppKit
import Carbon.HIToolbox
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum RecordingState {
        case idle
        case recording
        case transcribing
    }

    private enum BackendStartupState {
        case notStarted
        case starting
        case warming
        case ready
        case failed(String)
    }

    private var config = AppConfig.load()
    private let recorder = AudioRecorder()
    private var asrClient: ASRClient!
    private let transcriptPanel = TranscriptPanelController()

    private var statusItem: NSStatusItem?
    private var hotKeyManager: GlobalHotKeyManager?
    private let backendSupervisor = BackendSupervisor()

    private var state: RecordingState = .idle
    private var lastTranscript = ""
    private var backendStartupState: BackendStartupState = .notStarted
    private var backendNoticeText: String?
    private var isBackendReady = false
    private var queuedRecordingIntent = false
    private var backendWarmupStartedAt: Date?
    private var backendWarmupTimer: Timer?
    private var backendStatusIconTimer: Timer?
    private var backendStatusIconFrame = 0
    private var hasShownLongWarmupNotice = false
    private let appSessionID = UUID().uuidString
    private var outputTargetApplication: NSRunningApplication?
    private let settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .quickASRSettingsDidChange,
            object: nil
        )
        reloadConfiguration(rebuildHotkey: false)
        setupStatusItem()
        requestNotificationAuthorizationIfNeeded()
        registerHotKey()
        probeBackendReadiness { ready in
            if ready {
                self.markBackendReady(triggerQueuedRecording: false, notifyUser: false)
            } else {
                self.backendStartupState = .notStarted
                self.backendNoticeText = nil
                self.rebuildMenu()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopBackendWarmupPolling()
        stopBackendStatusIconAnimation()
        backendSupervisor.stop()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        statusItem = item
        rebuildMenu()
    }

    private func registerHotKey() {
        hotKeyManager = nil

        do {
            hotKeyManager = try GlobalHotKeyManager(config: config.hotKey) {
                self.toggleRecordingFromHotKey()
            }
        } catch {
            showError("Failed to register global hotkey (\(config.hotKey.displayText)): \(error.localizedDescription)")
        }
    }

    @objc
    private func settingsDidChange() {
        reloadConfiguration(rebuildHotkey: true)
        if !isManagedLocalBackendURL {
            backendSupervisor.stop()
        }
        probeBackendReadiness { ready in
            if ready {
                self.markBackendReady(triggerQueuedRecording: false, notifyUser: false)
            } else if self.backendSupervisor.isRunning {
                self.transitionBackendState(to: .warming)
                self.setBackendNotice("Backend is still warming up...")
            } else {
                self.transitionBackendState(to: .notStarted)
                if self.isManagedLocalBackendURL {
                    self.setBackendNotice(nil)
                } else {
                    self.setBackendNotice("Using external backend URL. Start it manually, then use Start Backend to wait for readiness.")
                }
            }
        }
    }

    private func reloadConfiguration(rebuildHotkey: Bool) {
        config = AppConfig.load()
        asrClient = ASRClient(
            config: ASRClientConfiguration(
                baseURL: config.backendBaseURL,
                timeoutSeconds: config.requestTimeoutSeconds,
                retryCount: config.maxRetryCount,
                retryBaseDelayMs: config.retryBaseDelayMs,
                apiToken: config.apiToken,
                maxUploadBytes: config.maxUploadBytes
            )
        )

        if rebuildHotkey {
            registerHotKey()
        }

        rebuildMenu()
        log("Configuration reloaded backend=\(config.backendBaseURL.absoluteString) hotkey=\(config.hotKey.displayText) output=\(outputModeLabel())")
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleTitle = state == .recording ? "Stop Recording" : "Start Recording"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleRecordingMenuAction), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = state != .transcribing
        menu.addItem(toggleItem)

        let showItem = NSMenuItem(title: "Show Last Transcript", action: #selector(showLastTranscript), keyEquivalent: "")
        showItem.target = self
        showItem.isEnabled = !lastTranscript.isEmpty
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let info = NSMenuItem(title: "Hotkey: \(config.hotKey.displayText)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        let backend = NSMenuItem(title: "Backend URL: \(config.backendBaseURL.absoluteString)", action: nil, keyEquivalent: "")
        backend.isEnabled = false
        menu.addItem(backend)

        let backendStatus = NSMenuItem(title: backendStatusLine(), action: nil, keyEquivalent: "")
        backendStatus.isEnabled = false
        menu.addItem(backendStatus)

        if let backendNoticeText, !backendNoticeText.isEmpty {
            let backendNote = NSMenuItem(title: backendNoticeText, action: nil, keyEquivalent: "")
            backendNote.isEnabled = false
            menu.addItem(backendNote)
        }

        let outputMode = NSMenuItem(title: "Output: \(outputModeLabel())", action: nil, keyEquivalent: "")
        outputMode.isEnabled = false
        menu.addItem(outputMode)

        let startBackend = NSMenuItem(title: startBackendMenuTitle(), action: #selector(startBackendAction), keyEquivalent: "")
        startBackend.target = self
        startBackend.isEnabled = canStartBackend
        menu.addItem(startBackend)

        let stopBackend = NSMenuItem(title: "Stop Backend", action: #selector(stopBackendAction), keyEquivalent: "")
        stopBackend.target = self
        stopBackend.isEnabled = backendSupervisor.isRunning && isManagedLocalBackendURL
        menu.addItem(stopBackend)

        let retryBackend = NSMenuItem(title: "Retry Startup", action: #selector(retryBackendAction), keyEquivalent: "")
        retryBackend.target = self
        retryBackend.isEnabled = canRetryBackend
        menu.addItem(retryBackend)

        let refreshBackendStatus = NSMenuItem(title: "Refresh Backend Status", action: #selector(refreshBackendStatusAction), keyEquivalent: "")
        refreshBackendStatus.target = self
        refreshBackendStatus.isEnabled = state != .transcribing
        menu.addItem(refreshBackendStatus)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = state != .transcribing
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        updateStatusItemAppearance()
    }

    private func menuBarTitle(for state: RecordingState) -> String {
        switch state {
        case .idle:
            return "Q"
        case .recording:
            return "R"
        case .transcribing:
            return "..."
        }
    }

    private func menuBarSymbolName(for state: RecordingState) -> String {
        switch state {
        case .idle:
            return "waveform"
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else {
            return
        }

        let symbolName = currentMenuBarSymbolName()
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Openflow status") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            button.image = image.withSymbolConfiguration(config)
            button.title = ""
            if state == .recording {
                button.contentTintColor = .systemRed
            } else if state == .transcribing {
                button.contentTintColor = .systemBlue
            } else if isBackendWarmupActive {
                button.contentTintColor = .systemOrange
            } else {
                button.contentTintColor = nil
            }
        } else {
            button.image = nil
            button.contentTintColor = nil
            button.title = menuBarTitle(for: state)
        }
    }

    private func transition(to nextState: RecordingState) {
        state = nextState
        refreshBackendStatusIconAnimation()
        rebuildMenu()
    }

    private func toggleRecordingFromHotKey() {
        DispatchQueue.main.async {
            self.toggleRecording()
        }
    }

    @objc
    private func toggleRecordingMenuAction() {
        toggleRecording()
    }

    @objc
    private func refreshBackendStatusAction() {
        probeBackendReadiness { ready in
            if ready {
                self.markBackendReady(triggerQueuedRecording: false, notifyUser: false)
            } else if self.backendSupervisor.isRunning {
                self.transitionBackendState(to: .warming)
                self.setBackendNotice("Backend is still loading. Please wait a little longer.")
                self.transcriptPanel.showWarming(
                    queuedRecording: self.queuedRecordingIntent,
                    subtitle: "Loading speech model..."
                )
            } else {
                self.transitionBackendState(to: .notStarted)
                if self.isManagedLocalBackendURL {
                    self.setBackendNotice("Backend is not running. Use Start Backend.")
                } else {
                    self.setBackendNotice("External backend URL configured. Start backend manually, then retry.")
                }
            }
        }
    }

    @objc
    private func startBackendAction() {
        startBackendFlow(userRequestedRecording: false)
    }

    @objc
    private func retryBackendAction() {
        startBackendFlow(userRequestedRecording: false)
    }

    @objc
    private func stopBackendAction() {
        queuedRecordingIntent = false
        stopBackendWarmupPolling()
        backendSupervisor.stop()
        isBackendReady = false
        transitionBackendState(to: .notStarted)
        if isManagedLocalBackendURL {
            setBackendNotice("Backend stopped.")
        } else {
            setBackendNotice("External backend mode: no managed process to stop.")
        }
        transcriptPanel.dismissRecordingOverlay()
    }

    @objc
    private func openSettingsAction() {
        settingsWindowController.show()
    }

    private func toggleRecording() {
        if state == .transcribing {
            return
        }

        if state == .recording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard isBackendReady else {
            ensureBackendReadyThenStartRecording()
            return
        }

        captureOutputTargetApplication()

        recorder.start { result in
            switch result {
            case .success:
                self.transition(to: .recording)
                self.transcriptPanel.showRecording()
            case .failure(let error):
                self.transition(to: .idle)
                self.showError("Unable to start recording: \(error.localizedDescription)")
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        guard state == .recording else {
            return
        }

        guard let fileURL = recorder.stop() else {
            transition(to: .idle)
            showError("No recording file found.")
            return
        }

        transition(to: .transcribing)
        transcriptPanel.showTranscribing()

        let requestID = "\(appSessionID)-\(UUID().uuidString.prefix(8))"
        asrClient.transcribe(audioFileURL: fileURL, requestID: requestID) { result in
            DispatchQueue.main.async {
                self.transition(to: .idle)

                switch result {
                case .success(let response):
                    let text = self.sanitizeTranscriptText(response.text)
                    self.lastTranscript = text
                    self.transcriptPanel.dismissRecordingOverlay()

                    if !text.isEmpty {
                        self.deliverTranscript(text)
                    }

                    if self.shouldAutoShowTranscriptPanel() {
                        self.transcriptPanel.show(
                            transcript: text.isEmpty ? "(empty transcript)" : text,
                            language: response.language ?? "unknown",
                            activateApp: !self.config.outputMode.shouldPasteToActiveApp
                        )
                    }

                case .failure(let error):
                    self.transcriptPanel.dismissRecordingOverlay()
                    self.log("Transcription failed request_id=\(requestID) error=\(error.localizedDescription)")
                    self.showError("Transcription failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func probeBackendReadiness(completion: @escaping (Bool) -> Void) {
        let requestID = "\(appSessionID)-health-\(UUID().uuidString.prefix(8))"
        asrClient.checkHealth(requestID: requestID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let health):
                    self.log("Health check request_id=\(requestID) status=\(health.status) model_loaded=\(health.modelLoaded)")
                    completion(health.modelLoaded)
                case .failure(let error):
                    self.log("Health check failed request_id=\(requestID) error=\(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }

    private func ensureBackendReadyThenStartRecording() {
        queuedRecordingIntent = true
        startBackendFlow(userRequestedRecording: true)
    }

    private func startBackendFlow(userRequestedRecording: Bool) {
        if userRequestedRecording {
            queuedRecordingIntent = true
        }

        if isBackendReady {
            markBackendReady(triggerQueuedRecording: true, notifyUser: false)
            return
        }

        if case .starting = backendStartupState {
            transcriptPanel.showWarming(queuedRecording: queuedRecordingIntent, subtitle: warmingSubtitle())
            return
        }
        if case .warming = backendStartupState {
            transcriptPanel.showWarming(queuedRecording: queuedRecordingIntent, subtitle: warmingSubtitle())
            return
        }

        probeBackendReadiness { ready in
            if ready {
                self.markBackendReady(triggerQueuedRecording: true, notifyUser: false)
                return
            }

            if self.isManagedLocalBackendURL {
                do {
                    let launchInfo = try self.backendSupervisor.start()
                    self.log("Started backend command=\(launchInfo.commandDescription) cwd=\(launchInfo.workingDirectory.path)")
                } catch BackendSupervisorError.alreadyRunning {
                    self.log("Backend process already running")
                } catch {
                    self.transitionBackendState(to: .failed("Could not start backend. \(error.localizedDescription)"))
                    self.transcriptPanel.dismissRecordingOverlay()
                    self.setBackendNotice("Could not start backend. \(error.localizedDescription)")
                    self.queuedRecordingIntent = false
                    return
                }
            } else {
                self.setBackendNotice("External backend URL mode. Start your server manually, then Openflow will auto-detect readiness.")
            }

            self.transitionBackendState(to: .starting)
            self.beginBackendWarmupPolling()
            self.transcriptPanel.showWarming(queuedRecording: self.queuedRecordingIntent, subtitle: self.warmingSubtitle())
        }
    }

    private func beginBackendWarmupPolling() {
        stopBackendWarmupPolling()
        backendWarmupStartedAt = Date()
        hasShownLongWarmupNotice = false

        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            self.probeBackendReadiness { ready in
                if ready {
                    self.markBackendReady(triggerQueuedRecording: true, notifyUser: true)
                    return
                }

                self.transitionBackendState(to: .warming)
                self.transcriptPanel.showWarming(queuedRecording: self.queuedRecordingIntent, subtitle: self.warmingSubtitle())

                let elapsed = Date().timeIntervalSince(self.backendWarmupStartedAt ?? Date())
                if elapsed >= 45, !self.hasShownLongWarmupNotice {
                    self.hasShownLongWarmupNotice = true
                    self.setBackendNotice("Still loading... first run can take longer.")
                }
                if elapsed >= 180 {
                    self.stopBackendWarmupPolling()
                    self.transitionBackendState(to: .failed("Backend startup timed out after 3 minutes. Retry startup or check backend logs."))
                    self.transcriptPanel.dismissRecordingOverlay()
                    if self.isManagedLocalBackendURL {
                        self.setBackendNotice("Backend startup timed out. Retry startup or check logs.")
                    } else {
                        self.setBackendNotice("External backend not ready yet. Verify URL/server, then retry.")
                    }
                    self.queuedRecordingIntent = false
                }
            }
        }

        backendWarmupTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopBackendWarmupPolling() {
        backendWarmupTimer?.invalidate()
        backendWarmupTimer = nil
    }

    private func markBackendReady(triggerQueuedRecording: Bool, notifyUser: Bool) {
        stopBackendWarmupPolling()
        transitionBackendState(to: .ready)
        isBackendReady = true
        setBackendNotice(nil)
        transcriptPanel.dismissRecordingOverlay()

        if notifyUser {
            deliverReadyNotificationIfAuthorized()
        }

        if triggerQueuedRecording, queuedRecordingIntent {
            queuedRecordingIntent = false
            startRecording()
        }
    }

    private func transitionBackendState(to nextState: BackendStartupState) {
        backendStartupState = nextState
        if case .ready = nextState {
            isBackendReady = true
        } else {
            isBackendReady = false
        }
        refreshBackendStatusIconAnimation()
        rebuildMenu()
    }

    private var isBackendWarmupActive: Bool {
        if case .starting = backendStartupState {
            return true
        }
        if case .warming = backendStartupState {
            return true
        }
        return false
    }

    private func currentMenuBarSymbolName() -> String {
        if state == .recording || state == .transcribing {
            return menuBarSymbolName(for: state)
        }

        if isBackendWarmupActive {
            let symbols = [
                "hourglass.bottomhalf.filled",
                "hourglass",
                "hourglass.tophalf.filled",
                "hourglass"
            ]
            return symbols[backendStatusIconFrame % symbols.count]
        }

        return menuBarSymbolName(for: state)
    }

    private func refreshBackendStatusIconAnimation() {
        if isBackendWarmupActive, state == .idle {
            startBackendStatusIconAnimationIfNeeded()
        } else {
            stopBackendStatusIconAnimation()
        }
    }

    private func startBackendStatusIconAnimationIfNeeded() {
        guard backendStatusIconTimer == nil else {
            return
        }

        backendStatusIconFrame = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            self.backendStatusIconFrame += 1
            self.updateStatusItemAppearance()
        }
        backendStatusIconTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        updateStatusItemAppearance()
    }

    private func stopBackendStatusIconAnimation() {
        backendStatusIconTimer?.invalidate()
        backendStatusIconTimer = nil
        backendStatusIconFrame = 0
        updateStatusItemAppearance()
    }

    private var canStartBackend: Bool {
        if backendSupervisor.isRunning && isManagedLocalBackendURL {
            return false
        }

        switch backendStartupState {
        case .starting, .warming:
            return false
        default:
            return true
        }
    }

    private var isManagedLocalBackendURL: Bool {
        guard let host = config.backendBaseURL.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func startBackendMenuTitle() -> String {
        isManagedLocalBackendURL ? "Start Backend" : "Wait for External Backend"
    }

    private func setBackendNotice(_ message: String?) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        backendNoticeText = (trimmed?.isEmpty == false) ? trimmed : nil
        rebuildMenu()
    }

    private func warmingSubtitle() -> String {
        let elapsedSeconds = Int(Date().timeIntervalSince(backendWarmupStartedAt ?? Date()))
        if queuedRecordingIntent {
            return "Warming up... ~\(elapsedSeconds)s elapsed. Recording starts automatically when ready."
        }
        return "Warming up... ~\(elapsedSeconds)s elapsed. We'll notify you when ready."
    }

    private var canRetryBackend: Bool {
        if case .failed = backendStartupState {
            return true
        }
        return false
    }

    private func backendStatusLine() -> String {
        switch backendStartupState {
        case .notStarted:
            return "Backend: not started"
        case .starting:
            return "Backend: starting service..."
        case .warming:
            return "Backend: loading speech model..."
        case .ready:
            return "Backend: healthy"
        case .failed:
            return "Backend: needs attention"
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                self.log("Notification permission request failed: \(error.localizedDescription)")
            } else {
                self.log("Notification permission granted=\(granted)")
            }
        }
    }

    private func deliverReadyNotificationIfAuthorized() {
        let content = UNMutableNotificationContent()
        content.title = "Openflow is ready"
        content.body = "Speech engine loaded. You can record now."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "openflow.backend.ready.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.log("Failed to post ready notification: \(error.localizedDescription)")
            }
        }
    }

    @objc
    private func showLastTranscript() {
        transcriptPanel.show(
            transcript: lastTranscript,
            language: "unknown",
            activateApp: true
        )
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Openflow"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func log(_ message: String) {
        NSLog("[Openflow] \(message)")
    }

    private func outputModeLabel() -> String {
        switch config.outputMode {
        case .clipboard:
            return "clipboard"
        case .activeApp:
            return "active app"
        case .both:
            return "clipboard + active app"
        case .none:
            return "none"
        }
    }

    private func captureOutputTargetApplication() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ownBundleIdentifier = Bundle.main.bundleIdentifier

        if let frontmost,
           frontmost.bundleIdentifier != ownBundleIdentifier {
            outputTargetApplication = frontmost
            log("Captured output target app bundle=\(frontmost.bundleIdentifier ?? "unknown")")
        } else {
            outputTargetApplication = nil
        }
    }

    private func deliverTranscript(_ text: String) {
        if config.outputMode.shouldCopyToClipboard {
            copyToClipboard(text)
        }

        if config.outputMode.shouldPasteToActiveApp {
            pasteToCapturedApplication(text)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pasteToCapturedApplication(_ text: String) {
        guard let targetApp = outputTargetApplication else {
            showError("No target app was focused when recording started. Keep the destination app focused, then record again.")
            return
        }

        let pasteboard = NSPasteboard.general
        let previousClipboardValue = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        targetApp.activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let pasted = self.sendPasteShortcut()

            if !self.config.outputMode.shouldCopyToClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    pasteboard.clearContents()
                    if let previousClipboardValue {
                        pasteboard.setString(previousClipboardValue, forType: .string)
                    }
                }
            }

            if !pasted {
                self.showError("Unable to paste into target app. Grant accessibility permission to Openflow in System Settings > Privacy & Security > Accessibility.")
            }
        }
    }

    private func sendPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func shouldAutoShowTranscriptPanel() -> Bool {
        !config.outputMode.shouldPasteToActiveApp
    }

    private func sanitizeTranscriptText(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ASRTranscription(") && trimmed.contains("text=''") {
            return ""
        }
        return trimmed
    }
}
