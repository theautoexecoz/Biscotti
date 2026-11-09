import AudioCapture
import Foundation
import Synchronization

/// Persistence seam for the microphone chosen in Settings.
///
/// Device-local by design: a mic's Core Audio UID only means something on
/// this Mac, so the choice lives in `UserDefaults` and never in the synced
/// SwiftData `AppSettings` (same reasoning as `SystemAudioPermissionStore`).
/// `nil` means "follow the macOS default input".
public protocol MicInputStore: Sendable {
    func load() -> AudioInputDevice?
    func save(_ device: AudioInputDevice?)
}

/// Production store backed by `UserDefaults`. Stores the UID plus the last
/// known name, so a disconnected choice can still be named in the UI.
public struct UserDefaultsMicInputStore: MicInputStore, @unchecked Sendable {
    private let defaults: UserDefaults
    static let uidKey = "micInputDeviceUID"
    static let nameKey = "micInputDeviceName"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AudioInputDevice? {
        guard let uid = defaults.string(forKey: Self.uidKey), !uid.isEmpty else { return nil }
        let name = defaults.string(forKey: Self.nameKey) ?? uid
        return AudioInputDevice(uid: uid, name: name)
    }

    public func save(_ device: AudioInputDevice?) {
        if let device {
            defaults.set(device.uid, forKey: Self.uidKey)
            defaults.set(device.name, forKey: Self.nameKey)
        } else {
            defaults.removeObject(forKey: Self.uidKey)
            defaults.removeObject(forKey: Self.nameKey)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryMicInputStore: MicInputStore, Sendable {
    private let device: Mutex<AudioInputDevice?>

    public init(_ device: AudioInputDevice? = nil) {
        self.device = Mutex(device)
    }

    public func load() -> AudioInputDevice? {
        device.withLock { $0 }
    }

    public func save(_ newValue: AudioInputDevice?) {
        device.withLock { $0 = newValue }
    }
}
