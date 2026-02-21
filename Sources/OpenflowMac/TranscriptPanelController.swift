import AppKit

final class RecordingWaveView: NSView {
    private var timer: Timer?
    private let barCount = 18
    private var bars: [CGFloat] = Array(repeating: 0.36, count: 18)
    private var targets: [CGFloat] = Array(repeating: 0.5, count: 18)
    private var phase: CGFloat = 0

    enum DisplayMode {
        case recording
        case transcribing
        case warming
    }

    var mode: DisplayMode = .recording {
        didSet {
            needsDisplay = true
        }
    }

    var isAnimating: Bool = false {
        didSet {
            if isAnimating {
                startTimerIfNeeded()
            } else {
                stopTimer()
                needsDisplay = true
            }
        }
    }

    override var isFlipped: Bool {
        true
    }

    deinit {
        stopTimer()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let primaryColor: NSColor
        let secondaryColor: NSColor
        switch mode {
        case .recording:
            primaryColor = AppStyle.Palette.accent
            secondaryColor = AppStyle.Palette.accentSoft
        case .transcribing:
            primaryColor = AppStyle.Palette.accentSoft
            secondaryColor = AppStyle.Palette.accent
        case .warming:
            primaryColor = AppStyle.Palette.accentWarm
            secondaryColor = AppStyle.Palette.accentSoft
        }

        let spacing: CGFloat = 4
        let barWidth: CGFloat = 2.6
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        var x = bounds.midX - (totalWidth / 2)

        for (index, heightFactor) in bars.enumerated() {
            let barHeight = max(8, (bounds.height - 6) * heightFactor)
            let rect = NSRect(x: x, y: bounds.midY - barHeight / 2, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            let colorMix = CGFloat(index) / CGFloat(max(1, barCount - 1))
            NSColor(
                calibratedRed: primaryColor.redComponent + (secondaryColor.redComponent - primaryColor.redComponent) * colorMix,
                green: primaryColor.greenComponent + (secondaryColor.greenComponent - primaryColor.greenComponent) * colorMix,
                blue: primaryColor.blueComponent + (secondaryColor.blueComponent - primaryColor.blueComponent) * colorMix,
                alpha: primaryColor.alphaComponent + (secondaryColor.alphaComponent - primaryColor.alphaComponent) * colorMix
            ).setFill()

            path.fill()
            x += barWidth + spacing
        }
    }

    @objc
    private func tick() {
        phase += 0.16

        for index in targets.indices {
            if Int.random(in: 0...7) == 0 {
                targets[index] = CGFloat.random(in: 0.26...0.98)
            }
        }

        var nextBars = bars
        for index in nextBars.indices {
            let centerDistance = abs(CGFloat(index) - CGFloat(barCount - 1) / 2) / (CGFloat(barCount) / 2)
            let centerBoost = 1 - (centerDistance * 0.35)
            let wobble = (sin((CGFloat(index) * 0.54) + phase) + 1) * 0.08
            let target = min(1.0, max(0.22, (targets[index] + wobble) * centerBoost))
            nextBars[index] += (target - nextBars[index]) * 0.28
        }

        bars = nextBars
        needsDisplay = true
    }

    private func startTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 42.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

final class TranscriptPanelController {
    private var transcriptPanel: NSPanel?
    private var recordingPanel: NSPanel?
    private var transcriptView: NSTextView?
    private var languageLabel: NSTextField?
    private var waveView: RecordingWaveView?
    private var recordingTitleLabel: NSTextField?
    private var recordingSubtitleLabel: NSTextField?

    func showRecording() {
        ensureRecordingPanel()
        waveView?.mode = .recording
        waveView?.isAnimating = true
        recordingTitleLabel?.stringValue = "Recording"
        recordingSubtitleLabel?.stringValue = "Listening..."
        positionRecordingPanel()
        recordingPanel?.orderFrontRegardless()
    }

    func showTranscribing() {
        ensureRecordingPanel()
        waveView?.mode = .transcribing
        waveView?.isAnimating = true
        recordingTitleLabel?.stringValue = "Transcribing"
        recordingSubtitleLabel?.stringValue = "Processing your recording..."
        positionRecordingPanel()
        recordingPanel?.orderFrontRegardless()
    }

    func showWarming(queuedRecording: Bool, subtitle: String? = nil) {
        ensureRecordingPanel()
        waveView?.mode = .warming
        waveView?.isAnimating = true
        recordingTitleLabel?.stringValue = "Preparing speech engine"
        if let subtitle, !subtitle.isEmpty {
            recordingSubtitleLabel?.stringValue = subtitle
        } else if queuedRecording {
            recordingSubtitleLabel?.stringValue = "First launch can take 1-3 min. Recording starts automatically when ready."
        } else {
            recordingSubtitleLabel?.stringValue = "First launch can take 1-3 min. We'll notify you when it's ready."
        }
        positionRecordingPanel()
        recordingPanel?.orderFrontRegardless()
    }

    func show(transcript: String, language: String, activateApp: Bool = true) {
        ensureTranscriptPanel()
        hideRecordingPanel()

        transcriptView?.string = transcript
        languageLabel?.stringValue = "Language: \(language)"

        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        transcriptPanel?.makeKeyAndOrderFront(nil)
    }

    func dismissRecordingOverlay() {
        hideRecordingPanel()
    }

    private func ensureTranscriptPanel() {
        if transcriptPanel != nil {
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "Openflow Transcript"
        panel.isFloatingPanel = true
        panel.center()

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content

        let language = NSTextField(labelWithString: "Language: unknown")
        language.frame = NSRect(x: 20, y: 320, width: 300, height: 20)
        language.font = AppStyle.Typography.helper
        language.textColor = AppStyle.Palette.hintText
        content.addSubview(language)
        languageLabel = language

        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyTranscript))
        copyButton.frame = NSRect(x: 520, y: 315, width: 80, height: 28)
        copyButton.bezelStyle = .texturedRounded
        content.addSubview(copyButton)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 580, height: 285))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        scrollView.documentView = textView

        content.addSubview(scrollView)

        self.transcriptPanel = panel
        self.transcriptView = textView
    }

    private func ensureRecordingPanel() {
        if recordingPanel != nil {
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 1.0
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        let root = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        root.material = .hudWindow
        root.blendingMode = .withinWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = AppStyle.Metrics.panelCornerRadius
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = AppStyle.Palette.panelBorder.cgColor
        root.layer?.backgroundColor = AppStyle.Palette.panelFill.cgColor
        panel.contentView = root

        let glowLayer = CAGradientLayer()
        glowLayer.frame = root.bounds
        glowLayer.colors = [
            AppStyle.Palette.panelGlowTop.cgColor,
            AppStyle.Palette.panelGlowBottom.cgColor,
            NSColor.clear.cgColor,
        ]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        root.layer?.addSublayer(glowLayer)

        let shadowContainer = NSView(frame: root.bounds)
        shadowContainer.autoresizingMask = [.width, .height]
        shadowContainer.wantsLayer = true
        shadowContainer.layer?.cornerRadius = AppStyle.Metrics.panelCornerRadius
        shadowContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.25).cgColor
        shadowContainer.layer?.shadowOpacity = 0.35
        shadowContainer.layer?.shadowRadius = 24
        shadowContainer.layer?.shadowOffset = CGSize(width: 0, height: 10)
        shadowContainer.layer?.backgroundColor = NSColor.clear.cgColor
        root.addSubview(shadowContainer, positioned: .below, relativeTo: nil)

        let titleLabel = NSTextField(labelWithString: "Recording")
        titleLabel.frame = NSRect(x: 18, y: 84, width: 264, height: 16)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        titleLabel.font = AppStyle.Typography.sectionTitle
        root.addSubview(titleLabel)

        let subtitleLabel = NSTextField(wrappingLabelWithString: "Listening...")
        subtitleLabel.frame = NSRect(x: 18, y: 64, width: 264, height: 16)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.80)
        subtitleLabel.font = AppStyle.Typography.helper
        subtitleLabel.maximumNumberOfLines = 2
        root.addSubview(subtitleLabel)

        let wave = RecordingWaveView(frame: NSRect(x: 18, y: 16, width: 264, height: 40))
        wave.autoresizingMask = [.width]
        root.addSubview(wave)
        waveView = wave
        recordingTitleLabel = titleLabel
        recordingSubtitleLabel = subtitleLabel

        recordingPanel = panel
    }

    private func positionRecordingPanel() {
        guard let panel = recordingPanel,
              let screen = NSScreen.main else {
            return
        }

        let visible = screen.visibleFrame
        let x = visible.midX - (panel.frame.width / 2)
        let y = visible.minY + max(90, visible.height * 0.16)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hideRecordingPanel() {
        waveView?.isAnimating = false
        recordingPanel?.orderOut(nil)
    }

    @objc
    private func copyTranscript() {
        guard let text = transcriptView?.string else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#if DEBUG
extension TranscriptPanelController {
    func _test_transcriptText() -> String {
        transcriptView?.string ?? ""
    }

    func _test_languageText() -> String {
        languageLabel?.stringValue ?? ""
    }

    func _test_recordingTitleText() -> String {
        recordingTitleLabel?.stringValue ?? ""
    }

    func _test_recordingSubtitleText() -> String {
        recordingSubtitleLabel?.stringValue ?? ""
    }

    func _test_isRecordingPanelVisible() -> Bool {
        recordingPanel?.isVisible == true
    }

    func _test_isTranscriptPanelVisible() -> Bool {
        transcriptPanel?.isVisible == true
    }

    func _test_triggerCopyTranscript() {
        copyTranscript()
    }
}
#endif
