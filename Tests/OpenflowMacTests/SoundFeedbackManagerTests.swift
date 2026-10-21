import XCTest
@testable import OpenflowMac
import AppKit

final class SoundFeedbackManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: UserSettingKey.playFeedbackSounds)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserSettingKey.playFeedbackSounds)
        super.tearDown()
    }

    func testDefaultIsEnabled() {
        let manager = SoundFeedbackManager()
        XCTAssertTrue(manager.isSoundEnabled, "Feedback sounds should be enabled by default")
    }

    func testToggleSoundEnabled() {
        let manager = SoundFeedbackManager()
        manager.isSoundEnabled = false
        XCTAssertFalse(manager.isSoundEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserSettingKey.playFeedbackSounds))

        manager.isSoundEnabled = true
        XCTAssertTrue(manager.isSoundEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UserSettingKey.playFeedbackSounds))
    }

    func testSoundCuesResolveToValidSounds() {
        let manager = SoundFeedbackManager()

        let startSound = manager.soundForCue(.start)
        XCTAssertNotNil(startSound, "Start sound cue should resolve to a valid NSSound")

        let finishSound = manager.soundForCue(.finish)
        XCTAssertNotNil(finishSound, "Finish sound cue should resolve to a valid NSSound")

        let cancelSound = manager.soundForCue(.cancel)
        XCTAssertNotNil(cancelSound, "Cancel sound cue should resolve to a valid NSSound")
    }

    func testPlayDoesNotCrashWhenEnabledOrDisabled() {
        let manager = SoundFeedbackManager()

        manager.isSoundEnabled = true
        manager.play(.start)
        manager.play(.finish)
        manager.play(.cancel)

        manager.isSoundEnabled = false
        manager.play(.start)
        manager.play(.finish)
        manager.play(.cancel)
    }
}
