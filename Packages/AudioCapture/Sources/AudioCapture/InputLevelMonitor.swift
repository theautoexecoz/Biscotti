import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os

private let logger = Logger(subsystem: "net.scosman.biscotti.audiocapture", category: "InputLevelMonitor")

/// Lightweight mic preview for Settings: a plain `AVAudioEngine` input tap
/// feeding an `AudioLevelMeter`. Nothing is written to disk.
///
/// Deliberately **without** voice processing, so a preview never flips
/// Bluetooth headsets into hands-free mode or ducks other apps. Levels are
/// therefore pre-processing and can read lower than the recording meter.
/// Do not run while a recording is active: two engines would contend for
/// the device.
public final class InputLevelMonitor: @unchecked Sendable {
    public let meter = AudioLevelMeter()

    private let queue = DispatchQueue(label: "net.scosman.biscotti.input-level-monitor", qos: .userInitiated)
    /// Owned by `queue`.
    private var engine: AVAudioEngine?

    public init() {}

    /// Starts metering the macOS default input (the device recordings use).
    /// Restarts if already running. Throws if the engine cannot start.
    public func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try startOnQueue()
                    cont.resume()
                } catch {
                    stopOnQueue()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Stops metering. Idempotent.
    public func stop() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                stopOnQueue()
                cont.resume()
            }
        }
    }

    deinit {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    // MARK: - Queue-confined

    private func startOnQueue() throws {
        stopOnQueue()
        meter.reset()

        let newEngine = AVAudioEngine()
        engine = newEngine
        let input = newEngine.inputNode

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.micEngineFailed("The microphone has no usable audio format.")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(meter: meter))
        newEngine.prepare()
        try newEngine.start()
        logger.notice("Level preview started: rate=\(format.sampleRate, privacy: .public) channels=\(format.channelCount, privacy: .public)")
    }

    private func stopOnQueue() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        self.engine = nil
        logger.notice("Level preview stopped")
    }

    /// Built outside any actor so the tap closure carries no isolation and
    /// is safe to call on the audio thread.
    private static func makeTap(meter: AudioLevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { return }
            meter.ingest(channels[0], count: Int(buffer.frameLength))
        }
    }
}
