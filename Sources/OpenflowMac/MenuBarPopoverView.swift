import AppKit
import Combine
import SwiftUI

// MARK: - Color Hex Helper
private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

// MARK: - Design System Tokens (Swiss Editorial & Apple Craft)
private enum PopoverTheme {
    static var isDark: Bool { AppThemeManager.shared.isDark }

    // Surfaces
    static var baseBg: Color {
        isDark ? Color(hex: "080d1a") : Color(hex: "ffffff")
    }
    static var cardBg: Color {
        isDark ? Color.white.opacity(0.04) : Color(hex: "f8fafc")
    }
    static var cardBorder: Color {
        isDark ? Color.white.opacity(0.08) : Color(hex: "0f172a").opacity(0.08)
    }
    static var subtleDivider: Color {
        isDark ? Color.white.opacity(0.06) : Color(hex: "0f172a").opacity(0.06)
    }
    static var hoverBg: Color {
        isDark ? Color.white.opacity(0.06) : Color(hex: "f1f5f9")
    }
    static var chipBg: Color {
        isDark ? Color.white.opacity(0.07) : Color(hex: "e2e8f0").opacity(0.75)
    }

    // Typography
    static var textPrimary: Color {
        isDark ? Color.white : Color(hex: "090d16")
    }
    static var textSecondary: Color {
        isDark ? Color.white.opacity(0.72) : Color(hex: "334155")
    }
    static var textMuted: Color {
        isDark ? Color.white.opacity(0.48) : Color(hex: "64748b")
    }
    static var textSubtle: Color {
        isDark ? Color.white.opacity(0.30) : Color(hex: "94a3b8")
    }

    // Brand Accents
    static let cyan = Color(hex: "0ea5e9")
    static let sky = Color(hex: "38bdf8")
    static let navy = Color(hex: "0a2540")
    static let teal = Color(hex: "0e7490")
    static let ice = Color(hex: "bae6fd")

    // Semantic Status
    static let emerald = Color(hex: "10b981")
    static let amber = Color(hex: "f59e0b")
    static let coral = Color(hex: "f43f5e")
}

// MARK: - Observable State for Menu Bar Popover
public final class MenuBarPopoverState: ObservableObject {
    @Published public var isRecording: Bool = false
    @Published public var hotkeyDisplay: String = "Cmd+Shift+Space"
    @Published public var engineTitle: String = "Native CoreML"
    @Published public var engineBadge: String = "ANE Optimized"
    @Published public var modelState: String = "Ready (On-Device Neural)"
    @Published public var backendStatus: String = "healthy · ~12ms"
    @Published public var outputTarget: String = "Active App"
    @Published public var lastTranscript: String = ""
    @Published public var lastTranscriptTime: String = ""
    @Published public var isRemoteServer: Bool = false
    @Published public var audioLevel: CGFloat = 0.0

    // Model Download Progress State
    @Published public var isDownloadingModel: Bool = false
    @Published public var modelDownloadProgress: Double = 0.0
    @Published public var modelDownloadStatus: String = ""
    @Published public var modelDownloadName: String = ""

    // Live Application Capacity & Resource Footprint
    @Published public var memoryUsage: String = "118 MB RAM"
    @Published public var cpuUsage: String = "1.2% CPU"
    @Published public var threadUsage: String = "8 Threads"
    @Published public var modelFootprint: String = "+140 MB Weights"
    @Published public var totalCapacity: String = "258 MB Total"

    // Audio Input Device
    @Published public var currentMicrophoneName: String = "Built-in Microphone"
    @Published public var selectedMicrophoneID: String = "default"
    @Published public var availableMicrophones: [AudioInputDevice] = []

    // Live Permission Statuses
    @Published public var isMicrophonePermissionGranted: Bool = true
    @Published public var isAccessibilityPermissionGranted: Bool = true
    @Published public var isSpeechRecognitionPermissionGranted: Bool = true

    public var onStartStopRecording: (() -> Void)?
    public var onShowLastTranscript: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onStartBackend: (() -> Void)?
    public var onStopBackend: (() -> Void)?
    public var onRetryBackend: (() -> Void)?
    public var onRefreshBackend: (() -> Void)?
    public var onSelectMicrophone: ((String) -> Void)?
    public var onRequestMicrophonePermission: (() -> Void)?
    public var onRequestAccessibilityPermission: (() -> Void)?
    public var onOpenPrivacySettings: ((PermissionsManager.PrivacySection) -> Void)?

    public init() {}
}

// MARK: - Main SwiftUI View
public struct MenuBarPopoverView: View {
    @ObservedObject public var state: MenuBarPopoverState
    @ObservedObject private var themeManager = AppThemeManager.shared
    @State private var showDiagnostics: Bool = false
    @State private var copiedTranscript: Bool = false

    public init(state: MenuBarPopoverState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Sleek Brand Header
            headerBar

            // 2. Primary Body Content
            VStack(spacing: 10) {
                // Permissions Callout (Contextual, refined amber tone)
                if !state.isMicrophonePermissionGranted || !state.isAccessibilityPermissionGranted {
                    permissionCallout
                }

                // Voice Recording Hero Instrument
                recordingHeroCard

                // Recent Flow Note (Editorial transcription card)
                recentTranscriptCard

                // Hardware & Neural Engine Instrument Strip
                hardwareInstrumentStrip

                // Expandable Telemetry Drawer (RAM, CPU, Latency - Clean by default!)
                if showDiagnostics {
                    diagnosticsDrawer
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Service Controls (If Remote Server Mode)
                if state.isRemoteServer {
                    serviceControlsSection
                }

                // System Actions & Utilities
                footerActionsList
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // 3. Bottom Whisper Status Bar
            bottomBar
        }
        .frame(width: 370)
        .background(PopoverTheme.baseBg)
        .preferredColorScheme(themeManager.colorScheme)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showDiagnostics)
        .animation(.easeInOut(duration: 0.2), value: state.isRecording)
    }

    // MARK: - 1. Sleek Brand Header
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            // Official Openflow Squircle Logo
            OpenflowLogoView(size: 28, cornerRadius: 8)
                .shadow(color: PopoverTheme.cyan.opacity(PopoverTheme.isDark ? 0.35 : 0.2), radius: 6, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text("Openflow")
                        .font(.system(size: 13.5, weight: .bold, design: .default))
                        .foregroundStyle(PopoverTheme.textPrimary)

                    Text("v0.1.0")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(PopoverTheme.chipBg)
                        .foregroundStyle(PopoverTheme.textMuted)
                        .clipShape(Capsule())
                }

                Text("On-Device Voice Engine")
                    .font(.system(size: 10.5))
                    .foregroundStyle(PopoverTheme.textMuted)
            }

            Spacer()

            // Status Indicator Pill
            let allPermsGranted = state.isMicrophonePermissionGranted && state.isAccessibilityPermissionGranted
            HStack(spacing: 5) {
                Circle()
                    .fill(allPermsGranted ? PopoverTheme.emerald : PopoverTheme.amber)
                    .frame(width: 6, height: 6)
                    .shadow(color: (allPermsGranted ? PopoverTheme.emerald : PopoverTheme.amber).opacity(0.6), radius: 3)

                Text(allPermsGranted ? "Ready" : "Setup Needed")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(allPermsGranted ? PopoverTheme.emerald : PopoverTheme.amber)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background((allPermsGranted ? PopoverTheme.emerald : PopoverTheme.amber).opacity(PopoverTheme.isDark ? 0.12 : 0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke((allPermsGranted ? PopoverTheme.emerald : PopoverTheme.amber).opacity(0.22), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [PopoverTheme.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.015), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(PopoverTheme.subtleDivider).frame(height: 1)
            }
        )
    }

    // MARK: - 2. Permission Callout (Warm Architectural Style)
    private var permissionCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(PopoverTheme.amber)

                Text("PERMISSIONS REQUIRED")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(PopoverTheme.amber)
                    .tracking(0.5)

                Spacer()
            }

            let micMissing = !state.isMicrophonePermissionGranted
            let accMissing = !state.isAccessibilityPermissionGranted
            let msg = (micMissing && accMissing)
                ? "Microphone and Accessibility permissions are needed to dictate and type into your active apps."
                : (micMissing
                    ? "Microphone access is needed to capture speech on Apple Silicon."
                    : "Accessibility permission is required to type transcribed text into active fields.")

            Text(msg)
                .font(.system(size: 10.5))
                .foregroundStyle(PopoverTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if micMissing {
                    Button {
                        state.onRequestMicrophonePermission?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 9))
                            Text("Grant Mic")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PopoverTheme.amber.opacity(PopoverTheme.isDark ? 0.18 : 0.12))
                        .foregroundStyle(PopoverTheme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PopoverTheme.amber.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if accMissing {
                    Button {
                        state.onRequestAccessibilityPermission?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 9))
                            Text("Grant Accessibility")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PopoverTheme.amber.opacity(PopoverTheme.isDark ? 0.18 : 0.12))
                        .foregroundStyle(PopoverTheme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PopoverTheme.amber.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    state.onOpenSettings?()
                } label: {
                    Text("Settings →")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PopoverTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PopoverTheme.amber.opacity(PopoverTheme.isDark ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PopoverTheme.amber.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - 3. Voice Recording Hero Instrument
    private var recordingHeroCard: some View {
        Button {
            state.onStartStopRecording?()
        } label: {
            HStack(spacing: 12) {
                // Tactile Record Icon / Equalizer Visualizer
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            state.isRecording
                                ? LinearGradient(colors: [Color(hex: "f43f5e"), Color(hex: "e11d48")], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [PopoverTheme.navy, PopoverTheme.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 38, height: 38)
                        .shadow(
                            color: state.isRecording ? PopoverTheme.coral.opacity(0.55) : PopoverTheme.cyan.opacity(0.25),
                            radius: state.isRecording ? 8 : 4,
                            x: 0,
                            y: 2
                        )

                    if state.isRecording {
                        // Live dancing acoustic waveform inside button
                        HStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { idx in
                                let barH = min(18.0, max(4.0, 4.0 + state.audioLevel * CGFloat(idx + 2) * 4.5))
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white)
                                    .frame(width: 2.2, height: barH)
                            }
                        }
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }

                // Contextual Typography
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.isRecording ? "Listening & Typing..." : "Start Dictating")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(state.isRecording ? PopoverTheme.coral : PopoverTheme.textPrimary)

                    Text(state.isRecording ? "Tap to finish transcription" : "Speak naturally into active field")
                        .font(.system(size: 10.5))
                        .foregroundStyle(PopoverTheme.textMuted)
                }

                Spacer()

                // Authentic Apple Mechanical Keycap Badge
                keycapsBadge(for: state.hotkeyDisplay)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        state.isRecording
                            ? PopoverTheme.coral.opacity(PopoverTheme.isDark ? 0.12 : 0.07)
                            : PopoverTheme.cardBg
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        state.isRecording
                            ? PopoverTheme.coral.opacity(0.35)
                            : PopoverTheme.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Recent Flow Note (Editorial Transcript Preview)
    private var recentTranscriptCard: some View {
        Button {
            state.onShowLastTranscript?()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center) {
                    HStack(spacing: 5) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PopoverTheme.cyan)

                        Text("LAST DICTATION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(PopoverTheme.textSubtle)
                            .tracking(0.6)
                    }

                    Spacer()

                    if !state.lastTranscript.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(state.lastTranscript, forType: .string)
                            copiedTranscript = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedTranscript = false
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copiedTranscript ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 8.5))
                                Text(copiedTranscript ? "Copied" : "Copy")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(PopoverTheme.chipBg)
                            .foregroundStyle(copiedTranscript ? PopoverTheme.emerald : PopoverTheme.textMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                let previewText = state.lastTranscript.isEmpty
                    ? "Ready for your next thought. Press the hotkey in any app."
                    : "“\(state.lastTranscript)”"

                Text(previewText)
                    .font(.system(size: 11, weight: state.lastTranscript.isEmpty ? .regular : .medium))
                    .foregroundStyle(state.lastTranscript.isEmpty ? PopoverTheme.textMuted : PopoverTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PopoverTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(PopoverTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Hardware & Neural Engine Strip
    private var hardwareInstrumentStrip: some View {
        HStack(spacing: 8) {
            // Microphone Selector Dropdown
            Menu {
                Button {
                    state.onSelectMicrophone?("default")
                } label: {
                    HStack {
                        Text("System Default")
                        if state.selectedMicrophoneID == "default" {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if !state.availableMicrophones.isEmpty {
                    Divider()
                    ForEach(state.availableMicrophones) { device in
                        Button {
                            state.onSelectMicrophone?(device.id)
                        } label: {
                            HStack {
                                Text(device.name)
                                if state.selectedMicrophoneID == device.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(PopoverTheme.cyan)

                    Text(state.currentMicrophoneName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(PopoverTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 130, alignment: .leading)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7.5))
                        .foregroundStyle(PopoverTheme.textSubtle)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(PopoverTheme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PopoverTheme.cardBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Engine & Neural Badge + Diagnostics Chevron
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showDiagnostics.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(PopoverTheme.emerald)
                        .frame(width: 4.5, height: 4.5)

                    Text("ANE · CoreML")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PopoverTheme.textSecondary)

                    Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(PopoverTheme.textSubtle)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(PopoverTheme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PopoverTheme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 6. Diagnostics Drawer (Discreet Expandable Tray)
    private var diagnosticsDrawer: some View {
        VStack(spacing: 5) {
            diagnosticMetricRow(title: "Engine Target", value: state.engineTitle, subvalue: state.engineBadge)
            diagnosticMetricRow(title: "Model Status", value: state.modelState, subvalue: nil)
            diagnosticMetricRow(title: "Pipeline Latency", value: state.backendStatus, subvalue: nil)
            diagnosticMetricRow(title: "Process Footprint", value: "\(state.memoryUsage) · \(state.cpuUsage)", subvalue: state.modelFootprint)

            if state.isDownloadingModel {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(state.modelDownloadName.isEmpty ? "Downloading Weights" : state.modelDownloadName)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(PopoverTheme.textPrimary)
                        Spacer()
                        Text("\(Int(state.modelDownloadProgress * 100))%")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(PopoverTheme.cyan)
                    }

                    ProgressView(value: state.modelDownloadProgress)
                        .progressViewStyle(.linear)
                        .tint(PopoverTheme.cyan)
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PopoverTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PopoverTheme.cardBorder, lineWidth: 1)
        )
    }

    private func diagnosticMetricRow(title: String, value: String, subvalue: String?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(PopoverTheme.textMuted)

            Spacer()

            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PopoverTheme.textPrimary)

                if let subvalue = subvalue {
                    Text(subvalue)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(PopoverTheme.chipBg)
                        .foregroundStyle(PopoverTheme.textMuted)
                        .cornerRadius(3)
                }
            }
        }
    }

    // MARK: - Service Management (Remote Server Only)
    private var serviceControlsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SERVER PIPELINE")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(PopoverTheme.textSubtle)
                .tracking(0.6)
                .padding(.horizontal, 2)

            HStack(spacing: 6) {
                serviceBtn(title: "Start", icon: "play.fill", color: PopoverTheme.emerald) {
                    state.onStartBackend?()
                }
                serviceBtn(title: "Stop", icon: "stop.fill", color: PopoverTheme.coral) {
                    state.onStopBackend?()
                }
                serviceBtn(title: "Sync", icon: "arrow.clockwise", color: PopoverTheme.cyan) {
                    state.onRefreshBackend?()
                }
            }
        }
    }

    private func serviceBtn(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8.5))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(PopoverTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3.5)
            .background(PopoverTheme.chipBg)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 7. Footer Actions List
    private var footerActionsList: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(PopoverTheme.subtleDivider)
                .frame(height: 1)
                .padding(.vertical, 2)

            // Theme Switcher Row
            menuActionRow(
                icon: themeManager.isDark ? "sun.max" : "moon.stars",
                iconColor: PopoverTheme.textMuted,
                title: themeManager.isDark ? "Light Paper Theme" : "Dark Obsidian Theme",
                shortcut: nil,
                badge: themeManager.theme.displayName
            ) {
                themeManager.toggleTheme()
            }

            // Speech Reader Row
            menuActionRow(
                icon: "waveform.badge.magnifyingglass",
                iconColor: PopoverTheme.textMuted,
                title: "Speech Reader (TTS)",
                shortcut: nil,
                badge: nil
            ) {
                ReaderPanelController.shared.show()
            }

            // Settings Row
            menuActionRow(
                icon: "slider.horizontal.3",
                iconColor: PopoverTheme.textMuted,
                title: "Settings...",
                shortcut: "⌘,",
                badge: nil
            ) {
                state.onOpenSettings?()
            }

            // Quit Row
            menuActionRow(
                icon: "power",
                iconColor: PopoverTheme.coral.opacity(0.85),
                title: "Quit Openflow",
                shortcut: "⌘Q",
                badge: nil,
                isDestructive: true
            ) {
                state.onQuit?()
            }
        }
    }

    private func menuActionRow(
        icon: String,
        iconColor: Color,
        title: String,
        shortcut: String?,
        badge: String?,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(isDestructive ? PopoverTheme.coral : PopoverTheme.textSecondary)

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(PopoverTheme.chipBg)
                        .foregroundStyle(PopoverTheme.textMuted)
                        .cornerRadius(3)
                }

                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PopoverTheme.textSubtle)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 8. Bottom Whisper Status Bar
    private var bottomBar: some View {
        HStack {
            HStack(spacing: 3) {
                Text("Press")
                    .font(.system(size: 9.5))
                    .foregroundStyle(PopoverTheme.textSubtle)

                Text("Esc")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(PopoverTheme.chipBg)
                    .foregroundStyle(PopoverTheme.textMuted)
                    .cornerRadius(3)

                Text("to close")
                    .font(.system(size: 9.5))
                    .foregroundStyle(PopoverTheme.textSubtle)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(PopoverTheme.emerald)
                    .frame(width: 4.5, height: 4.5)

                Text("Apple Silicon Neural Engine Active")
                    .font(.system(size: 9.5))
                    .foregroundStyle(PopoverTheme.textSubtle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            PopoverTheme.isDark ? Color.black.opacity(0.25) : Color(hex: "f8fafc")
        )
        .overlay(
            VStack {
                Rectangle().fill(PopoverTheme.subtleDivider).frame(height: 1)
                Spacer()
            }
        )
    }

    // MARK: - Mechanical Keycap View
    private func keycapsBadge(for text: String) -> some View {
        let parts = text.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        return HStack(spacing: 3) {
            ForEach(parts, id: \.self) { part in
                Text(keycapSymbol(for: part))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PopoverTheme.textPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(PopoverTheme.chipBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PopoverTheme.cardBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(PopoverTheme.isDark ? 0.2 : 0.04), radius: 1, x: 0, y: 1)
            }
        }
    }

    private func keycapSymbol(for token: String) -> String {
        switch token.lowercased() {
        case "cmd", "command": return "⌘"
        case "shift": return "⇧"
        case "opt", "option", "alt": return "⌥"
        case "ctrl", "control": return "⌃"
        default: return token
        }
    }
}
