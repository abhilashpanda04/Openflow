import AppKit
import Carbon
import Foundation

struct HotKeyConfiguration {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayText: String
    let isModifierOnly: Bool

    init(keyCode: UInt32, modifiers: UInt32, displayText: String, isModifierOnly: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayText = displayText
        self.isModifierOnly = isModifierOnly
    }

    static let `default` = HotKeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey),
        displayText: "Cmd+Shift+Space",
        isModifierOnly: false
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
            case "f1":
                keyCode = UInt32(kVK_F1)
                displayKey = "F1"
            case "f2":
                keyCode = UInt32(kVK_F2)
                displayKey = "F2"
            case "f3":
                keyCode = UInt32(kVK_F3)
                displayKey = "F3"
            case "f4":
                keyCode = UInt32(kVK_F4)
                displayKey = "F4"
            case "f5":
                keyCode = UInt32(kVK_F5)
                displayKey = "F5"
            case "f6":
                keyCode = UInt32(kVK_F6)
                displayKey = "F6"
            case "f7":
                keyCode = UInt32(kVK_F7)
                displayKey = "F7"
            case "f8":
                keyCode = UInt32(kVK_F8)
                displayKey = "F8"
            case "f9":
                keyCode = UInt32(kVK_F9)
                displayKey = "F9"
            case "f10":
                keyCode = UInt32(kVK_F10)
                displayKey = "F10"
            case "f11":
                keyCode = UInt32(kVK_F11)
                displayKey = "F11"
            case "f12":
                keyCode = UInt32(kVK_F12)
                displayKey = "F12"
            case "right_option", "right-option", "rightoption":
                keyCode = UInt32(kVK_RightOption)
                displayKey = "Right Option"
            case "right_cmd", "right-cmd", "rightcommand":
                keyCode = 54
                displayKey = "Right ⌘"
            case "fn", "globe":
                keyCode = UInt32(kVK_Function)
                displayKey = "Fn"
            case "left_option", "left-option":
                keyCode = UInt32(kVK_Option)
                displayKey = "Left Option"
            case "left_cmd", "left-cmd":
                keyCode = UInt32(kVK_Command)
                displayKey = "Left ⌘"
            default:
                if token.count == 1, let first = token.first {
                    if let descriptor = keyDescriptorForCharacter(first) {
                        keyCode = descriptor.keyCode
                        displayKey = descriptor.displayKey
                    }
                }
            }
        }

        guard let parsedKeyCode = keyCode else {
            return .default
        }

        let isModifier = isModifierKey(parsedKeyCode)
        let isSingle = isAllowedSingleKey(parsedKeyCode)

        // For regular typing keys (like 'a' or 'space'), require at least one modifier
        if !isSingle && modifiers == 0 {
            return .default
        }

        let modifierDisplay = modifierDisplayParts(modifiers: modifiers)
        let finalDisplay: String
        if modifierDisplay.isEmpty {
            finalDisplay = displayKey ?? "Key"
        } else {
            finalDisplay = (modifierDisplay + [displayKey ?? "Key"]).joined(separator: "+")
        }

        return HotKeyConfiguration(
            keyCode: parsedKeyCode,
            modifiers: modifiers,
            displayText: finalDisplay,
            isModifierOnly: isModifier && modifiers == 0
        )
    }

    static func capture(from event: NSEvent) -> (storageValue: String, configuration: HotKeyConfiguration)? {
        let keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let modifiers = carbonModifiers(from: flags)

        // Case 1: Modifier-only single key (e.g. Right Option, Fn, etc.)
        if isModifierKey(keyCode) {
            guard let descriptor = keyDescriptorForKeyCode(keyCode) else { return nil }
            let config = HotKeyConfiguration(
                keyCode: descriptor.keyCode,
                modifiers: 0,
                displayText: descriptor.displayKey,
                isModifierOnly: true
            )
            return (descriptor.storageToken, config)
        }

        // Case 2: Allowed single key without modifiers (e.g. F1-F12)
        if modifiers == 0 {
            if isAllowedSingleKey(keyCode), let descriptor = keyDescriptorForKeyCode(keyCode) {
                let config = HotKeyConfiguration(
                    keyCode: descriptor.keyCode,
                    modifiers: 0,
                    displayText: descriptor.displayKey,
                    isModifierOnly: false
                )
                return (descriptor.storageToken, config)
            }
            return nil
        }

        // Case 3: Combination with modifiers (e.g. Cmd+Shift+Space, Option+Space)
        guard let descriptor = keyDescriptorForKeyCode(keyCode) else {
            return nil
        }

        let storageParts = modifierStorageParts(modifiers: modifiers) + [descriptor.storageToken]
        let displayParts = modifierDisplayParts(modifiers: modifiers) + [descriptor.displayKey]
        let display = displayParts.joined(separator: "+")

        let configuration = HotKeyConfiguration(
            keyCode: descriptor.keyCode,
            modifiers: modifiers,
            displayText: display,
            isModifierOnly: false
        )
        return (storageParts.joined(separator: "+"), configuration)
    }

    static func isAllowedSingleKey(_ keyCode: UInt32) -> Bool {
        switch keyCode {
        case UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
             UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
             UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
             UInt32(kVK_RightOption), 54, UInt32(kVK_Function),
             UInt32(kVK_Option), UInt32(kVK_Command), UInt32(kVK_Control), UInt32(kVK_RightControl):
            return true
        default:
            return false
        }
    }

    static func isModifierKey(_ keyCode: UInt32) -> Bool {
        switch keyCode {
        case UInt32(kVK_RightOption), 54, UInt32(kVK_Function),
             UInt32(kVK_Option), UInt32(kVK_Command), UInt32(kVK_Control), UInt32(kVK_RightControl):
            return true
        default:
            return false
        }
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
        switch keyCode {
        case UInt32(kVK_Space): return (keyCode, "space", "Space")
        case UInt32(kVK_Return): return (keyCode, "return", "Return")
        case UInt32(kVK_Tab): return (keyCode, "tab", "Tab")
        case UInt32(kVK_F1): return (keyCode, "f1", "F1")
        case UInt32(kVK_F2): return (keyCode, "f2", "F2")
        case UInt32(kVK_F3): return (keyCode, "f3", "F3")
        case UInt32(kVK_F4): return (keyCode, "f4", "F4")
        case UInt32(kVK_F5): return (keyCode, "f5", "F5")
        case UInt32(kVK_F6): return (keyCode, "f6", "F6")
        case UInt32(kVK_F7): return (keyCode, "f7", "F7")
        case UInt32(kVK_F8): return (keyCode, "f8", "F8")
        case UInt32(kVK_F9): return (keyCode, "f9", "F9")
        case UInt32(kVK_F10): return (keyCode, "f10", "F10")
        case UInt32(kVK_F11): return (keyCode, "f11", "F11")
        case UInt32(kVK_F12): return (keyCode, "f12", "F12")
        case UInt32(kVK_RightOption): return (keyCode, "right_option", "Right Option")
        case 54: return (keyCode, "right_cmd", "Right ⌘")
        case UInt32(kVK_Function): return (keyCode, "fn", "Fn")
        case UInt32(kVK_Option): return (keyCode, "left_option", "Left Option")
        case UInt32(kVK_Command): return (keyCode, "left_cmd", "Left ⌘")
        case UInt32(kVK_Control): return (keyCode, "ctrl", "Ctrl")
        case UInt32(kVK_RightControl): return (keyCode, "right_ctrl", "Right Ctrl")
        default:
            break
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
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isModifierPressed = false

    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void

    init(
        config: HotKeyConfiguration,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void = {}
    ) throws {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        Self.activeManager = self

        if config.isModifierOnly {
            setupModifierMonitoring(for: config)
        } else {
            try setupCarbonHotKey(for: config)
        }
    }

    convenience init(config: HotKeyConfiguration, onPress: @escaping () -> Void) throws {
        try self.init(config: config, onKeyDown: onPress, onKeyUp: {})
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
    }

    private func setupCarbonHotKey(for config: HotKeyConfiguration) throws {
        var eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))
        ]

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyCallback,
            2,
            &eventSpecs,
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

    private func setupModifierMonitoring(for config: HotKeyConfiguration) {
        let targetKeyCode = UInt16(config.keyCode)

        let handleFlags: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }
            guard event.keyCode == targetKeyCode else { return }

            let isDown = Self.isModifierActive(keyCode: targetKeyCode, flags: event.modifierFlags)
            if isDown && !self.isModifierPressed {
                self.isModifierPressed = true
                self.onKeyDown()
            } else if !isDown && self.isModifierPressed {
                self.isModifierPressed = false
                self.onKeyUp()
            }
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: handleFlags)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            handleFlags(event)
            return event
        }
    }

    private static func isModifierActive(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case UInt16(kVK_RightOption), UInt16(kVK_Option):
            return flags.contains(.option)
        case 54, UInt16(kVK_Command):
            return flags.contains(.command)
        case UInt16(kVK_Function):
            return flags.contains(.function)
        case UInt16(kVK_Control), UInt16(kVK_RightControl):
            return flags.contains(.control)
        default:
            return false
        }
    }

    private static let hotKeyCallback: EventHandlerUPP = { _, eventRef, _ in
        guard let eventRef else { return noErr }
        let kind = GetEventKind(eventRef)
        if kind == UInt32(kEventHotKeyPressed) {
            GlobalHotKeyManager.activeManager?.onKeyDown()
        } else if kind == UInt32(kEventHotKeyReleased) {
            GlobalHotKeyManager.activeManager?.onKeyUp()
        }
        return noErr
    }
}
