import Foundation

final class RemoteServerASREngine: ASREngine {
    private let client: ASRClient
    private var ready: Bool = false

    var isReady: Bool { ready }
    var engineName: String { "Remote HTTP Backend" }
    var statusDescription: String { ready ? "Connected" : "Disconnected" }

    init(client: ASRClient) {
        self.client = client
    }

    func initialize(progress: ((Double, String) -> Void)? = nil) async throws {
        progress?(0.3, "Connecting to external backend...")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.checkHealth { [weak self] result in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                switch result {
                case .success(let health):
                    self.ready = health.modelLoaded
                    if health.modelLoaded {
                        progress?(1.0, "Connected")
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ASRClientError.serverError("Remote backend model not loaded."))
                    }
                case .failure(let err):
                    self.ready = false
                    continuation.resume(throwing: err)
                }
            }
        }
    }

    func transcribe(audioFileURL: URL, requestID: String) async throws -> TranscribeResponse {
        try await withCheckedThrowingContinuation { continuation in
            client.transcribe(audioFileURL: audioFileURL, requestID: requestID) { result in
                continuation.resume(with: result)
            }
        }
    }
}
