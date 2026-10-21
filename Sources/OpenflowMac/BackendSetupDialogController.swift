import AppKit

final class BackendSetupDialogController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var elapsedLabel: NSTextField?
    private var progressIndicator: NSProgressIndicator?
    private var percentLabel: NSTextField?
    private var hintLabel: NSTextField?
    private var retryButton: NSButton?
    private var settingsButton: NSButton?
    private var logsButton: NSButton?
    private var startRecordingButton: NSButton?
    private var abortButton: NSButton?

    var onRetry: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onViewLogs: (() -> Void)?
    var onStartRecording: (() -> Void)?
    var onAbort: (() -> Void)?

    private(set) var isDismissedByUser: Bool = false

    var isVisible: Bool {
        window?.isVisible == true
    }

    func showProgress(status: String, detail: String, percent: Double, elapsed: String, allowClose: Bool) {
        isDismissedByUser = false
        ensureWindow()
        statusLabel?.stringValue = status
        detailLabel?.stringValue = detail
        elapsedLabel?.stringValue = elapsed
        hintLabel?.stringValue = "First-time setup can take several minutes depending on network and hardware."
        percentLabel?.stringValue = "\(Int(percent.rounded()))%"
        progressIndicator?.doubleValue = min(100, max(0, percent))
        progressIndicator?.isIndeterminate = false
        closeButtonEnabled(allowClose)
        setActionButtons(ready: false, failed: false, inProgress: true)

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateProgress(status: String, detail: String, percent: Double, elapsed: String, allowClose: Bool) {
        guard window != nil else {
            return
        }
        statusLabel?.stringValue = status
        detailLabel?.stringValue = detail
        elapsedLabel?.stringValue = elapsed
        hintLabel?.stringValue = "First-time setup can take several minutes depending on network and hardware."
        percentLabel?.stringValue = "\(Int(percent.rounded()))%"
        progressIndicator?.doubleValue = min(100, max(0, percent))
        progressIndicator?.isIndeterminate = false
        closeButtonEnabled(allowClose)
        setActionButtons(ready: false, failed: false, inProgress: true)
    }

    func showFailure(status: String, detail: String, percent: Double) {
        ensureWindow()
        statusLabel?.stringValue = status
        detailLabel?.stringValue = detail
        elapsedLabel?.stringValue = "Setup interrupted"
        hintLabel?.stringValue = "Setup could not complete. Retry, check logs, or verify network access."
        percentLabel?.stringValue = "\(Int(percent.rounded()))%"
        progressIndicator?.doubleValue = min(100, max(0, percent))
        progressIndicator?.isIndeterminate = false
        closeButtonEnabled(true)
        setActionButtons(ready: false, failed: true, inProgress: false)

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func showReady(detail: String, startRecordingEnabled: Bool) {
        ensureWindow()
        statusLabel?.stringValue = "Speech engine is ready"
        detailLabel?.stringValue = detail
        elapsedLabel?.stringValue = "Setup complete"
        hintLabel?.stringValue = "Openflow is ready to transcribe audio. If recording fails, enable Openflow in System Settings > Privacy & Security > Microphone, then relaunch."
        percentLabel?.stringValue = "100%"
        progressIndicator?.doubleValue = 100
        progressIndicator?.isIndeterminate = false
        closeButtonEnabled(true)
        setActionButtons(ready: true, failed: false, inProgress: false)
        startRecordingButton?.isEnabled = startRecordingEnabled

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func focus() {
        guard isVisible else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        isDismissedByUser = true
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        isDismissedByUser = true
        onAbort?()
    }

    private func ensureWindow() {
        if window != nil {
            return
        }

        let dialog = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        dialog.title = "Setting Up Speech Engine"
        dialog.isReleasedWhenClosed = false
        dialog.delegate = self
        dialog.center()

        let content = NSView(frame: dialog.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        dialog.contentView = content

        let title = NSTextField(labelWithString: "Installing backend components")
        title.frame = NSRect(x: 24, y: 196, width: 360, height: 24)
        title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        content.addSubview(title)
        statusLabel = title

        let percent = NSTextField(labelWithString: "0%")
        percent.frame = NSRect(x: 422, y: 198, width: 74, height: 20)
        percent.alignment = .right
        percent.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        percent.textColor = AppStyle.Palette.hintText
        content.addSubview(percent)
        percentLabel = percent

        let detail = NSTextField(wrappingLabelWithString: "This can take a few minutes on first run.")
        detail.frame = NSRect(x: 24, y: 138, width: 472, height: 46)
        detail.font = AppStyle.Typography.body
        detail.textColor = AppStyle.Palette.hintText
        content.addSubview(detail)
        detailLabel = detail

        let elapsed = NSTextField(labelWithString: "Elapsed: 0s")
        elapsed.frame = NSRect(x: 24, y: 116, width: 320, height: 18)
        elapsed.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        elapsed.textColor = AppStyle.Palette.subtleText
        content.addSubview(elapsed)
        elapsedLabel = elapsed

        let progress = NSProgressIndicator(frame: NSRect(x: 24, y: 84, width: 472, height: 16))
        progress.style = .bar
        progress.controlSize = .regular
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = 0
        progress.isIndeterminate = false
        progress.usesThreadedAnimation = true
        content.addSubview(progress)
        progressIndicator = progress

        let hint = NSTextField(labelWithString: "First-time setup can take several minutes depending on network and hardware.")
        hint.frame = NSRect(x: 24, y: 60, width: 472, height: 18)
        hint.font = AppStyle.Typography.helper
        hint.textColor = AppStyle.Palette.hintText
        content.addSubview(hint)
        hintLabel = hint

        let retry = NSButton(title: "Retry Setup", target: self, action: #selector(retryTapped))
        retry.frame = NSRect(x: 24, y: 18, width: 102, height: 30)
        retry.isHidden = true
        content.addSubview(retry)
        retryButton = retry

        let logs = NSButton(title: "View Logs", target: self, action: #selector(viewLogsTapped))
        logs.frame = NSRect(x: 132, y: 18, width: 92, height: 30)
        logs.isHidden = true
        content.addSubview(logs)
        logsButton = logs

        let settings = NSButton(title: "Open Settings", target: self, action: #selector(openSettingsTapped))
        settings.frame = NSRect(x: 230, y: 18, width: 108, height: 30)
        settings.isHidden = true
        content.addSubview(settings)
        settingsButton = settings

        let startRecording = NSButton(title: "Start Recording", target: self, action: #selector(startRecordingTapped))
        startRecording.frame = NSRect(x: 376, y: 18, width: 120, height: 30)
        startRecording.isHidden = true
        startRecording.bezelStyle = .rounded
        content.addSubview(startRecording)
        startRecordingButton = startRecording

        let abort = NSButton(title: "Abort Setup", target: self, action: #selector(abortTapped))
        abort.frame = NSRect(x: 376, y: 18, width: 120, height: 30)
        abort.isHidden = true
        abort.bezelStyle = .rounded
        content.addSubview(abort)
        abortButton = abort

        window = dialog
    }

    private func closeButtonEnabled(_ enabled: Bool) {
        window?.standardWindowButton(.closeButton)?.isEnabled = enabled
    }

    private func setActionButtons(ready: Bool, failed: Bool, inProgress: Bool) {
        retryButton?.isHidden = !failed
        logsButton?.isHidden = !failed
        settingsButton?.isHidden = !failed
        startRecordingButton?.isHidden = !ready
        abortButton?.isHidden = !inProgress
    }

    @objc
    private func retryTapped() {
        onRetry?()
    }

    @objc
    private func openSettingsTapped() {
        onOpenSettings?()
    }

    @objc
    private func viewLogsTapped() {
        onViewLogs?()
    }

    @objc
    private func startRecordingTapped() {
        onStartRecording?()
    }

    @objc
    private func abortTapped() {
        onAbort?()
    }
}

#if DEBUG
extension BackendSetupDialogController {
    func _test_statusText() -> String {
        statusLabel?.stringValue ?? ""
    }

    func _test_detailText() -> String {
        detailLabel?.stringValue ?? ""
    }

    func _test_elapsedText() -> String {
        elapsedLabel?.stringValue ?? ""
    }

    func _test_percentText() -> String {
        percentLabel?.stringValue ?? ""
    }

    func _test_progressValue() -> Double {
        progressIndicator?.doubleValue ?? -1
    }

    func _test_triggerRetry() {
        retryTapped()
    }

    func _test_triggerOpenSettings() {
        openSettingsTapped()
    }

    func _test_triggerViewLogs() {
        viewLogsTapped()
    }

    func _test_triggerStartRecording() {
        startRecordingTapped()
    }

    func _test_triggerAbort() {
        abortTapped()
    }
}
#endif
