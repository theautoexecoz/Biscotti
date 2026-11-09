import AppCore
import AudioCapture
import Foundation
import os
import Permissions
import Recording

/// One row in the microphone picker.
public struct MicrophoneChoice: Identifiable, Hashable, Sendable {
    /// `nil` = follow the macOS default input.
    public let device: AudioInputDevice?
    public let label: String
    /// `true` for a saved choice whose device is not connected.
    public let isDisconnected: Bool

    public var id: String {
        device?.uid ?? MicrophoneChoice.systemDefaultID
    }

    static let systemDefaultID = "system-default"
}

/// State for Settings → Microphone: device choice and a level test.
///
/// The choice is device-local (`MicInputStore`) and applies from the next
/// recording. The test runs a separate, non-voice-processed preview engine
/// and is unavailable while recording, when the recording page's meter
/// shows the real signal.
@MainActor @Observable
public final class MicrophoneSettingsViewModel {
    private let core: AppCore
    private let store: any MicInputStore
    private let listDevices: @Sendable () -> [AudioInputDevice]
    private let systemDefault: @Sendable () -> AudioInputDevice?
    private let monitor: InputLevelMonitor

    private static let logger = Logger(subsystem: "net.scosman.biscotti", category: "MicrophoneSettings")

    /// How long a level test runs before stopping itself.
    static let testDuration: Duration = .seconds(60)
    /// Meter refresh interval during a test.
    static let testRefresh: Duration = .milliseconds(50)

    public private(set) var choices: [MicrophoneChoice] = []
    public private(set) var selectedID: String = MicrophoneChoice.systemDefaultID
    public private(set) var isTesting = false
    /// Meter fill 0...1 during a test.
    public private(set) var testFraction: Double = 0
    /// Error from the last test start, shown inline.
    public private(set) var testError: String?

    private var testTask: Task<Void, Never>?

    public init(
        core: AppCore,
        store: any MicInputStore = UserDefaultsMicInputStore(),
        listDevices: @escaping @Sendable () -> [AudioInputDevice] = { AudioInputDevices.available() },
        systemDefault: @escaping @Sendable () -> AudioInputDevice? = { AudioInputDevices.systemDefault() },
        monitor: InputLevelMonitor = InputLevelMonitor()
    ) {
        self.core = core
        self.store = store
        self.listDevices = listDevices
        self.systemDefault = systemDefault
        self.monitor = monitor
    }

    /// Recording in progress: the test is disabled to avoid two engines on one mic.
    public var isRecording: Bool {
        core.recording.state.isRecording
    }

    /// Mic permission must be granted before a test can run.
    public var micAuthorized: Bool {
        core.permissions.microphone == .authorized
    }

    public var canTest: Bool {
        micAuthorized && !isRecording
    }

    /// Why the test button is disabled, or `nil`.
    public var testUnavailableReason: String? {
        if !micAuthorized { return "Grant microphone access to test." }
        if isRecording { return "Recording now. The recording page shows live levels." }
        return nil
    }

    /// Re-reads connected devices and the saved choice.
    public func refresh() {
        let saved = store.load()
        choices = Self.makeChoices(
            devices: listDevices(), systemDefault: systemDefault(), saved: saved
        )
        selectedID = saved?.uid ?? MicrophoneChoice.systemDefaultID
    }

    /// Saves a new choice. Applies from the next recording; restarts a running test.
    public func select(id: String) {
        guard let choice = choices.first(where: { $0.id == id }) else { return }
        store.save(choice.device)
        selectedID = choice.id
        Self.logger.notice("Mic input choice changed: \(choice.device == nil ? "system default" : "selected device", privacy: .public)")
        if isTesting { startTest() }
    }

    /// Starts (or restarts) the level test on the selected device.
    ///
    /// Each test task waits for its predecessor to finish, and a cancelled
    /// task leaves stopping to whoever cancelled it, so a restart can never
    /// have a late `stop()` from the old task kill the new preview.
    public func startTest() {
        guard canTest else { return }
        let previous = testTask
        previous?.cancel()
        testError = nil
        isTesting = true
        let device = choices.first(where: { $0.id == selectedID })?.device
        let monitor = monitor
        testTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await monitor.start(device: device)
            } catch {
                guard let self, !Task.isCancelled else { return }
                testError = error.localizedDescription
                isTesting = false
                testFraction = 0
                return
            }
            let deadline = ContinuousClock.now + Self.testDuration
            while !Task.isCancelled, ContinuousClock.now < deadline {
                let level = monitor.meter.read()
                self?.testFraction = AudioLevel.meterFraction(fromLinear: level.peak)
                if self?.isRecording ?? true { break }
                try? await Task.sleep(for: Self.testRefresh)
            }
            guard !Task.isCancelled else { return }
            await monitor.stop()
            self?.isTesting = false
            self?.testFraction = 0
        }
    }

    /// Stops the test. Called on toggle and when Settings disappears.
    public func stopTest() {
        let previous = testTask
        previous?.cancel()
        testTask = nil
        isTesting = false
        testFraction = 0
        let monitor = monitor
        Task {
            await previous?.value
            await monitor.stop()
        }
    }

    /// Builds the picker rows: system default first, then connected devices,
    /// then the saved device if it is disconnected (so the choice stays
    /// visible rather than silently reverting).
    static func makeChoices(
        devices: [AudioInputDevice],
        systemDefault: AudioInputDevice?,
        saved: AudioInputDevice?
    ) -> [MicrophoneChoice] {
        let defaultLabel = systemDefault.map { "System default (\($0.name))" } ?? "System default"
        var rows = [MicrophoneChoice(device: nil, label: defaultLabel, isDisconnected: false)]
        rows += devices.map { MicrophoneChoice(device: $0, label: $0.name, isDisconnected: false) }
        if let saved, !devices.contains(where: { $0.uid == saved.uid }) {
            rows.append(MicrophoneChoice(device: saved, label: "\(saved.name) (not connected)", isDisconnected: true))
        }
        return rows
    }
}
