import Foundation
import WhisperKit

enum LocalWhisperEngineState: Equatable {
    case uninitialized
    case downloading(Double, String)
    case loading(String)
    case ready
    case failed(String)
}

final class LocalWhisperEngine: ASREngine {
    private var whisperKit: WhisperKit?
    private var state: LocalWhisperEngineState = .uninitialized
    private let modelName: String

    var isReady: Bool {
        if case .ready = state, whisperKit != nil { return true }
        return false
    }

    var engineName: String {
        "WhisperKit CoreML (\(modelName))"
    }

    var statusDescription: String {
        switch state {
        case .uninitialized:
            return "Not loaded"
        case .downloading(let pct, let desc):
            return "Downloading (\(Int(pct * 100))%): \(desc)"
        case .loading(let step):
            return "Loading: \(step)"
        case .ready:
            return "Ready (\(modelName))"
        case .failed(let err):
            return "Failed: \(err)"
        }
    }

    init(modelName: String = "openai_whisper-tiny") {
        self.modelName = modelName
    }

    func initialize(progress: ((Double, String) -> Void)? = nil) async throws {
        if case .ready = state, whisperKit != nil {
            return
        }
        state = .loading("Initializing WhisperKit...")

        progress?(0.15, "Preparing CoreML model: \(modelName)...")

        do {
            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { p in
                    progress?(p.fractionCompleted, "Downloading Whisper CoreML weights (\(Int(p.fractionCompleted * 100))%)...")
                }
            )

            let pipe = try await WhisperKit(
                modelFolder: modelFolder.path,
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: false
            )

            self.whisperKit = pipe
            self.state = .ready

            progress?(1.0, "CoreML Engine Ready")
        } catch {
            self.state = .failed(error.localizedDescription)
            throw error
        }
    }

    func offload() {
        whisperKit = nil
        state = .uninitialized
    }

    func transcribe(audioFileURL: URL, requestID: String) async throws -> TranscribeResponse {
        if whisperKit == nil {
            try await initialize()
        }

        guard let pipe = whisperKit else {
            throw ASRClientError.serverError("CoreML WhisperKit engine failed to initialize.")
        }

        let results = try await pipe.transcribe(audioPath: audioFileURL.path)
        let fullText = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let detectedLang = results.first?.language ?? "en"

        return TranscribeResponse(
            success: true,
            language: detectedLang,
            text: fullText,
            error: nil
        )
    }
}
