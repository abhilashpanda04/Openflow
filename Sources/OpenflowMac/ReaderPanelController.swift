import AppKit
import SwiftUI

public final class ReaderPanelController {
    public static let shared = ReaderPanelController()

    private var panel: NSPanel?

    private init() {}

    public func show(text: String? = nil) {
        ensurePanel()

        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ReaderManager.shared.startReading(text: text)
        }

        positionPanel()
        panel?.orderFrontRegardless()
    }

    public func hide() {
        ReaderManager.shared.stop()
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        if panel != nil { return }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true

        let rootView = ReaderMiniPlayerView(manager: .shared) { [weak self] in
            self?.hide()
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 90)
        p.contentView = hostingView

        self.panel = p
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 90

        // Place 40pt above bottom of visible screen
        let x = visibleFrame.origin.x + (visibleFrame.width - panelWidth) / 2.0
        let y = visibleFrame.origin.y + 40.0

        panel?.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
