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

// MARK: - Theme Constants
private enum PopoverTheme {
    static var isDark: Bool { AppThemeManager.shared.isDark }
    static var base: Color { isDark ? Color(hex: "0e121d") : Color.white }
    static var surface: Color { isDark ? Color(hex: "0f131c") : Color(hex: "f8fafc") }
    static var elevated: Color { isDark ? Color(hex: "181b25") : Color(hex: "f1f5f9") }
    static var border: Color { isDark ? Color(hex: "222736") : Color(hex: "e2e8f0") }
    static var borderLight: Color { isDark ? Color.white.opacity(0.09) : Color(hex: "cbd5e1").opacity(0.8) }
    static var textPrimary: Color { isDark ? Color.white : Color(hex: "0f172a") }
    static var textMuted: Color { isDark ? Color.white.opacity(0.55) : Color(hex: "64748b") }
    static var textSubtle: Color { isDark ? Color.white.opacity(0.40) : Color(hex: "94a3b8") }
    static var chipBg: Color { isDark ? Color.white.opacity(0.08) : Color(hex: "e2e8f0").opacity(0.70) }
    static var cardBg: Color { isDark ? Color.white.opacity(0.03) : Color(hex: "f8fafc") }
    static var cardBorder: Color { isDark ? Color.white.opacity(0.06) : Color(hex: "e2e8f0") }
    static var bottomBarBg: Color { isDark ? Color(hex: "0a0d14").opacity(0.80) : Color(hex: "f1f5f9").opacity(0.95) }
    static let coral = Color(hex: "ff5c5c")
    static let violet = Color(hex: "6366f1")
    static let cyan = Color(hex: "06b6d4")
    static let emerald = Color(hex: "10b981")
    static let amber = Color(hex: "f59e0b")
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

    public init(state: MenuBarPopoverState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Header / App Banner
            headerView

            // Menu Body Container
            VStack(spacing: 8) {
                // Section 0: Permission Warning Banner (if any required permission missing)
                if !state.isMicrophonePermissionGranted || !state.isAccessibilityPermissionGranted {
                    permissionAlertBanner
                }

                // Section 1: Primary Action Items
                primaryActionsSection

                // Section 2: Engine Diagnostics Card
                telemetryCardSection

                // Section 3: Service Management (If Remote Server)
                if state.isRemoteServer {
                    serviceControlsSection
                }

                // Section 4: Settings & Quit System Actions
                footerActionsSection
            }
            .padding(10)

            // Popover Bottom Notch & Tip Indicator
            bottomNotchBar
        }
        .frame(width: 390)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PopoverTheme.base.opacity(PopoverTheme.isDark ? 0.96 : 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PopoverTheme.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(PopoverTheme.isDark ? 0.65 : 0.12), radius: 30, x: 0, y: 15)
        .preferredColorScheme(themeManager.colorScheme)
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            // Unified Official Openflow Brand Logo
            OpenflowLogoView(size: 34, cornerRadius: 10)
                .shadow(color: Color(hex: "0284c7").opacity(0.35), radius: 8, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Openflow")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PopoverTheme.textPrimary)

                    Text("v0.1.0")
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(PopoverTheme.chipBg)
                        .foregroundStyle(PopoverTheme.textMuted)
                        .clipShape(Capsule())
                }

                Text("Real-time On-Device Neural Speech")
                    .font(.system(size: 11))
                    .foregroundStyle(PopoverTheme.textMuted)
            }

            Spacer()

            // Quick Status Indicator
            let allPermsGranted = state.isMicrophonePermissionGranted && state.isAccessibilityPermissionGranted
            HStack(spacing: 5) {
                Circle()
                    .fill(allPermsGranted ? Color(hex: "10b981") : Color(hex: "f59e0b"))
                    .frame(width: 6, height: 6)
                    .shadow(color: (allPermsGranted ? Color(hex: "10b981") : Color(hex: "f59e0b")).opacity(0.8), radius: 4)

                Text(allPermsGranted ? "Online" : "Needs Access")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(allPermsGranted ? Color(hex: "10b981") : Color(hex: "f59e0b"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((allPermsGranted ? Color(hex: "10b981") : Color(hex: "f59e0b")).opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke((allPermsGranted ? Color(hex: "10b981") : Color(hex: "f59e0b")).opacity(0.25), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [PopoverTheme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.02), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(PopoverTheme.borderLight).frame(height: 1)
            }
        )
    }

    // MARK: - Section 0: Permission Alert Banner
    private var permissionAlertBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "f59e0b"))

                Text("PERMISSIONS REQUIRED")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color(hex: "f59e0b"))
                    .tracking(0.5)

                Spacer()
            }

            let micMissing = !state.isMicrophonePermissionGranted
            let accMissing = !state.isAccessibilityPermissionGranted
            let message: String = {
                if micMissing && accMissing {
                    return "Microphone access is needed to capture speech, and Accessibility is required to type text into active apps."
                } else if micMissing {
                    return "Microphone access is needed to record your voice."
                } else {
                    return "Accessibility permission is required to paste transcribed text and run voice commands."
                }
            }()

            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(PopoverTheme.isDark ? Color.white.opacity(0.85) : Color(hex: "92400e"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if micMissing {
                    Button {
                        state.onRequestMicrophonePermission?()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 9))
                            Text("Grant Mic")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color(hex: "ef4444").opacity(0.25))
                        .foregroundStyle(PopoverTheme.isDark ? Color(hex: "fca5a5") : Color(hex: "b91c1c"))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color(hex: "ef4444").opacity(0.5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if accMissing {
                    Button {
                        state.onRequestAccessibilityPermission?()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 9))
                            Text("Grant Accessibility")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color(hex: "f59e0b").opacity(0.25))
                        .foregroundStyle(PopoverTheme.isDark ? Color(hex: "fcd34d") : Color(hex: "b45309"))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color(hex: "f59e0b").opacity(0.5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    state.onOpenSettings?()
                } label: {
                    Text("Resolve in Settings →")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: "3b82f6"))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PopoverTheme.isDark ? Color(hex: "b45309").opacity(0.18) : Color(hex: "fef3c7"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: "f59e0b").opacity(PopoverTheme.isDark ? 0.4 : 0.6), lineWidth: 1)
        )
    }

    // MARK: - Section 1: Primary Actions
    private var primaryActionsSection: some View {
        VStack(spacing: 6) {
            // Start / Stop Recording Hero Button
            Button {
                state.onStartStopRecording?()
            } label: {
                HStack(spacing: 12) {
                    if state.isRecording {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "ef4444"), Color(hex: "dc2626")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 30, height: 30)
                                .shadow(color: Color(hex: "ef4444").opacity(0.55), radius: 6)

                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "0284c7"), Color(hex: "0369a1")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 30, height: 30)
                                .shadow(color: Color(hex: "0284c7").opacity(0.35), radius: 6, x: 0, y: 1)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(PopoverTheme.textPrimary)

                        Text(state.isRecording ? "Transcribing & typing output..." : "Stream microphone directly into active field")
                            .font(.system(size: 10))
                            .foregroundStyle(state.isRecording ? Color(hex: "ef4444") : PopoverTheme.textMuted)
                    }

                    Spacer()

                    // Keycap Pills
                    keycapsView(for: state.hotkeyDisplay)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            state.isRecording
                                ? LinearGradient(
                                    colors: [Color(hex: "ef4444").opacity(PopoverTheme.isDark ? 0.22 : 0.14), Color(hex: "f43f5e").opacity(PopoverTheme.isDark ? 0.12 : 0.08), Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [Color(hex: "0284c7").opacity(PopoverTheme.isDark ? 0.22 : 0.12), Color(hex: "0369a1").opacity(PopoverTheme.isDark ? 0.12 : 0.06), Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            state.isRecording
                                ? Color(hex: "ef4444").opacity(0.40)
                                : Color(hex: "0284c7").opacity(PopoverTheme.isDark ? 0.35 : 0.25),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)

            // Show Last Transcript Row
            Button {
                state.onShowLastTranscript?()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PopoverTheme.chipBg)
                            .frame(width: 26, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(PopoverTheme.borderLight, lineWidth: 1)
                            )

                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(PopoverTheme.textPrimary.opacity(0.80))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show Last Transcript")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PopoverTheme.textPrimary.opacity(0.90))

                        let preview = state.lastTranscript.isEmpty
                            ? "No dictations stored yet"
                            : "“\(state.lastTranscript.prefix(28))...”"
                        Text(preview)
                            .font(.system(size: 10))
                            .foregroundStyle(PopoverTheme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PopoverTheme.textSubtle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.clear)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PopoverTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Section 2: Engine Diagnostics Card
    private var telemetryCardSection: some View {
        VStack(spacing: 8) {
            // Header with mini audio equalizer
            HStack {
                Text("ENGINE DIAGNOSTICS & STATUS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(PopoverTheme.textSubtle)
                    .tracking(0.6)

                Spacer()

                HStack(spacing: 5) {
                    Text("Input level")
                        .font(.system(size: 9.5))
                        .foregroundStyle(PopoverTheme.textSubtle)

                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { idx in
                            let h: CGFloat = state.isRecording
                                ? min(14, max(3, 3 + state.audioLevel * CGFloat(idx + 2) * 2.5))
                                : 3.0
                            RoundedRectangle(cornerRadius: 1)
                                .fill(state.isRecording ? Color(hex: "10b981") : (PopoverTheme.isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.15)))
                                .frame(width: 2, height: h)
                        }
                    }
                    .frame(height: 14)
                }
            }
            .padding(.bottom, 2)
            .overlay(
                VStack {
                    Spacer()
                    Rectangle().fill(PopoverTheme.cardBorder).frame(height: 1)
                }
            )

            // Diagnostic Rows
            VStack(spacing: 6) {
                // Engine Row
                diagnosticRow(
                    icon: "cpu",
                    iconColor: Color(hex: "818cf8"),
                    title: "Engine"
                ) {
                    HStack(spacing: 5) {
                        Text(state.engineTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PopoverTheme.textPrimary)

                        Text(state.engineBadge)
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(PopoverTheme.chipBg)
                            .foregroundStyle(PopoverTheme.textMuted)
                            .cornerRadius(4)
                    }
                }

                // Model State Row
                diagnosticRow(
                    icon: "checkmark.shield.fill",
                    iconColor: Color(hex: "38bdf8"),
                    title: "Model State"
                ) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(state.isDownloadingModel ? Color(hex: "f59e0b") : Color(hex: "10b981"))
                            .frame(width: 5, height: 5)
                        Text(state.isDownloadingModel ? "Downloading (\(Int(state.modelDownloadProgress * 100))%)" : state.modelState)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(state.isDownloadingModel ? Color(hex: "f59e0b") : Color(hex: "10b981"))
                    }
                }

                // Active Download Progress Bar (When Downloading)
                if state.isDownloadingModel {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(state.modelDownloadName.isEmpty ? "Downloading Weights" : state.modelDownloadName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(PopoverTheme.textPrimary)
                            Spacer()
                            Text("\(Int(state.modelDownloadProgress * 100))%")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(PopoverTheme.cyan)
                        }

                        ProgressView(value: state.modelDownloadProgress)
                            .progressViewStyle(.linear)
                            .tint(PopoverTheme.cyan)

                        Text(state.modelDownloadStatus.isEmpty ? "Fetching CoreML model from Hugging Face..." : state.modelDownloadStatus)
                            .font(.system(size: 9))
                            .foregroundStyle(PopoverTheme.textMuted)
                            .lineLimit(1)
                    }
                    .padding(8)
                    .background(Color(hex: "06b6d4").opacity(PopoverTheme.isDark ? 0.08 : 0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "06b6d4").opacity(0.25), lineWidth: 1)
                    )
                }

                // Backend Status Row
                diagnosticRow(
                    icon: "bolt.horizontal.fill",
                    iconColor: Color(hex: "10b981"),
                    title: "Backend"
                ) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "10b981"))
                            .frame(width: 5, height: 5)
                        Text(state.backendStatus)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(PopoverTheme.isDark ? Color(hex: "6ee7b7") : Color(hex: "065f46"))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "10b981").opacity(PopoverTheme.isDark ? 0.12 : 0.15))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: "10b981").opacity(0.25), lineWidth: 1)
                    )
                }

                // Output Target Row
                diagnosticRow(
                    icon: "arrow.right.to.line.compact",
                    iconColor: Color(hex: "fbbf24"),
                    title: "Output Target"
                ) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "6366f1"))
                            .frame(width: 6, height: 6)

                        Text(state.outputTarget)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(PopoverTheme.textPrimary.opacity(0.90))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PopoverTheme.chipBg)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(PopoverTheme.cardBorder, lineWidth: 1)
                    )
                }

                // Microphone Input Device Selector Row
                diagnosticRow(
                    icon: "mic.fill",
                    iconColor: Color(hex: "f43f5e"),
                    title: "Microphone"
                ) {
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
                        HStack(spacing: 4) {
                            Text(state.currentMicrophoneName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(PopoverTheme.textPrimary.opacity(0.95))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 165, alignment: .trailing)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(PopoverTheme.textSubtle)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(PopoverTheme.chipBg)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(PopoverTheme.cardBorder, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Application Capacity & Live Process Metrics (RAM & CPU)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        HStack(spacing: 3.5) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: "0284c7"))
                            Text(state.memoryUsage)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: "0284c7"))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color(hex: "0284c7").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        HStack(spacing: 3.5) {
                            Image(systemName: "gauge.medium")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: "10b981"))
                            Text(state.cpuUsage)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: "10b981"))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color(hex: "10b981").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Spacer()

                        Text(state.modelFootprint)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(PopoverTheme.textMuted)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PopoverTheme.elevated.opacity(PopoverTheme.isDark ? 0.70 : 0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverTheme.cardBorder, lineWidth: 1)
        )
    }

    private func diagnosticRow<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(PopoverTheme.textMuted)
            }

            Spacer()

            trailing()
        }
    }

    // MARK: - Section 3: Service Management (Remote Server Only)
    private var serviceControlsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DAEMON & PIPELINE CONTROL")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(PopoverTheme.textSubtle)
                .tracking(0.6)
                .padding(.horizontal, 4)
                .padding(.top, 2)

            serviceButton(title: "Start Backend", icon: "play.fill", color: Color(hex: "34d399")) {
                state.onStartBackend?()
            }

            serviceButton(title: "Stop Backend", icon: "stop.fill", color: Color(hex: "f87171")) {
                state.onStopBackend?()
            }

            serviceButton(title: "Retry Startup", icon: "arrow.clockwise", color: Color(hex: "fbbf24")) {
                state.onRetryBackend?()
            }

            serviceButton(title: "Refresh Backend Status", icon: "bolt.fill", color: Color(hex: "38bdf8"), badge: "Sync now") {
                state.onRefreshBackend?()
            }
        }
    }

    private func serviceButton(title: String, icon: String, color: Color, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(color)

                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(PopoverTheme.textPrimary.opacity(0.85))
                }

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 4: Settings & Quit
    private var footerActionsSection: some View {
        VStack(spacing: 2) {
            Divider().background(PopoverTheme.cardBorder).padding(.vertical, 2)

            // Quick Theme Switcher Button
            Button {
                themeManager.toggleTheme()
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: themeManager.isDark ? "sun.max.fill" : "moon.stars.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(themeManager.isDark ? Color(hex: "fbbf24") : Color(hex: "6366f1"))

                        Text(themeManager.isDark ? "Light Theme (White)" : "Dark Theme")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PopoverTheme.textPrimary.opacity(0.90))
                    }

                    Spacer()

                    Text(themeManager.theme.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(PopoverTheme.chipBg)
                        .foregroundStyle(PopoverTheme.textMuted)
                        .cornerRadius(4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Settings...
            Button {
                state.onOpenSettings?()
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundStyle(PopoverTheme.textMuted)

                        Text("Settings...")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PopoverTheme.textPrimary.opacity(0.90))
                    }

                    Spacer()

                    HStack(spacing: 2) {
                        keycapLabel("⌘")
                        keycapLabel(",")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Quit Openflow
            Button {
                state.onQuit?()
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "power")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "f87171"))

                        Text("Quit Openflow")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PopoverTheme.textPrimary.opacity(0.80))
                    }

                    Spacer()

                    HStack(spacing: 2) {
                        keycapLabel("⌘")
                        keycapLabel("Q")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom Notch Bar
    private var bottomNotchBar: some View {
        HStack {
            HStack(spacing: 3) {
                Text("Press")
                    .font(.system(size: 10))
                    .foregroundStyle(PopoverTheme.textSubtle)

                Text("Esc")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(PopoverTheme.chipBg)
                    .foregroundStyle(PopoverTheme.textPrimary.opacity(0.85))
                    .cornerRadius(3)

                Text("to close")
                    .font(.system(size: 10))
                    .foregroundStyle(PopoverTheme.textSubtle)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: "10b981"))
                    .frame(width: 5, height: 5)

                Text("Apple Silicon Neural Engine Active")
                    .font(.system(size: 10))
                    .foregroundStyle(PopoverTheme.textSubtle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(PopoverTheme.bottomBarBg)
        .overlay(
            VStack {
                Rectangle().fill(PopoverTheme.cardBorder).frame(height: 1)
                Spacer()
            }
        )
    }

    // MARK: - Helper Views & Animation
    private func keycapsView(for text: String) -> some View {
        let parts = text.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        return HStack(spacing: 2) {
            ForEach(parts, id: \.self) { part in
                keycapLabel(keycapSymbol(for: part))
            }
        }
    }

    private func keycapLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(PopoverTheme.textPrimary.opacity(0.90))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PopoverTheme.chipBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(PopoverTheme.borderLight, lineWidth: 1)
            )
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
