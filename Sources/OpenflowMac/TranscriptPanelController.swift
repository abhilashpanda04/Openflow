import AppKit

final class RecordingWaveView: NSView {
    static let barCount = 36

    /// Exact 36-color chromatic spectrum extracted from Harrison's voice recognition Lottie design
    /// Smoothly transitioning across vibrant orange-red, crimson, violet, deep indigo, royal blue, teal, and cyan.
    static let barColors: [NSColor] = [
        NSColor(srgbRed: 1.000, green: 0.278, blue: 0.090, alpha: 1.0), // #FF4717
        NSColor(srgbRed: 0.984, green: 0.267, blue: 0.118, alpha: 1.0), // #FB441E
        NSColor(srgbRed: 0.961, green: 0.251, blue: 0.153, alpha: 1.0), // #F54027
        NSColor(srgbRed: 0.941, green: 0.235, blue: 0.184, alpha: 1.0), // #F03C2F
        NSColor(srgbRed: 0.925, green: 0.224, blue: 0.212, alpha: 1.0), // #EC3936
        NSColor(srgbRed: 0.906, green: 0.212, blue: 0.243, alpha: 1.0), // #E7363E
        NSColor(srgbRed: 0.867, green: 0.184, blue: 0.302, alpha: 1.0), // #DD2F4D
        NSColor(srgbRed: 0.851, green: 0.173, blue: 0.329, alpha: 1.0), // #D92C54
        NSColor(srgbRed: 0.831, green: 0.161, blue: 0.361, alpha: 1.0), // #D4295C
        NSColor(srgbRed: 0.812, green: 0.145, blue: 0.392, alpha: 1.0), // #CF2564
        NSColor(srgbRed: 0.792, green: 0.129, blue: 0.427, alpha: 1.0), // #CA216D
        NSColor(srgbRed: 0.753, green: 0.106, blue: 0.486, alpha: 1.0), // #C01B7C
        NSColor(srgbRed: 0.737, green: 0.094, blue: 0.514, alpha: 1.0), // #BC1883
        NSColor(srgbRed: 0.718, green: 0.078, blue: 0.545, alpha: 1.0), // #B7148B
        NSColor(srgbRed: 0.698, green: 0.067, blue: 0.573, alpha: 1.0), // #B21192
        NSColor(srgbRed: 0.663, green: 0.043, blue: 0.631, alpha: 1.0), // #A90BA1
        NSColor(srgbRed: 0.620, green: 0.051, blue: 0.659, alpha: 1.0), // #9E0DA8
        NSColor(srgbRed: 0.620, green: 0.051, blue: 0.659, alpha: 1.0), // #9E0DA8
        NSColor(srgbRed: 0.588, green: 0.082, blue: 0.659, alpha: 1.0), // #9615A8
        NSColor(srgbRed: 0.525, green: 0.141, blue: 0.651, alpha: 1.0), // #8624A6
        NSColor(srgbRed: 0.498, green: 0.169, blue: 0.651, alpha: 1.0), // #7F2BA6
        NSColor(srgbRed: 0.471, green: 0.196, blue: 0.647, alpha: 1.0), // #7832A5
        NSColor(srgbRed: 0.443, green: 0.220, blue: 0.643, alpha: 1.0), // #7138A4
        NSColor(srgbRed: 0.416, green: 0.247, blue: 0.643, alpha: 1.0), // #6A3FA4
        NSColor(srgbRed: 0.384, green: 0.278, blue: 0.639, alpha: 1.0), // #6247A3
        NSColor(srgbRed: 0.349, green: 0.314, blue: 0.635, alpha: 1.0), // #5950A2
        NSColor(srgbRed: 0.318, green: 0.337, blue: 0.631, alpha: 1.0), // #5156A1
        NSColor(srgbRed: 0.286, green: 0.369, blue: 0.631, alpha: 1.0), // #495EA1
        NSColor(srgbRed: 0.255, green: 0.400, blue: 0.627, alpha: 1.0), // #4166A0
        NSColor(srgbRed: 0.255, green: 0.400, blue: 0.627, alpha: 1.0), // #4166A0
        NSColor(srgbRed: 0.200, green: 0.451, blue: 0.624, alpha: 1.0), // #33739F
        NSColor(srgbRed: 0.200, green: 0.451, blue: 0.624, alpha: 1.0), // #33739F
        NSColor(srgbRed: 0.141, green: 0.510, blue: 0.616, alpha: 1.0), // #24829D
        NSColor(srgbRed: 0.078, green: 0.569, blue: 0.612, alpha: 1.0), // #14919C
        NSColor(srgbRed: 0.078, green: 0.569, blue: 0.612, alpha: 1.0), // #14919C
        NSColor(srgbRed: 0.078, green: 0.569, blue: 0.612, alpha: 1.0)  // #14919C
    ]

    /// Keyframes sampled across the 120-frame harmonic voice undulation in the Lottie asset (normalized 0.0...1.0)
    private static let keyframes: [[CGFloat]] = [
        [0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200, 0.200],
        [0.175, 0.340, 0.530, 0.920, 0.755, 0.490, 0.815, 0.675, 0.560, 0.430, 0.770, 0.302, 0.635, 0.470, 0.910, 0.730, 0.555, 0.715, 0.265, 0.565, 0.465, 0.175, 0.585, 0.205, 0.500, 0.965, 0.805, 0.365, 0.615, 0.455, 0.300, 0.105, 0.450, 0.325, 0.510, 0.180],
        [0.125, 0.275, 0.420, 0.290, 0.640, 0.205, 0.425, 0.655, 0.835, 0.255, 0.575, 0.405, 0.840, 0.620, 0.310, 0.550, 0.975, 0.375, 0.685, 0.885, 0.400, 0.720, 0.270, 0.565, 0.350, 0.505, 0.215, 0.550, 0.865, 0.350, 0.605, 0.235, 0.450, 0.120, 0.385, 0.070],
        [0.255, 0.170, 0.310, 0.235, 0.435, 0.330, 0.590, 0.435, 0.690, 0.540, 0.240, 0.430, 0.715, 0.540, 0.820, 0.415, 0.730, 0.540, 0.805, 0.685, 0.465, 0.625, 0.390, 0.760, 0.180, 0.430, 0.730, 0.310, 0.650, 0.480, 0.375, 0.495, 0.650, 0.335, 0.210, 0.115],
        [0.105, 0.210, 0.420, 0.635, 0.320, 0.595, 0.470, 0.780, 0.990, 0.585, 0.305, 0.455, 0.680, 0.235, 0.600, 0.110, 0.290, 0.530, 0.380, 0.570, 0.250, 0.440, 0.785, 0.590, 0.330, 0.480, 0.180, 0.695, 0.375, 0.535, 0.130, 0.295, 0.510, 0.195, 0.415, 0.060],
        [0.205, 0.315, 0.505, 0.380, 0.240, 0.480, 0.755, 0.155, 0.335, 0.565, 0.205, 0.465, 0.695, 0.355, 0.595, 0.215, 0.525, 0.160, 0.325, 0.515, 0.715, 0.430, 0.655, 0.810, 0.510, 0.295, 0.410, 0.175, 0.565, 0.325, 0.540, 0.205, 0.415, 0.290, 0.160, 0.235],
        [0.110, 0.205, 0.130, 0.495, 0.385, 0.230, 0.500, 0.350, 0.165, 0.285, 0.535, 0.710, 0.440, 0.195, 0.365, 0.530, 0.320, 0.220, 0.435, 0.640, 0.565, 0.330, 0.495, 0.710, 0.240, 0.480, 0.615, 0.335, 0.525, 0.200, 0.460, 0.330, 0.235, 0.465, 0.310, 0.115],
        [0.175, 0.300, 0.230, 0.405, 0.615, 0.195, 0.390, 0.640, 0.305, 0.505, 0.355, 0.235, 0.535, 0.105, 0.410, 0.625, 0.490, 0.320, 0.175, 0.440, 0.295, 0.090, 0.235, 0.390, 0.180, 0.325, 0.600, 0.515, 0.285, 0.140, 0.215, 0.425, 0.070, 0.150, 0.310, 0.215],
        [0.100, 0.305, 0.185, 0.445, 0.700, 0.300, 0.560, 0.445, 0.185, 0.350, 0.600, 0.165, 0.290, 0.505, 0.210, 0.425, 0.645, 0.535, 0.320, 0.505, 0.195, 0.295, 0.455, 0.150, 0.290, 0.410, 0.270, 0.475, 0.130, 0.330, 0.510, 0.215, 0.395, 0.295, 0.150, 0.065],
        [0.180, 0.425, 0.280, 0.175, 0.565, 0.370, 0.695, 0.540, 0.265, 0.160, 0.395, 0.245, 0.145, 0.345, 0.550, 0.275, 0.445, 0.715, 0.190, 0.380, 0.575, 0.440, 0.250, 0.520, 0.350, 0.465, 0.175, 0.325, 0.485, 0.200, 0.360, 0.560, 0.210, 0.325, 0.145, 0.235],
        [0.235, 0.550, 0.380, 0.250, 0.475, 0.165, 0.385, 0.250, 0.510, 0.340, 0.205, 0.475, 0.340, 0.230, 0.410, 0.305, 0.220, 0.585, 0.445, 0.325, 0.530, 0.765, 0.400, 0.655, 0.520, 0.315, 0.480, 0.175, 0.415, 0.635, 0.275, 0.530, 0.405, 0.150, 0.280, 0.085],
        [0.115, 0.310, 0.515, 0.210, 0.420, 0.270, 0.600, 0.415, 0.240, 0.510, 0.330, 0.560, 0.415, 0.200, 0.525, 0.375, 0.190, 0.375, 0.550, 0.190, 0.420, 0.620, 0.295, 0.550, 0.415, 0.225, 0.370, 0.565, 0.255, 0.405, 0.680, 0.355, 0.195, 0.095, 0.240, 0.160],
        [0.180, 0.115, 0.400, 0.245, 0.520, 0.390, 0.645, 0.265, 0.435, 0.575, 0.255, 0.350, 0.190, 0.495, 0.825, 0.635, 0.380, 0.210, 0.510, 0.325, 0.135, 0.470, 0.340, 0.665, 0.195, 0.410, 0.305, 0.555, 0.155, 0.345, 0.550, 0.755, 0.445, 0.290, 0.165, 0.075],
        [0.135, 0.240, 0.470, 0.350, 0.125, 0.255, 0.540, 0.395, 0.650, 0.455, 0.205, 0.385, 0.655, 0.265, 0.365, 0.595, 0.445, 0.750, 0.565, 0.335, 0.205, 0.480, 0.310, 0.665, 0.410, 0.270, 0.505, 0.360, 0.235, 0.100, 0.325, 0.520, 0.665, 0.425, 0.265, 0.155],
        [0.325, 0.480, 0.640, 0.320, 0.195, 0.445, 0.605, 0.300, 0.760, 0.495, 0.155, 0.285, 0.505, 0.690, 0.115, 0.310, 0.625, 0.470, 0.760, 0.220, 0.430, 0.685, 0.535, 0.245, 0.615, 0.395, 0.620, 0.495, 0.255, 0.420, 0.155, 0.350, 0.560, 0.680, 0.450, 0.335],
        [0.140, 0.335, 0.565, 0.245, 0.455, 0.165, 0.355, 0.555, 0.290, 0.740, 0.460, 0.150, 0.370, 0.545, 0.270, 0.135, 0.430, 0.280, 0.565, 0.410, 0.255, 0.495, 0.360, 0.630, 0.265, 0.520, 0.410, 0.710, 0.530, 0.285, 0.450, 0.190, 0.455, 0.695, 0.325, 0.160],
        [0.080, 0.260, 0.455, 0.360, 0.220, 0.445, 0.570, 0.350, 0.200, 0.470, 0.675, 0.360, 0.200, 0.535, 0.390, 0.270, 0.120, 0.415, 0.275, 0.640, 0.410, 0.290, 0.580, 0.445, 0.160, 0.345, 0.175, 0.545, 0.290, 0.455, 0.645, 0.325, 0.565, 0.440, 0.185, 0.285],
        [0.145, 0.365, 0.600, 0.215, 0.365, 0.530, 0.275, 0.445, 0.105, 0.305, 0.520, 0.215, 0.105, 0.505, 0.700, 0.415, 0.225, 0.355, 0.120, 0.280, 0.630, 0.495, 0.305, 0.570, 0.380, 0.175, 0.285, 0.565, 0.420, 0.250, 0.495, 0.145, 0.360, 0.450, 0.325, 0.130],
        [0.065, 0.165, 0.405, 0.290, 0.505, 0.360, 0.125, 0.265, 0.475, 0.360, 0.635, 0.480, 0.275, 0.400, 0.610, 0.225, 0.475, 0.650, 0.380, 0.200, 0.360, 0.615, 0.485, 0.230, 0.155, 0.450, 0.210, 0.415, 0.615, 0.355, 0.510, 0.255, 0.170, 0.365, 0.515, 0.305],
        [0.120, 0.290, 0.225, 0.510, 0.385, 0.290, 0.545, 0.180, 0.365, 0.530, 0.265, 0.705, 0.470, 0.330, 0.595, 0.435, 0.290, 0.535, 0.790, 0.635, 0.325, 0.540, 0.720, 0.415, 0.245, 0.545, 0.370, 0.685, 0.230, 0.505, 0.355, 0.115, 0.345, 0.230, 0.130, 0.075],
        [0.200, 0.450, 0.340, 0.640, 0.445, 0.185, 0.325, 0.100, 0.220, 0.415, 0.145, 0.305, 0.755, 0.485, 0.280, 0.625, 0.440, 0.270, 0.540, 0.405, 0.135, 0.270, 0.140, 0.550, 0.410, 0.190, 0.535, 0.355, 0.140, 0.470, 0.255, 0.380, 0.555, 0.115, 0.275, 0.165],
        [0.100, 0.265, 0.155, 0.425, 0.640, 0.295, 0.160, 0.435, 0.075, 0.220, 0.370, 0.120, 0.545, 0.205, 0.380, 0.575, 0.200, 0.345, 0.520, 0.185, 0.355, 0.100, 0.280, 0.440, 0.140, 0.350, 0.645, 0.205, 0.310, 0.145, 0.555, 0.445, 0.200, 0.485, 0.105, 0.295],
        [0.155, 0.090, 0.295, 0.180, 0.470, 0.260, 0.410, 0.525, 0.270, 0.405, 0.595, 0.285, 0.385, 0.275, 0.530, 0.705, 0.375, 0.220, 0.500, 0.280, 0.155, 0.435, 0.255, 0.600, 0.355, 0.540, 0.285, 0.685, 0.405, 0.175, 0.310, 0.580, 0.395, 0.245, 0.395, 0.100],
        [0.060, 0.160, 0.385, 0.235, 0.615, 0.355, 0.545, 0.265, 0.425, 0.140, 0.440, 0.570, 0.230, 0.450, 0.125, 0.465, 0.775, 0.110, 0.290, 0.645, 0.410, 0.200, 0.335, 0.230, 0.405, 0.725, 0.560, 0.315, 0.185, 0.430, 0.495, 0.173, 0.381, 0.150, 0.225, 0.310]
    ]

    private var timer: Timer?
    private var bars: [CGFloat] = Array(repeating: 0.20, count: 36)
    private var frameIndex: Int = 0
    private var phase: CGFloat = 0

    /// Audio level modulation (0.0 silent to 1.0 active speech). Defaults to 1.0.
    var audioLevel: CGFloat = 1.0

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
                bars = Array(repeating: 0.20, count: Self.barCount)
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

        let count = Self.barCount
        let barWidth: CGFloat = 4.0
        let spacing: CGFloat = 2.5
        let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
        let startX = bounds.midX - (totalWidth / 2.0)
        let midY = bounds.midY
        let maxHeight = max(12.0, bounds.height - 8.0)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for i in 0..<count {
            let x = startX + CGFloat(i) * (barWidth + spacing)
            let heightFactor = (i < bars.count) ? bars[i] : 0.20
            let barHeight = max(barWidth, maxHeight * heightFactor)
            let y = midY - (barHeight / 2.0)
            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2.0, yRadius: barWidth / 2.0)

            let barColor: NSColor
            switch mode {
            case .recording:
                barColor = Self.barColors[i % Self.barColors.count]
            case .transcribing:
                let wave = (sin(CGFloat(i) * 0.35 - phase * 3.0) + 1.0) * 0.5
                let baseColor = Self.barColors[i % Self.barColors.count]
                barColor = baseColor.withAlphaComponent(0.40 + 0.60 * wave)
            case .warming:
                let baseColor = Self.barColors[i % Self.barColors.count]
                barColor = AppStyle.Palette.accentWarm.blended(withFraction: 0.40, of: baseColor) ?? baseColor
            }

            context.saveGState()
            // Ambient neon glow around each bar
            context.setShadow(
                offset: .zero,
                blur: 3.5,
                color: barColor.withAlphaComponent(0.38).cgColor
            )
            barColor.setFill()
            path.fill()
            context.restoreGState()
        }
    }

    @objc
    private func tick() {
        phase += 0.08
        frameIndex = (frameIndex + 1) % 120

        switch mode {
        case .recording:
            let stepProgress = (Double(frameIndex) / 120.0) * Double(Self.keyframes.count)
            let idx0 = Int(stepProgress) % Self.keyframes.count
            let idx1 = (idx0 + 1) % Self.keyframes.count
            let frac = CGFloat(stepProgress - Double(Int(stepProgress)))
            let eased = frac * frac * (3.0 - 2.0 * frac)

            var nextBars = bars
            let row0 = Self.keyframes[idx0]
            let row1 = Self.keyframes[idx1]
            let speechModulation = max(0.65, min(1.25, 0.70 + 0.55 * audioLevel))

            for i in 0..<Self.barCount {
                let k0 = (i < row0.count) ? row0[i] : 0.20
                let k1 = (i < row1.count) ? row1[i] : 0.20
                let rawTarget = k0 + (k1 - k0) * eased
                let target = min(1.0, max(0.12, rawTarget * speechModulation))
                nextBars[i] += (target - nextBars[i]) * 0.45
            }
            bars = nextBars

        case .transcribing:
            var nextBars = bars
            for i in 0..<Self.barCount {
                let wave = (sin(CGFloat(i) * 0.35 - phase * 3.0) + 1.0) * 0.5
                let target = 0.18 + wave * 0.52
                nextBars[i] += (target - nextBars[i]) * 0.35
            }
            bars = nextBars

        case .warming:
            var nextBars = bars
            let pulse = (sin(phase * 2.0) + 1.0) * 0.5
            for i in 0..<Self.barCount {
                let centerDist = abs(CGFloat(i) - 17.5) / 18.0
                let target = 0.16 + (pulse * (1.0 - centerDist * 0.35)) * 0.42
                nextBars[i] += (target - nextBars[i]) * 0.25
            }
            bars = nextBars
        }

        needsDisplay = true
    }

    private func startTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
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

import SwiftUI

final class TranscriptPanelController {
    public let hudState = DictationHUDState()
    public var onCancel: (() -> Void)?
    public var onFinish: (() -> Void)?

    private var transcriptPanel: NSPanel?
    private var recordingPanel: NSPanel?
    private var transcriptView: NSTextView?
    private var languageLabel: NSTextField?
    private var waveView: RecordingWaveView?
    private var recordingTitleLabel: NSTextField?
    private var recordingSubtitleLabel: NSTextField?
    private var durationTimer: Timer?
    private var placementObserver: NSObjectProtocol?

    private var overlayPlacement: OverlayPlacement {
        OverlayPlacement.parse(UserDefaults.standard.string(forKey: UserSettingKey.overlayPlacement)) ?? .top
    }

    init() {
        placementObserver = NotificationCenter.default.addObserver(
            forName: .openflowOverlayPlacementDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.recordingPanel?.isVisible == true else { return }
            self.positionRecordingPanel()
        }
    }

    deinit {
        stopDurationTimer()
        if let token = placementObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func showRecording(targetAppName: String = "Active App") {
        ensureRecordingPanel()
        hudState.mode = .recording
        hudState.targetAppName = targetAppName
        hudState.statusMessage = "Listening..."
        hudState.streamingText = "Listening to your voice..."
        recordingTitleLabel?.stringValue = "Recording"
        recordingSubtitleLabel?.stringValue = "Listening..."
        startDurationTimer()
        positionRecordingPanel()
        recordingPanel?.orderFrontRegardless()
    }

    func showTranscribing() {
        ensureRecordingPanel()
        stopDurationTimer()
        hudState.mode = .transcribing
        hudState.statusMessage = "Transcribing with WhisperKit..."
        hudState.streamingText = "Processing audio with Neural Engine..."
        recordingTitleLabel?.stringValue = "Transcribing"
        recordingSubtitleLabel?.stringValue = "Processing your recording..."
        positionRecordingPanel()
        recordingPanel?.orderFrontRegardless()
    }

    func showWarming(queuedRecording: Bool, subtitle: String? = nil) {
        ensureRecordingPanel()
        stopDurationTimer()
        hudState.mode = .warming
        hudState.statusMessage = "Preparing speech engine..."
        hudState.streamingText = subtitle ?? (queuedRecording
            ? "First launch can take 1-3 min. Recording starts automatically when ready."
            : "First launch can take 1-3 min. We'll notify you when it's ready.")
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

    func updateAudioLevel(_ level: Float) {
        hudState.audioLevel = CGFloat(max(0.0, min(1.0, level)))
        waveView?.audioLevel = CGFloat(max(0.0, min(1.0, level)))
    }

    func updateStreamingText(_ text: String) {
        hudState.streamingText = text
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

    private var feedbackDismissToken = UUID()

    func showActionFeedback(_ message: String, duration: TimeInterval = 1.6) {
        ensureRecordingPanel()
        stopDurationTimer()
        hudState.mode = .actionNotice
        hudState.statusMessage = message
        recordingTitleLabel?.stringValue = message
        recordingSubtitleLabel?.stringValue = message
        positionRecordingPanel()
        recordingPanel?.orderFrontRegardless()

        let token = UUID()
        feedbackDismissToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self,
                  self.hudState.mode == .actionNotice,
                  self.feedbackDismissToken == token else { return }
            self.hideRecordingPanel()
        }
    }

    private func startDurationTimer() {
        stopDurationTimer()
        hudState.elapsedDeciseconds = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.hudState.elapsedDeciseconds += 1
        }
        RunLoop.main.add(durationTimer!, forMode: .common)
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func ensureTranscriptPanel() {
        if transcriptPanel != nil {
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
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
        language.frame = NSRect(x: 20, y: 340, width: 380, height: 20)
        language.font = AppStyle.Typography.helper
        language.textColor = AppStyle.Palette.hintText
        content.addSubview(language)
        languageLabel = language

        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyTranscript))
        copyButton.frame = NSRect(x: 520, y: 335, width: 80, height: 28)
        copyButton.bezelStyle = .rounded
        content.addSubview(copyButton)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 580, height: 305))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
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
            contentRect: NSRect(x: 0, y: 0, width: 530, height: 50),
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

        let hudView = DictationHUDView(
            state: hudState,
            onCancel: { [weak self] in self?.onCancel?() },
            onFinish: { [weak self] in self?.onFinish?() }
        )
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // Internal labels for test compatibility
        let titleLabel = NSTextField(labelWithString: "Recording")
        let subtitleLabel = NSTextField(labelWithString: "Listening...")
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
        let y: CGFloat
        switch overlayPlacement {
        case .top:
            y = visible.maxY - panel.frame.height - 18
        case .bottom:
            y = visible.minY + 28
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hideRecordingPanel() {
        stopDurationTimer()
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
