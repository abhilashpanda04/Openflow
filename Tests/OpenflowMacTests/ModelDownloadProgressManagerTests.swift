import XCTest
@testable import OpenflowMac

final class ModelDownloadProgressManagerTests: XCTestCase {
    private var manager: ModelDownloadProgressManager!

    override func setUp() {
        super.setUp()
        manager = ModelDownloadProgressManager.shared
    }

    func testStartAndProgressUpdates() {
        manager.start(modelName: "nvidia_parakeet-tdt-0.6b", displayName: "Parakeet TDT 0.6B")
        
        let startExpectation = expectation(description: "manager started")
        DispatchQueue.main.async {
            XCTAssertTrue(self.manager.isDownloading)
            XCTAssertEqual(self.manager.modelName, "nvidia_parakeet-tdt-0.6b")
            XCTAssertEqual(self.manager.modelDisplayName, "Parakeet TDT 0.6B")
            XCTAssertEqual(self.manager.statusMessage, "Starting download...")
            XCTAssertEqual(self.manager.progress, 0.05)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        manager.update(progress: 0.45, message: "Downloading weights 45%")
        let updateExpectation = expectation(description: "manager updated")
        DispatchQueue.main.async {
            XCTAssertTrue(self.manager.isDownloading)
            XCTAssertEqual(self.manager.progress, 0.45)
            XCTAssertEqual(self.manager.statusMessage, "Downloading weights 45%")
            updateExpectation.fulfill()
        }
        wait(for: [updateExpectation], timeout: 1.0)

        manager.finish()
        let finishExpectation = expectation(description: "manager finished")
        DispatchQueue.main.async {
            XCTAssertEqual(self.manager.progress, 1.0)
            XCTAssertEqual(self.manager.statusMessage, "Ready")
            finishExpectation.fulfill()
        }
        wait(for: [finishExpectation], timeout: 1.0)
    }

    func testFailureHandling() {
        manager.start(modelName: "test_model", displayName: "Test Model")
        manager.fail(error: "Network connection lost")

        let failExpectation = expectation(description: "manager failed")
        DispatchQueue.main.async {
            XCTAssertFalse(self.manager.isDownloading)
            XCTAssertEqual(self.manager.statusMessage, "Failed: Network connection lost")
            failExpectation.fulfill()
        }
        wait(for: [failExpectation], timeout: 1.0)
    }
}
