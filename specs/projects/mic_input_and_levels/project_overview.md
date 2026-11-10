---
status: hardware validation pending
---

# Microphone selection, live levels and silence warning

Addresses [#116](https://github.com/scosman/Biscotti/issues/116) and the "recording silently captured nothing" reports (#64, #82). The goal is trust: the user picks the mic, can test it, and can see it working during a recording.

## UX

- **Settings → Microphone** (second section, after General):
  - **Input device** picker: "System default (current default's name)", then each connected input device. A saved device that is unplugged stays listed as "Name (not connected)" instead of silently reverting.
  - Caption: changes apply from the next recording.
  - **Test level**: Test/Stop button and a segmented meter. Runs for up to 60 s, stops when Settings closes. Disabled without mic permission, and while recording (the recording page has the real meter).
- **Recording page**, under the status row:
  - Mic icon, live segmented level meter (sage, ochre near the top, red at clipping) and the name of the device being recorded.
  - Warning banner if the chosen mic is not the one recording ("Shure MV7 isn't available. Recording from MacBook Pro Microphone instead.") or its binding could not be confirmed.
  - Error banner after 30 s of no mic audio ("No microphone audio for 30 seconds. Check your mic is connected and not muted."). Clears itself when audio returns. Never stops the recording.

## Technical

- **Persistence:** device-local `UserDefaults` (`micInputDeviceUID`, `micInputDeviceName`) via `MicInputStore` in `Recording`. Not SwiftData: a Core Audio UID only means something on this Mac, and `AppSettings` syncs. `nil` means follow the macOS default, which is the original behaviour and the default.
- **Selection (AudioCapture):** `AudioRecorder.live(preferredInput:)` → `LiveMicCaptureEngine`. Hardware testing (10 November 2026, HyperX SoloCast chosen, MacBook mic as default) showed **VPIO ignores `kAudioOutputUnitProperty_CurrentDevice`** on the input node and always captures from the macOS default input: muting the HyperX left the voice recorded, and the post-start check flagged `.selectedUnconfirmed`. So at recording start the engine makes the chosen mic the macOS default input (`kAudioHardwarePropertyDefaultInputDevice`) before building VPIO, and restores the previous default on stop, unless the user changed the default during the recording or the previous device is gone. The switch happens before `AudioRecorder` starts its device-change listener, so it does not trigger a reconnect. Side effect, stated in Settings: meeting apps following the system input use the chosen mic too.
  - Chosen device missing at start → no switch, `MicInputStatus.binding = .selectedUnavailable`, error log.
  - Every build compares the actual default input with the choice for display. Unplugging the chosen mic mid-recording makes macOS move the default; the existing reconnect follows it and the page shows the fallback banner. A user's own mid-recording change is followed, not reverted.
  - After start, `kAudioDevicePropertyDeviceIsRunningSomewhere` on the chosen device; if false → `.selectedUnconfirmed` and an error log.
  - If the app crashes mid-recording, the default input stays on the chosen mic.
- **Levels:** `AudioLevelMeter` (lock-free, vDSP) is fed from the `MicCaptureSession` tap, shared across attempts and rebuilds. `AudioRecorder`'s 250 ms state timer reads it into `CaptureState.micLevelSample` (RMS, peak held since the last read, buffer age) and `micInput`. `RecordingController` publishes `micLevel`, `micInput` and `micSilenceWarning`.
- **Silence:** `MicSilenceDetector` warns after 30 s of peak ≤ −90 dBFS or no buffer for more than 2 s. The threshold targets the dead-device and all-zeros failure modes, sitting well below a quiet room after voice processing, so a user who is listening is not flagged. Tunable constants.
- **Settings test:** `InputLevelMonitor`, a plain `AVAudioEngine` input tap **without** voice processing (so it never flips AirPods into hands-free mode or ducks other apps). Its levels are pre-processing and can read lower than the recording meter. The tap closure is built in a nonisolated static so it carries no main-actor isolation onto the audio thread.

## Hardware validation (required before upstreaming)

Unit tests cover resolution, level maths, the detector and UI text. They cannot prove which device VPIO captures from. Persist info logs once (`sudo log config --subsystem net.scosman.biscotti --mode "level:info,persist:info"`), then:

1. **Default path unchanged:** Settings → System default. Record 20 s talking. Meter moves, device name is the macOS default, no banners. Measure with `Tools/aac_track_report.py`.
2. **Chosen external mic (not the macOS default):** set the macOS default to the built-in mic, choose the external mic in Biscotti, Test (meter moves when speaking into the external mic, not the built-in). Record 20 s speaking into the external mic only. Log must show `Mic input: switching default input … status=0` and `Mic input verify: … runningSomewhere=true`; muting the external mic must silence the meter; after stop the macOS input is back on the built-in mic; the recording page names the external mic; the mic track has speech at a normal level.
3. **Unplug mid-recording:** record with the external mic chosen, unplug at ~10 s, keep talking to ~25 s. Expect the fallback banner naming both devices, the meter continues on the built-in mic, the track has audio throughout apart from a short gap fill.
4. **Chosen mic missing at start:** unplug the external mic, start recording. Expect the fallback banner from the start and audio from the default.
5. **Silence warning:** record with a mic whose hardware mute is on (or a muted USB interface). Expect the error banner after ~30 s, clearing within a second of unmuting. Also record 60 s in a quiet room without speaking: expect **no** banner (validates the −90 dBFS floor).
6. **AirPods:** choose the built-in mic while AirPods are the output. Confirm AirPods stay in high-quality (A2DP) playback during recording; this is the #116 request.

Log query:

```
/usr/bin/log show --style compact --info --last 10m --predicate 'subsystem BEGINSWITH "net.scosman.biscotti" AND (eventMessage CONTAINS "Mic input" OR eventMessage CONTAINS "Mic setup" OR eventMessage CONTAINS "Mic silent" OR eventMessage CONTAINS "Level preview")'
```
