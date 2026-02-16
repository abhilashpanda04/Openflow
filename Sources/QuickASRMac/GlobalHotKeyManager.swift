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
            case "return", "enter":
                keyCode = UInt32(kVK_Return)
            case "tab":
                keyCode = UInt32(kVK_Tab)
            default:
                if token.count == 1, let first = token.first {
                    keyCode = keyCodeForCharacter(first)
                }
            }
        }

        guard let parsedKeyCode = keyCode, modifiers != 0 else {
            return .default
        }

        return HotKeyConfiguration(
            keyCode: parsedKeyCode,
            modifiers: modifiers,
            displayText: value
        )
    }

    private static func keyCodeForCharacter(_ value: Character) -> UInt32? {
        let mapping: [Character: UInt32] = [
            "a": UInt32(kVK_ANSI_A),
            "b": UInt32(kVK_ANSI_B),
            "c": UInt32(kVK_ANSI_C),
            "d": UInt32(kVK_ANSI_D),
            "e": UInt32(kVK_ANSI_E),
            "f": UInt32(kVK_ANSI_F),
            "g": UInt32(kVK_ANSI_G),
            "h": UInt32(kVK_ANSI_H),
            "i": UInt32(kVK_ANSI_I),
            "j": UInt32(kVK_ANSI_J),
            "k": UInt32(kVK_ANSI_K),
            "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M),
            "n": UInt32(kVK_ANSI_N),
            "o": UInt32(kVK_ANSI_O),
            "p": UInt32(kVK_ANSI_P),
            "q": UInt32(kVK_ANSI_Q),
            "r": UInt32(kVK_ANSI_R),
            "s": UInt32(kVK_ANSI_S),
            "t": UInt32(kVK_ANSI_T),
            "u": UInt32(kVK_ANSI_U),
            "v": UInt32(kVK_ANSI_V),
            "w": UInt32(kVK_ANSI_W),
            "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y),
            "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0),
            "1": UInt32(kVK_ANSI_1),
            "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4),
            "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6),
            "7": UInt32(kVK_ANSI_7),
            "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
        ]

        return mapping[value]
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
