import XCTest
@testable import OpenflowMac

final class MockTTSEngine: TTSEngineProtocol {
    var availableVoices: [TTSVoice] = [
        TTSVoice(id: "mock.voice.1", name: "Mock Voice", language: "en-US", quality: .premium, gender: .female),
        TTSVoice(id: "mock.voice.2", name: "Mock Storyteller", language: "en-GB", quality: .enhanced, gender: .male)
    ]
    var currentVoice: TTSVoice?
    var playbackRate: Float = 1.0
    var pitchMultiplier: Float = 1.0
    var volume: Float = 1.0

    var speakCount = 0
    var lastSpokenSentence: String?
    var isPaused = false
    var isStopped = false
    var autoTriggerCompletion = false

    func speak(sentence: String, onWord: @escaping (NSRange) -> Void, onCompletion: @escaping () -> Void) {
        speakCount += 1
        lastSpokenSentence = sentence
        isStopped = false
        isPaused = false
        onWord(NSRange(location: 0, length: min(4, (sentence as NSString).length)))
        if autoTriggerCompletion {
            onCompletion()
        }
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func stop() {
        isStopped = true
    }
}

final class TextReaderTests: XCTestCase {
    // MARK: - TextChunker Tests

    func testEmptyTextChunking() {
        XCTAssertTrue(TextChunker.splitIntoSentences("").isEmpty)
        XCTAssertTrue(TextChunker.splitIntoSentences("   \n\t  ").isEmpty)
    }

    func testSingleSentenceChunking() {
        let text = "This is a single sentence without punctuation"
        let sentences = TextChunker.splitIntoSentences(text)
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences.first?.text, text)
    }

    func testBookParagraphChunking() {
        let text = """
        Call me Ishmael. Some years ago—never mind how long precisely—having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world. It is a way I have of driving off the spleen and regulating the circulation.
        """
        let sentences = TextChunker.splitIntoSentences(text)
        XCTAssertEqual(sentences.count, 3)
        XCTAssertEqual(sentences[0].text, "Call me Ishmael.")
        XCTAssertTrue(sentences[1].text.contains("Some years ago"))
        XCTAssertTrue(sentences[2].text.contains("It is a way I have"))
    }

    func testSentenceIDAndRange() {
        let text = "First sentence. Second sentence. Third sentence."
        let sentences = TextChunker.splitIntoSentences(text)
        XCTAssertEqual(sentences.count, 3)
        for (i, s) in sentences.enumerated() {
            XCTAssertEqual(s.id, i)
            XCTAssertGreaterThan(s.range.length, 0)
        }
    }

    // MARK: - ReaderManager Tests

    func testReaderManagerInitialState() {
        let mock = MockTTSEngine()
        let manager = ReaderManager(engine: mock)
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.sentences.count, 0)
        XCTAssertNil(manager.currentSentence)
        XCTAssertEqual(manager.progress, 0.0)
    }

    func testReaderManagerStartReading() {
        let mock = MockTTSEngine()
        let manager = ReaderManager(engine: mock)

        let bookExcerpt = "Chapter 1. It was the best of times. It was the worst of times."
        manager.startReading(text: bookExcerpt)

        XCTAssertEqual(manager.state, .playing)
        XCTAssertEqual(manager.sentences.count, 3)
        XCTAssertEqual(manager.currentSentenceIndex, 0)
        XCTAssertEqual(manager.currentSentence?.text, "Chapter 1.")
        XCTAssertEqual(mock.speakCount, 1)
        XCTAssertEqual(mock.lastSpokenSentence, "Chapter 1.")
        XCTAssertNotNil(manager.currentWordRange)
    }

    func testReaderManagerNavigation() {
        let mock = MockTTSEngine()
        let manager = ReaderManager(engine: mock)

        let bookExcerpt = "First sentence. Second sentence. Third sentence."
        manager.startReading(text: bookExcerpt)

        XCTAssertEqual(manager.currentSentenceIndex, 0)

        // Skip forward
        manager.skipForward()
        XCTAssertEqual(manager.currentSentenceIndex, 1)
        XCTAssertEqual(mock.lastSpokenSentence, "Second sentence.")

        // Skip forward again
        manager.skipForward()
        XCTAssertEqual(manager.currentSentenceIndex, 2)
        XCTAssertEqual(mock.lastSpokenSentence, "Third sentence.")

        // Skip beyond bounds
        manager.skipForward()
        XCTAssertEqual(manager.currentSentenceIndex, 2)

        // Skip backward
        manager.skipBackward()
        XCTAssertEqual(manager.currentSentenceIndex, 1)
        XCTAssertEqual(mock.lastSpokenSentence, "Second sentence.")

        // Seek directly
        manager.seek(to: 0)
        XCTAssertEqual(manager.currentSentenceIndex, 0)
        XCTAssertEqual(mock.lastSpokenSentence, "First sentence.")
    }

    func testReaderManagerPauseResumeStop() {
        let mock = MockTTSEngine()
        let manager = ReaderManager(engine: mock)

        manager.startReading(text: "Sentence one. Sentence two.")
        XCTAssertEqual(manager.state, .playing)

        manager.pause()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertTrue(mock.isPaused)

        manager.resume()
        XCTAssertEqual(manager.state, .playing)
        XCTAssertFalse(mock.isPaused)

        manager.stop()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertTrue(mock.isStopped)
        XCTAssertNil(manager.currentWordRange)
    }

    func testReaderManagerPlaybackRateAndVoice() {
        let mock = MockTTSEngine()
        let manager = ReaderManager(engine: mock)

        manager.playbackRate = 1.5
        XCTAssertEqual(mock.playbackRate, 1.5)

        let testVoice = TTSVoice(id: "custom.voice", name: "Custom Voice", language: "en-US", quality: .premium, gender: .female)
        manager.currentVoice = testVoice
        XCTAssertEqual(mock.currentVoice?.id, "custom.voice")
    }

    func testReaderManagerProgress() {
        let mock = MockTTSEngine()
        let manager = ReaderManager(engine: mock)

        manager.startReading(text: "One. Two. Three. Four.")
        XCTAssertEqual(manager.sentences.count, 4)

        XCTAssertEqual(manager.progress, 0.25)

        manager.skipForward()
        XCTAssertEqual(manager.progress, 0.5)

        manager.skipForward()
        XCTAssertEqual(manager.progress, 0.75)

        manager.skipForward()
        XCTAssertEqual(manager.progress, 1.0)
    }

    func testReaderManagerAutoProgression() {
        let mock = MockTTSEngine()
        mock.autoTriggerCompletion = true
        let manager = ReaderManager(engine: mock)

        manager.startReading(text: "The first sentence. The second sentence.")
        // When autoTriggerCompletion is true, Sentence 1 finishes immediately and transitions to Sentence 2,
        // and Sentence 2 finishes immediately and transitions to idle!
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(mock.speakCount, 2)
    }

    func testTTSVoiceDisplayName() {
        let v1 = TTSVoice(id: "1", name: "Ava", language: "en-US", quality: .premium, gender: .female)
        XCTAssertTrue(v1.displayName.contains("Ava"))
        XCTAssertTrue(v1.displayName.contains("Premium"))
        XCTAssertTrue(v1.displayName.contains("en-US"))

        let v2 = TTSVoice(id: "2", name: "Default", language: "en-US", quality: .standard, gender: .male)
        XCTAssertEqual(v2.displayName, "Default [en-US]")
    }
}
