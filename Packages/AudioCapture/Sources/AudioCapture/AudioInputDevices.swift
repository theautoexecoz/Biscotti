import CoreAudio
import Foundation

/// A microphone (input-capable Core Audio device).
public struct AudioInputDevice: Sendable, Equatable, Hashable, Identifiable {
    /// Core Audio device UID (`kAudioDevicePropertyDeviceUID`).
    public let uid: String
    /// Human-readable name (e.g. "MacBook Pro Microphone").
    public let name: String

    public var id: String {
        uid
    }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// Input device queries for display.
public enum AudioInputDevices {
    /// The current macOS default input device, if any. Biscotti always
    /// records from this device.
    public static func systemDefault() -> AudioInputDevice? {
        guard let id = CoreAudioHelpers.defaultInputDeviceID(),
              id != kAudioObjectUnknown,
              let uid = CoreAudioHelpers.deviceUID(for: id)
        else { return nil }
        return AudioInputDevice(uid: uid, name: CoreAudioHelpers.deviceName(for: id) ?? uid)
    }
}

/// The device the mic engine is capturing from, for display and logs.
public struct MicInputStatus: Sendable, Equatable {
    /// Name of the device audio is being captured from.
    public let deviceName: String

    public init(deviceName: String) {
        self.deviceName = deviceName
    }
}
