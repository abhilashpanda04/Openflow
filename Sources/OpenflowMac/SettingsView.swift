// Copyright 2025 Abhilash Panda
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
    @State private var modelName = ModelName(rawValue: UserDefaults.standard.string(forKey: UserSettingKey.modelName) ?? "") ?? .fast06B
    @State private var statusMessage = ""
    @State private var showModelRestartNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Openflow Settings")
                    .font(AppStyle.SwiftUI.titleFont)
                Text("These settings are applied instantly after saving.")
                    .font(AppStyle.SwiftUI.helperFont)
                    .foregroundStyle(AppStyle.SwiftUI.secondaryText)
            }

            settingsCard(title: "Model") {
                settingRow("Speech Model") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Model", selection: $modelName) {
                            ForEach(ModelName.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: AppStyle.Metrics.pickerWidth)

                        Text(modelName.description)
                            .font(AppStyle.SwiftUI.helperFont)
                            .foregroundStyle(AppStyle.SwiftUI.secondaryText)
                            .frame(width: AppStyle.Metrics.contentWidth, alignment: .leading)

                        if showModelRestartNotice {
                            Text("Model changed. Restart backend to apply.")
                                .font(AppStyle.SwiftUI.helperFont)
                                .foregroundStyle(AppStyle.SwiftUI.accentWarm)
                                .frame(width: AppStyle.Metrics.contentWidth, alignment: .leading)
                        }
                    }
                }
            }

            settingsCard(title: "Connection") {
                settingRow("Backend URL") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("http://127.0.0.1:8001", text: $backendBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: AppStyle.Metrics.contentWidth)
                        Text("Use localhost/127.0.0.1 for managed startup. External URLs require manual backend start.")
                            .font(AppStyle.SwiftUI.helperFont)
                            .foregroundStyle(AppStyle.SwiftUI.secondaryText)
                            .frame(width: AppStyle.Metrics.contentWidth, alignment: .leading)
                    }
                }

                settingRow("API Token") {
                    TextField("Optional", text: $apiToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: AppStyle.Metrics.compactControlWidth)
                }

                settingRow("Max Upload Bytes") {
                    TextField("26214400", text: $maxUploadBytes)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: AppStyle.Metrics.smallFieldWidth)
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
                    .frame(width: AppStyle.Metrics.compactControlWidth)
                }

                settingRow("Hotkey") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(isRecordingHotkey ? "Press shortcut..." : hotkeyDisplay)
                                .font(AppStyle.SwiftUI.monoFont)
                                .foregroundStyle(isRecordingHotkey ? AppStyle.SwiftUI.accentWarm : .primary)
                                .frame(width: AppStyle.Metrics.compactControlWidth, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isRecordingHotkey ? AppStyle.SwiftUI.accentWarm.opacity(0.7) : Color.secondary.opacity(0.3), lineWidth: 1)
                                )

                            Button(isRecordingHotkey ? "Cancel" : "Record") {
                                toggleHotkeyCapture()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Press a key with Cmd/Shift/Option/Ctrl. Example: Cmd+Shift+Space")
                            .font(AppStyle.SwiftUI.helperFont)
                            .foregroundStyle(AppStyle.SwiftUI.secondaryText)

                        Text("If recording fails, enable Openflow in System Settings > Privacy & Security > Microphone, then relaunch.")
                            .font(AppStyle.SwiftUI.helperFont)
                            .foregroundStyle(AppStyle.SwiftUI.subtleText)
                    }
                }
            }

            settingsCard(title: "Reliability") {
                settingRow("Timeout (seconds)") {
                    TextField("45", text: $timeoutSeconds)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: AppStyle.Metrics.numericFieldWidth)
                }

                settingRow("Retry Count") {
                    TextField("2", text: $retryCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: AppStyle.Metrics.numericFieldWidth)
                }

                settingRow("Retry Delay (ms)") {
                    TextField("250", text: $retryDelayMs)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: AppStyle.Metrics.numericFieldWidth)
                }
            }

            HStack {
                Button("Restore Defaults") {
                    restoreDefaults()
                }

                Spacer()

                Text(statusMessage)
                    .font(AppStyle.SwiftUI.bodyFont.weight(.medium))
                    .foregroundStyle(AppStyle.SwiftUI.secondaryText)

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
                .font(AppStyle.SwiftUI.sectionFont)
                .foregroundStyle(AppStyle.SwiftUI.secondaryText)
            content()
        }
        .padding(AppStyle.Metrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Metrics.cardCornerRadius, style: .continuous)
                .fill(AppStyle.SwiftUI.cardBackground)
        )
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(AppStyle.SwiftUI.bodyFont.weight(.medium))
                .frame(width: AppStyle.Metrics.rowLabelWidth, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func save() {
        stopHotkeyCapture()

        let defaults = UserDefaults.standard
        
        // Check if model changed
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

#if DEBUG
extension SettingsView {
    mutating func _test_restoreDefaults() {
        restoreDefaults()
    }

    mutating func _test_save() {
        save()
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
