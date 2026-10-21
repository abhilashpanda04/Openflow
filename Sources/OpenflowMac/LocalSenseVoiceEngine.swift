import Foundation
import CoreML
import FluidAudio

enum LocalSenseVoiceEngineState: Equatable {
    case uninitialized
    case downloading(Double, String)
    case loading(String)
    case ready
    case failed(String)
}

final class LocalSenseVoiceEngine: ASREngine {
    private var senseVoiceManager: SenseVoiceManager?
    private var state: LocalSenseVoiceEngineState = .uninitialized
    private let modelName: String

    var isReady: Bool {
        if case .ready = state, senseVoiceManager != nil { return true }
        return false
    }

    var engineName: String {
        "SenseVoice CoreML (\(modelName))"
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

    init(modelName: String = "qwen_qwen3-asr-0.6b") {
        self.modelName = modelName
    }

    func initialize(progress: ((Double, String) -> Void)? = nil) async throws {
        if case .ready = state, senseVoiceManager != nil {
            return
        }
        state = .loading("Initializing SenseVoice CoreML...")
        progress?(0.15, "Preparing CoreML model: \(modelName)...")

        do {
            let manager = try await SenseVoiceManager.load(
                precision: .fp16,
                progressHandler: { p in
                    progress?(p.fractionCompleted, "Downloading CoreML weights (\(Int(p.fractionCompleted * 100))%)...")
                }
            )

            self.senseVoiceManager = manager
            self.state = .ready
            progress?(1.0, "CoreML Engine Ready")
        } catch {
            self.state = .failed(error.localizedDescription)
            throw error
        }
    }

    func transcribe(audioFileURL: URL, requestID: String) async throws -> TranscribeResponse {
        if senseVoiceManager == nil {
            try await initialize()
        }

        guard let manager = senseVoiceManager else {
            throw ASRClientError.serverError("CoreML SenseVoice engine failed to initialize.")
        }

        let converter = AudioConverter(sampleRate: Double(SenseVoiceConfig.sampleRate))
        let samples = try converter.resampleAudioFile(audioFileURL)
        let detailed = try await manager.transcribeDetailed(audio: samples)
        let fullText = detailed.text.trimmingCharacters(in: .whitespacesAndNewlines)

        return TranscribeResponse(
            success: true,
            language: detailed.language ?? "auto",
            text: fullText,
            error: nil
        )
    }
}
