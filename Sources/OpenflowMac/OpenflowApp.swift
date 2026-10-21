import SwiftUI

@main
struct OpenflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Openflow", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}
