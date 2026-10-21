import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?
    private var themeObserver: NSObjectProtocol?

    deinit {
        if let token = themeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func show() {
        if window == nil {
            let hostingController = NSHostingController(rootView: SettingsView())
            let settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow.title = "Openflow Settings"
            settingsWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            settingsWindow.titleVisibility = .hidden
            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.setContentSize(NSSize(width: 860, height: 620))
            settingsWindow.minSize = NSSize(width: 800, height: 520)
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.center()
            window = settingsWindow

            applyTheme(to: settingsWindow)

            themeObserver = NotificationCenter.default.addObserver(
                forName: .openflowThemeDidChange,
                object: nil,
                queue: .main
            ) { [weak self, weak settingsWindow] _ in
                if let win = settingsWindow {
                    self?.applyTheme(to: win)
                }
            }
        } else if let win = window {
            applyTheme(to: win)
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func applyTheme(to window: NSWindow) {
        let isDark = AppThemeManager.shared.isDark
        if isDark {
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(red: 0x11/255.0, green: 0x12/255.0, blue: 0x16/255.0, alpha: 1.0)
        } else {
            window.appearance = NSAppearance(named: .aqua)
            window.backgroundColor = NSColor(red: 0xf8/255.0, green: 0xfa/255.0, blue: 0xfc/255.0, alpha: 1.0)
        }
    }
}

#if DEBUG
extension SettingsWindowController {
    func _test_windowExists() -> Bool {
        window != nil
    }
}
#endif
