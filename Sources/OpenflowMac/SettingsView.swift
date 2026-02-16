import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Notification.Name {
    static let quickASRSettingsDidChange = Notification.Name("quickASRSettingsDidChange")
}

struct SettingsView: View {
    @State private var backendBaseURL = UserDefaults.standard.string(forKey: UserSettingKey.backendBaseURL) ?? "http://127.0.0.1:8001"
    @State private var timeoutSeconds = UserDefaults.standard.string(forKey: UserSettingKey.timeoutSeconds) ?? "45"
    @State private var retryCount = UserDefaults.standard.string(forKey: UserSettingKey.retryCount) ?? "2"
    @State private var retryDelayMs = UserDefaults.standard.string(forKey: UserSettingKey.retryBaseDelayMs) ?? "250"
    @State private var hotkey = UserDefaults.standard.string(forKey: UserSettingKey.hotkey) ?? "cmd+shift+space"
    @State private var hotkeyDisplay = HotKeyConfiguration.parse(UserDefaults.standard.string(forKey: UserSettingKey.hotkey) ?? "cmd+shift+space").displayText
    @State private var isRecordingHotkey = false
    @State private var hotkeyCaptureMonitor: Any?
    @State private var apiToken = UserDefaults.standard.string(forKey: UserSettingKey.apiToken) ?? ""
    @State private var maxUploadBytes = UserDefaults.standard.string(forKey: UserSettingKey.maxUploadBytes) ?? "26214400"
    @State private var outputMode = TranscriptOutputMode.parse(UserDefaults.standard.string(forKey: UserSettingKey.outputMode)) ?? .activeApp
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Openflow Settings")
                    .font(.system(size: 24, weight: .semibold))
                Text("These settings are applied instantly after saving.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            settingsCard(title: "Connection") {
                settingRow("Backend URL") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("http://127.0.0.1:8001", text: $backendBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 330)
                        Text("Use localhost/127.0.0.1 for managed startup. External URLs require manual backend start.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 330, alignment: .leading)
                    }
                }

                settingRow("API Token") {
                    TextField("Optional", text: $apiToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                settingRow("Max Upload Bytes") {
                    TextField("26214400", text: $maxUploadBytes)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
            }

            settingsCard(title: "Behavior") {
                settingRow("Output Mode") {
                    Picker("Output Mode", selection: $outputMode) {
                        ForEach(TranscriptOutputMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }

                settingRow("Hotkey") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(isRecordingHotkey ? "Press shortcut..." : hotkeyDisplay)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(isRecordingHotkey ? .orange : .primary)
                                .frame(width: 220, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isRecordingHotkey ? Color.orange.opacity(0.7) : Color.secondary.opacity(0.3), lineWidth: 1)
                                )

                            Button(isRecordingHotkey ? "Cancel" : "Record") {
                                toggleHotkeyCapture()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Press a key with Cmd/Shift/Option/Ctrl. Example: Cmd+Shift+Space")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            settingsCard(title: "Reliability") {
                settingRow("Timeout (seconds)") {
                    TextField("45", text: $timeoutSeconds)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                settingRow("Retry Count") {
                    TextField("2", text: $retryCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                settingRow("Retry Delay (ms)") {
                    TextField("250", text: $retryDelayMs)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }

            HStack {
                Button("Restore Defaults") {
                    restoreDefaults()
                }

                Spacer()

                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600)
        .onDisappear {
            stopHotkeyCapture()
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
        )
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 165, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func save() {
        stopHotkeyCapture()

        let defaults = UserDefaults.standard
        defaults.set(backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.backendBaseURL)
        defaults.set(timeoutSeconds.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.timeoutSeconds)
        defaults.set(retryCount.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.retryCount)
        defaults.set(retryDelayMs.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.retryBaseDelayMs)
        defaults.set(hotkey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.hotkey)
        defaults.set(apiToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.apiToken)
        defaults.set(maxUploadBytes.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UserSettingKey.maxUploadBytes)
        defaults.set(outputMode.rawValue, forKey: UserSettingKey.outputMode)

        statusMessage = "Saved. Applied immediately."
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
        statusMessage = "Defaults loaded. Click Save to apply."
    }

    private func toggleHotkeyCapture() {
        if isRecordingHotkey {
            stopHotkeyCapture()
            statusMessage = "Hotkey capture cancelled."
            return
        }

        isRecordingHotkey = true
        statusMessage = "Press your shortcut now."
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
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
            statusMessage = "Use at least one modifier (Cmd/Shift/Option/Ctrl) with a supported key."
            return nil
        }

        hotkey = captured.storageValue
        hotkeyDisplay = captured.configuration.displayText
        stopHotkeyCapture()
        statusMessage = "Hotkey set to \(captured.configuration.displayText). Click Save to apply."
        return nil
    }
}
