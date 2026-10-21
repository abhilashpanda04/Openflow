import XCTest
@testable import OpenflowMac

final class ModelStorageManagerTests: XCTestCase {
    func testModelStorageManagerSharedInstance() {
        let manager = ModelStorageManager.shared
        XCTAssertNotNil(manager)
    }

    func testIsWhisperModelDownloadedDoesNotCrash() {
        let manager = ModelStorageManager.shared
        manager.refresh()
        for choice in WhisperModelChoice.allCases {
            _ = manager.isWhisperModelDownloaded(choice)
        }
    }

    func testOffloadMethodsDoNotCrash() {
        let manager = ModelStorageManager.shared
        manager.offloadSpeechEngine()
        manager.offloadReaderEngine()
        manager.offloadAll()
        XCTAssertEqual(manager.lastActionNotice, "All models offloaded from memory")
    }

    func testKokoroEngineOffloadAndInMemory() {
        let engine = KokoroTTSEngine.shared
        engine.offload()
        XCTAssertFalse(engine.isLoadedInMemory)
    }
}
