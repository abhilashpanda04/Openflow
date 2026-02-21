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
import Carbon
import Foundation

struct HotKeyConfiguration {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayText: String

    static let `default` = HotKeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey),
        displayText: "Cmd+Shift+Space"
    )

    static func parse(_ value: String?) -> HotKeyConfiguration {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .default
        }

        let normalizedTokens = value
            .lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedTokens.isEmpty else {
            return .default
        }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        var displayKey: String?

        for token in normalizedTokens {
            switch token {
            case "cmd", "command":
                modifiers |= UInt32(cmdKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            case "option", "alt":
                modifiers |= UInt32(optionKey)
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            case "space":
                keyCode = UInt32(kVK_Space)
                displayKey = "Space"
            case "return", "enter":
                keyCode = UInt32(kVK_Return)
                displayKey = "Return"
            case "tab":
                keyCode = UInt32(kVK_Tab)
                displayKey = "Tab"
            default:
                if token.count == 1, let first = token.first {
                    if let descriptor = keyDescriptorForCharacter(first) {
                        keyCode = descriptor.keyCode
                        displayKey = descriptor.displayKey
                    }
                }
            }
        }

        guard let parsedKeyCode = keyCode, modifiers != 0 else {
            return .default
        }

        let modifierDisplay = modifierDisplayParts(modifiers: modifiers)
        let finalDisplay = (modifierDisplay + [displayKey ?? "Key"]).joined(separator: "+")

        return HotKeyConfiguration(
            keyCode: parsedKeyCode,
            modifiers: modifiers,
            displayText: finalDisplay
        )
    }

    static func capture(from event: NSEvent) -> (storageValue: String, configuration: HotKeyConfiguration)? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let modifiers = carbonModifiers(from: flags)
        guard modifiers != 0 else {
            return nil
        }

        guard let descriptor = keyDescriptorForKeyCode(UInt32(event.keyCode)) else {
            return nil
        }

        let storageParts = modifierStorageParts(modifiers: modifiers) + [descriptor.storageToken]
        let displayParts = modifierDisplayParts(modifiers: modifiers) + [descriptor.displayKey]
        let display = displayParts.joined(separator: "+")

        let configuration = HotKeyConfiguration(
            keyCode: descriptor.keyCode,
            modifiers: modifiers,
            displayText: display
        )
        return (storageParts.joined(separator: "+"), configuration)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private static func modifierStorageParts(modifiers: UInt32) -> [String] {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("cmd") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("option") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("ctrl") }
        return parts
    }

    private static func modifierDisplayParts(modifiers: UInt32) -> [String] {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        return parts
    }

    private static func keyDescriptorForCharacter(_ value: Character) -> (keyCode: UInt32, storageToken: String, displayKey: String)? {
        let lower = Character(String(value).lowercased())
        let mapping: [Character: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D),
            "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F), "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H),
            "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
            "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R), "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
            "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7),
            "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
        ]

        guard let keyCode = mapping[lower] else {
            return nil
        }

        let display = String(lower).uppercased()
        return (keyCode, String(lower), display)
    }

    private static func keyDescriptorForKeyCode(_ keyCode: UInt32) -> (keyCode: UInt32, storageToken: String, displayKey: String)? {
        if keyCode == UInt32(kVK_Space) {
            return (keyCode, "space", "Space")
        }
        if keyCode == UInt32(kVK_Return) {
            return (keyCode, "return", "Return")
        }
        if keyCode == UInt32(kVK_Tab) {
            return (keyCode, "tab", "Tab")
        }

        let charMappings: [(UInt32, Character)] = [
            (UInt32(kVK_ANSI_A), "a"), (UInt32(kVK_ANSI_B), "b"), (UInt32(kVK_ANSI_C), "c"), (UInt32(kVK_ANSI_D), "d"),
            (UInt32(kVK_ANSI_E), "e"), (UInt32(kVK_ANSI_F), "f"), (UInt32(kVK_ANSI_G), "g"), (UInt32(kVK_ANSI_H), "h"),
            (UInt32(kVK_ANSI_I), "i"), (UInt32(kVK_ANSI_J), "j"), (UInt32(kVK_ANSI_K), "k"), (UInt32(kVK_ANSI_L), "l"),
            (UInt32(kVK_ANSI_M), "m"), (UInt32(kVK_ANSI_N), "n"), (UInt32(kVK_ANSI_O), "o"), (UInt32(kVK_ANSI_P), "p"),
            (UInt32(kVK_ANSI_Q), "q"), (UInt32(kVK_ANSI_R), "r"), (UInt32(kVK_ANSI_S), "s"), (UInt32(kVK_ANSI_T), "t"),
            (UInt32(kVK_ANSI_U), "u"), (UInt32(kVK_ANSI_V), "v"), (UInt32(kVK_ANSI_W), "w"), (UInt32(kVK_ANSI_X), "x"),
            (UInt32(kVK_ANSI_Y), "y"), (UInt32(kVK_ANSI_Z), "z"),
            (UInt32(kVK_ANSI_0), "0"), (UInt32(kVK_ANSI_1), "1"), (UInt32(kVK_ANSI_2), "2"), (UInt32(kVK_ANSI_3), "3"),
            (UInt32(kVK_ANSI_4), "4"), (UInt32(kVK_ANSI_5), "5"), (UInt32(kVK_ANSI_6), "6"), (UInt32(kVK_ANSI_7), "7"),
            (UInt32(kVK_ANSI_8), "8"), (UInt32(kVK_ANSI_9), "9"),
        ]

        if let (_, token) = charMappings.first(where: { $0.0 == keyCode }) {
            return (keyCode, String(token), String(token).uppercased())
        }

        return nil
    }
}

final class GlobalHotKeyManager {
    private static weak var activeManager: GlobalHotKeyManager?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let onPress: () -> Void

    init(config: HotKeyConfiguration, onPress: @escaping () -> Void) throws {
        self.onPress = onPress
        Self.activeManager = self

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyCallback,
            1,
            &eventSpec,
            nil,
            &eventHandler
        )

        guard installStatus == noErr else {
            throw NSError(
                domain: "Openflow.HotKey",
                code: Int(installStatus),
                userInfo: [NSLocalizedDescriptionKey: "InstallEventHandler failed"]
            )
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x51534152), id: 1) // 'QSAR'
        let registerStatus = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw NSError(
                domain: "Openflow.HotKey",
                code: Int(registerStatus),
                userInfo: [NSLocalizedDescriptionKey: "RegisterEventHotKey failed"]
            )
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private static let hotKeyCallback: EventHandlerUPP = { _, _, _ in
        GlobalHotKeyManager.activeManager?.onPress()
        return noErr
    }
}
