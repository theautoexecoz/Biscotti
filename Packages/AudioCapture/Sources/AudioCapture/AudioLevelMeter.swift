import Accelerate
import Foundation
import Synchronization

/// One reading from an `AudioLevelMeter`.
public struct AudioLevelSample: Sendable, Equatable {
    /// RMS of the most recent buffer, linear 0...1.
    public let rms: Float
    /// Peak |sample| since the previous reading, linear 0...1.
    public let peak: Float
    /// Seconds since the last buffer arrived, or `nil` if none has yet.
    public let secondsSinceLastBuffer: Double?

    public init(rms: Float, peak: Float, secondsSinceLastBuffer: Double?) {
        self.rms = rms
        self.peak = peak
        self.secondsSinceLastBuffer = secondsSinceLastBuffer
    }

    /// No audio has arrived.
    public static let silent = AudioLevelSample(rms: 0, peak: 0, secondsSinceLastBuffer: nil)

    /// Peak level in dBFS (floored at `AudioLevel.floorDB`).
    public var peakDB: Float {
        AudioLevel.decibels(fromLinear: peak)
    }
}

/// Lock-free level meter fed from an audio tap and read from any thread.
///
/// `ingest` is allocation-free (vDSP over the tap's channel pointer plus
/// atomic stores), so it is safe on the capture callback. `read()` returns
/// the peak held since the previous read, so a slow reader (a 250 ms UI
/// pump) still sees short speech transients.
public final class AudioLevelMeter: Sendable {
    private let rmsBits = Atomic<UInt32>(0)
    private let peakBits = Atomic<UInt32>(0)
    private let lastBufferNanos = Atomic<UInt64>(0)

    public init() {}

    /// Measures one buffer of float samples.
    public func ingest(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var rms: Float = 0
        var peak: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        rmsBits.store(rms.bitPattern, ordering: .relaxed)
        // Hold the highest peak until the next read.
        var current = peakBits.load(ordering: .relaxed)
        while Float(bitPattern: current) < peak {
            let (exchanged, original) = peakBits.compareExchange(
                expected: current, desired: peak.bitPattern, ordering: .relaxed
            )
            if exchanged { break }
            current = original
        }
        lastBufferNanos.store(DispatchTime.now().uptimeNanoseconds, ordering: .releasing)
    }

    /// Returns the current reading and resets the held peak.
    public func read() -> AudioLevelSample {
        let last = lastBufferNanos.load(ordering: .acquiring)
        let age: Double? = if last == 0 {
            nil
        } else {
            Double(DispatchTime.now().uptimeNanoseconds &- last) / 1_000_000_000
        }
        let peak = Float(bitPattern: peakBits.exchange(0, ordering: .relaxed))
        let rms = Float(bitPattern: rmsBits.load(ordering: .relaxed))
        return AudioLevelSample(rms: rms, peak: peak, secondsSinceLastBuffer: age)
    }

    /// Clears all state (no buffer seen).
    public func reset() {
        rmsBits.store(0, ordering: .relaxed)
        peakBits.store(0, ordering: .relaxed)
        lastBufferNanos.store(0, ordering: .releasing)
    }
}

/// Level conversions shared by the meters and the silence detector.
public enum AudioLevel {
    /// Lowest level reported; digital silence maps here.
    public static let floorDB: Float = -120

    /// Bottom of the visible meter range. Quieter audio shows as empty.
    public static let meterMinDB: Float = -60

    /// Linear amplitude → dBFS, floored at `floorDB`.
    public static func decibels(fromLinear value: Float) -> Float {
        guard value > 0, value.isFinite else { return floorDB }
        return max(floorDB, 20 * log10f(value))
    }

    /// dBFS → meter fill 0...1 across `meterMinDB...0`.
    public static func meterFraction(fromDB decibels: Float) -> Double {
        guard decibels > meterMinDB else { return 0 }
        return Double(min(1, (decibels - meterMinDB) / -meterMinDB))
    }

    /// Linear peak → meter fill 0...1.
    public static func meterFraction(fromLinear value: Float) -> Double {
        meterFraction(fromDB: decibels(fromLinear: value))
    }
}

/// Detects a microphone that has gone silent during a recording.
///
/// Warns when the mic has delivered no buffers, or only near-digital
/// silence, for `window` seconds. The threshold sits well below a quiet
/// room after voice processing, so a user who is simply listening is not
/// flagged; the target is the dead-device and all-zeros failure modes.
/// Advisory only: it never stops a recording.
public struct MicSilenceDetector: Sendable, Equatable {
    /// Peak level at or below which audio counts as silent (dBFS).
    public static let defaultSilenceDB: Float = -90
    /// How long silence must last before warning (seconds).
    public static let defaultWindow: TimeInterval = 30
    /// No buffer for this long counts as silent (seconds).
    public static let defaultStaleAfter: TimeInterval = 2

    public let silenceDB: Float
    public let window: TimeInterval
    public let staleAfter: TimeInterval
    private var silentSince: TimeInterval?

    public init(
        silenceDB: Float = Self.defaultSilenceDB,
        window: TimeInterval = Self.defaultWindow,
        staleAfter: TimeInterval = Self.defaultStaleAfter
    ) {
        self.silenceDB = silenceDB
        self.window = window
        self.staleAfter = staleAfter
    }

    /// Feeds one reading taken at `time` (any monotonic seconds, e.g. elapsed
    /// recording time). Returns `true` while the warning should show.
    public mutating func ingest(_ sample: AudioLevelSample, at time: TimeInterval) -> Bool {
        let stale = sample.secondsSinceLastBuffer.map { $0 > staleAfter } ?? true
        let quiet = stale || sample.peakDB <= silenceDB
        guard quiet else {
            silentSince = nil
            return false
        }
        let since = silentSince ?? time
        silentSince = since
        return time - since >= window
    }

    /// Seconds of continuous silence so far, at `time`.
    public func silentDuration(at time: TimeInterval) -> TimeInterval {
        silentSince.map { max(0, time - $0) } ?? 0
    }

    public mutating func reset() {
        silentSince = nil
    }
}
