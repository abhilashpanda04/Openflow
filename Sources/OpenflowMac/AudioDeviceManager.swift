import AVFoundation
import CoreAudio
import Foundation

// MARK: - Audio Input Device Model

public struct AudioInputDevice: Identifiable, Hashable, Equatable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

// MARK: - Audio Device Manager

public final class AudioDeviceManager: ObservableObject {
    public static let shared = AudioDeviceManager()
    private static let selectedDeviceKey = "openflow.selected_microphone_id"

    @Published public var availableDevices: [AudioInputDevice] = []
    @Published public var selectedDeviceID: String = "default"

    public var currentDeviceName: String {
        if selectedDeviceID == "default" {
            if let def = availableDevices.first(where: { $0.isDefault }) {
                return "\(def.name) (Default)"
            }
            return "System Default Microphone"
        }
        return availableDevices.first(where: { $0.id == selectedDeviceID })?.name ?? "Default Microphone"
    }

    public init() {
        self.selectedDeviceID = UserDefaults.standard.string(forKey: Self.selectedDeviceKey) ?? "default"
        refreshDevices()
        registerNotifications()
    }

    public func refreshDevices() {
        var devices: [AudioInputDevice] = []

        let defaultDevice = AVCaptureDevice.default(for: .audio)
        let defaultID = defaultDevice?.uniqueID

        var deviceTypes: [AVCaptureDevice.DeviceType] = []
        if #available(macOS 14.0, *) {
            deviceTypes = [.microphone, .external]
        } else {
            deviceTypes = [.builtInMicrophone, .externalUnknown]
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )

        for device in discoverySession.devices {
            let isDef = (device.uniqueID == defaultID)
            devices.append(AudioInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: isDef
            ))
        }

        if devices.isEmpty {
            devices.append(AudioInputDevice(id: "default", name: "Built-in Microphone", isDefault: true))
        }

        self.availableDevices = devices
    }

    public func selectDevice(id: String) {
        selectedDeviceID = id
        UserDefaults.standard.set(id, forKey: Self.selectedDeviceKey)

        if id != "default" {
            // Apply input device to CoreAudio if an AudioDeviceID is resolved
            if let coreAudioID = getAudioDeviceID(forUID: id) {
                _ = setDefaultInputDevice(coreAudioID)
            }
        }
    }

    // MARK: - CoreAudio Device Helpers

    private func getAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return nil }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(), count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else { return nil }

        for dev in devices {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(dev, &uidAddress, 0, nil, &uidSize, &cfUID) == noErr,
               let deviceUID = cfUID?.takeRetainedValue() as String?, deviceUID == uid {
                return dev
            }
        }
        return nil
    }

    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var dev = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &dev
        )
        return err == noErr
    }

    private func registerNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDevices()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDevices()
        }
    }
}
