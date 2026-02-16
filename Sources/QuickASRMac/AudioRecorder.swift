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
                        .appendingPathComponent("quickasr-\(UUID().uuidString).wav")

                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 16_000,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                    ]

                    let recorder = try AVAudioRecorder(url: url, settings: settings)
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

    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        return currentFileURL
    }
}
