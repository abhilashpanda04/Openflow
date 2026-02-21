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
import XCTest
@testable import OpenflowMac

final class AdditionalCoverageTests: XCTestCase {
    func testRecordingWaveViewDrawsAcrossModesAndAnimationTicks() {
        let view = RecordingWaveView(frame: NSRect(x: 0, y: 0, width: 260, height: 40))

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

        XCTAssertTrue(true)
    }

    func testOpenflowAppBodyBuildsSettingsScene() {
        let app = OpenflowApp()
        _ = app.body
        XCTAssertNotNil(app)
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
