import XCTest
@testable import OpenflowMac

final class AudioDeviceAndPermissionsTests: XCTestCase {

    func testAudioInputDeviceModel() {
        let dev1 = AudioInputDevice(id: "built-in-1", name: "MacBook Pro Microphone", isDefault: true)
        let dev2 = AudioInputDevice(id: "built-in-1", name: "MacBook Pro Microphone", isDefault: true)
        let dev3 = AudioInputDevice(id: "usb-2", name: "Yeti Stereo Microphone", isDefault: false)

        XCTAssertEqual(dev1, dev2)
        XCTAssertNotEqual(dev1, dev3)
        XCTAssertEqual(dev1.id, "built-in-1")
        XCTAssertEqual(dev1.name, "MacBook Pro Microphone")
        XCTAssertTrue(dev1.isDefault)
        XCTAssertFalse(dev3.isDefault)
    }

    func testAudioDeviceManagerEnumerationAndSelection() {
        let manager = AudioDeviceManager.shared
        manager.refreshDevices()

        // Should have at least one device (either real or fallback default)
        XCTAssertFalse(manager.availableDevices.isEmpty)

        let initialDeviceName = manager.currentDeviceName
        XCTAssertFalse(initialDeviceName.isEmpty)

        // Test selecting default
        manager.selectDevice(id: "default")
        XCTAssertEqual(manager.selectedDeviceID, "default")

        // Test selecting a specific device ID
        if let first = manager.availableDevices.first {
            manager.selectDevice(id: first.id)
            XCTAssertEqual(manager.selectedDeviceID, first.id)
            XCTAssertEqual(manager.currentDeviceName, first.name)
        }

        // Restore default
        manager.selectDevice(id: "default")
        XCTAssertEqual(manager.selectedDeviceID, "default")
    }

    func testAppPermissionStatusEnum() {
        XCTAssertTrue(AppPermissionStatus.granted.isGranted)
        XCTAssertFalse(AppPermissionStatus.denied.isGranted)
        XCTAssertFalse(AppPermissionStatus.notDetermined.isGranted)
        XCTAssertFalse(AppPermissionStatus.restricted.isGranted)

        XCTAssertEqual(AppPermissionStatus.granted.rawValue, "Granted")
        XCTAssertEqual(AppPermissionStatus.denied.rawValue, "Denied")
        XCTAssertEqual(AppPermissionStatus.notDetermined.rawValue, "Not Requested")
        XCTAssertEqual(AppPermissionStatus.restricted.rawValue, "Restricted")
    }

    func testPermissionsManagerStatusCheck() {
        let manager = PermissionsManager.shared
        manager.refreshStatuses()

        // Verify status fields are populated
        XCTAssertNotNil(manager.microphoneStatus)
        XCTAssertNotNil(manager.accessibilityStatus)
        XCTAssertNotNil(manager.speechRecognitionStatus)

        let expectedAllGranted = (manager.microphoneStatus == .granted && manager.accessibilityStatus == .granted)
        XCTAssertEqual(manager.allRequiredPermissionsGranted, expectedAllGranted)
    }

    func testMenuBarPopoverStateAudioAndPermissionProperties() {
        let state = MenuBarPopoverState()

        XCTAssertEqual(state.selectedMicrophoneID, "default")
        XCTAssertEqual(state.currentMicrophoneName, "Built-in Microphone")
        XCTAssertTrue(state.isMicrophonePermissionGranted)
        XCTAssertTrue(state.isAccessibilityPermissionGranted)

        state.currentMicrophoneName = "Blue Yeti USB"
        state.selectedMicrophoneID = "usb-mic-123"
        state.availableMicrophones = [
            AudioInputDevice(id: "default", name: "Internal Mic", isDefault: true),
            AudioInputDevice(id: "usb-mic-123", name: "Blue Yeti USB", isDefault: false)
        ]
        state.isMicrophonePermissionGranted = false

        XCTAssertEqual(state.currentMicrophoneName, "Blue Yeti USB")
        XCTAssertEqual(state.selectedMicrophoneID, "usb-mic-123")
        XCTAssertEqual(state.availableMicrophones.count, 2)
        XCTAssertFalse(state.isMicrophonePermissionGranted)

        var selectedID: String?
        state.onSelectMicrophone = { id in
            selectedID = id
        }
        state.onSelectMicrophone?("usb-mic-123")
        XCTAssertEqual(selectedID, "usb-mic-123")
    }
}
