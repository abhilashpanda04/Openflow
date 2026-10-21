import AVFoundation
import XCTest
@testable import OpenflowMac

final class AudioSilenceProcessorTests: XCTestCase {

    // Helper to generate a test WAV file with specified audio tones/silence
    private func createTestWavFile(sampleRate: Double = 16000, durationSeconds: Double, toneStartSeconds: Double?, toneDurationSeconds: Double?) -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let totalFrames = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        buffer.frameLength = totalFrames

        let channel = buffer.floatChannelData![0]

        // Zero out (silence)
        for i in 0..<Int(totalFrames) {
            channel[i] = 0.0
        }

        // Add 440Hz audible sine wave tone if specified
        if let toneStart = toneStartSeconds, let toneDuration = toneDurationSeconds {
            let startFrame = Int(toneStart * sampleRate)
            let toneFrames = Int(toneDuration * sampleRate)
            let endFrame = min(Int(totalFrames), startFrame + toneFrames)

            for i in startFrame..<endFrame {
                let t = Double(i - startFrame) / sampleRate
                // Sine wave tone with peak 0.40 (~ -8 dB, clearly above -38 dB silence threshold)
                channel[i] = Float(sin(2.0 * .pi * 440.0 * t) * 0.40)
            }
        }

        do {
            let file = try AVAudioFile(forWriting: tempURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        } catch {
            XCTFail("Failed to write test WAV file: \(error)")
        }

        return tempURL
    }

    func testSilenceSensitivityParsingAndThresholds() {
        XCTAssertEqual(SilenceSensitivity.low.thresholdDb, -30.0)
        XCTAssertEqual(SilenceSensitivity.medium.thresholdDb, -38.0)
        XCTAssertEqual(SilenceSensitivity.high.thresholdDb, -46.0)

        XCTAssertEqual(SilenceSensitivity.parse("low"), .low)
        XCTAssertEqual(SilenceSensitivity.parse("medium"), .medium)
        XCTAssertEqual(SilenceSensitivity.parse("high"), .high)
        XCTAssertEqual(SilenceSensitivity.parse("-30"), .low)
    }

    func testStopAfterSilenceChoiceParsingAndDurations() {
        XCTAssertEqual(StopAfterSilenceChoice.off.durationSeconds, 0.0)
        XCTAssertEqual(StopAfterSilenceChoice.oneSecond.durationSeconds, 1.0)
        XCTAssertEqual(StopAfterSilenceChoice.oneAndHalfSeconds.durationSeconds, 1.5)
        XCTAssertEqual(StopAfterSilenceChoice.twoSeconds.durationSeconds, 2.0)
        XCTAssertEqual(StopAfterSilenceChoice.threeSeconds.durationSeconds, 3.0)
        XCTAssertEqual(StopAfterSilenceChoice.fiveSeconds.durationSeconds, 5.0)

        XCTAssertEqual(StopAfterSilenceChoice.parse("off"), .off)
        XCTAssertEqual(StopAfterSilenceChoice.parse("2.0s"), .twoSeconds)
        XCTAssertEqual(StopAfterSilenceChoice.parse("1.5"), .oneAndHalfSeconds)
    }

    func testMaxRecordingDurationChoiceParsingAndDurations() {
        XCTAssertEqual(MaxRecordingDurationChoice.off.durationSeconds, 0.0)
        XCTAssertEqual(MaxRecordingDurationChoice.thirtySeconds.durationSeconds, 30.0)
        XCTAssertEqual(MaxRecordingDurationChoice.oneMinute.durationSeconds, 60.0)
        XCTAssertEqual(MaxRecordingDurationChoice.twoMinutes.durationSeconds, 120.0)
        XCTAssertEqual(MaxRecordingDurationChoice.fiveMinutes.durationSeconds, 300.0)
        XCTAssertEqual(MaxRecordingDurationChoice.tenMinutes.durationSeconds, 600.0)

        XCTAssertEqual(MaxRecordingDurationChoice.parse("unlimited"), .off)
        XCTAssertEqual(MaxRecordingDurationChoice.parse("60"), .oneMinute)
        XCTAssertEqual(MaxRecordingDurationChoice.parse("2m"), .twoMinutes)
    }

    func testAudioSilenceProcessorDetectsAllSilence() {
        // Create 2.0 seconds of pure silence
        let fileURL = createTestWavFile(durationSeconds: 2.0, toneStartSeconds: nil, toneDurationSeconds: nil)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = AudioSilenceProcessor.trimSilence(audioFileURL: fileURL, thresholdDb: -38.0)

        XCTAssertTrue(result.isAllSilence)
        XCTAssertFalse(result.didTrim)
    }

    func testAudioSilenceProcessorTrimsLeadingAndTrailingSilence() {
        // 4.0 seconds total: 1.0s silence, 1.5s tone, 1.5s silence
        let fileURL = createTestWavFile(durationSeconds: 4.0, toneStartSeconds: 1.0, toneDurationSeconds: 1.5)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = AudioSilenceProcessor.trimSilence(audioFileURL: fileURL, thresholdDb: -38.0, paddingMs: 100.0)

        XCTAssertFalse(result.isAllSilence)
        XCTAssertTrue(result.didTrim)
        XCTAssertNotEqual(result.trimmedURL, fileURL)
        defer { try? FileManager.default.removeItem(at: result.trimmedURL) }

        // Trimmed duration should be approximately 1.5s tone + ~200ms padding = ~1.7s (significantly less than 4.0s)
        XCTAssertLessThan(result.trimmedDurationSeconds, 2.5)
        XCTAssertGreaterThan(result.trimmedDurationSeconds, 1.4)
    }

    func testAudioSilenceProcessorPreservesAudioWhenNoTrimmingNeeded() {
        // Audio that fills the entire file from start to finish
        let fileURL = createTestWavFile(durationSeconds: 1.0, toneStartSeconds: 0.0, toneDurationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = AudioSilenceProcessor.trimSilence(audioFileURL: fileURL, thresholdDb: -38.0)

        XCTAssertFalse(result.isAllSilence)
        XCTAssertFalse(result.didTrim)
        XCTAssertEqual(result.trimmedURL, fileURL)
    }

    func testAppConfigDefaultsIncludeSilenceAndDuration() {
        let config = AppConfig.default
        XCTAssertEqual(config.recordingSilence.maxRecordingDuration, .twoMinutes)
        XCTAssertTrue(config.recordingSilence.skipSilenceBeforeTranscribing)
        XCTAssertEqual(config.recordingSilence.silenceSensitivity, .medium)
        XCTAssertEqual(config.recordingSilence.stopAfterSilence, .twoSeconds)
    }
}
