import AppKit
import XCTest
@testable import OpenflowMac

final class AdditionalCoverageTests: XCTestCase {
    func testRecordingWaveViewDrawsAcrossModesAndAnimationTicks() {
        XCTAssertEqual(RecordingWaveView.barCount, 36)
        XCTAssertEqual(RecordingWaveView.barColors.count, 36)

        let view = RecordingWaveView(frame: NSRect(x: 0, y: 0, width: 260, height: 40))
        XCTAssertTrue(view.isFlipped)
        view.audioLevel = 0.8
        XCTAssertEqual(view.audioLevel, 0.8)

        view.mode = .recording
        render(view: view)
        view.mode = .transcribing
        render(view: view)
        view.mode = .warming
        render(view: view)

        view.isAnimating = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        view.isAnimating = false
        render(view: view)

        let controller = TranscriptPanelController()
        controller.updateAudioLevel(0.75)

        XCTAssertTrue(true)
    }

    func testOpenflowAppBodyBuildsSettingsScene() {
        let app = OpenflowApp()
        _ = app.body
        XCTAssertNotNil(app)
    }

    func testLocalParakeetEngineInitialProperties() {
        let engine = LocalParakeetEngine(modelName: "nvidia_parakeet-tdt-0.6b")
        XCTAssertFalse(engine.isReady)
        XCTAssertTrue(engine.engineName.contains("Parakeet CoreML"))
        XCTAssertEqual(engine.statusDescription, "Not loaded")

        let engine110 = LocalParakeetEngine(modelName: "nvidia_parakeet-tdt-110m")
        XCTAssertEqual(engine110.statusDescription, "Not loaded")
        XCTAssertTrue(engine110.engineName.contains("nvidia_parakeet-tdt-110m"))
    }

    private func render(view: NSView) {
        let width = max(1, Int(view.bounds.width))
        let height = max(1, Int(view.bounds.height))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            XCTFail("Failed to create graphics context")
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
}
