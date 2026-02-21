import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hostingController = NSHostingController(rootView: SettingsView())
            let settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow.title = "Openflow Settings"
            settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow.setContentSize(NSSize(width: 620, height: 560))
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.center()
            window = settingsWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

#if DEBUG
extension SettingsWindowController {
    func _test_windowExists() -> Bool {
        window != nil
    }
}
#endif
