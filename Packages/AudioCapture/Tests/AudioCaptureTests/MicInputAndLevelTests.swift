import CoreAudio
import Foundation
import Testing
@testable import AudioCapture

@Suite("InputDeviceResolver")
struct InputDeviceResolverTests {
    private let candidates = [
        InputDeviceCandidate(uid: "BuiltInMicrophoneDevice", id: 81),
        InputDeviceCandidate(uid: "AppleUSBAudioEngine:Shure:MV7", id: 112)
    ]

    @Test("no preference follows the system default")
    func noPreference() {
        #expect(InputDeviceResolver.resolve(preferredUID: nil, candidates: candidates) == .systemDefault)
    }

    @Test("empty preference follows the system default")
    func emptyPreference() {
        #expect(InputDeviceResolver.resolve(preferredUID: "", candidates: candidates) == .systemDefault)
    }

    @Test("connected preference resolves to its current object ID")
    func connectedPreference() {
        let result = InputDeviceResolver.resolve(
            preferredUID: "AppleUSBAudioEngine:Shure:MV7", candidates: candidates
        )
        #expect(result == .preferred(112))
    }

    @Test("disconnected preference reports unavailable for visible fallback")
    func disconnectedPreference() {
        let result = InputDeviceResolver.resolve(preferredUID: "AirPodsPro", candidates: candidates)
        #expect(result == .preferredUnavailable)
    }
}

@Suite("AudioLevel")
struct AudioLevelTests {
    @Test("full scale is 0 dBFS")
    func fullScale() {
        #expect(abs(AudioLevel.decibels(fromLinear: 1.0)) < 0.001)
    }

    @Test("half amplitude is about -6 dBFS")
    func halfAmplitude() {
        #expect(abs(AudioLevel.decibels(fromLinear: 0.5) + 6.0206) < 0.01)
    }

    @Test("digital silence maps to the floor")
    func silenceFloor() {
        #expect(AudioLevel.decibels(fromLinear: 0) == AudioLevel.floorDB)
        #expect(AudioLevel.decibels(fromLinear: .nan) == AudioLevel.floorDB)
    }

    @Test("meter fraction spans meterMinDB...0")
    func meterFraction() {
        #expect(AudioLevel.meterFraction(fromDB: 0) == 1)
        #expect(AudioLevel.meterFraction(fromDB: AudioLevel.meterMinDB) == 0)
        #expect(AudioLevel.meterFraction(fromDB: -120) == 0)
        #expect(abs(AudioLevel.meterFraction(fromDB: -30) - 0.5) < 0.0001)
        #expect(AudioLevel.meterFraction(fromDB: 6) == 1)
    }
}

@Suite("AudioLevelMeter")
struct AudioLevelMeterTests {
    @Test("fresh meter reports no buffer")
    func freshMeter() {
        let meter = AudioLevelMeter()
        let sample = meter.read()
        #expect(sample.secondsSinceLastBuffer == nil)
        #expect(sample.peak == 0)
    }

    @Test("ingest measures RMS and peak; read resets the held peak")
    func ingestAndRead() {
        let meter = AudioLevelMeter()
        let loud: [Float] = [0.5, -0.5, 0.5, -0.5]
        let quiet: [Float] = [0.01, -0.01, 0.01, -0.01]
        loud.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            meter.ingest(base, count: ptr.count)
        }
        quiet.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            meter.ingest(base, count: ptr.count)
        }
        let first = meter.read()
        // Peak holds the loud buffer; RMS is the latest (quiet) buffer.
        #expect(abs(first.peak - 0.5) < 0.0001)
        #expect(abs(first.rms - 0.01) < 0.0001)
        #expect(first.secondsSinceLastBuffer != nil)

        let second = meter.read()
        #expect(second.peak == 0)
    }

    @Test("reset clears the buffer timestamp")
    func reset() {
        let meter = AudioLevelMeter()
        let samples: [Float] = [0.2, 0.2]
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            meter.ingest(base, count: ptr.count)
        }
        meter.reset()
        #expect(meter.read().secondsSinceLastBuffer == nil)
    }
}

@Suite("MicSilenceDetector")
struct MicSilenceDetectorTests {
    private func sample(peakDB: Float, age: Double? = 0.05) -> AudioLevelSample {
        let linear: Float = peakDB <= AudioLevel.floorDB ? 0 : powf(10, peakDB / 20)
        return AudioLevelSample(rms: linear, peak: linear, secondsSinceLastBuffer: age)
    }

    @Test("speech never warns")
    func speechNeverWarns() {
        var detector = MicSilenceDetector(window: 30)
        for second in 0 ... 120 {
            #expect(detector.ingest(sample(peakDB: -20), at: Double(second)) == false)
        }
    }

    @Test("quiet listening above the floor does not warn")
    func quietListening() {
        var detector = MicSilenceDetector(window: 30)
        for second in 0 ... 120 {
            #expect(detector.ingest(sample(peakDB: -70), at: Double(second)) == false)
        }
    }

    @Test("digital silence warns after the window, not before")
    func digitalSilenceWarns() {
        var detector = MicSilenceDetector(window: 30)
        #expect(detector.ingest(sample(peakDB: -120), at: 0) == false)
        #expect(detector.ingest(sample(peakDB: -120), at: 29.9) == false)
        #expect(detector.ingest(sample(peakDB: -120), at: 30) == true)
        #expect(abs(detector.silentDuration(at: 30) - 30) < 0.0001)
    }

    @Test("stale buffers count as silence even with an old loud peak")
    func staleBuffersWarn() {
        var detector = MicSilenceDetector(window: 10, staleAfter: 2)
        #expect(detector.ingest(sample(peakDB: -10, age: 5), at: 0) == false)
        #expect(detector.ingest(sample(peakDB: -10, age: 15), at: 10) == true)
    }

    @Test("no buffer yet counts as silence")
    func noBufferYet() {
        var detector = MicSilenceDetector(window: 5)
        #expect(detector.ingest(sample(peakDB: -10, age: nil), at: 0) == false)
        #expect(detector.ingest(sample(peakDB: -10, age: nil), at: 5) == true)
    }

    @Test("audio returning clears the warning and restarts the window")
    func recoveryClears() {
        var detector = MicSilenceDetector(window: 10)
        _ = detector.ingest(sample(peakDB: -120), at: 0)
        #expect(detector.ingest(sample(peakDB: -120), at: 10) == true)
        #expect(detector.ingest(sample(peakDB: -30), at: 11) == false)
        #expect(detector.ingest(sample(peakDB: -120), at: 12) == false)
        #expect(detector.ingest(sample(peakDB: -120), at: 21.9) == false)
        #expect(detector.ingest(sample(peakDB: -120), at: 22) == true)
    }
}

@Suite("MicInputStatus")
struct MicInputStatusTests {
    @Test("only fallback and unconfirmed bindings need attention")
    func needsAttention() {
        let make = { (binding: MicInputStatus.Binding) in
            MicInputStatus(deviceName: "Mic", requestedName: "Mic", binding: binding)
        }
        #expect(make(.systemDefault).needsAttention == false)
        #expect(make(.selected).needsAttention == false)
        #expect(make(.selectedUnconfirmed).needsAttention == true)
        #expect(make(.selectedUnavailable).needsAttention == true)
    }
}

@Suite("AudioRecorder mic level")
struct AudioRecorderMicLevelTests {
    @Test("state stream carries the mic engine's level and input status while recording")
    func stateCarriesLevelAndInput() async throws {
        let ctx = try TestRecorderFactory.make()
        defer { TestRecorderFactory.cleanup(ctx) }
        let level = AudioLevelSample(rms: 0.1, peak: 0.4, secondsSinceLastBuffer: 0.02)
        let input = MicInputStatus(deviceName: "Shure MV7", requestedName: "Shure MV7", binding: .selected)
        ctx.micEngine.setLevel(level)
        ctx.micEngine.setInputStatus(input)

        try await ctx.recorder.start(paths: ctx.paths)
        let stream = await ctx.recorder.stateStream()
        var received: CaptureState?
        for await state in stream {
            received = state
            break
        }
        #expect(received?.micLevelSample == level)
        #expect(received?.micLevel == 0.1)
        #expect(received?.micInput == input)

        ctx.deviceChangeProvider.finish()
        await ctx.recorder.stop()
    }

    @Test("idle state has no mic level or input")
    func idleHasNoLevel() async throws {
        let ctx = try TestRecorderFactory.make()
        defer { TestRecorderFactory.cleanup(ctx) }
        ctx.micEngine.setLevel(AudioLevelSample(rms: 0.1, peak: 0.4, secondsSinceLastBuffer: 0.02))
        let stream = await ctx.recorder.stateStream()
        var received: CaptureState?
        for await state in stream {
            received = state
            break
        }
        #expect(received?.micLevelSample == nil)
        #expect(received?.micInput == nil)
    }
}
