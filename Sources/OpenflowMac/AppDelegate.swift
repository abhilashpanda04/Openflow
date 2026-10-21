import AppKit
import Carbon.HIToolbox
import SwiftUI
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

    private var localWhisperEngine: LocalWhisperEngine?
    private var localParakeetEngine: LocalParakeetEngine?
    private var localSenseVoiceEngine: LocalSenseVoiceEngine?
    private var appleSpeechEngine: AppleSpeechEngine?
    private var remoteServerEngine: RemoteServerASREngine?
    private var customEngine: ASREngine?

    var activeEngine: ASREngine {
        if let custom = customEngine { return custom }
        switch config.engineType {
        case .localCoreML:
            switch config.localWhisperModel.family {
            case .parakeet:
                if let parakeet = localParakeetEngine { return parakeet }
                let created = LocalParakeetEngine(modelName: config.localWhisperModel.rawValue)
                localParakeetEngine = created
                return created
            case .qwen:
                if let sense = localSenseVoiceEngine { return sense }
                let created = LocalSenseVoiceEngine(modelName: config.localWhisperModel.rawValue)
                localSenseVoiceEngine = created
                return created
            case .whisper, .all:
                if let local = localWhisperEngine { return local }
                let created = LocalWhisperEngine(modelName: config.localWhisperModel.rawValue)
                localWhisperEngine = created
                return created
            }
        case .appleSpeech:
            if let apple = appleSpeechEngine { return apple }
            let created = AppleSpeechEngine()
            appleSpeechEngine = created
            return created
        case .remoteServer:
            if let remote = remoteServerEngine { return remote }
            let created = RemoteServerASREngine(client: asrClient)
            remoteServerEngine = created
            return created
        }
    }

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let popoverState = MenuBarPopoverState()
    private var statusMenu: NSMenu?
    private var hotKeyManager: GlobalHotKeyManager?
    private let backendSupervisor = BackendSupervisor()

    private var state: RecordingState = .idle
    private var recordingStartedAt: Date?
    private var silenceTrackingStartTime: Date?
    private var hasSpokenInCurrentRecording: Bool = false
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
    private var audioLevelTimer: Timer?
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
    private var capturedSelectedText: String?
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
        transcriptPanel.onCancel = { [weak self] in
            self?.cancelRecording()
        }
        transcriptPanel.onFinish = { [weak self] in
            self?.stopRecordingAndTranscribe()
        }
        if config.engineType == .remoteServer {
            startHealthMonitorIfNeeded()
        }
        registerHotKey()
        presentLaunchGuideIfNeeded()
        if config.engineType == .localCoreML || config.engineType == .appleSpeech {
            backendSupervisor.stop()
            stopBackendWarmupPolling()
            stopHealthMonitor()
            backendSetupDialogController.hide()
            startBackendFlow(userRequestedRecording: false)
        } else {
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
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        setupPopover()
        rebuildMenu()
    }

    private func setupPopover() {
        let hostingController = NSHostingController(rootView: MenuBarPopoverView(state: popoverState))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 390, height: 440)
        popover.behavior = .transient
        popover.animates = true
        updatePopoverAppearance()

        NotificationCenter.default.addObserver(
            forName: .openflowThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePopoverAppearance()
        }

        popoverState.onStartStopRecording = { [weak self] in
            self?.toggleRecording()
        }
        popoverState.onShowLastTranscript = { [weak self] in
            self?.showLastTranscript()
        }
        popoverState.onOpenSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.openSettingsAction()
        }
        popoverState.onQuit = { [weak self] in
            self?.quitApp()
        }
        popoverState.onStartBackend = { [weak self] in
            self?.startBackendAction()
        }
        popoverState.onStopBackend = { [weak self] in
            self?.stopBackendAction()
        }
        popoverState.onRetryBackend = { [weak self] in
            self?.retryBackendAction()
        }
        popoverState.onRefreshBackend = { [weak self] in
            self?.refreshBackendStatusAction()
        }
        popoverState.onSelectMicrophone = { [weak self] id in
            AudioDeviceManager.shared.selectDevice(id: id)
            self?.syncPopoverState()
        }
        popoverState.onRequestMicrophonePermission = { [weak self] in
            PermissionsManager.shared.requestMicrophonePermission { _ in
                self?.syncPopoverState()
            }
        }
        popoverState.onRequestAccessibilityPermission = { [weak self] in
            PermissionsManager.shared.requestAccessibilityPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.syncPopoverState()
            }
        }
        popoverState.onOpenPrivacySettings = { section in
            PermissionsManager.shared.openSystemSettings(for: section)
        }
    }

    private func updatePopoverAppearance() {
        let isDark = AppThemeManager.shared.isDark
        popover.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    @objc
    private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            if let menu = statusMenu {
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        syncPopoverState()

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func syncPopoverState() {
        popoverState.isRecording = (state == .recording)
        popoverState.hotkeyDisplay = config.hotKey.displayText
        switch config.engineType {
        case .localCoreML:
            popoverState.engineTitle = "Native CoreML"
            popoverState.engineBadge = "ANE Optimized"
        case .appleSpeech:
            popoverState.engineTitle = "Apple Speech"
            popoverState.engineBadge = "macOS Built-in"
        case .remoteServer:
            popoverState.engineTitle = "Remote Server"
            popoverState.engineBadge = "HTTP"
        }
        if popoverState.isDownloadingModel {
            popoverState.modelState = "Downloading (\(Int(popoverState.modelDownloadProgress * 100))%)"
        } else {
            popoverState.modelState = isBackendReady ? "Ready (On-Device Neural)" : "Initializing..."
        }
        popoverState.backendStatus = isBackendReady ? "healthy · ~12ms" : "offline"
        let targetApp = outputTargetApplication?.localizedName ?? "Cursor"
        popoverState.outputTarget = "\(outputModeLabel()) (\(targetApp))"
        popoverState.lastTranscript = lastTranscript
        popoverState.isRemoteServer = (config.engineType == .remoteServer)

        let modelFootprint = config.engineType == .localCoreML ? config.localWhisperModel.sizeMB : (config.engineType == .remoteServer ? config.modelName.sizeMB : 0)
        let report = ProcessCapacityMonitor.currentReport(modelFootprintMB: modelFootprint)
        popoverState.memoryUsage = report.formattedRAM
        popoverState.cpuUsage = report.formattedCPU
        popoverState.threadUsage = "\(report.threadCount) Threads"
        popoverState.modelFootprint = modelFootprint > 0 ? report.formattedModelFootprint : "Zero Model RAM"
        popoverState.totalCapacity = report.formattedTotalCapacity

        AudioDeviceManager.shared.refreshDevices()
        PermissionsManager.shared.refreshStatuses()
        popoverState.currentMicrophoneName = AudioDeviceManager.shared.currentDeviceName
        popoverState.selectedMicrophoneID = AudioDeviceManager.shared.selectedDeviceID
        popoverState.availableMicrophones = AudioDeviceManager.shared.availableDevices
        popoverState.isMicrophonePermissionGranted = PermissionsManager.shared.microphoneStatus.isGranted
        popoverState.isAccessibilityPermissionGranted = PermissionsManager.shared.accessibilityStatus.isGranted
        popoverState.isSpeechRecognitionPermissionGranted = PermissionsManager.shared.speechRecognitionStatus.isGranted
    }

    private var hotKeyDownTimestamp: Date?
    private var isLongPressActive = false

    private func registerHotKey() {
        hotKeyManager = nil

        do {
            hotKeyManager = try GlobalHotKeyManager(
                config: config.hotKey,
                onKeyDown: { [weak self] in
                    DispatchQueue.main.async {
                        self?.handleHotKeyDown()
                    }
                },
                onKeyUp: { [weak self] in
                    DispatchQueue.main.async {
                        self?.handleHotKeyUp()
                    }
                }
            )
        } catch {
            showError("Failed to register global hotkey (\(config.hotKey.displayText)): \(error.localizedDescription)")
        }
    }

    private func handleHotKeyDown() {
        hotKeyDownTimestamp = Date()

        if state == .transcribing {
            return
        }

        if state == .recording {
            isLongPressActive = false
            stopRecordingAndTranscribe()
            return
        }

        isLongPressActive = true
        startRecording()
    }

    private func handleHotKeyUp() {
        guard let downTime = hotKeyDownTimestamp else {
            return
        }
        let elapsed = Date().timeIntervalSince(downTime)
        hotKeyDownTimestamp = nil

        if isLongPressActive && state == .recording {
            if elapsed >= 0.35 {
                // Long-press: user held the key while speaking and just released it!
                isLongPressActive = false
                stopRecordingAndTranscribe()
            } else {
                // Quick tap: keep recording in hands-free toggle mode
                isLongPressActive = false
            }
        }
    }

    @objc
    private func settingsDidChange() {
        reloadConfiguration(rebuildHotkey: true)
        if config.engineType != .remoteServer {
            backendSupervisor.stop()
            stopHealthMonitor()
            startBackendFlow(userRequestedRecording: false)
            return
        }
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
        remoteServerEngine = RemoteServerASREngine(client: asrClient)
        switch config.engineType {
        case .localCoreML:
            switch config.localWhisperModel.family {
            case .parakeet:
                localParakeetEngine = LocalParakeetEngine(modelName: config.localWhisperModel.rawValue)
                localWhisperEngine = nil
                localSenseVoiceEngine = nil
            case .qwen:
                localSenseVoiceEngine = LocalSenseVoiceEngine(modelName: config.localWhisperModel.rawValue)
                localWhisperEngine = nil
                localParakeetEngine = nil
            case .whisper, .all:
                localWhisperEngine = LocalWhisperEngine(modelName: config.localWhisperModel.rawValue)
                localParakeetEngine = nil
                localSenseVoiceEngine = nil
            }
            stopHealthMonitor()
        case .appleSpeech:
            appleSpeechEngine = AppleSpeechEngine()
            stopHealthMonitor()
        case .remoteServer:
            startHealthMonitorIfNeeded()
        }

        if rebuildHotkey {
            registerHotKey()
        }

        rebuildMenu()
        log("Configuration reloaded engine=\(config.engineType.rawValue) model=\(config.engineType == .localCoreML ? config.localWhisperModel.rawValue : config.modelName.rawValue) hotkey=\(config.hotKey.displayText) output=\(outputModeLabel())")
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleTitle = state == .recording ? "Stop Recording" : "Start Recording"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleRecordingMenuAction), keyEquivalent: "")
        toggleItem.image = NSImage(systemSymbolName: state == .recording ? "stop.circle.fill" : "mic.fill", accessibilityDescription: toggleTitle)
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

        let backendTitle: String
        switch config.engineType {
        case .localCoreML:
            let engineLabel: String
            switch config.localWhisperModel.family {
            case .parakeet: engineLabel = "Parakeet CoreML"
            case .qwen: engineLabel = "SenseVoice CoreML"
            case .whisper, .all: engineLabel = "WhisperKit CoreML"
            }
            backendTitle = "Engine: Native \(engineLabel) (\(config.localWhisperModel.rawValue))"
        case .appleSpeech:
            backendTitle = "Engine: Apple Speech (macOS Built-in)"
        case .remoteServer:
            backendTitle = "Backend URL: \(config.backendBaseURL.absoluteString)"
        }
        let backend = NSMenuItem(title: backendTitle, action: nil, keyEquivalent: "")
        backend.isEnabled = false
        menu.addItem(backend)

        let backendStatus = NSMenuItem(title: menuStatusLine(), action: nil, keyEquivalent: "")
        backendStatus.isEnabled = false
        menu.addItem(backendStatus)

        if config.engineType == .remoteServer, let backendNoticeText, !backendNoticeText.isEmpty {
            let backendNote = NSMenuItem(title: backendNoticeText, action: nil, keyEquivalent: "")
            backendNote.isEnabled = false
            menu.addItem(backendNote)
        }

        let outputMode = NSMenuItem(title: "Output: \(outputModeLabel())", action: nil, keyEquivalent: "")
        outputMode.isEnabled = false
        menu.addItem(outputMode)

        if config.engineType == .remoteServer {
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
        }

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = state != .transcribing
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
        syncPopoverState()
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

        if isBackendWarmupActive {
            let symbolName = currentMenuBarSymbolName()
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Openflow status") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                button.image = image.withSymbolConfiguration(config)
                button.contentTintColor = AppStyle.Palette.accentWarm
            }
        } else {
            let icon = OpenflowLogoHelper.makeMenuBarIcon(isRecording: state == .recording)
            button.image = icon
            if state == .recording {
                button.contentTintColor = .systemRed
            } else if state == .transcribing {
                button.contentTintColor = AppStyle.Palette.accent
            } else {
                button.contentTintColor = nil
            }
        }
        button.title = ""
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
        if config.engineType != .remoteServer {
            isBackendReady = true
        }
        guard isBackendReady else {
            ensureBackendReadyThenStartRecording()
            return
        }

        captureOutputTargetApplication()
        capturedSelectedText = AccessibilitySelectionHelper.getSelectedText()

        recorder.start { result in
            switch result {
            case .success:
                SoundFeedbackManager.shared.play(.start)
                self.recordingStartedAt = Date()
                self.hasSpokenInCurrentRecording = false
                self.silenceTrackingStartTime = nil
                self.transition(to: .recording)
                let targetName = self.outputTargetApplication?.localizedName ?? "Active App"
                self.transcriptPanel.showRecording(targetAppName: targetName)
                self.startAudioLevelMetering()
            case .failure(let error):
                self.stopAudioLevelMetering()
                self.transition(to: .idle)
                if let recorderError = error as? AudioRecorderError, recorderError == .micPermissionDenied {
                    self.showError("Microphone access is disabled. Enable Openflow in System Settings > Privacy & Security > Microphone, then relaunch.")
                } else {
                    self.showError("Unable to start recording: \(error.localizedDescription)")
                }
            }
        }
    }

    private func startAudioLevelMetering() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let level = self.recorder.currentAudioLevel()
            let powerDb = self.recorder.currentAudioPowerDb()
            self.transcriptPanel.updateAudioLevel(level)
            self.popoverState.audioLevel = CGFloat(level)

            // 1. Longest Recording Check (Max Recording Duration limit)
            if let started = self.recordingStartedAt {
                let elapsed = Date().timeIntervalSince(started)
                let maxSeconds = self.config.recordingSilence.maxRecordingDuration.durationSeconds
                if maxSeconds > 0 && elapsed >= maxSeconds {
                    self.log("Maximum recording duration reached (\(Int(maxSeconds))s). Auto-stopping.")
                    self.transcriptPanel.showActionFeedback("⏱️ Max Recording Limit (\(Int(maxSeconds))s)")
                    self.stopRecordingAndTranscribe()
                    return
                }
            }

            // 2. Stop After Silence Check (VAD Auto-Stop)
            let stopSilenceSeconds = self.config.recordingSilence.stopAfterSilence.durationSeconds
            if stopSilenceSeconds > 0 {
                let thresholdDb = self.config.recordingSilence.silenceSensitivity.thresholdDb
                if powerDb >= thresholdDb {
                    self.hasSpokenInCurrentRecording = true
                    self.silenceTrackingStartTime = nil
                } else if self.hasSpokenInCurrentRecording {
                    if self.silenceTrackingStartTime == nil {
                        self.silenceTrackingStartTime = Date()
                    } else if let silenceStart = self.silenceTrackingStartTime,
                              Date().timeIntervalSince(silenceStart) >= stopSilenceSeconds {
                        self.log("Silence detected for \(stopSilenceSeconds)s. Auto-stopping dictation.")
                        self.transcriptPanel.showActionFeedback("🤫 Auto-Stopped (Silence)")
                        self.stopRecordingAndTranscribe()
                        return
                    }
                }
            }
        }
    }

    private func stopAudioLevelMetering() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }

    private func cancelRecording() {
        guard state == .recording else { return }
        SoundFeedbackManager.shared.play(.cancel)
        stopAudioLevelMetering()
        recordingStartedAt = nil
        hasSpokenInCurrentRecording = false
        silenceTrackingStartTime = nil
        _ = recorder.stop()
        transition(to: .idle)
        transcriptPanel.dismissRecordingOverlay()
    }

    private func stopRecordingAndTranscribe() {
        stopAudioLevelMetering()
        guard state == .recording else {
            return
        }
        SoundFeedbackManager.shared.play(.finish)

        let recordingDuration = recordingStartedAt.map { Date().timeIntervalSince($0) }
        recordingStartedAt = nil
        hasSpokenInCurrentRecording = false
        silenceTrackingStartTime = nil

        guard var fileURL = recorder.stop() else {
            transition(to: .idle)
            transcriptPanel.showActionFeedback("⚠️ No Recording Found", duration: 1.8)
            return
        }

        // 3. Skip Silence Before Transcribing
        if config.recordingSilence.skipSilenceBeforeTranscribing {
            let trimResult = AudioSilenceProcessor.trimSilence(
                audioFileURL: fileURL,
                thresholdDb: config.recordingSilence.silenceSensitivity.thresholdDb,
                paddingMs: 120.0
            )

            if trimResult.isAllSilence {
                log("Audio is entirely silent. Skipping transcription.")
                transition(to: .idle)
                transcriptPanel.showActionFeedback("🤫 No Speech Detected", duration: 1.8)
                try? FileManager.default.removeItem(at: fileURL)
                return
            }

            if trimResult.didTrim {
                log("Trimmed silence from audio file: \(String(format: "%.1f", trimResult.originalDurationSeconds))s -> \(String(format: "%.1f", trimResult.trimmedDurationSeconds))s")
                try? FileManager.default.removeItem(at: fileURL)
                fileURL = trimResult.trimmedURL
            }
        }

        transition(to: .transcribing)
        transcriptPanel.showTranscribing()

        let requestID = "\(appSessionID)-\(UUID().uuidString.prefix(8))"
        let engine = activeEngine

        Task { [weak self] in
            defer {
                try? FileManager.default.removeItem(at: fileURL)
            }
            guard let self = self else { return }
            do {
                let response = try await engine.transcribe(audioFileURL: fileURL, requestID: requestID)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.transition(to: .idle)
                    let sanitized = self.sanitizeTranscriptText(response.text)
                    if sanitized.isEmpty {
                        self.log("Empty transcript received. Showing No Speech Detected in HUD modal.")
                        self.transcriptPanel.showActionFeedback("🤫 No Speech Detected", duration: 1.8)
                        return
                    }

                    let commandEngine = VoiceCommandEngine()
                    let selected = self.capturedSelectedText ?? AccessibilitySelectionHelper.getSelectedText(targetApp: self.outputTargetApplication)
                    let result = commandEngine.process(
                        rawTranscript: sanitized,
                        selectedText: selected
                    )
                    self.capturedSelectedText = nil

                    let targetAppName = self.outputTargetApplication?.localizedName

                    switch result {
                    case .systemAction(let action):
                        VoiceActionPerformer.performAction(action, on: self.outputTargetApplication) { [weak self] success in
                            self?.log("Executed in-line voice command: \(action.displayName) (success: \(success))")
                        }
                        TranscriptHistoryStore.shared.recordVoiceAction(action.displayName)
                        self.transcriptPanel.showActionFeedback("⚡️ \(action.displayName)")
                        return

                    case .discarded:
                        self.log("Dictation discarded via voice command (scratch that / cancel)")
                        SoundFeedbackManager.shared.play(.cancel)
                        self.transcriptPanel.showActionFeedback("🚫 Dictation Cancelled")
                        return

                    case .selectionEditRequestedWithoutSelection(let desc):
                        self.log("Selection edit '\(desc)' requested without highlighted text")
                        self.transcriptPanel.showActionFeedback("⚠️ Highlight text first to use '\(desc)'")
                        return

                    case .selectionEdit(let transformed, let desc):
                        let text = self.formatTranscriptText(transformed)
                        self.lastTranscript = text
                        if !text.isEmpty {
                            self.transcriptPanel.dismissRecordingOverlay()
                            self.deliverTranscript(text)
                            TranscriptHistoryStore.shared.add(
                                text: text,
                                language: response.language,
                                engine: "Edit: \(desc)",
                                durationSeconds: recordingDuration,
                                appName: targetAppName
                            )
                            self.transcriptPanel.showActionFeedback("✨ \(desc)")
                        } else {
                            self.transcriptPanel.showActionFeedback("🤫 No Speech Detected", duration: 1.8)
                        }
                        return

                    case .appleIntelligence(let cmd):
                        self.handleAppleIntelligenceCommand(
                            cmd,
                            recordingDuration: recordingDuration,
                            targetAppName: targetAppName
                        )
                        return

                    case .processedText(let processed):
                        let text = self.formatTranscriptText(processed)
                        self.lastTranscript = text

                        if !text.isEmpty {
                            self.transcriptPanel.dismissRecordingOverlay()
                            self.deliverTranscript(text)
                            let engineDesc: String
                            switch self.config.engineType {
                            case .localCoreML:
                                engineDesc = "CoreML (\(self.config.localWhisperModel.rawValue))"
                            case .appleSpeech:
                                engineDesc = "Apple Speech"
                            case .remoteServer:
                                engineDesc = "Remote Server"
                            }
                            TranscriptHistoryStore.shared.add(
                                text: text,
                                language: response.language,
                                engine: engineDesc,
                                durationSeconds: recordingDuration,
                                appName: targetAppName
                            )

                            if self.shouldAutoShowTranscriptPanel() {
                                self.transcriptPanel.show(
                                    transcript: text,
                                    language: response.language ?? "unknown",
                                    activateApp: !self.config.outputMode.shouldPasteToActiveApp
                                )
                            }
                        } else {
                            self.log("Processed text was empty. Showing No Speech Detected in HUD modal.")
                            self.transcriptPanel.showActionFeedback("🤫 No Speech Detected", duration: 1.8)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.transition(to: .idle)
                    self.log("Transcription ended/error request_id=\(requestID) error=\(error.localizedDescription)")
                    // Present in the same wavy UI HUD modal without popping up any NSAlert modal asking the user to click OK
                    let isNoSpeech = error.localizedDescription.lowercased().contains("speech") ||
                                     error.localizedDescription.lowercased().contains("silence") ||
                                     error.localizedDescription.lowercased().contains("empty") ||
                                     error.localizedDescription.lowercased().contains("retry")
                    let feedback = isNoSpeech ? "🤫 No Speech Detected" : "⚠️ \(error.localizedDescription)"
                    self.transcriptPanel.showActionFeedback(feedback, duration: 2.0)
                }
            }
        }
    }

    private func handleAppleIntelligenceCommand(
        _ command: AppleIntelligenceCommand,
        recordingDuration: TimeInterval?,
        targetAppName: String?
    ) {
        if command.style == .showWritingTools {
            self.transcriptPanel.dismissRecordingOverlay()
            let success = AppleIntelligenceEngine.shared.showWritingTools(targetApp: self.outputTargetApplication)
            self.transcriptPanel.showActionFeedback(success ? "🧠 Writing Tools" : "🧠 Writing Tools (Edit Menu)")
            TranscriptHistoryStore.shared.recordVoiceAction("Apple Intelligence Writing Tools")
            return
        }

        self.transcriptPanel.showActionFeedback("🧠 Apple Intelligence: \(command.style.displayName)...")

        Task { [weak self] in
            guard let self = self else { return }
            let result = await AppleIntelligenceEngine.shared.execute(
                command: command,
                selectedText: command.targetText
            )

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch result {
                case .textReplaced(let transformedText, let style):
                    self.transcriptPanel.dismissRecordingOverlay()
                    let formatted = self.formatTranscriptText(transformedText)
                    self.lastTranscript = formatted
                    if !formatted.isEmpty {
                        self.deliverTranscript(formatted)
                        TranscriptHistoryStore.shared.add(
                            text: formatted,
                            language: "en",
                            engine: "Apple Intelligence (\(style.displayName))",
                            durationSeconds: recordingDuration,
                            appName: targetAppName
                        )
                        self.transcriptPanel.showActionFeedback("✨ \(style.displayName) Applied")
                    }

                case .writingToolsTriggered:
                    self.transcriptPanel.dismissRecordingOverlay()
                    self.transcriptPanel.showActionFeedback("🧠 Writing Tools Activated")
                    TranscriptHistoryStore.shared.recordVoiceAction("Apple Intelligence Writing Tools")

                case .error(let message):
                    self.transcriptPanel.dismissRecordingOverlay()
                    self.transcriptPanel.showActionFeedback("⚠️ \(message)")
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
        guard config.engineType == .remoteServer else {
            return
        }
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
        if config.engineType != .remoteServer {
            if isBackendReady {
                startRecording()
            } else {
                startBackendFlow(userRequestedRecording: true)
            }
            return
        }
        queuedRecordingIntent = true
        startBackendFlow(userRequestedRecording: true)
    }

    private func startBackendFlow(userRequestedRecording: Bool) {
        if userRequestedRecording {
            queuedRecordingIntent = true
        }

        if config.engineType == .localCoreML {
            transitionBackendState(to: .warming)
            let engineLabel: String
            switch config.localWhisperModel.family {
            case .parakeet: engineLabel = "Parakeet CoreML"
            case .qwen: engineLabel = "SenseVoice CoreML"
            case .whisper, .all: engineLabel = "WhisperKit CoreML"
            }
            setBackendNotice("Preparing \(engineLabel) (\(config.localWhisperModel.rawValue))...")
            rebuildMenu()
            let currentModelRaw = config.localWhisperModel.rawValue
            let currentModelShortTitle = config.localWhisperModel.shortTitle
            ModelDownloadProgressManager.shared.start(modelName: currentModelRaw, displayName: currentModelShortTitle)
            DispatchQueue.main.async { [weak self] in
                self?.popoverState.isDownloadingModel = true
                self?.popoverState.modelDownloadProgress = 0.05
                self?.popoverState.modelDownloadStatus = "Preparing \(currentModelShortTitle)..."
                self?.popoverState.modelDownloadName = currentModelShortTitle
            }
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.activeEngine.initialize(progress: { [weak self] pct, msg in
                        DispatchQueue.main.async {
                            ModelDownloadProgressManager.shared.update(progress: pct, message: msg)
                            self?.popoverState.isDownloadingModel = (pct < 1.0)
                            self?.popoverState.modelDownloadProgress = pct
                            self?.popoverState.modelDownloadStatus = msg
                            self?.popoverState.modelDownloadName = currentModelShortTitle
                            self?.setBackendNotice("CoreML: \(msg)")
                        }
                    })
                    DispatchQueue.main.async {
                        ModelDownloadProgressManager.shared.finish()
                        self.popoverState.isDownloadingModel = false
                        self.markBackendReady(triggerQueuedRecording: true, notifyUser: false)
                        self.setBackendNotice("\(engineLabel) Ready (\(self.config.localWhisperModel.rawValue))")
                        self.rebuildMenu()
                    }
                } catch {
                    DispatchQueue.main.async {
                        ModelDownloadProgressManager.shared.fail(error: error.localizedDescription)
                        self.popoverState.isDownloadingModel = false
                        self.transitionBackendState(to: .failed("CoreML load error: \(error.localizedDescription)"))
                        self.setBackendNotice("CoreML error: \(error.localizedDescription)")
                        self.rebuildMenu()
                    }
                }
            }
            return
        } else if config.engineType == .appleSpeech {
            transitionBackendState(to: .warming)
            setBackendNotice("Preparing Apple Speech...")
            rebuildMenu()
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.activeEngine.initialize(progress: { [weak self] pct, msg in
                        DispatchQueue.main.async {
                            self?.setBackendNotice("Apple Speech: \(msg)")
                        }
                    })
                    DispatchQueue.main.async {
                        self.markBackendReady(triggerQueuedRecording: true, notifyUser: false)
                        self.setBackendNotice("Apple Speech Ready (On-Device)")
                        self.rebuildMenu()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.transitionBackendState(to: .failed("Apple Speech error: \(error.localizedDescription)"))
                        self.setBackendNotice("Apple Speech error: \(error.localizedDescription)")
                        self.rebuildMenu()
                    }
                }
            }
            return
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
                // Check if backend needs installation
                if !BackendInstaller.shared.isInstalled {
                    self.installBackendThenStart()
                    return
                }
                
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
        if config.engineType == .remoteServer || backendSetupDialogController.isVisible {
            backendSetupDialogController.showReady(
                detail: queuedRecordingIntent ? "Ready. Recording will start now." : "Ready. You can start recording.",
                startRecordingEnabled: true
            )
            scheduleBackendSetupReadyAutoClose()
        }
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

    private func menuStatusLine() -> String {
        switch config.engineType {
        case .localCoreML, .appleSpeech:
            if isBackendReady {
                return "Status: Ready (On-Device)"
            } else if case .warming = backendStartupState {
                return "Status: Initializing engine..."
            } else if case .failed(let err) = backendStartupState {
                return "Status: Error (\(err))"
            } else {
                return "Status: Ready (On-Device)"
            }
        case .remoteServer:
            return backendStatusLine()
        }
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
        backendSetupDialogController.hide()
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
        } else if !backendSetupDialogController.isDismissedByUser {
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
        if isRunningUnitTests {
            return
        }

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

        defaults.set(true, forKey: UserSettingKey.launchGuideShown)
        if config.engineType != .remoteServer {
            isBackendReady = true
            transitionBackendState(to: .ready)
            rebuildMenu()
        }
    }

    private func presentBackendSetupAgreementDialog() -> Bool {
        UserDefaults.standard.set(true, forKey: UserSettingKey.backendSetupAgreementAccepted)
        return true
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

        if !NSApp.isActive && !isRunningUnitTests {
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
        if isRunningUnitTests {
            log("Suppressed error alert in tests: \(message)")
            return
        }

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
        if isRunningUnitTests {
            log("Suppressed info alert in tests: \(message)")
            return
        }

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

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
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
            transcriptPanel.showActionFeedback("⚠️ No Active App Focused", duration: 1.8)
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

    private func formatTranscriptText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let formatter = TypedTextFormatter(config: config.typedText)
        return formatter.format(text)
    }
 
     // MARK: - Backend Installation
 
     private func installBackendThenStart() {
         updateSetupProgress(
             phase: .checkingRuntime,
             progress: 0,
             status: "Initializing backend setup",
             detail: "Checking system requirements..."
         )
         
         // Start installation in background
         Task.detached(priority: .userInitiated) { [weak self] in
             do {
                 try await self?.performBackendInstallation()
                 
                 // After installation, try to start backend
                 DispatchQueue.main.async {
                     self?.startBackendFlow(userRequestedRecording: self?.queuedRecordingIntent ?? false)
                 }
             } catch {
                 DispatchQueue.main.async {
                     self?.transitionBackendState(to: .failed("Backend installation failed. \(error.localizedDescription)"))
                     self?.transcriptPanel.dismissRecordingOverlay()
                     self?.setBackendNotice("Backend installation failed. \(error.localizedDescription)")
                     self?.queuedRecordingIntent = false
                     self?.showSetupFailure(reason: "Backend installation failed. \(error.localizedDescription)")
                 }
             }
         }
     }
 
     private func performBackendInstallation() async throws {
         let pythonInstaller = PythonInstaller.shared
         let backendInstaller = BackendInstaller.shared
         
         // Step 1: Check or install Python
         if let pythonPath = pythonInstaller.detectPython() {
             self.log("Found Python at: \(pythonPath.path)")
             DispatchQueue.main.async {
                 self.updateSetupProgress(
                     phase: .checkingRuntime,
                     progress: 0.2,
                     status: "Checking system requirements",
                     detail: "Found Python 3.12+"
                 )
             }
         } else {
             self.log("Python 3.12+ not found, downloading...")
             DispatchQueue.main.async {
                 self.updateSetupProgress(
                     phase: .checkingRuntime,
                     progress: 0.1,
                     status: "Downloading Python",
                     detail: "Downloading Python 3.12 (~50MB)..."
                 )
             }
             
             // Download and install Python
             _ = try await pythonInstaller.downloadAndInstallPython { [weak self] progress, status in
                 DispatchQueue.main.async {
                     self?.updateSetupProgress(
                         phase: .checkingRuntime,
                         progress: 0.1 + (progress * 0.15),
                         status: "Installing Python",
                         detail: status
                     )
                 }
             }
             
             self.log("Python installed successfully")
         }
         
         // Step 2: Install backend dependencies with retry
         guard let pythonPath = pythonInstaller.detectPython() else {
             throw BackendInstallerError.pythonNotAvailable
         }
         
         self.log("Installing backend dependencies...")
         
         try await backendInstaller.installWithRetry(pythonPath: pythonPath, progressCallback: { [weak self] progress, status in
             DispatchQueue.main.async {
                 self?.updateSetupProgress(
                     phase: .launchingBackend,
                     progress: 0.25 + (progress * 0.65),
                     status: "Installing dependencies",
                     detail: status
                 )
             }
         }, maxRetries: 5)
         
         self.log("Backend installation complete!")
     }
 }
 
 #if DEBUG
extension AppDelegate {
    func _test_applicationDidFinishLaunching() {
        applicationDidFinishLaunching(Notification(name: Notification.Name("test.launch")))
    }

    func _test_applicationWillTerminate() {
        applicationWillTerminate(Notification(name: Notification.Name("test.terminate")))
    }

    func _test_setupStatusItem() {
        setupStatusItem()
    }

    func _test_registerHotKey() {
        registerHotKey()
    }

    func _test_settingsDidChange() {
        settingsDidChange()
    }

    func _test_reloadConfiguration(rebuildHotkey: Bool) {
        reloadConfiguration(rebuildHotkey: rebuildHotkey)
    }

    func _test_refreshBackendStatusAction() {
        refreshBackendStatusAction()
    }

    func _test_refreshLiveBackendHealth() {
        refreshLiveBackendHealth()
    }

    func _test_startHealthMonitorIfNeeded() {
        startHealthMonitorIfNeeded()
    }

    func _test_stopHealthMonitor() {
        stopHealthMonitor()
    }

    func _test_startBackendAction() {
        startBackendAction()
    }

    func _test_retryBackendAction() {
        retryBackendAction()
    }

    func _test_showSetupProgressAction() {
        showSetupProgressAction()
    }

    func _test_stopBackendAction() {
        stopBackendAction()
    }

    func _test_openSettingsAction() {
        openSettingsAction()
    }

    func _test_transitionRecordingState(_ state: String) {
        switch state {
        case "recording":
            transition(to: .recording)
        case "transcribing":
            transition(to: .transcribing)
        default:
            transition(to: .idle)
        }
    }

    func _test_recordingState() -> String {
        switch state {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .transcribing:
            return "transcribing"
        }
    }

    func _test_currentMenuBarSymbolName() -> String {
        currentMenuBarSymbolName()
    }

    func _test_toggleRecordingFromHotKey() {
        toggleRecordingFromHotKey()
    }

    func _test_toggleRecordingMenuAction() {
        toggleRecordingMenuAction()
    }

    func _test_toggleRecording() {
        toggleRecording()
    }

    func _test_startRecording() {
        startRecording()
    }

    func _test_stopRecordingAndTranscribe() {
        stopRecordingAndTranscribe()
    }

    func _test_markBackendReady(triggerQueuedRecording: Bool, notifyUser: Bool) {
        markBackendReady(triggerQueuedRecording: triggerQueuedRecording, notifyUser: notifyUser)
    }

    func _test_beginBackendWarmupPolling() {
        beginBackendWarmupPolling()
    }

    func _test_configureBackendSetupDialogActions() {
        configureBackendSetupDialogActions()
    }

    func _test_setConfig(_ config: AppConfig) {
        self.config = config
    }

    func _test_setASRClient(_ asrClient: ASRClient) {
        self.asrClient = asrClient
        self.remoteServerEngine = RemoteServerASREngine(client: asrClient)
    }

    func _test_setEngine(_ engine: ASREngine) {
        self.customEngine = engine
    }

    func _test_startBackendFlow(userRequestedRecording: Bool) {
        startBackendFlow(userRequestedRecording: userRequestedRecording)
    }

    func _test_transitionBackendState(_ state: String) {
        switch state {
        case "notStarted":
            transitionBackendState(to: .notStarted)
        case "starting":
            transitionBackendState(to: .starting)
        case "warming":
            transitionBackendState(to: .warming)
        case "degraded":
            transitionBackendState(to: .degraded)
        case "ready":
            transitionBackendState(to: .ready)
        case "failed":
            transitionBackendState(to: .failed("failed"))
        default:
            transitionBackendState(to: .notStarted)
        }
    }

    func _test_backendStartupState() -> String {
        switch backendStartupState {
        case .notStarted:
            return "notStarted"
        case .starting:
            return "starting"
        case .warming:
            return "warming"
        case .degraded:
            return "degraded"
        case .ready:
            return "ready"
        case .failed:
            return "failed"
        }
    }

    func _test_setBackendSetupPhase(_ phase: String) {
        switch phase {
        case "idle":
            backendSetupPhase = .idle
        case "agreementAccepted":
            backendSetupPhase = .agreementAccepted
        case "checkingRuntime":
            backendSetupPhase = .checkingRuntime
        case "launchingBackend":
            backendSetupPhase = .launchingBackend
        case "warmingModel":
            backendSetupPhase = .warmingModel
        case "ready":
            backendSetupPhase = .ready
        case "failed":
            backendSetupPhase = .failed
        default:
            backendSetupPhase = .idle
        }
    }

    func _test_backendSetupPhase() -> String {
        switch backendSetupPhase {
        case .idle:
            return "idle"
        case .agreementAccepted:
            return "agreementAccepted"
        case .checkingRuntime:
            return "checkingRuntime"
        case .launchingBackend:
            return "launchingBackend"
        case .warmingModel:
            return "warmingModel"
        case .ready:
            return "ready"
        case .failed:
            return "failed"
        }
    }

    func _test_setQueuedRecordingIntent(_ value: Bool) {
        queuedRecordingIntent = value
    }

    func _test_setRecentBackendOutputLines(_ lines: [String]) {
        recentBackendOutputLines = lines
    }

    func _test_setBackendWarmupStartedAt(_ date: Date?) {
        backendWarmupStartedAt = date
    }

    func _test_setBackendSetupStartedAt(_ date: Date?) {
        backendSetupStartedAt = date
    }

    func _test_setBackendDownloadDetected(_ value: Bool) {
        backendDownloadDetected = value
    }

    func _test_setLastDownloadProgressAt(_ date: Date?) {
        lastDownloadProgressAt = date
    }

    func _test_setBackendSetupProgress(_ value: Double) {
        backendSetupProgress = value
    }

    func _test_setBackendSetupTimeoutSeconds(_ value: TimeInterval) {
        backendSetupTimeoutSeconds = value
    }

    func _test_backendSetupProgress() -> Double {
        backendSetupProgress
    }

    func _test_isBackendReady() -> Bool {
        isBackendReady
    }

    func _test_backendNoticeText() -> String? {
        backendNoticeText
    }

    func _test_outputModeLabel() -> String {
        outputModeLabel()
    }

    func _test_menuBarTitle(_ state: String) -> String {
        switch state {
        case "recording":
            return menuBarTitle(for: .recording)
        case "transcribing":
            return menuBarTitle(for: .transcribing)
        default:
            return menuBarTitle(for: .idle)
        }
    }

    func _test_menuBarSymbolName(_ state: String) -> String {
        switch state {
        case "recording":
            return menuBarSymbolName(for: .recording)
        case "transcribing":
            return menuBarSymbolName(for: .transcribing)
        default:
            return menuBarSymbolName(for: .idle)
        }
    }

    func _test_startBackendMenuTitle() -> String {
        startBackendMenuTitle()
    }

    func _test_backendStatusLine() -> String {
        backendStatusLine()
    }

    func _test_canStartBackend() -> Bool {
        canStartBackend
    }

    func _test_canRetryBackend() -> Bool {
        canRetryBackend
    }

    func _test_isManagedLocalBackendURL() -> Bool {
        isManagedLocalBackendURL
    }

    func _test_canUseUserNotifications() -> Bool {
        canUseUserNotifications
    }

    func _test_warmingProgressFloor(elapsedSeconds: TimeInterval, timeoutSeconds: TimeInterval) -> Double {
        warmingProgressFloor(elapsedSeconds: elapsedSeconds, timeoutSeconds: timeoutSeconds)
    }

    func _test_warmingDetailMessage(elapsedSeconds: TimeInterval) -> String {
        warmingDetailMessage(elapsedSeconds: elapsedSeconds)
    }

    func _test_setBackendNotice(_ message: String?) {
        setBackendNotice(message)
    }

    func _test_extractPercentage(_ text: String) -> Int? {
        extractPercentage(from: text)
    }

    func _test_extractFraction(_ text: String) -> Double? {
        extractFraction(from: text)
    }

    func _test_setupElapsedText() -> String {
        setupElapsedText()
    }

    func _test_latestBackendOutputDetail() -> String {
        latestBackendOutputDetail()
    }

    func _test_handleBackendOutputLine(_ line: String) {
        handleBackendOutputLine(line)
    }

    func _test_updateSetupProgress(phase: String, progress: Double, status: String, detail: String) {
        switch phase {
        case "agreementAccepted":
            updateSetupProgress(phase: .agreementAccepted, progress: progress, status: status, detail: detail)
        case "checkingRuntime":
            updateSetupProgress(phase: .checkingRuntime, progress: progress, status: status, detail: detail)
        case "launchingBackend":
            updateSetupProgress(phase: .launchingBackend, progress: progress, status: status, detail: detail)
        case "warmingModel":
            updateSetupProgress(phase: .warmingModel, progress: progress, status: status, detail: detail)
        case "ready":
            updateSetupProgress(phase: .ready, progress: progress, status: status, detail: detail)
        case "failed":
            updateSetupProgress(phase: .failed, progress: progress, status: status, detail: detail)
        default:
            updateSetupProgress(phase: .idle, progress: progress, status: status, detail: detail)
        }
    }

    func _test_showSetupFailure(reason: String) {
        showSetupFailure(reason: reason)
    }

    func _test_resetSetupProgress() {
        resetSetupProgress()
    }

    func _test_abortBackendSetup() {
        abortBackendSetup()
    }

    func _test_handleBackendProcessExit(status: Int32) {
        handleBackendProcessExit(status: status)
    }

    func _test_showLastTranscript() {
        showLastTranscript()
    }

    func _test_requestNotificationAuthorizationIfNeeded() {
        requestNotificationAuthorizationIfNeeded()
    }

    func _test_notifyBackendReady() {
        notifyBackendReady()
    }

    func _test_deliverReadyLocalNotification() {
        deliverReadyLocalNotification()
    }

    func _test_presentReadyFallbackNotification() {
        presentReadyFallbackNotification()
    }

    func _test_captureOutputTargetApplication() {
        captureOutputTargetApplication()
    }

    func _test_setOutputTargetApplicationToCurrentApp() {
        outputTargetApplication = NSRunningApplication.current
    }

    func _test_deliverTranscript(_ text: String) {
        deliverTranscript(text)
    }

    func _test_copyToClipboard(_ text: String) {
        copyToClipboard(text)
    }

    func _test_openBackendLogs() {
        openBackendLogs()
    }

    func _test_hasAcceptedBackendSetupAgreement() -> Bool {
        hasAcceptedBackendSetupAgreement()
    }

    func _test_presentBackendSetupAgreementDialog() -> Bool {
        presentBackendSetupAgreementDialog()
    }

    func _test_pasteToCapturedApplication(_ text: String) {
        pasteToCapturedApplication(text)
    }

    func _test_sendPasteShortcut() -> Bool {
        sendPasteShortcut()
    }

    func _test_showError(_ message: String) {
        showError(message)
    }

    func _test_showInfo(_ message: String) {
        showInfo(message)
    }

    func _test_sanitizeTranscriptText(_ text: String) -> String {
        sanitizeTranscriptText(text)
    }

    func _test_formatTranscriptText(_ text: String) -> String {
        formatTranscriptText(text)
    }

    func _test_shouldAutoShowTranscriptPanel() -> Bool {
        shouldAutoShowTranscriptPanel()
    }

     func _test_stopBackendForCleanup() {
         stopBackendWarmupPolling()
         stopBackendStatusIconAnimation()
         stopHealthMonitor()
         stopBackendSetupReadyCloseTimer()
         backendSupervisor.stop()
     }
 }
 #endif
