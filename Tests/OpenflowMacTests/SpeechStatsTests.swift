import XCTest
@testable import OpenflowMac

final class SpeechStatsTests: XCTestCase {
    private var testStore: TranscriptHistoryStore!

    override func setUp() {
        super.setUp()
        testStore = TranscriptHistoryStore()
        testStore.clear()
        testStore.resetStats()
    }

    override func tearDown() {
        testStore.clear()
        testStore.resetStats()
        super.tearDown()
    }

    func testInitialStatsEmpty() {
        let summary = testStore.statsSummary
        XCTAssertEqual(summary.totalWords, 0)
        XCTAssertEqual(summary.totalSessions, 0)
        XCTAssertEqual(summary.formattedTimeSaved, "< 1 min")
        XCTAssertEqual(summary.speakingSpeedWPM, 150)
        XCTAssertEqual(summary.dailyActivity.count, 7)
    }

    func testAddRecordCalculatesWordsAndPace() {
        let sentence = "The quick brown fox jumps over the lazy dog" // 9 words
        testStore.add(
            text: sentence,
            language: "en",
            engine: "Apple Speech",
            durationSeconds: 3.6, // 9 words in 3.6s = 150 WPM
            appName: "Cursor"
        )

        let summary = testStore.statsSummary
        XCTAssertEqual(summary.totalWords, 9)
        XCTAssertEqual(summary.totalSessions, 1)
        XCTAssertEqual(summary.wordsToday, 9)
        XCTAssertEqual(summary.sessionsToday, 1)
        XCTAssertEqual(summary.speakingSpeedWPM, 150)

        // Engine distribution
        XCTAssertFalse(summary.engineDistribution.isEmpty)
        XCTAssertEqual(summary.engineDistribution.first?.name, "Apple Speech")

        // Top apps distribution
        XCTAssertFalse(summary.topAppsDistribution.isEmpty)
        XCTAssertEqual(summary.topAppsDistribution.first?.name, "Cursor")
    }

    func testTimeSavedCalculation() {
        // 600 words:
        // Typing at 40 WPM takes 15 minutes.
        // Speaking at 150 WPM takes 4 minutes.
        // Saved: 11 minutes!
        let words = Array(repeating: "hello", count: 600).joined(separator: " ")
        testStore.add(text: words, engine: "Apple Speech")

        let summary = testStore.statsSummary
        XCTAssertEqual(summary.totalWords, 600)
        XCTAssertEqual(summary.formattedTimeSaved, "11 min")
    }

    func testTimeSavedFormattingHours() {
        // 4000 words:
        // Typing: 100 min. Speaking: 26.67 min.
        // Saved: 73.33 min = ~1.2 hrs
        let words = Array(repeating: "word", count: 4000).joined(separator: " ")
        testStore.add(text: words, engine: "Whisper")

        let summary = testStore.statsSummary
        XCTAssertEqual(summary.formattedTimeSaved, "1.2 hrs")
    }

    func testRecordVoiceAction() {
        testStore.recordVoiceAction("Select All")
        testStore.recordVoiceAction("Undo")

        let summary = testStore.statsSummary
        XCTAssertEqual(summary.totalCommands, 2)
    }

    func testResetStatsClearsAccumulation() {
        testStore.add(text: "Hello world testing reset stats", engine: "CoreML")
        XCTAssertGreaterThan(testStore.statsSummary.totalWords, 0)

        testStore.clear()
        testStore.resetStats()

        let summary = testStore.statsSummary
        XCTAssertEqual(summary.totalWords, 0)
        XCTAssertEqual(summary.totalSessions, 0)
    }

    func testTranscriptRecordBackwardsCompatibility() throws {
        // Legacy JSON without durationSeconds or appName
        let legacyJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "text": "Legacy transcript entry",
            "language": "en",
            "engine": "Legacy Engine",
            "timestamp": 751234567.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptRecord.self, from: legacyJSON)
        XCTAssertEqual(decoded.text, "Legacy transcript entry")
        XCTAssertEqual(decoded.engine, "Legacy Engine")
        XCTAssertNil(decoded.durationSeconds)
        XCTAssertNil(decoded.appName)
        XCTAssertEqual(decoded.wordCount, 3)
    }
}
