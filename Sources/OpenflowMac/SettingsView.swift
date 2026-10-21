import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

extension Notification.Name {
    static let quickASRSettingsDidChange = Notification.Name("quickASRSettingsDidChange")
}

// MARK: - Color Extension for Hex
private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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

// MARK: - Theme Palette
enum MacTheme {
    static var isDark: Bool { AppThemeManager.shared.isDark }
    static var bg: Color { isDark ? Color(hex: "111216") : Color(hex: "f8fafc") }
    static var sidebar: Color { isDark ? Color(hex: "16181f") : Color(hex: "f1f5f9") }
    static var surface: Color { isDark ? Color(hex: "1b1d26") : Color.white }
    static var surfaceHover: Color { isDark ? Color(hex: "232632") : Color(hex: "f1f5f9") }
    static var card: Color { isDark ? Color(hex: "1e212b") : Color.white }
    static var cardSecondary: Color { isDark ? Color.white.opacity(0.03) : Color(hex: "f1f5f9").opacity(0.70) }
    static var border: Color { isDark ? Color.white.opacity(0.08) : Color(hex: "e2e8f0") }
    static var borderFocus: Color { isDark ? Color(hex: "60a5fa").opacity(0.45) : Color(hex: "2563eb").opacity(0.45) }
    static var accent: Color { isDark ? Color(hex: "3b82f6") : Color(hex: "2563eb") }
    static var accentHover: Color { isDark ? Color(hex: "2563eb") : Color(hex: "1d4ed8") }
    static var textPrimary: Color { isDark ? Color.white : Color(hex: "0f172a") }
    static var textHeader: Color { isDark ? Color.white.opacity(0.60) : Color(hex: "334155") }
    static var textMuted: Color { isDark ? Color(hex: "94a3b8") : Color(hex: "475569") }
    static var textSecondary: Color { isDark ? Color(hex: "64748b") : Color(hex: "64748b") }
    static var inputBg: Color { isDark ? Color.black.opacity(0.35) : Color(hex: "f1f5f9") }
    static var divider: Color { isDark ? Color.white.opacity(0.06) : Color(hex: "e2e8f0") }
    static var pillBg: Color { isDark ? Color.black.opacity(0.25) : Color(hex: "e2e8f0").opacity(0.70) }
    static var chipBg: Color { isDark ? Color.black.opacity(0.25) : Color(hex: "f1f5f9") }
    static var headerBg: Color { isDark ? Color.black.opacity(0.25) : Color(hex: "ffffff").opacity(0.90) }
    static var tabBarBg: Color { isDark ? Color.black.opacity(0.45) : Color(hex: "e2e8f0").opacity(0.75) }
    static var tabSelectedFill: Color { isDark ? Color.white.opacity(0.14) : Color.white }
    static var tabSelectedText: Color { isDark ? Color.white : Color(hex: "0f172a") }
    static var tabInactiveText: Color { isDark ? Color(hex: "94a3b8") : Color(hex: "64748b") }
    static var footerBg: Color { isDark ? Color(hex: "16181f").opacity(0.70) : Color(hex: "f8fafc").opacity(0.95) }
    static var cancelBtnBg: Color { isDark ? Color.white.opacity(0.08) : Color(hex: "e2e8f0") }
    static var cancelBtnText: Color { isDark ? Color(hex: "cbd5e1") : Color(hex: "334155") }
    static var cardShadow: Color { isDark ? Color.clear : Color.black.opacity(0.04) }
}

// MARK: - Settings Tab Enum
enum SettingsTab: String, CaseIterable, Identifiable {
    case dictation = "Dictation"
    case engines = "Speech Engine"
    case reader = "Reader"
    case stats = "Speech Stats"
    case history = "History"
    case permissions = "Permissions"
    case general = "General"
    case about = "About"

    var id: String { rawValue }
}

// MARK: - Settings View
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .dictation
    @State private var showingResetStatsAlert = false
    @ObservedObject private var themeManager = AppThemeManager.shared
    @ObservedObject private var downloadManager = ModelDownloadProgressManager.shared
    @ObservedObject private var readerManager = ReaderManager.shared
    @ObservedObject private var kokoroEngine = KokoroTTSEngine.shared
    @ObservedObject private var modelStorageManager = ModelStorageManager.shared

    // Engine & Backend Settings
    @State private var backendBaseURL = UserDefaults.standard.string(forKey: UserSettingKey.backendBaseURL) ?? "http://127.0.0.1:8001"
    @State private var timeoutSeconds = UserDefaults.standard.string(forKey: UserSettingKey.timeoutSeconds) ?? "45"
    @State private var retryCount = UserDefaults.standard.string(forKey: UserSettingKey.retryCount) ?? "2"
    @State private var retryDelayMs = UserDefaults.standard.string(forKey: UserSettingKey.retryBaseDelayMs) ?? "250"
    @State private var apiToken = UserDefaults.standard.string(forKey: UserSettingKey.apiToken) ?? ""
    @State private var maxUploadBytes = UserDefaults.standard.string(forKey: UserSettingKey.maxUploadBytes) ?? "26214400"
    @State private var outputMode = TranscriptOutputMode.parse(UserDefaults.standard.string(forKey: UserSettingKey.outputMode)) ?? .activeApp
    @State private var engineType = ASREngineType.parse(UserDefaults.standard.string(forKey: UserSettingKey.engineType)) ?? .localCoreML
    @State private var localWhisperModel = UserDefaults.standard.string(forKey: UserSettingKey.localWhisperModel).flatMap({ WhisperModelChoice(rawValue: $0) }) ?? .tiny
    @State private var modelName = ModelName(rawValue: UserDefaults.standard.string(forKey: UserSettingKey.modelName) ?? "") ?? .fast06B
    @State private var selectedModelFamily: ModelFamily = .all

    // Hotkey Settings
    @State private var hotkey = UserDefaults.standard.string(forKey: UserSettingKey.hotkey) ?? "cmd+shift+space"
    @State private var hotkeyDisplay = HotKeyConfiguration.parse(UserDefaults.standard.string(forKey: UserSettingKey.hotkey) ?? "cmd+shift+space").displayText
    @State private var isRecordingHotkey = false
    @State private var hotkeyCaptureMonitor: Any?

    // Typed Text Formatting
    @State private var addTrailingSpace = UserDefaults.standard.object(forKey: UserSettingKey.addTrailingSpace) != nil
        ? UserDefaults.standard.bool(forKey: UserSettingKey.addTrailingSpace)
        : true
    @State private var capitalizeSentences = UserDefaults.standard.object(forKey: UserSettingKey.capitalizeSentences) != nil
        ? UserDefaults.standard.bool(forKey: UserSettingKey.capitalizeSentences)
        : true
    @State private var writeNumbersAsDigits = UserDefaults.standard.bool(forKey: UserSettingKey.writeNumbersAsDigits)
    @State private var useSymbolsAndOrdinals = UserDefaults.standard.bool(forKey: UserSettingKey.useSymbolsAndOrdinals)
    @State private var spokenEmoji = UserDefaults.standard.bool(forKey: UserSettingKey.spokenEmoji)
    @State private var paragraphBreaks = UserDefaults.standard.object(forKey: UserSettingKey.paragraphBreaks) != nil
        ? UserDefaults.standard.bool(forKey: UserSettingKey.paragraphBreaks)
        : true
    @State private var spokenPunctuation = UserDefaults.standard.object(forKey: UserSettingKey.spokenPunctuation) != nil
        ? UserDefaults.standard.bool(forKey: UserSettingKey.spokenPunctuation)
        : true

    // Voice & Silence Detection
    @State private var maxRecordingDuration = MaxRecordingDurationChoice.parse(UserDefaults.standard.string(forKey: UserSettingKey.maxRecordingDuration)) ?? .twoMinutes
    @State private var skipSilenceBeforeTranscribing = UserDefaults.standard.object(forKey: UserSettingKey.skipSilenceBeforeTranscribing) != nil
        ? UserDefaults.standard.bool(forKey: UserSettingKey.skipSilenceBeforeTranscribing)
        : true
    @State private var silenceSensitivity = SilenceSensitivity.parse(UserDefaults.standard.string(forKey: UserSettingKey.silenceSensitivity)) ?? .medium
    @State private var stopAfterSilence = StopAfterSilenceChoice.parse(UserDefaults.standard.string(forKey: UserSettingKey.stopAfterSilence)) ?? .twoSeconds
    @State private var overlayPlacement = OverlayPlacement.parse(UserDefaults.standard.string(forKey: UserSettingKey.overlayPlacement)) ?? .top
    @State private var playFeedbackSounds = UserDefaults.standard.object(forKey: UserSettingKey.playFeedbackSounds) != nil
        ? UserDefaults.standard.bool(forKey: UserSettingKey.playFeedbackSounds)
        : true

    // Playground Interactive State
    @State private var playgroundInput: String = "let's meet at six pm party emoji first question"
    private let spectrumHeights: [CGFloat] = [6, 14, 20, 10, 16, 22, 8]
    @State private var cachedCapacityReport: ProcessCapacityReport?

    // History Search
    @State private var historySearchQuery: String = ""

    // UI Status
    @State private var statusMessage = ""
    @State private var showModelRestartNotice = false

    @ObservedObject private var historyStore = TranscriptHistoryStore.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared

    var body: some View {
        ZStack {
            // Main Obsidian Window Background
            MacTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Unified Header Toolbar (Integrates window controls, branding, and tab pills)
                unifiedHeaderToolbar

                // Scrollable Content
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .dictation:
                            dictationTabView
                        case .engines:
                            enginesTabView
                        case .reader:
                            readerTabView
                        case .stats:
                            statsTabView
                        case .history:
                            historyTabView
                        case .permissions:
                            permissionsTabView
                        case .general:
                            generalTabView
                        case .about:
                            aboutTabView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Window Footer Actions
                windowFooterActions
            }
        }
        .frame(minWidth: 700, idealWidth: 740, minHeight: 490, idealHeight: 560)
        .preferredColorScheme(themeManager.colorScheme)
        .onDisappear {
            stopHotkeyCapture()
        }
    }

    // MARK: - Unified Header Toolbar
    private var unifiedHeaderToolbar: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left spacer for native macOS window traffic lights
            Color.clear
                .frame(width: 78, height: 1)

            // App Brand Pill
            HStack(spacing: 7) {
                OpenflowLogoView(size: 22, cornerRadius: 6)

                Text("Openflow")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text("v0.1.0")
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color(hex: "0284c7").opacity(0.15))
                    .foregroundStyle(Color(hex: "0284c7"))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 14)

            // Center macOS Tab Navigation Segmented Bar
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11.5, weight: selectedTab == tab ? .semibold : .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(selectedTab == tab ? MacTheme.tabSelectedText : MacTheme.tabInactiveText)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selectedTab == tab ? MacTheme.tabSelectedFill : Color.clear)
                                    .shadow(color: selectedTab == tab ? MacTheme.cardShadow : Color.clear, radius: 2, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(MacTheme.tabBarBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            Spacer(minLength: 14)

            // Right Status Indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: "34d399"))
                    .frame(width: 6, height: 6)
                Text(engineType == .localCoreML ? "ANE Active" : (engineType == .appleSpeech ? "macOS Native" : "Remote"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: "34d399"))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(hex: "10b981").opacity(0.12))
            .clipShape(Capsule())
            .padding(.trailing, 14)
        }
        .frame(height: 48)
        .background(MacTheme.headerBg)
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(MacTheme.divider).frame(height: 1)
            }
        )
    }

    // MARK: - Tab 1: Dictation & Typed Text
    private var dictationTabView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Quick Productivity / Speech Stats Glance Banner
            let stats = historyStore.statsSummary
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTab = .stats
                }
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Color(hex: "f59e0b"))
                        Text("\(stats.totalWords) words dictated")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                    }

                    Text("•")
                        .foregroundStyle(MacTheme.textMuted)

                    HStack(spacing: 5) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(MacTheme.isDark ? Color(hex: "10b981") : Color(hex: "059669"))
                        Text("\(stats.formattedTimeSaved) saved")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(MacTheme.isDark ? Color(hex: "34d399") : Color(hex: "047857"))
                    }

                    Spacer()

                    HStack(spacing: 3) {
                        Text("View Speech Stats")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.isDark ? Color(hex: "60a5fa") : Color(hex: "2563eb"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(MacTheme.isDark ? Color(hex: "60a5fa") : Color(hex: "2563eb"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(MacTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(MacTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Heading & Subtitle
            HStack {
                Text("TYPED TEXT & FORMATTING")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MacTheme.textHeader)
                    .tracking(0.6)

                Spacer()

                Text("Intelligent on-device post-processing")
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacTheme.textMuted)
            }

            // Setting Switches Container (Card with rounded corners & dividers)
            VStack(spacing: 0) {
                toggleRow(
                    title: "Add a trailing space",
                    subtitle: "Keeps continuous dictations from running directly into existing words.",
                    isOn: $addTrailingSpace
                )

                Divider().background(MacTheme.divider)

                toggleRow(
                    title: "Capitalize sentences",
                    subtitle: "Starts each recognized sentence with a capital letter automatically.",
                    isOn: $capitalizeSentences
                )

                Divider().background(MacTheme.divider)

                toggleRow(
                    title: "Write numbers as digits",
                    subtitle: "“six pm” becomes “6 pm”, “forty two” becomes “42”. (English only)",
                    isOn: $writeNumbersAsDigits
                )

                Divider().background(MacTheme.divider)

                toggleRow(
                    title: "Use symbols and ordinals",
                    subtitle: "Converts “first” to “1st”, “percent” to “%”. Requires “Write numbers as digits”.",
                    isOn: $useSymbolsAndOrdinals,
                    isEnabled: writeNumbersAsDigits
                )

                Divider().background(MacTheme.divider)

                toggleRow(
                    title: "Spoken emoji",
                    subtitle: "Say “party emoji” to output 🎉 or “fire emoji” to insert 🔥 directly into your document.",
                    isOn: $spokenEmoji,
                    badge: "🎉 Active"
                )

                Divider().background(MacTheme.divider)

                toggleRow(
                    title: "Paragraph breaks",
                    subtitle: "Natural breath pauses between longer passages produce clean paragraph breaks. Email greetings get dedicated lines.",
                    isOn: $paragraphBreaks
                )

                Divider().background(MacTheme.divider)

                toggleRow(
                    title: "Spoken punctuation",
                    subtitle: "Converts spoken “comma”, “period”, “question mark”, “exclamation point”, “colon”, etc. into punctuation symbols.",
                    isOn: $spokenPunctuation,
                    badge: "✍️ Active"
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacTheme.surface.opacity(0.90))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Voice & Silence Detection Panel
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("VOICE & SILENCE DETECTION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MacTheme.textHeader)
                        .tracking(0.6)

                    Spacer()

                    Text("VAD & Hands-Free Auto-Stop")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacTheme.textMuted)
                }

                // Row 1: Stop After Silence
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Stop after silence")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(MacTheme.textPrimary)

                            Text(stopAfterSilence == .off ? "Manual" : "Auto-Stop")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(stopAfterSilence == .off ? MacTheme.pillBg : (MacTheme.isDark ? Color(hex: "10b981").opacity(0.18) : Color(hex: "10b981").opacity(0.15)))
                                .foregroundStyle(stopAfterSilence == .off ? MacTheme.textMuted : (MacTheme.isDark ? Color(hex: "34d399") : Color(hex: "047857")))
                                .cornerRadius(4)
                        }

                        Text("Automatically finishes recording and transcribes when you pause speaking.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacTheme.textMuted)
                    }

                    Spacer()

                    dropdownMenu(
                        title: stopAfterSilence.rawValue,
                        options: StopAfterSilenceChoice.allCases.map { ($0, $0.rawValue) },
                        onSelect: { stopAfterSilence = $0 },
                        width: 125
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider().background(MacTheme.divider)

                // Row 2: Silence Sensitivity
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Silence sensitivity")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)

                        Text("Cutoff threshold for separating voice from ambient room noise.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacTheme.textMuted)
                    }

                    Spacer()

                    dropdownMenu(
                        title: silenceSensitivity.rawValue,
                        options: SilenceSensitivity.allCases.map { ($0, $0.rawValue) },
                        onSelect: { silenceSensitivity = $0 },
                        width: 135
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider().background(MacTheme.divider)

                // Row 3: Longest Recording
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Longest recording")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)

                        Text("Safety timeout that auto-stops recording to prevent runaway background recordings.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacTheme.textMuted)
                    }

                    Spacer()

                    dropdownMenu(
                        title: maxRecordingDuration.displayLabel,
                        options: MaxRecordingDurationChoice.allCases.map { ($0, $0.displayLabel) },
                        onSelect: { maxRecordingDuration = $0 },
                        width: 130
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider().background(MacTheme.divider)

                // Row 4: Skip Silence Before Transcribing
                toggleRow(
                    title: "Skip silence before transcribing",
                    subtitle: "Trims silent pauses before sending audio to ASR to speed up recognition and avoid hallucinations.",
                    isOn: $skipSilenceBeforeTranscribing,
                    badge: "⚡️ Optimized"
                )

                Divider().background(MacTheme.divider)

                // Row 5: Audio cues on start & stop
                toggleRow(
                    title: "Audio cues on start & stop",
                    subtitle: "Plays native Apple chime feedback when dictation starts, finishes, or cancels.",
                    isOn: $playFeedbackSounds,
                    badge: "🔔 Audio Cue"
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Recording Overlay Placement Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RECORDING OVERLAY PLACEMENT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MacTheme.textHeader)
                        .tracking(0.6)

                    Spacer()

                    Text("Screen position while speaking")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacTheme.textMuted)
                }

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Overlay placement")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)

                        Text("Choose whether the floating dictation bar appears at the top (below notch) or bottom (above dock) while speaking.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacTheme.textMuted)
                    }

                    Spacer()

                    HStack(spacing: 3) {
                        ForEach(OverlayPlacement.allCases) { choice in
                            Button {
                                overlayPlacement = choice
                                UserDefaults.standard.set(choice.rawValue, forKey: UserSettingKey.overlayPlacement)
                                NotificationCenter.default.post(name: .openflowOverlayPlacementDidChange, object: choice)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: choice.icon)
                                        .font(.system(size: 10.5, weight: .bold))
                                    Text(choice.rawValue)
                                        .font(.system(size: 11, weight: overlayPlacement == choice ? .semibold : .medium))
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5.5)
                                .background(
                                    overlayPlacement == choice
                                        ? (MacTheme.isDark ? Color.white.opacity(0.18) : Color.white)
                                        : Color.clear
                                )
                                .foregroundStyle(
                                    overlayPlacement == choice
                                        ? (MacTheme.isDark ? Color.white : MacTheme.accent)
                                        : MacTheme.textMuted
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .shadow(
                                    color: (overlayPlacement == choice && !MacTheme.isDark) ? Color.black.opacity(0.08) : Color.clear,
                                    radius: 2,
                                    y: 1
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2.5)
                    .background(MacTheme.tabBarBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MacTheme.border, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Live Dictation Playground Card (Compact)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(MacTheme.isDark ? Color(hex: "34d399") : Color(hex: "059669")).frame(width: 7, height: 7)
                        Text("LIVE PLAYGROUND")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MacTheme.textHeader)
                            .tracking(0.6)
                    }

                    Spacer()

                    HStack(spacing: 2) {
                        ForEach(0..<spectrumHeights.count, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(MacTheme.isDark ? Color(hex: "60a5fa") : Color(hex: "2563eb"))
                                .frame(width: 2, height: spectrumHeights[index])
                        }
                    }
                    .frame(height: 16)
                    .padding(.horizontal, 6)
                    .background(MacTheme.inputBg)
                    .cornerRadius(4)
                }

                HStack(spacing: 8) {
                    TextField("Test spoken text...", text: $playgroundInput)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(MacTheme.textPrimary)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MacTheme.inputBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MacTheme.border, lineWidth: 1)
                        )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MacTheme.textMuted)

                    HStack(spacing: 4) {
                        Text(formatPlayground(playgroundInput))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.isDark ? Color(hex: "dbeafe") : Color(hex: "1d4ed8"))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: "3b82f6").opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(hex: "3b82f6").opacity(0.30), lineWidth: 1)
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Voice Commands & Self-Correction (In-line, No Extra Hotkey)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("VOICE COMMANDS & ACTIONS (IN-LINE)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MacTheme.textHeader)
                        .tracking(0.6)

                    Spacer()

                    Text("No separate hotkey required")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacTheme.isDark ? Color(hex: "34d399") : Color(hex: "059669"))
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 6) {
                    voiceCommandChip(say: "“scratch that”", does: "Erases recent dictation")
                    voiceCommandChip(say: "“select all”", does: "Selects all text (⌘A)")
                    voiceCommandChip(say: "“undo that”", does: "Reverts last change (⌘Z)")
                    voiceCommandChip(say: "“new line / paragraph”", does: "Inserts line break")
                    voiceCommandChip(say: "“... actually / no, ...”", does: "Self-corrects words")
                    voiceCommandChip(say: "“make shorter / bullet points”", does: "Edits selected text")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Apple Intelligence & Writing Tools Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MacTheme.isDark ? Color(hex: "a78bfa") : Color(hex: "7c3aed"))

                    Text("APPLE INTELLIGENCE & WRITING TOOLS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MacTheme.textHeader)
                        .tracking(0.6)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle().fill(MacTheme.isDark ? Color(hex: "a78bfa") : Color(hex: "7c3aed")).frame(width: 6, height: 6)
                        Text(AppleIntelligenceEngine.shared.isAppleIntelligenceSupported ? "Apple Silicon • macOS 15.1+" : "On-Device Engine Active")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(MacTheme.isDark ? Color(hex: "c4b5fd") : Color(hex: "6d28d9"))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "8b5cf6").opacity(MacTheme.isDark ? 0.15 : 0.12))
                    .cornerRadius(4)
                }

                Text("Speak intelligent transformation commands to instantly proofread, rewrite, summarize, or trigger macOS Writing Tools on selected text:")
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacTheme.textMuted)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 6) {
                    voiceCommandChip(say: "“proofread this”", does: "Fixes grammar & spelling")
                    voiceCommandChip(say: "“rewrite friendly”", does: "Warm, natural tone")
                    voiceCommandChip(say: "“rewrite professionally”", does: "Formal executive tone")
                    voiceCommandChip(say: "“rewrite concise”", does: "Removes filler & fluff")
                    voiceCommandChip(say: "“summarize key points”", does: "Extracts bullet points")
                    voiceCommandChip(say: "“make a table”", does: "Formats as Markdown table")
                    voiceCommandChip(say: "“show writing tools”", does: "Launches macOS palette")
                    voiceCommandChip(say: "“apple intelligence [cue]”", does: "Generates custom prompt")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "8b5cf6").opacity(MacTheme.isDark ? 0.04 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: "8b5cf6").opacity(MacTheme.isDark ? 0.20 : 0.30), lineWidth: 1)
            )
        }
    }

    private func voiceCommandChip(say: String, does: String) -> some View {
        HStack(spacing: 6) {
            Text(say)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(MacTheme.isDark ? Color(hex: "60a5fa") : Color(hex: "1d4ed8"))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(does)
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MacTheme.chipBg)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(MacTheme.border, lineWidth: 1)
        )
        .cornerRadius(6)
    }

    private func dropdownMenu<T: Hashable>(
        title: String,
        options: [(T, String)],
        onSelect: @escaping (T) -> Void,
        width: CGFloat
    ) -> some View {
        Menu {
            ForEach(options, id: \.1) { option in
                Button(option.1) {
                    onSelect(option.0)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MacTheme.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(width: width)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true,
        badge: String? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(isEnabled ? MacTheme.textPrimary : MacTheme.textMuted)

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(hex: "f59e0b").opacity(MacTheme.isDark ? 0.12 : 0.16))
                            .foregroundStyle(MacTheme.isDark ? Color(hex: "fcd34d") : Color(hex: "b45309"))
                            .clipShape(Capsule())
                    }
                }

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isEnabled ? MacTheme.textMuted : MacTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(MacTheme.accent)
                .labelsHidden()
                .disabled(!isEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Tab 2: Speech Engines
    private var enginesTabView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section Title & Intro
            VStack(alignment: .leading, spacing: 4) {
                Text("Speech Engine & Inference")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text("Choose between hardware-accelerated on-device models or custom high-speed endpoints.")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textMuted)
            }

            // Compressed 3-Engine Horizontal Card Deck
            HStack(spacing: 12) {
                compressedEngineCard(
                    type: .localCoreML,
                    title: "WhisperKit CoreML",
                    badge: "Recommended",
                    badgeColor: Color(hex: "10b981"),
                    gradient: [Color(hex: "6366f1"), Color(hex: "2563eb")],
                    icon: "bolt.fill",
                    subtitle: "Apple Neural Engine (ANE)",
                    tag: "100% Offline"
                )

                compressedEngineCard(
                    type: .appleSpeech,
                    title: "Apple Speech",
                    badge: "macOS Native",
                    badgeColor: Color(hex: "0284c7"),
                    gradient: [Color(hex: "3b82f6"), Color(hex: "0284c7")],
                    icon: "applelogo",
                    subtitle: "Zero download required",
                    tag: "Instant Launch"
                )

                compressedEngineCard(
                    type: .remoteServer,
                    title: "Remote Server",
                    badge: "Advanced",
                    badgeColor: Color(hex: "d97706"),
                    gradient: [Color(hex: "9333ea"), Color(hex: "1e293b")],
                    icon: "network",
                    subtitle: "HTTP backend / Ollama",
                    tag: "Custom API"
                )
            }

            // Engine Diagnostics & Privacy Pill Strip
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Engine Active:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.textHeader)
                    Text(engineType.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                }

                Divider().frame(height: 12).background(MacTheme.divider)

                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.cyan)
                    Text(engineHardwareSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textHeader)
                }

                Divider().frame(height: 12).background(MacTheme.divider)

                HStack(spacing: 5) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "34d399"))
                    Text(enginePrivacySummary)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textHeader)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MacTheme.cardSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Live Application Capacity & Resource Consumption (RAM, CPU, Footprint)
            let footprintMB = engineType == .localCoreML ? localWhisperModel.sizeMB : (engineType == .remoteServer ? modelName.sizeMB : 0)
            let report = cachedCapacityReport ?? ProcessCapacityMonitor.currentReport(modelFootprintMB: footprintMB)
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color(hex: "0284c7"))
                    Text("App RAM: \(report.formattedRAM)")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(MacTheme.textPrimary)
                }

                Text("•")
                    .foregroundStyle(MacTheme.divider)

                HStack(spacing: 5) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color(hex: "10b981"))
                    Text("Model Footprint: +\(engineType == .localCoreML ? localWhisperModel.sizeMB : (engineType == .remoteServer ? modelName.sizeMB : 0)) MB")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "10b981"))
                }

                Text("•")
                    .foregroundStyle(MacTheme.divider)

                HStack(spacing: 5) {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color(hex: "d97706"))
                    Text("CPU: \(report.formattedCPU)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "d97706"))
                }

                Spacer()

                Button {
                    withAnimation {
                        modelStorageManager.offloadSpeechEngine()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Offload RAM")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: "0284c7").opacity(0.15))
                    .foregroundStyle(Color(hex: "0284c7"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Unload active speech models from RAM to free system memory")

                Text("Total: \(report.formattedTotalCapacity)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(MacTheme.chipBg)
                    .foregroundStyle(MacTheme.textPrimary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: "38bdf8").opacity(MacTheme.isDark ? 0.20 : 0.40), lineWidth: 1)
            )

            // CoreML Model Picker (Parakeet, Qwen, Whisper)
            if engineType == .localCoreML {
                VStack(alignment: .leading, spacing: 12) {
                    ModelDownloadBannerView(downloadManager: downloadManager)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("On-Device Speech Models (Mac Accelerated)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MacTheme.textPrimary)

                            Text("Each model indicates exact size in MB and supported languages.")
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.textMuted)
                        }

                        Spacer()

                        // Family Filter Tabs
                        HStack(spacing: 3) {
                            ForEach(ModelFamily.allCases) { family in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedModelFamily = family
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: family.icon)
                                            .font(.system(size: 9))
                                        Text(family.rawValue)
                                            .font(.system(size: 10, weight: selectedModelFamily == family ? .semibold : .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedModelFamily == family ? (MacTheme.isDark ? Color.white.opacity(0.18) : Color.white) : Color.clear)
                                    .foregroundStyle(selectedModelFamily == family ? (MacTheme.isDark ? Color.white : MacTheme.accent) : MacTheme.textMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .shadow(color: (selectedModelFamily == family && !MacTheme.isDark) ? Color.black.opacity(0.06) : Color.clear, radius: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2.5)
                        .background(MacTheme.tabBarBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MacTheme.border, lineWidth: 1)
                        )
                    }

                    let filteredModels = WhisperModelChoice.allCases.filter { model in
                        selectedModelFamily == .all || model.family == selectedModelFamily
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], spacing: 8) {
                        ForEach(filteredModels, id: \.self) { model in
                            compressedModelCard(model: model)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MacTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MacTheme.border, lineWidth: 1)
                )
            }

            // Remote Server Details & Backend Models
            if engineType == .remoteServer {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server Connection Parameters")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)

                    VStack(spacing: 8) {
                        serverSettingRow("Backend URL") {
                            TextField("http://127.0.0.1:8001", text: $backendBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            serverSettingRow("API Token") {
                                TextField("Optional", text: $apiToken)
                                    .textFieldStyle(.roundedBorder)
                            }
                            serverSettingRow("Timeout (sec)") {
                                TextField("45", text: $timeoutSeconds)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(spacing: 12) {
                            serverSettingRow("Retry Count") {
                                TextField("2", text: $retryCount)
                                    .textFieldStyle(.roundedBorder)
                            }
                            serverSettingRow("Retry Delay (ms)") {
                                TextField("250", text: $retryDelayMs)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    Divider().background(MacTheme.divider)

                    // Backend Models
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backend Models (Qwen & Parakeet)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(ModelName.allCases) { model in
                                backendModelCard(model: model)
                            }
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MacTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MacTheme.border, lineWidth: 1)
                )
            }
        }
    }

    private var engineHardwareSummary: String {
        switch engineType {
        case .localCoreML:
            return "Neural Engine (ANE) Active"
        case .appleSpeech:
            return "System Audio Processing"
        case .remoteServer:
            return "HTTP Network Socket"
        }
    }

    private var enginePrivacySummary: String {
        switch engineType {
        case .localCoreML:
            return "100% Offline • Zero Data Leaves Mac"
        case .appleSpeech:
            return "macOS Local Speech Framework"
        case .remoteServer:
            return "Transmits to \(backendBaseURL)"
        }
    }

    private func compressedEngineCard(
        type: ASREngineType,
        title: String,
        badge: String,
        badgeColor: Color,
        gradient: [Color],
        icon: String,
        subtitle: String,
        tag: String
    ) -> some View {
        let isSelected = engineType == type

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                engineType = type
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 26, height: 26)

                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                    }

                    Spacer()

                    Text(badge)
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(badgeColor.opacity(0.30), lineWidth: 1)
                        )

                    ZStack {
                        Circle()
                            .stroke(isSelected ? MacTheme.accent : (MacTheme.isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.20)), lineWidth: isSelected ? 2 : 1)
                            .frame(width: 16, height: 16)

                        if isSelected {
                            Circle()
                                .fill(MacTheme.accent)
                                .frame(width: 16, height: 16)

                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? (MacTheme.isDark ? Color.white.opacity(0.85) : MacTheme.accent) : MacTheme.textMuted)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(tag)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? (MacTheme.isDark ? Color(hex: "93c5fd") : MacTheme.accent) : MacTheme.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? MacTheme.accent.opacity(MacTheme.isDark ? 0.10 : 0.08) : MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? MacTheme.accent : MacTheme.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: isSelected ? MacTheme.accent.opacity(0.20) : Color.clear, radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func compressedModelCard(model: WhisperModelChoice) -> some View {
        let isSelected = localWhisperModel == model
        let isDownloaded = modelStorageManager.isWhisperModelDownloaded(model)

        return Button {
            localWhisperModel = model
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.shortTitle)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(MacTheme.textPrimary)

                            Text(model.family.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    model.family == .parakeet
                                        ? Color(hex: "10b981").opacity(0.18)
                                        : (model.family == .qwen ? Color(hex: "f59e0b").opacity(0.18) : Color(hex: "3b82f6").opacity(0.18))
                                )
                                .foregroundStyle(
                                    model.family == .parakeet
                                        ? Color(hex: "10b981")
                                        : (model.family == .qwen ? Color(hex: "d97706") : Color(hex: "2563eb"))
                                )
                                .clipShape(Capsule())
                        }

                        Text(model.macSuitability)
                            .font(.system(size: 9.5))
                            .foregroundStyle(isSelected ? (MacTheme.isDark ? Color.white.opacity(0.85) : MacTheme.accent) : MacTheme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if isDownloaded {
                        Button {
                            modelStorageManager.deleteWhisperModel(model)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.red.opacity(0.85))
                                .frame(width: 18, height: 18)
                                .background(Color.red.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Delete \(model.shortTitle) from disk to free storage")
                    }

                    ZStack {
                        Circle()
                            .stroke(isSelected ? MacTheme.accent : (MacTheme.isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.20)), lineWidth: isSelected ? 2 : 1)
                            .frame(width: 14, height: 14)

                        if isSelected {
                            Circle()
                                .fill(MacTheme.accent)
                                .frame(width: 14, height: 14)

                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                }

                // Two High-Visibility Badges: Exact Size in MB & Languages Supported
                HStack(spacing: 6) {
                    HStack(spacing: 3.5) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(model.formattedSize)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(MacTheme.chipBg)
                    .foregroundStyle(Color(hex: "0284c7"))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    HStack(spacing: 3.5) {
                        Image(systemName: "globe")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(model.languageSummary)
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(MacTheme.chipBg)
                    .foregroundStyle(Color(hex: "10b981"))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    if isDownloaded {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("Cached")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color(hex: "10b981").opacity(0.15))
                        .foregroundStyle(Color(hex: "10b981"))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                ModelDownloadCardProgressView(
                    downloadManager: downloadManager,
                    modelName: model.rawValue,
                    isSelected: isSelected
                )
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? MacTheme.accent.opacity(MacTheme.isDark ? 0.12 : 0.08) : MacTheme.cardSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? MacTheme.accent.opacity(0.80) : MacTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func backendModelCard(model: ModelName) -> some View {
        let isSelected = modelName == model

        return Button {
            modelName = model
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.displayName)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(MacTheme.accent)
                    }
                }

                HStack(spacing: 5) {
                    Text(model.formattedSize)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MacTheme.chipBg)
                        .foregroundStyle(Color(hex: "0284c7"))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(model.languageSummary)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MacTheme.chipBg)
                        .foregroundStyle(Color(hex: "10b981"))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Text(model.description)
                    .font(.system(size: 9.5))
                    .foregroundStyle(MacTheme.textMuted)
                    .lineLimit(2)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? MacTheme.accent.opacity(MacTheme.isDark ? 0.12 : 0.08) : MacTheme.cardSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? MacTheme.accent : MacTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func serverSettingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.textHeader)
                .frame(width: 140, alignment: .leading)
            content()
            Spacer()
        }
    }

    // MARK: - Tab 3: General & Shortcuts
    private var generalTabView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Heading & Subtitle
            HStack {
                Text("GENERAL & SHORTCUTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MacTheme.textHeader)
                    .tracking(0.6)

                Spacer()

                Text("Theme, invocation keys & output destinations")
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacTheme.textMuted)
            }

            // Theme Selection Card
            themeSelectorCard

            // Dictation Shortcut Panel
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Dictation Shortcut")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)

                    Spacer()

                    Text("Global system listener")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacTheme.textMuted)
                }

                HStack(spacing: 12) {
                    // Keycap visual pill
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 13))
                            .foregroundStyle(MacTheme.textMuted)

                        if isRecordingHotkey {
                            Text("Press shortcut on keyboard...")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.orange)
                        } else {
                            keycapsView(for: hotkeyDisplay)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(MacTheme.inputBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isRecordingHotkey ? Color.orange : MacTheme.border, lineWidth: 1)
                    )

                    Button {
                        toggleHotkeyCapture()
                    } label: {
                        Text(isRecordingHotkey ? "Cancel" : "Record Shortcut")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(MacTheme.pillBg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(MacTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Text("Presets:")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MacTheme.textMuted)

                    presetPill(label: "F5 (Single Key)", storage: "f5", display: "F5")
                    presetPill(label: "Right Option", storage: "right_option", display: "Right Option")
                    presetPill(label: "Fn / Globe", storage: "fn", display: "Fn")
                    presetPill(label: "⌘⇧Space", storage: "cmd+shift+space", display: "Cmd+Shift+Space")
                }

                Text("Supports Long Press / Push-to-Talk: hold key to speak and release to transcribe instantly. Or quick-tap to toggle recording hands-free.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacTheme.textMuted)
                    .lineSpacing(2)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Output Delivery Panel
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output Delivery")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)

                    Text("Specify where transcribed text is dispatched immediately upon completion.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacTheme.textMuted)
                }

                // 2x2 Grid for Delivery Modes
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    deliveryCard(
                        mode: .clipboard,
                        title: "Clipboard",
                        subtitle: "Copies text without pasting"
                    )

                    deliveryCard(
                        mode: .activeApp,
                        title: "Active App",
                        subtitle: "Directly types into focused field",
                        hasActiveDot: true
                    )

                    deliveryCard(
                        mode: .both,
                        title: "Clipboard + Active App",
                        subtitle: "Pastes and keeps in history"
                    )

                    deliveryCard(
                        mode: .none,
                        title: "None",
                        subtitle: "Broadcasts via AppleScript / URL"
                    )
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Audio Input Hardware Device
            audioInputDeviceSelectorCard

            // Quick Permissions Glance Banner
            quickPermissionsGlanceBanner
        }
    }

    // MARK: - Tab: System Permissions & Audio Hardware
    private var permissionsTabView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Heading & Subtitle
            HStack {
                Text("SYSTEM PERMISSIONS & AUDIO HARDWARE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MacTheme.textHeader)
                    .tracking(0.6)

                Spacer()

                Button {
                    permissionsManager.refreshStatuses()
                    audioDeviceManager.refreshDevices()
                    statusMessage = "Permissions and audio hardware re-checked."
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Refresh Status")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MacTheme.cardSecondary)
                    .foregroundStyle(MacTheme.textPrimary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(MacTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Overall Readiness Banner
            if permissionsManager.allRequiredPermissionsGranted {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "10b981").opacity(0.20))
                            .frame(width: 34, height: 34)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: "10b981"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Ready for Dictation")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(MacTheme.isDark ? Color.white : Color(hex: "065f46"))

                        Text("Microphone and Accessibility permissions are fully authorized. Openflow can listen and type into active windows seamlessly.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.isDark ? Color.white.opacity(0.70) : Color(hex: "047857"))
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MacTheme.isDark ? Color(hex: "064e3b").opacity(0.35) : Color(hex: "ecfdf5"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "10b981").opacity(MacTheme.isDark ? 0.40 : 0.60), lineWidth: 1)
                )
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "f59e0b").opacity(0.20))
                            .frame(width: 34, height: 34)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color(hex: "f59e0b"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Action Required to Enable Dictation")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(MacTheme.isDark ? Color.white : Color(hex: "92400e"))

                        Text("macOS requires explicit authorization before Openflow can record audio or inject keystrokes into active applications. Please resolve the permissions below.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.isDark ? Color.white.opacity(0.70) : Color(hex: "b45309"))
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MacTheme.isDark ? Color(hex: "78350f").opacity(0.35) : Color(hex: "fffbeb"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "f59e0b").opacity(MacTheme.isDark ? 0.40 : 0.60), lineWidth: 1)
                )
            }

            // Card 1: Microphone Permission
            permissionCardView(
                icon: "mic.fill",
                iconColor: Color(hex: "ef4444"),
                title: "Microphone Access",
                badge: permissionsManager.microphoneStatus.rawValue,
                isGranted: permissionsManager.microphoneStatus.isGranted,
                description: "Required to capture audio when the dictation shortcut or push-to-talk key is activated.",
                primaryButtonTitle: permissionsManager.microphoneStatus.isGranted ? nil : "Grant Microphone Permission",
                primaryAction: {
                    permissionsManager.requestMicrophonePermission { _ in
                        audioDeviceManager.refreshDevices()
                    }
                },
                secondaryButtonTitle: "Open System Settings",
                secondaryAction: {
                    permissionsManager.openSystemSettings(for: .microphone)
                }
            )

            // Card 2: Audio Input Hardware (Microphone Selector)
            audioInputDeviceSelectorCard

            // Card 3: Accessibility Permission
            permissionCardView(
                icon: "hand.raised.fill",
                iconColor: Color(hex: "3b82f6"),
                title: "Accessibility (Keystroke Injection & Voice Commands)",
                badge: permissionsManager.accessibilityStatus.rawValue,
                isGranted: permissionsManager.accessibilityStatus.isGranted,
                description: "Allows Openflow to paste transcribed text directly into whichever app you are focused on (Cursor, Slack, Notes, Xcode, Web browsers) and execute voice commands.",
                primaryButtonTitle: permissionsManager.accessibilityStatus.isGranted ? nil : "Grant Accessibility Access",
                primaryAction: {
                    permissionsManager.requestAccessibilityPermission()
                },
                secondaryButtonTitle: "Open Accessibility Settings",
                secondaryAction: {
                    permissionsManager.openSystemSettings(for: .accessibility)
                }
            )

            // Card 4: Apple Speech Recognition (Optional)
            permissionCardView(
                icon: "waveform.and.magnifyingglass",
                iconColor: Color(hex: "10b981"),
                title: "Speech Recognition Engine",
                badge: permissionsManager.speechRecognitionStatus.rawValue,
                isGranted: permissionsManager.speechRecognitionStatus.isGranted,
                description: "Required only when running the native macOS Speech Engine. Not required when running on-device Whisper CoreML or local Parakeet/Qwen servers.",
                primaryButtonTitle: nil,
                primaryAction: nil,
                secondaryButtonTitle: "Open Privacy Settings",
                secondaryAction: {
                    permissionsManager.openSystemSettings(for: .speechRecognition)
                }
            )
        }
    }

    private var audioInputDeviceSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: "f43f5e").opacity(0.15))
                        .frame(width: 30, height: 30)

                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "f43f5e"))
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Active Input Microphone")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)

                        Text("\(audioDeviceManager.availableDevices.count) Found")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(MacTheme.chipBg)
                            .foregroundStyle(MacTheme.textMuted)
                            .cornerRadius(4)
                    }

                    Text("Route audio capture to your preferred internal, USB, or Bluetooth microphone.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacTheme.textMuted)
                }

                Spacer()
            }

            // Device Picker
            HStack(spacing: 10) {
                Menu {
                    Button {
                        audioDeviceManager.selectDevice(id: "default")
                        statusMessage = "Audio input set to System Default."
                    } label: {
                        HStack {
                            Text("System Default Microphone")
                            if audioDeviceManager.selectedDeviceID == "default" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    if !audioDeviceManager.availableDevices.isEmpty {
                        Divider()
                        ForEach(audioDeviceManager.availableDevices) { dev in
                            Button {
                                audioDeviceManager.selectDevice(id: dev.id)
                                statusMessage = "Audio input set to \(dev.name)."
                            } label: {
                                HStack {
                                    Text(dev.name + (dev.isDefault ? " (Default)" : ""))
                                    if audioDeviceManager.selectedDeviceID == dev.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "f43f5e"))

                        Text(audioDeviceManager.currentDeviceName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(MacTheme.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(MacTheme.inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MacTheme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)

                Button {
                    audioDeviceManager.refreshDevices()
                    statusMessage = "Scanned audio devices."
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text("Rescan")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(MacTheme.cardSecondary)
                    .foregroundStyle(MacTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MacTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MacTheme.border, lineWidth: 1)
        )
    }

    private func permissionCardView(
        icon: String,
        iconColor: Color,
        title: String,
        badge: String,
        isGranted: Bool,
        description: String,
        primaryButtonTitle: String?,
        primaryAction: (() -> Void)?,
        secondaryButtonTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 30, height: 30)

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)

                    Text(description)
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(isGranted ? Color(hex: "10b981") : Color(hex: "ef4444"))
                        .frame(width: 6, height: 6)
                    Text(badge)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isGranted ? Color(hex: "10b981") : Color(hex: "ef4444"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background((isGranted ? Color(hex: "10b981") : Color(hex: "ef4444")).opacity(0.14))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke((isGranted ? Color(hex: "10b981") : Color(hex: "ef4444")).opacity(0.30), lineWidth: 1)
                )
            }

            // Action Buttons
            HStack(spacing: 8) {
                if let primaryTitle = primaryButtonTitle, let action = primaryAction {
                    Button(action: action) {
                        Text(primaryTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(MacTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: secondaryAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                        Text(secondaryButtonTitle)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(MacTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(MacTheme.cardSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(MacTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MacTheme.border, lineWidth: 1)
        )
    }

    private var quickPermissionsGlanceBanner: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = .permissions
            }
        } label: {
            HStack(spacing: 10) {
                let allGranted = permissionsManager.allRequiredPermissionsGranted
                Image(systemName: allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(allGranted ? Color(hex: "10b981") : Color(hex: "f59e0b"))

                VStack(alignment: .leading, spacing: 1) {
                    Text(allGranted ? "System Permissions: Fully Authorized" : "System Permissions: Action Required")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)

                    Text(allGranted ? "Microphone & Accessibility access granted" : "Resolve Microphone or Accessibility permissions")
                        .font(.system(size: 10))
                        .foregroundStyle(MacTheme.textMuted)
                }

                Spacer()

                HStack(spacing: 3) {
                    Text("Manage Permissions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(MacTheme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func presetPill(label: String, storage: String, display: String) -> some View {
        let isSelected = hotkey == storage
        return Button {
            hotkey = storage
            hotkeyDisplay = display
            statusMessage = "Shortcut set to \(display). Click Save to apply."
        } label: {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? (MacTheme.isDark ? Color.white : MacTheme.accent) : MacTheme.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? MacTheme.accent.opacity(MacTheme.isDark ? 0.25 : 0.15) : MacTheme.chipBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? MacTheme.accent.opacity(0.6) : MacTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func keycapsView(for text: String) -> some View {
        let parts = text.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        return HStack(spacing: 4) {
            ForEach(parts, id: \.self) { part in
                let symbol = keycapSymbol(for: part)
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MacTheme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(MacTheme.chipBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(MacTheme.border, lineWidth: 1)
                    )
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

    // MARK: - Theme Selector Card
    private var themeSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "f59e0b"))

                    Text("APPEARANCE & THEME")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MacTheme.textHeader)
                        .tracking(0.6)
                }

                Spacer()

                Text("Current: \(themeManager.theme.displayName)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(MacTheme.textMuted)
            }

            Text("Select your preferred visual aesthetic. Choose a clean White / Light theme, an obsidian Dark theme, or automatically match your macOS system appearance.")
                .font(.system(size: 10.5))
                .foregroundStyle(MacTheme.textMuted)

            HStack(spacing: 12) {
                themeOptionCard(
                    theme: .light,
                    title: "Light (White)",
                    subtitle: "Crisp white canvas",
                    icon: "sun.max.fill",
                    iconColor: Color(hex: "f59e0b"),
                    previewColors: [Color.white, Color(hex: "f1f5f9"), Color(hex: "2563eb")]
                )

                themeOptionCard(
                    theme: .dark,
                    title: "Dark",
                    subtitle: "Obsidian & neon accents",
                    icon: "moon.stars.fill",
                    iconColor: Color(hex: "818cf8"),
                    previewColors: [Color(hex: "111216"), Color(hex: "1e212b"), Color(hex: "3b82f6")]
                )

                themeOptionCard(
                    theme: .system,
                    title: "System (Auto)",
                    subtitle: "Syncs with macOS",
                    icon: "circle.lefthalf.filled",
                    iconColor: Color(hex: "34d399"),
                    previewColors: [Color(hex: "f8fafc"), Color(hex: "111216"), Color(hex: "10b981")]
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MacTheme.border, lineWidth: 1)
        )
        .shadow(color: MacTheme.cardShadow, radius: 4, y: 1)
    }

    private func themeOptionCard(
        theme: AppTheme,
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        previewColors: [Color]
    ) -> some View {
        let isSelected = themeManager.theme == theme

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                themeManager.setTheme(theme)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(iconColor)

                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(isSelected ? MacTheme.accent : MacTheme.border, lineWidth: isSelected ? 2 : 1)
                            .frame(width: 14, height: 14)
                        if isSelected {
                            Circle()
                                .fill(MacTheme.accent)
                                .frame(width: 8, height: 8)
                        }
                    }
                }

                HStack(spacing: 3) {
                    ForEach(0..<previewColors.count, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(previewColors[idx])
                            .frame(height: 6)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                    }
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? MacTheme.textPrimary : MacTheme.textMuted)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? MacTheme.accent.opacity(0.10) : MacTheme.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? MacTheme.accent : MacTheme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func deliveryCard(
        mode: TranscriptOutputMode,
        title: String,
        subtitle: String,
        hasActiveDot: Bool = false
    ) -> some View {
        let isSelected = outputMode == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                outputMode = mode
            }
        } label: {
            HStack(spacing: 12) {
                // Radio Circle
                ZStack {
                    Circle()
                        .stroke(isSelected ? MacTheme.accent : MacTheme.border, lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(MacTheme.accent)
                            .frame(width: 8, height: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? MacTheme.textPrimary : MacTheme.textMuted)

                        if hasActiveDot && isSelected {
                            Circle()
                                .fill(Color(hex: "60a5fa"))
                                .frame(width: 6, height: 6)
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? MacTheme.textPrimary : MacTheme.textMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? MacTheme.accent.opacity(0.12) : MacTheme.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? MacTheme.accent.opacity(0.50) : MacTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab: Speech & Productivity Stats
    private var statsTabView: some View {
        let stats = historyStore.statsSummary
        let maxDailyWords = max(1, stats.dailyActivity.map { $0.words }.max() ?? 1)

        return VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SPEECH & PRODUCTIVITY STATS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MacTheme.textHeader)
                        .tracking(0.6)

                    Text("Real-time dictation metrics, speaking pace, and typing time saved")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textMuted)
                }

                Spacer()

                Button {
                    showingResetStatsAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9.5, weight: .medium))
                        Text("Reset Stats")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(MacTheme.pillBg)
                    .foregroundStyle(MacTheme.textMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .alert("Reset Speech Statistics?", isPresented: $showingResetStatsAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        historyStore.resetStats()
                    }
                } message: {
                    Text("This will clear all accumulated word counts, session logs, and daily speaking records.")
                }
            }

            // Hero Highlight Card: Typing Time Saved Spotlight
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("🚀 SPEED MULTIPLIER")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "f59e0b").opacity(0.18))
                                .foregroundStyle(Color(hex: "fbbf24"))
                                .clipShape(Capsule())

                            Text("~3.7× Faster than Typing")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: "34d399"))
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(stats.formattedTimeSaved)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [MacTheme.textPrimary, MacTheme.textPrimary.opacity(0.85)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            Text("TYPING TIME SAVED")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MacTheme.textHeader)
                                .tracking(0.5)
                        }

                        Text("Comparing your natural speech (\(stats.speakingSpeedWPM) WPM) against standard keyboard typing (~40 WPM).")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textMuted)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Visual Clock / Hourglass Icon Pill
                    ZStack {
                        Circle()
                            .fill(Color(hex: "10b981").opacity(0.15))
                            .frame(width: 48, height: 48)

                        Image(systemName: "hourglass.badge.plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color(hex: "34d399"))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "10b981").opacity(0.35), MacTheme.border],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )

            // 4 Primary KPI Metric Cards Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                statKpiCard(
                    title: "WORDS DICTATED",
                    value: "\(stats.totalWords)",
                    subvalue: "\(stats.wordsToday) words today",
                    icon: "text.word.spacing",
                    accent: Color(hex: "10b981")
                )

                statKpiCard(
                    title: "SPEAKING PACE",
                    value: "\(stats.speakingSpeedWPM) WPM",
                    subvalue: "\(stats.averageWordsPerSession > 0 ? String(format: "%.0f words / dictation", stats.averageWordsPerSession) : "Active")",
                    icon: "speedometer",
                    accent: Color(hex: "818cf8")
                )

                statKpiCard(
                    title: "TOTAL SESSIONS",
                    value: "\(stats.totalSessions)",
                    subvalue: "\(stats.sessionsToday) sessions today",
                    icon: "mic.badge.checkmark",
                    accent: Color(hex: "06b6d4")
                )

                statKpiCard(
                    title: "VOICE COMMANDS",
                    value: "\(stats.totalCommands)",
                    subvalue: "In-line edits & actions",
                    icon: "wand.and.stars",
                    accent: Color(hex: "f43f5e")
                )
            }

            // Daily Activity Chart (Last 7 Days)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "60a5fa"))
                        Text("DAILY DICTATION VOLUME (LAST 7 DAYS)")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(MacTheme.textHeader)
                            .tracking(0.5)
                    }

                    Spacer()

                    Text("\(stats.wordsThisWeek) words this week")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color(hex: "60a5fa"))
                }

                // 7 Bar Columns
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(stats.dailyActivity) { day in
                        VStack(spacing: 5) {
                            Text(day.words > 0 ? "\(day.words)" : "–")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(day.isToday ? MacTheme.textPrimary : MacTheme.textSecondary)

                            // Bar Capsule
                            let heightRatio = CGFloat(day.words) / CGFloat(maxDailyWords)
                            let barHeight = max(6.0, heightRatio * 64.0)

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(MacTheme.inputBg)
                                    .frame(height: 64)

                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(
                                        day.isToday
                                            ? LinearGradient(
                                                colors: [Color(hex: "f43f5e"), Color(hex: "f59e0b")],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                            : LinearGradient(
                                                colors: [Color(hex: "60a5fa").opacity(0.75), Color(hex: "3b82f6").opacity(0.40)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                    )
                                    .frame(height: barHeight)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(day.isToday ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                            }
                            .frame(maxWidth: .infinity)

                            Text(day.dayLabel)
                                .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                                .foregroundStyle(day.isToday ? Color(hex: "fb7185") : MacTheme.textMuted)
                        }
                    }
                }
                .frame(height: 100)
                .padding(.top, 4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Two-Column Breakdown: Engines & Top Applications
            HStack(alignment: .top, spacing: 10) {
                // Speech Engine Distribution
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Color(hex: "10b981"))
                        Text("SPEECH ENGINES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MacTheme.textHeader)
                            .tracking(0.5)
                    }

                    if stats.engineDistribution.isEmpty {
                        Text("No speech recorded yet")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textSecondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(Array(stats.engineDistribution.prefix(4)), id: \.name) { item in
                                distributionRow(
                                    label: item.name,
                                    detail: "\(item.count)",
                                    percentage: item.percentage,
                                    tint: Color(hex: "10b981")
                                )
                            }
                        }
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MacTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MacTheme.border, lineWidth: 1)
                )

                // Top Target Apps Distribution
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Color(hex: "60a5fa"))
                        Text("ACTIVE WORKFLOW APPS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MacTheme.textHeader)
                            .tracking(0.5)
                    }

                    if stats.topAppsDistribution.isEmpty {
                        Text("Target apps appear after dictating")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textSecondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(Array(stats.topAppsDistribution.prefix(4)), id: \.name) { item in
                                distributionRow(
                                    label: item.name,
                                    detail: "\(item.count)",
                                    percentage: item.percentage,
                                    tint: Color(hex: "60a5fa")
                                )
                            }
                        }
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MacTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MacTheme.border, lineWidth: 1)
                )
            }

            // Summary Glance by Period
            HStack(spacing: 8) {
                periodPill(
                    title: "Today",
                    words: "\(stats.wordsToday) words",
                    saved: stats.timeSavedTodayFormatted
                )
                periodPill(
                    title: "This Week",
                    words: "\(stats.wordsThisWeek) words",
                    saved: stats.timeSavedThisWeekFormatted
                )
                periodPill(
                    title: "All Time",
                    words: "\(stats.totalWords) words",
                    saved: stats.formattedTimeSaved
                )
            }
        }
    }

    private func statKpiCard(title: String, value: String, subvalue: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(MacTheme.textHeader)
                    .tracking(0.4)

                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MacTheme.textPrimary)

                Text(subvalue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MacTheme.border, lineWidth: 1)
        )
    }

    private func distributionRow(label: String, detail: String, percentage: Double, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text("\(detail) (\(Int(round(percentage)))%)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacTheme.textMuted)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MacTheme.inputBg)
                        .frame(height: 4)

                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat(percentage / 100.0)), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private func periodPill(title: String, words: String, saved: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(MacTheme.textHeader)
                .tracking(0.4)

            Text(words)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MacTheme.textPrimary)

            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 8.5))
                Text("\(saved) saved")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color(hex: "34d399"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MacTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Tab 4: Transcript History
    private var historyTabView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription History")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)

                    Text("Review recent on-device audio transcriptions.")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textMuted)
                }

                Spacer()

                if !historyStore.records.isEmpty {
                    Button {
                        historyStore.clear()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "f87171"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: "ef4444").opacity(0.12))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            if historyStore.records.isEmpty {
                // Dashed Empty Container matching HTML
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(MacTheme.textSecondary.opacity(0.6))

                    Text("No audio sessions stored. History retention is set to 24 hours.")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MacTheme.border, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(historyStore.records) { record in
                        historyRecordCard(record: record)
                    }
                }
            }
        }
    }

    private func historyRecordCard(record: TranscriptRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.timestamp, style: .time)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.textMuted)

                Text("•")
                    .foregroundStyle(MacTheme.textSecondary)

                Text("\(record.wordCount) words")
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.textMuted)

                Text("•")
                    .foregroundStyle(MacTheme.textSecondary)

                Text(record.engine)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(MacTheme.accent.opacity(0.15))
                    .foregroundStyle(MacTheme.isDark ? Color(hex: "93c5fd") : MacTheme.accent)
                    .cornerRadius(4)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
                    statusMessage = "Copied to clipboard!"
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MacTheme.cardSecondary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MacTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    historyStore.delete(id: record.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MacTheme.textMuted)
                }
                .buttonStyle(.plain)
            }

            Text(record.text)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textPrimary)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MacTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Tab: Reader (Text-to-Speech)
    private var readerTabView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section Title & Intro
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speech Reader & Voice Narration")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)

                    Text("Listen to books, documents, and clipboard text using studio-grade Kokoro-82M AI or Apple neural voices.")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textMuted)
                }

                Spacer()

                Button {
                    ReaderPanelController.shared.show()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 11))
                        Text("Open Floating Player")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "0284c7"))
                    .foregroundStyle(Color.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Compressed 2-Engine Horizontal Card Deck
            HStack(spacing: 12) {
                compressedReaderEngineCard(
                    kind: .kokoro,
                    title: "Kokoro-82M AI Studio",
                    badge: "Recommended",
                    badgeColor: Color(hex: "10b981"),
                    gradient: [Color(hex: "6366f1"), Color(hex: "a855f7")],
                    icon: "waveform.circle.fill",
                    subtitle: "Apple Neural Engine (ANE)",
                    tag: "100% Offline"
                )

                compressedReaderEngineCard(
                    kind: .appleNative,
                    title: "Apple Speech / Siri",
                    badge: "macOS Native",
                    badgeColor: Color(hex: "0284c7"),
                    gradient: [Color(hex: "3b82f6"), Color(hex: "0284c7")],
                    icon: "applelogo",
                    subtitle: "Zero download required",
                    tag: "Instant Launch"
                )
            }

            // Engine Diagnostics & Privacy Pill Strip
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Engine Active:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.textHeader)
                    Text(readerManager.engineKind.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                }

                Divider().frame(height: 12).background(MacTheme.divider)

                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.cyan)
                    Text(readerManager.engineKind == .kokoro ? "Apple Neural Engine • 82M Params" : "AVSpeechSynthesizer • Native")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textHeader)
                }

                Divider().frame(height: 12).background(MacTheme.divider)

                HStack(spacing: 5) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "34d399"))
                    Text("100% On-Device • Zero Network")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textHeader)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MacTheme.cardSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Kokoro Model Card with Live Download Progress Button
            if readerManager.engineKind == .kokoro {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Kokoro-82M CoreML Model")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(MacTheme.textPrimary)

                                Text("150 MB")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(MacTheme.chipBg)
                                    .foregroundStyle(Color(hex: "0284c7"))
                                    .clipShape(Capsule())

                                Text("15 Curated Voices")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(MacTheme.chipBg)
                                    .foregroundStyle(Color(hex: "10b981"))
                                    .clipShape(Capsule())
                            }

                            Text(kokoroEngine.statusMessage.isEmpty ? "Optimized for Apple Silicon Neural Engine (M1/M2/M3/M4)" : kokoroEngine.statusMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.textMuted)
                        }

                        Spacer()

                        // Download / Status Action Button
                        if kokoroEngine.isDownloading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                                Text("Downloading \(Int(kokoroEngine.downloadProgress * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(hex: "0284c7"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "0284c7").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color(hex: "0284c7").opacity(0.35), lineWidth: 1)
                            )
                        } else if kokoroEngine.isModelDownloaded {
                            HStack(spacing: 8) {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color(hex: "10b981"))
                                    Text("Ready")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(hex: "10b981"))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(hex: "10b981").opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color(hex: "10b981").opacity(0.30), lineWidth: 1)
                                )

                                Button {
                                    withAnimation {
                                        modelStorageManager.offloadReaderEngine()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.to.line.compact")
                                            .font(.system(size: 9.5, weight: .bold))
                                        Text("Offload RAM")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(MacTheme.cardSecondary)
                                    .foregroundStyle(MacTheme.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(MacTheme.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Offload Kokoro weights from RAM/ANE")

                                Button {
                                    withAnimation {
                                        modelStorageManager.deleteKokoroModel()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 9.5))
                                        Text("Delete")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.12))
                                    .foregroundStyle(Color.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Delete Kokoro-82M model files from disk to free 150 MB")
                            }
                        } else {
                            Button {
                                kokoroEngine.downloadModel()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 12))
                                    Text("Download Model (150 MB)")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(hex: "0284c7"))
                                .foregroundStyle(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Progress bar if downloading
                    if kokoroEngine.isDownloading {
                        ProgressView(value: kokoroEngine.downloadProgress)
                            .progressViewStyle(.linear)
                            .tint(Color(hex: "0284c7"))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MacTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MacTheme.border, lineWidth: 1)
                )
            }

            // Voice & Playback Controls Card
            VStack(alignment: .leading, spacing: 14) {
                Text("Voice & Playback Settings")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(MacTheme.textPrimary)

                // Voice Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Narrator Voice")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.textMuted)

                    Picker("", selection: Binding(
                        get: { readerManager.currentVoice?.id ?? "" },
                        set: { newId in
                            if let v = readerManager.availableVoices.first(where: { $0.id == newId }) {
                                readerManager.currentVoice = v
                            }
                        }
                    )) {
                        ForEach(readerManager.availableVoices) { voice in
                            Text(voice.displayName).tag(voice.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                // Speech Rate Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Playback Speed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.textMuted)

                        Spacer()

                        Text(String(format: "%.2fx", readerManager.playbackRate))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "0284c7"))
                    }

                    Slider(value: Binding(
                        get: { readerManager.playbackRate },
                        set: { readerManager.playbackRate = $0 }
                    ), in: 0.5...2.0, step: 0.05)
                }

                // Test Voice Button & Read Clipboard
                HStack(spacing: 10) {
                    Button {
                        readerManager.startReading(text: "Hello! This is Openflow reading with ultra-clear voice synthesis.")
                    } label: {
                        HStack(spacing: 5) {
                            if readerManager.isSynthesizing {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                                Text("Synthesizing...")
                                    .font(.system(size: 11, weight: .medium))
                            } else {
                                Image(systemName: "speaker.wave.2")
                                    .font(.system(size: 11))
                                Text("Test Voice")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(MacTheme.cardSecondary)
                        .foregroundStyle(MacTheme.textPrimary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MacTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(readerManager.isSynthesizing)

                    Button {
                        readerManager.readClipboard()
                        ReaderPanelController.shared.show()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11))
                            Text("Read Clipboard")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(MacTheme.cardSecondary)
                        .foregroundStyle(MacTheme.textPrimary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MacTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        readerManager.openFilePicker()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 11))
                            Text("Open Book or File (.pdf, .txt, .md)...")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(MacTheme.cardSecondary)
                        .foregroundStyle(Color(hex: "0284c7"))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MacTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if readerManager.state == .playing || readerManager.state == .paused {
                        Button {
                            readerManager.stop()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 10))
                                Text("Stop")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(Color.red)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // How to Read Books Card
            VStack(alignment: .leading, spacing: 8) {
                Text("How to Read Books & Documents")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MacTheme.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "0284c7"))
                        Text("Open any document (.pdf, .txt, .md, .rtf) using the button above, or copy text from Apple Books, Kindle, or Safari.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textMuted)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text("2.")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "0284c7"))
                        Text("Openflow begins voice synthesis and opens the floating mini-player HUD.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textMuted)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "0284c7"))
                        Text("Follow along sentence-by-sentence with pause, rewind, forward, and playback speed adjustments.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textMuted)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )
        }
    }

    private func compressedReaderEngineCard(
        kind: TTSEngineKind,
        title: String,
        badge: String,
        badgeColor: Color,
        gradient: [Color],
        icon: String,
        subtitle: String,
        tag: String
    ) -> some View {
        let isSelected = readerManager.engineKind == kind

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                readerManager.engineKind = kind
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 26, height: 26)

                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                    }

                    Spacer()

                    Text(badge)
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(badgeColor.opacity(0.30), lineWidth: 1)
                        )

                    ZStack {
                        Circle()
                            .stroke(isSelected ? MacTheme.accent : (MacTheme.isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.20)), lineWidth: isSelected ? 2 : 1)
                            .frame(width: 16, height: 16)

                        if isSelected {
                            Circle()
                                .fill(MacTheme.accent)
                                .frame(width: 16, height: 16)

                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? (MacTheme.isDark ? Color.white.opacity(0.85) : MacTheme.accent) : MacTheme.textMuted)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(tag)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? (MacTheme.isDark ? Color(hex: "93c5fd") : MacTheme.accent) : MacTheme.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? MacTheme.accent.opacity(MacTheme.isDark ? 0.10 : 0.08) : MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? MacTheme.accent : MacTheme.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: isSelected ? MacTheme.accent.opacity(0.20) : Color.clear, radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 5: About
    private var aboutTabView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                // Official Brand App Icon
                OpenflowLogoView(size: 64, cornerRadius: 16)
                    .shadow(color: Color(hex: "0284c7").opacity(0.35), radius: 12, x: 0, y: 4)

                Text("Openflow")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text("Ultra-fast local speech recognition designed natively for macOS Sonoma & Sequoia.")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                Text("Build 2026.10.20-release • MIT License")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MacTheme.textSecondary)

                Divider().background(MacTheme.divider).padding(.vertical, 4)

                // Feature Highlights
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "34d399"))

                        Text("100% On-Device & Private")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "34d399"))
                    }

                    Text("All speech recognition runs locally via Apple Silicon Neural Engine & GPU (WhisperKit) or Apple Speech. Your audio and transcripts never leave your Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textMuted)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )

            // Software Updates Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Software Updates")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)

                        Text("Version 0.1.0 • Automatic updates enabled")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textMuted)
                    }

                    Spacer()

                    Button {
                        UpdateManager.shared.checkForUpdates()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                            Text("Check for Updates...")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(MacTheme.cardSecondary)
                        .foregroundStyle(MacTheme.textPrimary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MacTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MacTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Window Footer Actions
    private var windowFooterActions: some View {
        HStack(alignment: .center) {
            Button("Restore Defaults") {
                restoreDefaults()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MacTheme.textMuted)

            Spacer()

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusMessage.contains("Restart") ? Color.orange : Color(hex: "34d399"))
                    .transition(.opacity)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    stopHotkeyCapture()
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.cancelBtnText)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(MacTheme.cancelBtnBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(MacTheme.border, lineWidth: 1)
                )

                Button("Save Settings") {
                    save()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "3b82f6"), Color(hex: "2563eb")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color(hex: "60a5fa").opacity(0.40), lineWidth: 1)
                )
                .shadow(color: Color(hex: "3b82f6").opacity(0.45), radius: 8, x: 0, y: 3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(MacTheme.footerBg)
        .overlay(
            VStack {
                Rectangle().fill(MacTheme.divider).frame(height: 1)
                Spacer()
            }
        )
    }

    // MARK: - Logic & Actions
    private func formatPlayground(_ text: String) -> String {
        let config = TypedTextConfig(
            addTrailingSpace: addTrailingSpace,
            capitalizeSentences: capitalizeSentences,
            writeNumbersAsDigits: writeNumbersAsDigits,
            useSymbolsAndOrdinals: useSymbolsAndOrdinals,
            spokenEmoji: spokenEmoji,
            paragraphBreaks: paragraphBreaks,
            spokenPunctuation: spokenPunctuation
        )
        let formatter = TypedTextFormatter(config: config)
        let formatted = formatter.format(text)
        return formatted.isEmpty ? "Type above to preview formatting" : formatted
    }

    private func save() {
        stopHotkeyCapture()

        let defaults = UserDefaults.standard
        let previousModel = ModelName(rawValue: defaults.string(forKey: UserSettingKey.modelName) ?? "") ?? .fast06B
        let modelChanged = previousModel != modelName

        defaults.set(backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.backendBaseURL)
        defaults.set(timeoutSeconds.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.timeoutSeconds)
        defaults.set(retryCount.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.retryCount)
        defaults.set(retryDelayMs.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.retryBaseDelayMs)
        defaults.set(hotkey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.hotkey)
        defaults.set(apiToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.apiToken)
        defaults.set(maxUploadBytes.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.maxUploadBytes)
        defaults.set(outputMode.rawValue, forKey: UserSettingKey.outputMode)
        defaults.set(modelName.rawValue, forKey: UserSettingKey.modelName)
        defaults.set(engineType.rawValue, forKey: UserSettingKey.engineType)
        defaults.set(localWhisperModel.rawValue, forKey: UserSettingKey.localWhisperModel)
        defaults.set(addTrailingSpace, forKey: UserSettingKey.addTrailingSpace)
        defaults.set(capitalizeSentences, forKey: UserSettingKey.capitalizeSentences)
        defaults.set(writeNumbersAsDigits, forKey: UserSettingKey.writeNumbersAsDigits)
        defaults.set(useSymbolsAndOrdinals, forKey: UserSettingKey.useSymbolsAndOrdinals)
        defaults.set(spokenEmoji, forKey: UserSettingKey.spokenEmoji)
        defaults.set(paragraphBreaks, forKey: UserSettingKey.paragraphBreaks)
        defaults.set(spokenPunctuation, forKey: UserSettingKey.spokenPunctuation)
        defaults.set(maxRecordingDuration.rawValue, forKey: UserSettingKey.maxRecordingDuration)
        defaults.set(skipSilenceBeforeTranscribing, forKey: UserSettingKey.skipSilenceBeforeTranscribing)
        defaults.set(silenceSensitivity.rawValue, forKey: UserSettingKey.silenceSensitivity)
        defaults.set(stopAfterSilence.rawValue, forKey: UserSettingKey.stopAfterSilence)
        defaults.set(overlayPlacement.rawValue, forKey: UserSettingKey.overlayPlacement)
        defaults.set(playFeedbackSounds, forKey: UserSettingKey.playFeedbackSounds)
        NotificationCenter.default.post(name: .openflowOverlayPlacementDidChange, object: overlayPlacement)

        if modelChanged {
            showModelRestartNotice = true
            statusMessage = "Saved. Restart backend to apply model change."
        } else {
            showModelRestartNotice = false
            statusMessage = "Saved. Applied immediately."
        }
        NotificationCenter.default.post(name: .quickASRSettingsDidChange, object: nil)
    }

    private func restoreDefaults() {
        let defaults = AppConfig.default
        backendBaseURL = defaults.backendBaseURL.absoluteString
        timeoutSeconds = String(Int(defaults.requestTimeoutSeconds))
        retryCount = String(defaults.maxRetryCount)
        retryDelayMs = String(defaults.retryBaseDelayMs)
        hotkey = "cmd+shift+space"
        hotkeyDisplay = defaults.hotKey.displayText
        apiToken = ""
        maxUploadBytes = String(defaults.maxUploadBytes)
        outputMode = defaults.outputMode
        modelName = defaults.modelName
        engineType = defaults.engineType
        localWhisperModel = defaults.localWhisperModel
        addTrailingSpace = defaults.typedText.addTrailingSpace
        capitalizeSentences = defaults.typedText.capitalizeSentences
        writeNumbersAsDigits = defaults.typedText.writeNumbersAsDigits
        useSymbolsAndOrdinals = defaults.typedText.useSymbolsAndOrdinals
        spokenEmoji = defaults.typedText.spokenEmoji
        paragraphBreaks = defaults.typedText.paragraphBreaks
        spokenPunctuation = defaults.typedText.spokenPunctuation

        let defSilence = defaults.recordingSilence
        maxRecordingDuration = defSilence.maxRecordingDuration
        skipSilenceBeforeTranscribing = defSilence.skipSilenceBeforeTranscribing
        silenceSensitivity = defSilence.silenceSensitivity
        stopAfterSilence = defSilence.stopAfterSilence
        overlayPlacement = defaults.overlayPlacement
        playFeedbackSounds = true
        NotificationCenter.default.post(name: .openflowOverlayPlacementDidChange, object: OverlayPlacement.top)
        showModelRestartNotice = false
        statusMessage = "Defaults loaded. Click Save to apply."
    }

    private func toggleHotkeyCapture() {
        if isRecordingHotkey {
            stopHotkeyCapture()
            statusMessage = "Hotkey capture cancelled."
            return
        }

        isRecordingHotkey = true
        statusMessage = "Press your shortcut now (e.g. F5, Right Option, or ⌘⇧Space)."
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleHotkeyCapture(event)
        }
    }

    private func stopHotkeyCapture() {
        isRecordingHotkey = false
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
            self.hotkeyCaptureMonitor = nil
        }
    }

    private func handleHotkeyCapture(_ event: NSEvent) -> NSEvent? {
        guard isRecordingHotkey else {
            return event
        }

        if event.keyCode == UInt16(kVK_Escape) {
            stopHotkeyCapture()
            statusMessage = "Hotkey capture cancelled."
            return nil
        }

        guard let captured = HotKeyConfiguration.capture(from: event) else {
            if event.type == .flagsChanged {
                return nil
            }
            statusMessage = "Press a single key (e.g. F5, Right Option, Fn) or key combination (Cmd/Shift/Option)."
            return nil
        }

        hotkey = captured.storageValue
        hotkeyDisplay = captured.configuration.displayText
        stopHotkeyCapture()
        statusMessage = "Hotkey set to \(captured.configuration.displayText). Click Save to apply."
        return nil
    }
}

// MARK: - Debug Test Helpers
#if DEBUG
extension SettingsView {
    mutating func _test_save() {
        save()
    }

    mutating func _test_restoreDefaults() {
        restoreDefaults()
    }

    mutating func _test_toggleHotkeyCapture() {
        toggleHotkeyCapture()
    }

    mutating func _test_stopHotkeyCapture() {
        stopHotkeyCapture()
    }

    mutating func _test_handleHotkeyCapture(_ event: NSEvent) -> NSEvent? {
        handleHotkeyCapture(event)
    }

    mutating func _test_setBackendBaseURL(_ value: String) {
        backendBaseURL = value
    }

    mutating func _test_setTimeoutSeconds(_ value: String) {
        timeoutSeconds = value
    }

    mutating func _test_setRetryCount(_ value: String) {
        retryCount = value
    }

    mutating func _test_setRetryDelayMs(_ value: String) {
        retryDelayMs = value
    }

    mutating func _test_setHotkey(_ value: String, display: String) {
        hotkey = value
        hotkeyDisplay = display
    }

    mutating func _test_setApiToken(_ value: String) {
        apiToken = value
    }

    mutating func _test_setMaxUploadBytes(_ value: String) {
        maxUploadBytes = value
    }

    mutating func _test_setOutputMode(_ mode: TranscriptOutputMode) {
        outputMode = mode
    }

    mutating func _test_setModelName(_ model: ModelName) {
        modelName = model
    }

    func _test_statusMessage() -> String {
        statusMessage
    }

    func _test_hotkeyStorageValue() -> String {
        hotkey
    }

    func _test_hotkeyDisplayValue() -> String {
        hotkeyDisplay
    }

    func _test_isRecordingHotkey() -> Bool {
        isRecordingHotkey
    }

    func _test_showModelRestartNotice() -> Bool {
        showModelRestartNotice
    }

    @ViewBuilder
    func _test_body() -> some View {
        body
    }
}
#endif

// MARK: - Download Progress Indicator Subviews

struct ModelDownloadBannerView: View {
    @ObservedObject var downloadManager: ModelDownloadProgressManager

    @ViewBuilder
    var body: some View {
        if downloadManager.isDownloading {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            progressBar
            statusRow
        }
        .padding(12)
        .background(backgroundShape)
        .overlay(borderShape)
    }

    private var headerRow: some View {
        HStack {
            titleGroup
            Spacer()
            percentText
        }
    }

    private var titleGroup: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color(hex: "0284c7"))
                .font(.system(size: 15))
            Text("Downloading Model: \(downloadManager.modelDisplayName)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MacTheme.textPrimary)
        }
    }

    private var percentText: some View {
        Text(downloadManager.formattedPercent)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(hex: "0284c7"))
    }

    private var progressBar: some View {
        ProgressView(value: downloadManager.progress)
            .progressViewStyle(.linear)
            .tint(Color(hex: "0284c7"))
    }

    private var statusRow: some View {
        HStack {
            Text(downloadManager.statusMessage)
                .font(.system(size: 10.5))
                .foregroundStyle(MacTheme.textMuted)
            Spacer()
            Text("Apple Neural Engine CoreML")
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textMuted)
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(hex: "0284c7").opacity(MacTheme.isDark ? 0.12 : 0.08))
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color(hex: "0284c7").opacity(0.35), lineWidth: 1)
    }
}

struct ModelDownloadCardProgressView: View {
    @ObservedObject var downloadManager: ModelDownloadProgressManager
    let modelName: String
    let isSelected: Bool

    @ViewBuilder
    var body: some View {
        if downloadManager.isDownloading && (downloadManager.modelName == modelName || isSelected) {
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: downloadManager.progress)
                    .progressViewStyle(.linear)
                    .tint(MacTheme.accent)
                HStack {
                    Text("Downloading CoreML weights...")
                        .font(.system(size: 8.5))
                        .foregroundStyle(MacTheme.textMuted)
                    Spacer()
                    Text(downloadManager.formattedPercent)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(MacTheme.accent)
                }
            }
            .padding(.top, 2)
        }
    }
}
