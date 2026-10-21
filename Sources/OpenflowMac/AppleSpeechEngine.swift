import Foundation
import Speech

enum AppleSpeechEngineState: Equatable {
    case uninitialized
    case unauthorized
    case ready
    case failed(String)
}

final class AppleSpeechEngine: ASREngine {
    private var state: AppleSpeechEngineState = .uninitialized
    private var recognizer: SFSpeechRecognizer?
    private let locale: Locale

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var engineName: String {
        "Apple Speech (\(recognizer?.locale.identifier ?? locale.identifier))"
    }

    var statusDescription: String {
        switch state {
        case .uninitialized:
            return "Not initialized"
        case .unauthorized:
            return "Speech Recognition permission required"
        case .ready:
            let onDevice = recognizer?.supportsOnDeviceRecognition == true ? " (On-Device)" : ""
            return "Ready (\(recognizer?.locale.identifier ?? "system")\(onDevice))"
        case .failed(let err):
            return "Failed: \(err)"
        }
    }

    init(locale: Locale = .current) {
        self.locale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    func initialize(progress: ((Double, String) -> Void)? = nil) async throws {
        progress?(0.2, "Checking Speech Recognition permissions...")

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }

        switch status {
        case .authorized:
            guard let rec = recognizer ?? SFSpeechRecognizer(locale: locale) else {
                state = .failed("No speech recognizer for locale \(locale.identifier)")
                throw ASRClientError.serverError("Apple Speech recognizer unavailable for current locale.")
            }
            self.recognizer = rec
            state = .ready
            progress?(1.0, "Apple Speech Ready")
        case .denied, .restricted:
            state = .unauthorized
            throw ASRClientError.serverError("Speech Recognition access denied. Enable it in System Settings > Privacy & Security > Speech Recognition.")
        case .notDetermined:
            state = .uninitialized
            throw ASRClientError.serverError("Speech Recognition authorization not determined.")
        @unknown default:
            state = .uninitialized
            throw ASRClientError.serverError("Unknown speech recognition authorization state.")
        }
    }

    func transcribe(audioFileURL: URL, requestID: String) async throws -> TranscribeResponse {
        if !isReady {
            try await initialize()
        }

        guard let rec = recognizer, rec.isAvailable else {
            throw ASRClientError.serverError("Apple Speech recognizer is currently unavailable.")
        }

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        if rec.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            rec.recognitionTask(with: request) { result, error in
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }

                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }

                if let result = result, result.isFinal {
                    hasResumed = true
                    let text = result.bestTranscription.formattedString
                    continuation.resume(returning: TranscribeResponse(
                        success: true,
                        language: rec.locale.identifier,
                        text: text,
                        error: nil
                    ))
                }
            }
        }
    }
}
