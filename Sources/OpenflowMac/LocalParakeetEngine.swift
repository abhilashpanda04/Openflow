import Foundation
import CoreML
import FluidAudio

enum LocalParakeetEngineState: Equatable {
    case uninitialized
    case downloading(Double, String)
    case loading(String)
    case ready
    case failed(String)
}

final class LocalParakeetEngine: ASREngine {
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?
    private var state: LocalParakeetEngineState = .uninitialized
    private let modelName: String

    var isReady: Bool {
        if case .ready = state, asrManager != nil { return true }
        return false
    }

    var engineName: String {
        "FluidAudio Parakeet CoreML (\(modelName))"
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

    init(modelName: String = "nvidia_parakeet-tdt-0.6b") {
        self.modelName = modelName
    }

    private var targetVersion: AsrModelVersion {
        if modelName.contains("110m") {
            return .tdtCtc110m
        } else if modelName.contains("0.6b") {
            return .v3
        } else if modelName.contains("1.1b") {
            return .ultra
        } else {
            return .v3
        }
    }

    func initialize(progress: ((Double, String) -> Void)? = nil) async throws {
        if case .ready = state, asrManager != nil {
            return
        }
        state = .loading("Initializing Parakeet CoreML...")
        progress?(0.15, "Preparing CoreML model: \(modelName)...")

        do {
            let version = targetVersion
            let models = try await AsrModels.downloadAndLoad(
                version: version,
                progressHandler: { p in
                    progress?(p.fractionCompleted, "Downloading Parakeet CoreML weights (\(Int(p.fractionCompleted * 100))%)...")
                }
            )

            let manager = AsrManager(config: .default, models: models)
            self.asrModels = models
            self.asrManager = manager
            self.state = .ready
            progress?(1.0, "Parakeet CoreML Ready")
        } catch {
            self.state = .failed(error.localizedDescription)
            throw error
        }
    }

    func transcribe(audioFileURL: URL, requestID: String) async throws -> TranscribeResponse {
        if asrManager == nil || asrModels == nil {
            try await initialize()
        }

        guard let manager = asrManager, let models = asrModels else {
            throw ASRClientError.serverError("CoreML Parakeet engine failed to initialize.")
        }

        var decoderState = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
        let result = try await manager.transcribe(audioFileURL, decoderState: &decoderState)
        let fullText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        return TranscribeResponse(
            success: true,
            language: "en",
            text: fullText,
            error: nil
        )
    }
}
