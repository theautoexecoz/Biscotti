---
status: hardware validation pending
---

# Microphone levels, silence warning and transcript turns

Addresses the "recording silently captured nothing" reports (#64, #82) by making the mic visibly work: the user can test the mic before a meeting and watch it during one. Also shows transcripts as speaker turns rather than one row per segment.

## UX

- **Settings → Microphone** (second section, after General):
  - **Input**: the Mac's current input device name, with a **Sound Settings…** button. Caption: Biscotti records from the Mac's input; change it in System Settings → Sound.
  - **Test level**: Test/Stop button and a segmented meter on that input. Runs for up to 60 s, stops when Settings closes. Disabled without mic permission, and while recording (the recording page has the real meter).
- **Recording page**, under the status row: mic icon, live segmented level meter (sage, ochre near the top, red at clipping) and the name of the device being recorded.
- **Silence warning**: error banner after 30 s of no mic audio ("No microphone audio for 30 seconds. Check your mic is connected and not muted."). Clears itself when audio returns. Never stops the recording.
- **Transcript**: consecutive segments from the same speaker show as one row (one name and timestamp per turn), matching the existing Copy and CSV output.

## Why there is no in-app mic picker

An in-app device choice was built and tested on hardware (10 November 2026: HyperX SoloCast chosen, MacBook mic as the macOS default). **VoiceProcessingIO ignores `kAudioOutputUnitProperty_CurrentDevice`** on the input node and always captures from the macOS default input: muting the HyperX left the voice recorded, and a post-start `kAudioDevicePropertyDeviceIsRunningSomewhere` check flagged the mismatch. The only working route was switching the macOS default input during recording, which also changes the meeting app's mic. The decision was to keep Biscotti on the system input and show it clearly instead (relevant to #116).

## Technical

- **Levels:** `AudioLevelMeter` (lock-free, vDSP) is fed from the `MicCaptureSession` tap and shared across attempts and rebuilds. `AudioRecorder`'s 250 ms state timer reads it into `CaptureState.micLevelSample` (RMS, peak held since the last read, buffer age) and `micInput` (device name). `RecordingController` publishes `micLevel`, `micInput` and `micSilenceWarning`. The mic engine's output rate match and `Mic setup:` log use the same default-input ID it reports.
- **Silence:** `MicSilenceDetector` warns after 30 s of peak ≤ −90 dBFS or no buffer for more than 2 s. The threshold targets the dead-device and all-zeros failure modes, sitting well below a quiet room after voice processing, so a user who is listening is not flagged. Tunable constants.
- **Settings test:** `InputLevelMonitor`, a plain `AVAudioEngine` input tap on the default input **without** voice processing (so it never flips AirPods into hands-free mode or ducks other apps). Its levels are pre-processing and can read lower than the recording meter. The tap closure is built in a nonisolated static so it carries no main-actor isolation onto the audio thread.
- **Turns:** `TranscriptTurns.merge` (Formatting) collapses consecutive same-`speakerID` segments; `TranscriptTextFormatting.render` now uses it, and the transcript list renders its output.

## Hardware validation

1. Record 20 s talking: the meter moves, the device name matches System Settings → Sound → Input, no banners.
2. Mute the mic mid-recording (hardware mute or a muted interface): the meter drops flat and the error banner appears after ~30 s, then clears within a second of unmuting.
3. Record 60 s in a quiet room without speaking: **no** banner (validates the −90 dBFS floor).
4. Settings → Test: the meter moves with speech; it is disabled while recording.
5. Open a long transcript: one row per speaker turn; tapping a turn's timestamp seeks to its start.
