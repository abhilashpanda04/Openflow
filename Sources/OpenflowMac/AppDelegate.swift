import AppKit
import Carbon.HIToolbox
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum RecordingState {
        case idle
        case recording
        case transcribing
    }

    private enum BackendStartupState: Equatable {
        case notStarted
        case starting
        case warming
        case degraded
        case ready
        case failed(String)
    }

    private enum LiveBackendHealth {
        case healthy
        case degraded
        case unreachable
    }

    private enum BackendSetupPhase {
        case idle
        case agreementAccepted
        case checkingRuntime
        case launchingBackend
        case warmingModel
        case ready
        case failed
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
    private var healthMonitorTimer: Timer?
    private var hasShownLongWarmupNotice = false
    private var backendSetupPhase: BackendSetupPhase = .idle
    private var backendSetupProgress: Double = 0
    private var backendSetupStartedAt: Date?
    private var backendSetupReadyCloseTimer: Timer?
    private var backendSetupTimeoutSeconds: TimeInterval = 180
    private var backendDownloadDetected = false
    private var lastDownloadProgressAt: Date?
    private var hasShownDownloadStallWarning = false
    private var recentBackendOutputLines: [String] = []
    private let appSessionID = UUID().uuidString
    private var outputTargetApplication: NSRunningApplication?
    private let settingsWindowController = SettingsWindowController()
    private let backendSetupDialogController = BackendSetupDialogController()

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
        backendSupervisor.onProcessExit = { [weak self] status in
            self?.handleBackendProcessExit(status: status)
        }
        backendSupervisor.onOutputLine = { [weak self] line in
            self?.handleBackendOutputLine(line)
        }
        configureBackendSetupDialogActions()
        startHealthMonitorIfNeeded()
        registerHotKey()
        presentLaunchGuideIfNeeded()
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
        stopHealthMonitor()
        stopBackendSetupReadyCloseTimer()
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

        if backendSetupDialogController.isVisible {
            let showSetupProgress = NSMenuItem(title: "Show Setup Progress", action: #selector(showSetupProgressAction), keyEquivalent: "")
            showSetupProgress.target = self
            menu.addItem(showSetupProgress)
        }

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
                self.transcriptPanel.dismissRecordingOverlay()
                self.updateSetupProgress(
                    phase: .warmingModel,
                    progress: max(self.backendSetupProgress, 60),
                    status: "Loading speech model",
                    detail: "Live health check: backend is still warming up."
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
    private func showSetupProgressAction() {
        backendSetupDialogController.focus()
    }

    @objc
    private func stopBackendAction() {
        queuedRecordingIntent = false
        stopBackendWarmupPolling()
        stopBackendSetupReadyCloseTimer()
        backendSupervisor.stop()
        backendSetupDialogController.hide()
        resetSetupProgress()
        isBackendReady = false
        transitionBackendState(to: .notStarted)
        if isManagedLocalBackendURL {
            setBackendNotice("Backend stopped.")
        } else {
            setBackendNotice("External backend mode: no managed process to stop.")
        }
        transcriptPanel.dismissRecordingOverlay()
    }

    private func handleBackendProcessExit(status: Int32) {
        if case .notStarted = backendStartupState {
            return
        }
        if case .ready = backendStartupState {
            transitionBackendState(to: .failed("Backend stopped unexpectedly (exit code: \(status))."))
            setBackendNotice("Backend stopped unexpectedly. Click Retry Startup.")
            showSetupFailure(reason: "Backend stopped unexpectedly (exit code \(status)).")
            return
        }

        transitionBackendState(to: .failed("Backend process exited during warm-up (exit code: \(status))."))
        setBackendNotice("Backend exited during warm-up. Click Retry Startup.")
        queuedRecordingIntent = false
        stopBackendWarmupPolling()
        showSetupFailure(reason: "Backend exited during warm-up (exit code \(status)).")
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
        probeBackendHealth { health in
            completion(health == .healthy)
        }
    }

    private func probeBackendHealth(completion: @escaping (LiveBackendHealth) -> Void) {
        let requestID = "\(appSessionID)-health-\(UUID().uuidString.prefix(8))"
        asrClient.checkHealth(requestID: requestID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let health):
                    self.log("Health check request_id=\(requestID) status=\(health.status) model_loaded=\(health.modelLoaded)")
                    completion(health.modelLoaded ? .healthy : .degraded)
                case .failure(let error):
                    self.log("Health check failed request_id=\(requestID) error=\(error.localizedDescription)")
                    completion(.unreachable)
                }
            }
        }
    }

    private func startHealthMonitorIfNeeded() {
        guard healthMonitorTimer == nil else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshLiveBackendHealth()
        }
        healthMonitorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHealthMonitor() {
        healthMonitorTimer?.invalidate()
        healthMonitorTimer = nil
    }

    private func refreshLiveBackendHealth() {
        if case .starting = backendStartupState {
            return
        }
        if case .warming = backendStartupState {
            return
        }

        probeBackendHealth { health in
            switch health {
            case .healthy:
                if self.backendStartupState != .ready {
                    self.transitionBackendState(to: .ready)
                }
                if self.backendNoticeText == "Backend reachable but model not ready yet." ||
                    self.backendNoticeText == "Backend is unreachable. Check URL or start backend." {
                    self.setBackendNotice(nil)
                }

            case .degraded:
                if self.backendStartupState != .degraded {
                    self.transitionBackendState(to: .degraded)
                }
                self.setBackendNotice("Backend reachable but model not ready yet.")

            case .unreachable:
                if self.backendSupervisor.isRunning {
                    self.transitionBackendState(to: .warming)
                } else {
                    self.transitionBackendState(to: .notStarted)
                }
                self.setBackendNotice("Backend is unreachable. Check URL or start backend.")
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

        if backendSetupPhase == .failed || backendSetupPhase == .idle || backendSetupPhase == .ready {
            resetSetupProgress()
        }

        if isManagedLocalBackendURL, !hasAcceptedBackendSetupAgreement() {
            let accepted = presentBackendSetupAgreementDialog()
            if !accepted {
                setBackendNotice("Backend setup cancelled. Accept agreement to continue.")
                queuedRecordingIntent = false
                return
            }
            updateSetupProgress(
                phase: .agreementAccepted,
                progress: 10,
                status: "Agreement accepted",
                detail: "Preparing backend setup..."
            )
        }

        if isBackendReady {
            markBackendReady(triggerQueuedRecording: true, notifyUser: false)
            return
        }

        if case .starting = backendStartupState {
            transcriptPanel.dismissRecordingOverlay()
            updateSetupProgress(
                phase: .warmingModel,
                progress: max(60, backendSetupProgress),
                status: "Loading speech model",
                detail: warmingDetailMessage(elapsedSeconds: Date().timeIntervalSince(backendWarmupStartedAt ?? Date()))
            )
            return
        }
        if case .warming = backendStartupState {
            transcriptPanel.dismissRecordingOverlay()
            updateSetupProgress(
                phase: .warmingModel,
                progress: max(60, backendSetupProgress),
                status: "Loading speech model",
                detail: warmingDetailMessage(elapsedSeconds: Date().timeIntervalSince(backendWarmupStartedAt ?? Date()))
            )
            return
        }

        updateSetupProgress(
            phase: .checkingRuntime,
            progress: max(25, backendSetupProgress),
            status: "Checking backend runtime",
            detail: "Locating bundled runtime or local backend environment..."
        )

        probeBackendReadiness { ready in
            if ready {
                self.markBackendReady(triggerQueuedRecording: true, notifyUser: false)
                return
            }

            if self.isManagedLocalBackendURL {
                do {
                    let launchInfo = try self.backendSupervisor.start(modelName: self.config.modelName)
                    self.log("Started backend command=\(launchInfo.commandDescription) cwd=\(launchInfo.workingDirectory.path)")
                    self.updateSetupProgress(
                        phase: .launchingBackend,
                        progress: max(40, self.backendSetupProgress),
                        status: "Backend process launched",
                        detail: launchInfo.commandDescription
                    )
                } catch BackendSupervisorError.alreadyRunning {
                    self.log("Backend process already running")
                    self.updateSetupProgress(
                        phase: .launchingBackend,
                        progress: max(40, self.backendSetupProgress),
                        status: "Backend already running",
                        detail: "Connecting to existing local process..."
                    )
                } catch {
                    self.transitionBackendState(to: .failed("Could not start backend. \(error.localizedDescription)"))
                    self.transcriptPanel.dismissRecordingOverlay()
                    self.setBackendNotice("Could not start backend. \(error.localizedDescription)")
                    self.queuedRecordingIntent = false
                    self.showSetupFailure(reason: "Could not start backend. \(error.localizedDescription)")
                    return
                }
            } else {
                self.setBackendNotice("External backend URL mode. Start your server manually, then Openflow will auto-detect readiness.")
                self.updateSetupProgress(
                    phase: .launchingBackend,
                    progress: max(40, self.backendSetupProgress),
                    status: "Waiting for external backend",
                    detail: "Start your backend at \(self.config.backendBaseURL.absoluteString), then Openflow will continue."
                )
            }

            self.transitionBackendState(to: .starting)
            self.beginBackendWarmupPolling()
            self.transcriptPanel.dismissRecordingOverlay()
            self.updateSetupProgress(
                phase: .warmingModel,
                progress: max(60, self.backendSetupProgress),
                status: "Loading speech model",
                detail: self.warmingDetailMessage(elapsedSeconds: 0)
            )
        }
    }

    private func beginBackendWarmupPolling() {
        stopBackendWarmupPolling()
        backendWarmupStartedAt = Date()
        backendSetupTimeoutSeconds = 180
        backendDownloadDetected = false
        lastDownloadProgressAt = nil
        hasShownDownloadStallWarning = false
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
                let elapsed = Date().timeIntervalSince(self.backendWarmupStartedAt ?? Date())
                let minimumProgress = self.warmingProgressFloor(elapsedSeconds: elapsed, timeoutSeconds: self.backendSetupTimeoutSeconds)
                self.updateSetupProgress(
                    phase: .warmingModel,
                    progress: max(minimumProgress, self.backendSetupProgress),
                    status: "Loading speech model",
                    detail: self.warmingDetailMessage(elapsedSeconds: elapsed)
                )

                if self.backendDownloadDetected {
                    let lastProgress = self.lastDownloadProgressAt ?? (self.backendWarmupStartedAt ?? Date())
                    let stalledFor = Date().timeIntervalSince(lastProgress)
                    if stalledFor >= 480 {
                        if !self.hasShownDownloadStallWarning {
                            self.hasShownDownloadStallWarning = true
                            self.setBackendNotice("Download appears stalled. Check internet/VPN, or keep waiting.")
                        }
                        self.updateSetupProgress(
                            phase: .checkingRuntime,
                            progress: max(55, self.backendSetupProgress),
                            status: "Download appears stalled",
                            detail: "No model download progress for \(Int(stalledFor))s. You can keep waiting, retry, or abort setup."
                        )
                    }
                    return
                }

                if elapsed >= 45, !self.hasShownLongWarmupNotice {
                    self.hasShownLongWarmupNotice = true
                    self.setBackendNotice("Still loading... first run can take longer.")
                }
                if elapsed >= self.backendSetupTimeoutSeconds {
                    self.stopBackendWarmupPolling()
                    let timeoutMinutes = Int(self.backendSetupTimeoutSeconds / 60)
                    self.transitionBackendState(to: .failed("Backend startup timed out after \(timeoutMinutes) minutes. Retry startup or check backend logs."))
                    self.transcriptPanel.dismissRecordingOverlay()
                    if self.isManagedLocalBackendURL {
                        self.setBackendNotice("Backend startup timed out. Retry setup and verify network access.")
                    } else {
                        self.setBackendNotice("External backend not ready yet. Verify URL/server, then retry.")
                    }
                    self.queuedRecordingIntent = false
                    if self.backendDownloadDetected {
                        self.showSetupFailure(reason: "Backend setup timed out after \(timeoutMinutes) minutes while downloading model files. Check internet/VPN access and retry.")
                    } else {
                        self.showSetupFailure(reason: "Backend startup timed out after \(timeoutMinutes) minutes.")
                    }
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
        stopBackendSetupReadyCloseTimer()
        transitionBackendState(to: .ready)
        isBackendReady = true
        setBackendNotice(nil)
        updateSetupProgress(
            phase: .ready,
            progress: 100,
            status: "Speech engine is ready",
            detail: "Backend setup finished successfully."
        )
        backendSetupDialogController.showReady(
            detail: queuedRecordingIntent ? "Ready. Recording will start now." : "Ready. You can start recording.",
            startRecordingEnabled: true
        )
        scheduleBackendSetupReadyAutoClose()
        transcriptPanel.dismissRecordingOverlay()

        if notifyUser {
            notifyBackendReady()
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

    private func warmingProgressFloor(elapsedSeconds: TimeInterval, timeoutSeconds: TimeInterval) -> Double {
        let timeout = max(60, timeoutSeconds)
        let cappedElapsed = min(timeout, max(0, elapsedSeconds))
        return 60 + ((cappedElapsed / timeout) * 30)
    }

    private func warmingDetailMessage(elapsedSeconds: TimeInterval) -> String {
        let elapsed = Int(max(0, elapsedSeconds))
        var detail: String

        if backendDownloadDetected {
            detail = "Downloading speech model files (\(elapsed)s elapsed). No timeout is applied while download progresses."
        } else {
            detail = "Model warm-up is still running on this Mac (\(elapsed)s elapsed)."
        }

        if elapsed >= 30 {
            detail += " First run can take a few minutes."
        }
        if elapsed >= 90 {
            detail += " This is normal on slower CPUs or with low memory."
        }

        if let lastLine = recentBackendOutputLines.last, !lastLine.isEmpty {
            detail += " Latest backend log: \(lastLine)"
        }

        if queuedRecordingIntent {
            detail += " Recording will start automatically when setup finishes."
        }

        return detail
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
        case .degraded:
            return "Backend: reachable, model not ready"
        case .ready:
            return "Backend: healthy"
        case .failed:
            return "Backend: needs attention"
        }
    }

    private func configureBackendSetupDialogActions() {
        backendSetupDialogController.onRetry = { [weak self] in
            self?.startBackendFlow(userRequestedRecording: false)
        }
        backendSetupDialogController.onOpenSettings = { [weak self] in
            self?.settingsWindowController.show()
        }
        backendSetupDialogController.onViewLogs = { [weak self] in
            self?.openBackendLogs()
        }
        backendSetupDialogController.onStartRecording = { [weak self] in
            guard let self else {
                return
            }
            if self.state == .idle, self.isBackendReady {
                self.startRecording()
            }
        }
        backendSetupDialogController.onAbort = { [weak self] in
            self?.abortBackendSetup()
        }
    }

    private func abortBackendSetup() {
        if backendSetupPhase == .idle || backendSetupPhase == .failed || backendSetupPhase == .ready {
            return
        }

        queuedRecordingIntent = false
        stopBackendWarmupPolling()
        stopBackendSetupReadyCloseTimer()
        transitionBackendState(to: .notStarted)
        backendSupervisor.stop()
        isBackendReady = false
        transcriptPanel.dismissRecordingOverlay()
        setBackendNotice("Backend setup aborted by user.")
        showSetupFailure(reason: "Setup aborted by user.")
    }

    private func updateSetupProgress(phase: BackendSetupPhase, progress: Double, status: String, detail: String) {
        if backendSetupStartedAt == nil {
            backendSetupStartedAt = Date()
        }

        backendSetupPhase = phase
        backendSetupProgress = max(backendSetupProgress, min(100, max(0, progress)))

        let elapsedText = "Elapsed: \(setupElapsedText())"
        let allowClose = phase == .ready || phase == .failed

        if backendSetupDialogController.isVisible {
            backendSetupDialogController.updateProgress(
                status: status,
                detail: detail,
                percent: backendSetupProgress,
                elapsed: elapsedText,
                allowClose: allowClose
            )
        } else {
            backendSetupDialogController.showProgress(
                status: status,
                detail: detail,
                percent: backendSetupProgress,
                elapsed: elapsedText,
                allowClose: allowClose
            )
        }

        rebuildMenu()
    }

    private func showSetupFailure(reason: String) {
        stopBackendSetupReadyCloseTimer()
        backendSetupPhase = .failed
        backendSetupProgress = max(backendSetupProgress, 1)
        let details = [reason, latestBackendOutputDetail()]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        backendSetupDialogController.showFailure(
            status: "Backend setup failed",
            detail: details,
            percent: backendSetupProgress
        )
        rebuildMenu()
    }

    private func resetSetupProgress() {
        stopBackendSetupReadyCloseTimer()
        backendSetupPhase = .idle
        backendSetupProgress = 0
        backendSetupStartedAt = nil
        backendSetupTimeoutSeconds = 180
        backendDownloadDetected = false
        lastDownloadProgressAt = nil
        hasShownDownloadStallWarning = false
        recentBackendOutputLines = []
        rebuildMenu()
    }

    private func scheduleBackendSetupReadyAutoClose() {
        stopBackendSetupReadyCloseTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            self.backendSetupDialogController.hide()
            if self.backendSetupPhase == .ready {
                self.resetSetupProgress()
            }
        }
        backendSetupReadyCloseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopBackendSetupReadyCloseTimer() {
        backendSetupReadyCloseTimer?.invalidate()
        backendSetupReadyCloseTimer = nil
    }

    private func setupElapsedText() -> String {
        guard let started = backendSetupStartedAt else {
            return "0s"
        }
        let elapsed = Int(Date().timeIntervalSince(started))
        return "\(elapsed)s"
    }

    private func handleBackendOutputLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            recentBackendOutputLines.append(trimmed)
            if recentBackendOutputLines.count > 12 {
                recentBackendOutputLines.removeFirst(recentBackendOutputLines.count - 12)
            }
        }

        if trimmed.localizedCaseInsensitiveContains("Fetching"), trimmed.localizedCaseInsensitiveContains("files") {
            backendDownloadDetected = true
            lastDownloadProgressAt = Date()
            hasShownDownloadStallWarning = false
            var downloadDetail = "Openflow is downloading speech model assets. This can take several minutes on first run."
            if let fraction = extractFraction(from: trimmed) {
                let fractionPercent = Int((fraction * 100).rounded())
                let mapped = 45 + (fraction * 13)
                backendSetupProgress = max(backendSetupProgress, mapped)
                downloadDetail = "Downloading model files (\(fractionPercent)%). This can take several minutes on first run."
                lastDownloadProgressAt = Date()
            }
            updateSetupProgress(
                phase: .checkingRuntime,
                progress: max(45, backendSetupProgress),
                status: "Downloading model files",
                detail: downloadDetail
            )
        }

        guard backendSetupPhase == .warmingModel || backendSetupPhase == .launchingBackend || backendSetupPhase == .checkingRuntime else {
            return
        }

        if line.localizedCaseInsensitiveContains("Model loaded successfully") {
            backendDownloadDetected = false
            updateSetupProgress(
                phase: .warmingModel,
                progress: max(95, backendSetupProgress),
                status: "Finalizing speech engine",
                detail: "Model loaded. Waiting for backend health check..."
            )
            return
        }

        if line.localizedCaseInsensitiveContains("Loading Qwen") {
            backendDownloadDetected = false
            updateSetupProgress(
                phase: .warmingModel,
                progress: max(62, backendSetupProgress),
                status: "Loading speech model",
                detail: "Initializing model runtime..."
            )
        }

        if line.localizedCaseInsensitiveContains("Loading checkpoint shards"),
           let percent = extractPercentage(from: line) {
            backendDownloadDetected = false
            let mapped = 60 + (Double(percent) * 0.35)
            updateSetupProgress(
                phase: .warmingModel,
                progress: max(mapped, backendSetupProgress),
                status: "Loading model checkpoints",
                detail: "Model warm-up in progress (\(percent)%)."
            )
        }
    }

    private func latestBackendOutputDetail() -> String {
        guard let last = recentBackendOutputLines.last else {
            return ""
        }
        return "Last backend log: \(last)"
    }

    private func extractPercentage(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "([0-9]{1,3})%") else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Int(text[valueRange]) else {
            return nil
        }
        return min(100, max(0, value))
    }

    private func extractFraction(from text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "([0-9]+)\\s*/\\s*([0-9]+)") else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 2,
              let completedRange = Range(match.range(at: 1), in: text),
              let totalRange = Range(match.range(at: 2), in: text),
              let completed = Double(text[completedRange]),
              let total = Double(text[totalRange]),
              total > 0 else {
            return nil
        }
        return min(1, max(0, completed / total))
    }

    private func openBackendLogs() {
        let consoleURL = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        if FileManager.default.fileExists(atPath: consoleURL.path) {
            NSWorkspace.shared.openApplication(at: consoleURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    self.showError("Could not open Console: \(error.localizedDescription)")
                }
            }
            return
        }

        let fallbackLog = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../openflow.log")
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: fallbackLog.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fallbackLog])
        } else {
            showError("No log viewer available. Open macOS Console and search for Openflow logs.")
        }
    }

    private func hasAcceptedBackendSetupAgreement() -> Bool {
        UserDefaults.standard.bool(forKey: UserSettingKey.backendSetupAgreementAccepted)
    }

    private func presentLaunchGuideIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: UserSettingKey.launchGuideShown) {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Welcome to Openflow"
            alert.informativeText = "Openflow runs in the menu bar. Click the waveform icon near the clock to open controls. You can start backend setup now, or open Settings first."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Start Backend Setup")
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Not Now")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            defaults.set(true, forKey: UserSettingKey.launchGuideShown)

            if response == .alertFirstButtonReturn {
                self.startBackendFlow(userRequestedRecording: false)
            } else if response == .alertSecondButtonReturn {
                self.settingsWindowController.show()
            }
        }
    }

    private func presentBackendSetupAgreementDialog() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Backend Setup Agreement"
        alert.informativeText = "Openflow will install and run a local speech engine runtime on this Mac. Initial setup and model warm-up may take several minutes, and may use significant disk/memory. Audio is processed locally by this backend service. Do you agree to continue?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Agree and Continue")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again on this Mac"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let accepted = response == .alertFirstButtonReturn
        if accepted {
            UserDefaults.standard.set(true, forKey: UserSettingKey.backendSetupAgreementAccepted)
        }
        return accepted
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard canUseUserNotifications else {
            log("Skipping notification authorization in non-bundled run")
            return
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                self.log("Notification permission request failed: \(error.localizedDescription)")
            } else {
                self.log("Notification permission granted=\(granted)")
            }
        }
    }

    private func notifyBackendReady() {
        if !canUseUserNotifications {
            presentReadyFallbackNotification()
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliverReadyLocalNotification()
            default:
                DispatchQueue.main.async {
                    self.presentReadyFallbackNotification()
                }
            }
        }
    }

    private func deliverReadyLocalNotification() {
        guard canUseUserNotifications else {
            return
        }

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
                DispatchQueue.main.async {
                    self.presentReadyFallbackNotification()
                }
            }
        }
    }

    private func presentReadyFallbackNotification() {
        setBackendNotice("Backend ready. You can start recording now.")
        _ = NSApp.requestUserAttention(.informationalRequest)

        if !NSApp.isActive {
            showInfo("Openflow is ready. Speech engine loaded.")
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

    private func showInfo(_ message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Openflow"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    private func log(_ message: String) {
        NSLog("[Openflow] \(message)")
    }

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
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
