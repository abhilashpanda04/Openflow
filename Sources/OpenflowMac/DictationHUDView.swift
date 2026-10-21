import AppKit
import Combine
import SwiftUI

public enum HUDMode {
    case recording
    case transcribing
    case warming
    case actionNotice
}

public final class DictationHUDState: ObservableObject {
    @Published public var mode: HUDMode = .recording
    @Published public var targetAppName: String = "Active App"
    @Published public var streamingText: String = "Listening to your voice..."
    @Published public var audioLevel: CGFloat = 0.5
    @Published public var elapsedDeciseconds: Int = 0
    @Published public var micName: String = "Studio Mic (Built-in)"
    @Published public var statusMessage: String = "Listening..."
    @Published public var audioFormatInfo: String = "16 kHz • WhisperKit Lossless"

    public static let waveBarHexes = [
        // Orange / Coral cluster
        "f95738", "fa5f38", "ff483a", "ff385c", "ff385c", "f72585",
        // Vibrant Pink / Magenta cluster
        "f72585", "e81c96", "d91cb0", "cc22bd", "b526d1", "a12be4", "9b30ff",
        // Purple / Center Crest
        "913bff", "8247ff", "7552ff", "6a5cff", "5f66ff", "5672ff",
        // Electric Indigo / Slate Blue
        "4e7dff", "4688ff", "3e94ff", "3aa1ff", "35b1ff",
        // Cyan / Teal Tail end
        "2ec4f6", "24d3e8", "18e2d7", "14ecc9", "12f7b8"
    ]

    public static let rainbowHexes = [
        "f95738", "ff385c", "f72585", "913bff", "5f66ff", "2ec4f6", "12f7b8"
    ]

    public init() {}
}

public struct DictationHUDView: View {
    @ObservedObject public var state: DictationHUDState
    public var onCancel: () -> Void
    public var onFinish: () -> Void

    @State private var isBlinkingCursor = false

    public init(
        state: DictationHUDState,
        onCancel: @escaping () -> Void = {},
        onFinish: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onCancel = onCancel
        self.onFinish = onFinish
    }

    public var body: some View {
        Group {
            if state.mode == .actionNotice {
                HStack(spacing: 9) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "34d399"))

                    Text(state.statusMessage)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white)

                    Spacer()

                    Text("Done")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(width: 440, height: 44)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    // 1. Ruby Red Pulsing Recording Dot
                    ZStack {
                        Circle()
                            .fill(indicatorColor.opacity(0.35))
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(indicatorColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: indicatorColor.opacity(0.85), radius: 5)
                    }

                    // 2. Monospaced Elapsed Timer (e.g. 01:23.4)
                    HStack(spacing: 0) {
                        Text(timerMinutesAndSeconds)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white)
                        Text("." + timerDecisecond)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.60))
                    }

                    // 3. Compact 7-Bar Chromatic Rainbow Equalizer
                    CompactRainbowWaveformView(state: state)

                    // 4. Real-time Live Streaming Transcription Text (Single line)
                    HStack(spacing: 2) {
                        Text(state.streamingText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("|")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.cyan)
                            .opacity(isBlinkingCursor ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBlinkingCursor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 5. Esc Keycap Button
                    Button(action: onCancel) {
                        Text("esc")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    // 6. Done ↵ Pill Button
                    Button(action: onFinish) {
                        HStack(spacing: 3) {
                            Text(finishButtonTitle)
                                .font(.system(size: 11, weight: .semibold))
                            Text("↵")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "2563eb"), Color(hex: "4f46e5")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color.indigo.opacity(0.35), radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(width: 520, height: 44)
            }
        }
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedRed: 11/255.0, green: 15/255.0, blue: 20/255.0, alpha: 0.94)))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(state.mode == .actionNotice ? Color(hex: "34d399").opacity(0.4) : Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.65), radius: 24, x: 0, y: 12)
        )
        .onAppear {
            isBlinkingCursor = true
        }
    }

    private var indicatorColor: Color {
        switch state.mode {
        case .recording:
            return Color(hex: "ef4444")
        case .transcribing:
            return Color(hex: "a855f7")
        case .warming:
            return Color(hex: "f59e0b")
        case .actionNotice:
            return Color(hex: "10b981")
        }
    }

    private var finishButtonTitle: String {
        switch state.mode {
        case .recording:
            return "Done"
        case .transcribing:
            return "Processing"
        case .warming:
            return "Wait"
        case .actionNotice:
            return "Done"
        }
    }

    private var timerMinutesAndSeconds: String {
        let totalSeconds = state.elapsedDeciseconds / 10
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var timerDecisecond: String {
        let decisecond = state.elapsedDeciseconds % 10
        return String(decisecond)
    }
}

// MARK: - Compact 7-Bar Chromatic Rainbow Equalizer

public struct CompactRainbowWaveformView: View {
    @ObservedObject public var state: DictationHUDState
    @State private var phase: Double = 0
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    public init(state: DictationHUDState) {
        self.state = state
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<DictationHUDState.rainbowHexes.count, id: \.self) { i in
                let color = Color(hex: DictationHUDState.rainbowHexes[i])
                let height = barHeight(for: i)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color)
                    .frame(width: 3, height: height)
                    .shadow(color: color.opacity(0.70), radius: 2, x: 0, y: 0)
                    .animation(.easeOut(duration: 0.10), value: height)
            }
        }
        .frame(height: 20)
        .onReceive(timer) { _ in
            phase += 0.08
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minH: CGFloat = 4.0
        let maxH: CGFloat = 18.0

        switch state.mode {
        case .warming:
            let pulse = (sin(phase * 3.0) + 1.0) * 0.5
            return minH + CGFloat(pulse * 6.0)
        case .transcribing:
            let wave = sin(phase * 6.0 - Double(index) * 0.5) * 0.5 + 0.5
            return minH + CGFloat(wave * 12.0)
        case .recording:
            let wave = sin(phase * 4.5 + Double(index) * 0.8) * 0.5 + 0.5
            let level = Double(max(0.08, state.audioLevel))
            let dynamicH = minH + CGFloat(wave * level * Double(maxH - minH))
            return min(maxH, max(minH, dynamicH))
        case .actionNotice:
            return minH
        }
    }
}

// MARK: - Color Hex Extension

private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleanHex.count {
        case 6:
            (r, g, b) = (int >> 16, (int >> 8) & 0xff, int & 0xff)
        default:
            (r, g, b) = (128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1.0
        )
    }
}
