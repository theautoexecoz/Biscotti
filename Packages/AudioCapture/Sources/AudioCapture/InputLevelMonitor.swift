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

    /// Starts metering `device`, or the system default input when `nil`.
    /// Restarts if already running. Throws if the engine cannot start.
    public func start(device: AudioInputDevice?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try startOnQueue(device: device)
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

    private func startOnQueue(device: AudioInputDevice?) throws {
        stopOnQueue()
        meter.reset()

        let newEngine = AVAudioEngine()
        engine = newEngine
        let input = newEngine.inputNode

        if let device {
            let candidates = AudioInputDevices.candidates()
            guard case let .preferred(id) = InputDeviceResolver.resolve(
                preferredUID: device.uid, candidates: candidates
            ) else {
                throw CaptureError.micEngineFailed("\(device.name) is not connected.")
            }
            guard let unit = input.audioUnit else {
                throw CaptureError.micEngineFailed("The microphone input is unavailable.")
            }
            var deviceID = id
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioObjectID>.size)
            )
            logger.notice("Level preview bind: device id=\(id, privacy: .public) status=\(status, privacy: .public)")
            guard status == noErr else {
                throw CaptureError.micEngineFailed("Could not open \(device.name) (OSStatus \(status)).")
            }
        }

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
