// Copyright 2025 Abhilash Panda
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
