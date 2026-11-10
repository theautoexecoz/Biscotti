import AppCore
import AudioCapture
import Foundation
import Permissions

/// State for Settings → Microphone: which mic the Mac is using, and a
/// level test on it.
///
/// Biscotti always records from the macOS default input, so this shows
/// that device rather than offering a separate choice. The test runs a
/// separate, non-voice-processed preview engine and is unavailable while
/// recording, when the recording page's meter shows the real signal.
@MainActor @Observable
public final class MicrophoneSettingsViewModel {
    private let core: AppCore
    private let systemDefault: @Sendable () -> AudioInputDevice?
    private let monitor: InputLevelMonitor

    /// How long a level test runs before stopping itself.
    static let testDuration: Duration = .seconds(60)
    /// Meter refresh interval during a test.
    static let testRefresh: Duration = .milliseconds(50)

    /// Name of the Mac's current input, or `nil` if there is none.
    public private(set) var currentInputName: String?
    public private(set) var isTesting = false
    /// Meter fill 0...1 during a test.
    public private(set) var testFraction: Double = 0
    /// Error from the last test start, shown inline.
    public private(set) var testError: String?

    private var testTask: Task<Void, Never>?

    public init(
        core: AppCore,
        systemDefault: @escaping @Sendable () -> AudioInputDevice? = { AudioInputDevices.systemDefault() },
        monitor: InputLevelMonitor = InputLevelMonitor()
    ) {
        self.core = core
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

    /// Display text for the current input.
    public var currentInputText: String {
        currentInputName ?? "No microphone found"
    }

    /// Re-reads the Mac's current input.
    public func refresh() {
        currentInputName = systemDefault()?.name
    }

    /// Starts (or restarts) the level test on the Mac's current input.
    ///
    /// Each test task waits for its predecessor to finish, and a cancelled
    /// task leaves stopping to whoever cancelled it, so a restart can never
    /// have a late `stop()` from the old task kill the new preview.
    public func startTest() {
        guard canTest else { return }
        refresh()
        let previous = testTask
        previous?.cancel()
        testError = nil
        isTesting = true
        let monitor = monitor
        testTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await monitor.start()
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
}
