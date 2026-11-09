import CoreAudio
import Foundation

/// A microphone (input-capable Core Audio device) the user can record from.
///
/// Identified by its Core Audio **UID**, which is stable across reboots and
/// reconnects. `AudioObjectID`s are reassigned when a device reappears, so
/// they are never persisted.
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

/// Enumerates input devices and resolves saved UIDs to live device IDs.
public enum AudioInputDevices {
    /// Every device with at least one input channel, in Core Audio order.
    /// Private aggregate devices created by voice processing are excluded.
    public static func available() -> [AudioInputDevice] {
        inputDeviceIDs().compactMap { id in
            guard let uid = CoreAudioHelpers.deviceUID(for: id) else { return nil }
            let name = CoreAudioHelpers.deviceName(for: id) ?? uid
            return AudioInputDevice(uid: uid, name: name)
        }
    }

    /// The current macOS default input device, if any.
    public static func systemDefault() -> AudioInputDevice? {
        guard let id = CoreAudioHelpers.defaultInputDeviceID(),
              id != kAudioObjectUnknown,
              let uid = CoreAudioHelpers.deviceUID(for: id)
        else { return nil }
        return AudioInputDevice(uid: uid, name: CoreAudioHelpers.deviceName(for: id) ?? uid)
    }

    /// Live input candidates as (UID, ID) pairs for `InputDeviceResolver`.
    static func candidates() -> [InputDeviceCandidate] {
        inputDeviceIDs().compactMap { id in
            guard let uid = CoreAudioHelpers.deviceUID(for: id) else { return nil }
            return InputDeviceCandidate(uid: uid, id: id)
        }
    }

    private static func inputDeviceIDs() -> [AudioObjectID] {
        let all = CoreAudioHelpers.getPropertyArray(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            type: AudioObjectID.self
        )
        return all.filter { id in
            guard let channels = CoreAudioHelpers.channelCount(
                for: id, scope: kAudioObjectPropertyScopeInput
            ), channels > 0 else { return false }
            let name = CoreAudioHelpers.deviceName(for: id) ?? ""
            return !name.hasPrefix("CADefaultDeviceAggregate")
        }
    }
}

/// A live input device: its persistent UID and its current object ID.
struct InputDeviceCandidate: Sendable, Equatable {
    let uid: String
    let id: AudioObjectID
}

/// Which device the mic engine should bind to for this build.
enum InputDeviceSelection: Sendable, Equatable {
    /// No preference saved: follow the macOS default input (original behaviour).
    case systemDefault
    /// The preferred device is connected; bind to this object ID.
    case preferred(AudioObjectID)
    /// A preference is saved but that device is not connected. Fall back to
    /// the system default and report it visibly.
    case preferredUnavailable
}

/// Pure UID → device resolution, separated from Core Audio for testing.
enum InputDeviceResolver {
    static func resolve(
        preferredUID: String?,
        candidates: [InputDeviceCandidate]
    ) -> InputDeviceSelection {
        guard let preferredUID, !preferredUID.isEmpty else { return .systemDefault }
        guard let match = candidates.first(where: { $0.uid == preferredUID }) else {
            return .preferredUnavailable
        }
        return .preferred(match.id)
    }
}

/// What the mic engine is actually recording from, for display and logs.
public struct MicInputStatus: Sendable, Equatable {
    public enum Binding: Sendable, Equatable {
        /// Following the macOS default input (no device chosen in Settings).
        case systemDefault
        /// Recording from the device chosen in Settings.
        case selected
        /// The chosen device was bound, but Core Audio did not report it
        /// running after start. Audio may be coming from another device.
        case selectedUnconfirmed
        /// The chosen device is not connected (or could not be bound);
        /// recording from the system default instead.
        case selectedUnavailable
    }

    /// Name of the device audio is being captured from.
    public let deviceName: String
    /// Name of the device chosen in Settings, when one is chosen.
    public let requestedName: String?
    public let binding: Binding

    public init(deviceName: String, requestedName: String?, binding: Binding) {
        self.deviceName = deviceName
        self.requestedName = requestedName
        self.binding = binding
    }

    /// `true` when the user should be warned that the chosen mic is not in use.
    public var needsAttention: Bool {
        binding == .selectedUnavailable || binding == .selectedUnconfirmed
    }
}

// MARK: - Core Audio helpers for device binding

extension CoreAudioHelpers {
    /// `true` while any process (including us) has IO running on the device.
    static func isRunningSomewhere(_ deviceID: AudioObjectID) -> Bool? {
        let value: UInt32? = getPropertyData(
            objectID: deviceID,
            address: AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            type: UInt32.self
        )
        return value.map { $0 != 0 }
    }
}
