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
