import Foundation

protocol ASREngine: AnyObject {
    var isReady: Bool { get }
    var engineName: String { get }
    var statusDescription: String { get }

    func initialize(progress: ((Double, String) -> Void)?) async throws
    func transcribe(audioFileURL: URL, requestID: String) async throws -> TranscribeResponse
}

extension ASREngine {
    func initialize() async throws {
        try await initialize(progress: nil)
    }
}
