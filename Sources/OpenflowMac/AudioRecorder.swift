import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case micPermissionDenied
    case recorderCreationFailed

    var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            return "Microphone permission was denied."
        case .recorderCreationFailed:
            return "Failed to create audio recorder."
        }
    }
}

final class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var currentFileURL: URL?

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                guard granted else {
                    completion(.failure(AudioRecorderError.micPermissionDenied))
                    return
                }

                do {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("openflow-\(UUID().uuidString).wav")

                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 16_000,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                    ]

                    let recorder = try AVAudioRecorder(url: url, settings: settings)
                    recorder.isMeteringEnabled = true
                    recorder.prepareToRecord()
                    recorder.record()

                    self.recorder = recorder
                    self.currentFileURL = url

                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func currentAudioLevel() -> Float {
        guard let recorder = recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let clamped = max(-50.0, min(0.0, power))
        return Float((clamped + 50.0) / 50.0)
    }

    func currentAudioPowerDb() -> Float {
        guard let recorder = recorder, recorder.isRecording else { return -160.0 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }

    func stop() -> URL? {
        guard let url = currentFileURL else { return nil }
        recorder?.stop()
        recorder = nil
        currentFileURL = nil
        return url
    }
}
