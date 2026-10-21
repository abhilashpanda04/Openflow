import AVFoundation
import Foundation

// MARK: - Silence Trim Result

public struct SilenceTrimResult: Equatable {
    public let trimmedURL: URL
    public let didTrim: Bool
    public let isAllSilence: Bool
    public let originalDurationSeconds: Double
    public let trimmedDurationSeconds: Double

    public init(
        trimmedURL: URL,
        didTrim: Bool,
        isAllSilence: Bool,
        originalDurationSeconds: Double,
        trimmedDurationSeconds: Double
    ) {
        self.trimmedURL = trimmedURL
        self.didTrim = didTrim
        self.isAllSilence = isAllSilence
        self.originalDurationSeconds = originalDurationSeconds
        self.trimmedDurationSeconds = trimmedDurationSeconds
    }
}

// MARK: - Audio Silence Processor

public enum AudioSilenceProcessor {
    /// Trims leading and trailing silence from an audio WAV file.
    /// - Parameters:
    ///   - audioFileURL: The source audio file URL (16kHz 16-bit mono Linear PCM)
    ///   - thresholdDb: Decibel cutoff below which audio is treated as silence (e.g. -38.0 dB)
    ///   - paddingMs: Padding in milliseconds preserved before and after speech to avoid clipping
    /// - Returns: SilenceTrimResult with trimmed URL and duration info
    public static func trimSilence(
        audioFileURL: URL,
        thresholdDb: Float = -38.0,
        paddingMs: Double = 120.0
    ) -> SilenceTrimResult {
        do {
            let file = try AVAudioFile(forReading: audioFileURL)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)

            let sampleRate = format.sampleRate
            let originalDuration = sampleRate > 0 ? Double(frameCount) / sampleRate : 0.0

            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return SilenceTrimResult(
                    trimmedURL: audioFileURL,
                    didTrim: false,
                    isAllSilence: true,
                    originalDurationSeconds: originalDuration,
                    trimmedDurationSeconds: 0.0
                )
            }

            try file.read(into: buffer)

            guard let channelData = buffer.floatChannelData?[0] else {
                return SilenceTrimResult(
                    trimmedURL: audioFileURL,
                    didTrim: false,
                    isAllSilence: false,
                    originalDurationSeconds: originalDuration,
                    trimmedDurationSeconds: originalDuration
                )
            }

            // Convert threshold in dB to linear amplitude
            let linearThreshold = pow(10.0, thresholdDb / 20.0)

            // Evaluate in 10ms chunk windows (e.g., 160 samples at 16kHz)
            let windowSize = max(16, Int(sampleRate * 0.010))
            let totalWindows = Int(frameCount) / windowSize

            var firstSpeechWindow: Int?
            var lastSpeechWindow: Int?

            for w in 0..<totalWindows {
                let offset = w * windowSize
                let limit = min(offset + windowSize, Int(frameCount))
                var peak: Float = 0.0

                for i in offset..<limit {
                    let absVal = abs(channelData[i])
                    if absVal > peak {
                        peak = absVal
                    }
                }

                if peak >= linearThreshold {
                    if firstSpeechWindow == nil {
                        firstSpeechWindow = w
                    }
                    lastSpeechWindow = w
                }
            }

            // Check if entire audio is silent
            guard let firstW = firstSpeechWindow, let lastW = lastSpeechWindow else {
                return SilenceTrimResult(
                    trimmedURL: audioFileURL,
                    didTrim: false,
                    isAllSilence: true,
                    originalDurationSeconds: originalDuration,
                    trimmedDurationSeconds: 0.0
                )
            }

            // Calculate padding in terms of windows
            let paddingWindows = max(1, Int(ceil((paddingMs / 1000.0) / 0.010)))
            let startFrame = max(0, (firstW - paddingWindows) * windowSize)
            let endFrame = min(Int(frameCount), (lastW + 1 + paddingWindows) * windowSize)
            let trimmedFrameCount = AVAudioFrameCount(endFrame - startFrame)

            let trimmedDuration = sampleRate > 0 ? Double(trimmedFrameCount) / sampleRate : 0.0

            // If trimming saves less than 150ms total, keep original file
            let durationSaved = originalDuration - trimmedDuration
            if durationSaved < 0.15 || trimmedFrameCount >= frameCount {
                return SilenceTrimResult(
                    trimmedURL: audioFileURL,
                    didTrim: false,
                    isAllSilence: false,
                    originalDurationSeconds: originalDuration,
                    trimmedDurationSeconds: originalDuration
                )
            }

            // Create trimmed PCM buffer
            guard let trimmedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: trimmedFrameCount) else {
                return SilenceTrimResult(
                    trimmedURL: audioFileURL,
                    didTrim: false,
                    isAllSilence: false,
                    originalDurationSeconds: originalDuration,
                    trimmedDurationSeconds: originalDuration
                )
            }

            trimmedBuffer.frameLength = trimmedFrameCount
            if let dest = trimmedBuffer.floatChannelData?[0] {
                dest.initialize(from: channelData.advanced(by: startFrame), count: Int(trimmedFrameCount))
            }

            // Write trimmed buffer to temporary WAV file matching disk format
            let trimmedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("openflow-trimmed-\(UUID().uuidString).wav")

            let outputFile = try AVAudioFile(
                forWriting: trimmedURL,
                settings: file.fileFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: trimmedBuffer)

            return SilenceTrimResult(
                trimmedURL: trimmedURL,
                didTrim: true,
                isAllSilence: false,
                originalDurationSeconds: originalDuration,
                trimmedDurationSeconds: trimmedDuration
            )
        } catch {
            return SilenceTrimResult(
                trimmedURL: audioFileURL,
                didTrim: false,
                isAllSilence: false,
                originalDurationSeconds: 0.0,
                trimmedDurationSeconds: 0.0
            )
        }
    }
}
