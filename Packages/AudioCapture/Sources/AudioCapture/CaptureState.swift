import Foundation

/// Observable snapshot of an active capture session.
///
/// Emitted periodically via `AudioRecorder.stateStream()`.
/// `micLevel` is the mic RMS (0...1) and `micLevelSample` the full mic
/// reading (held peak and buffer age). `systemLevel` remains unwired (0).
public struct CaptureState: Sendable, Equatable {
    public let isRecording: Bool
    public let elapsed: TimeInterval
    /// RMS level 0...1 for the mic stream's most recent buffer.
    public let micLevel: Float
    /// RMS level 0...1 for the system audio stream. Unwired; always 0.
    public let systemLevel: Float
    /// Shared `CACurrentMediaTime()` reference captured at start.
    public let startTimestamp: Double
    /// Full mic reading for meters and silence detection; `nil` when the
    /// engine does not meter or the recorder is idle.
    public let micLevelSample: AudioLevelSample?
    /// The device the mic is capturing from; `nil` when idle.
    public let micInput: MicInputStatus?

    public init(
        isRecording: Bool,
        elapsed: TimeInterval,
        micLevel: Float,
        systemLevel: Float,
        startTimestamp: Double,
        micLevelSample: AudioLevelSample? = nil,
        micInput: MicInputStatus? = nil
    ) {
        self.isRecording = isRecording
        self.elapsed = elapsed
        self.micLevel = micLevel
        self.systemLevel = systemLevel
        self.startTimestamp = startTimestamp
        self.micLevelSample = micLevelSample
        self.micInput = micInput
    }

    /// The resting state before any capture has started.
    public static let idle = CaptureState(
        isRecording: false,
        elapsed: 0,
        micLevel: 0,
        systemLevel: 0,
        startTimestamp: 0
    )
}
