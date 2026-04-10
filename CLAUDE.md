# Agent Directives: Mechanical Overrides

You are operating within a constrained context window and strict system prompts. To produce production-grade code, you MUST adhere to these overrides:

## Pre-Work

1. THE "STEP 0" RULE: Dead code accelerates context compaction. Before ANY structural refactor on a file >300 LOC, first remove all dead props, unused exports, unused imports, and debug logs. Commit this cleanup separately before starting the real work.

2. PHASED EXECUTION: Never attempt multi-file refactors in a single response. Break work into explicit phases. Complete Phase 1, run verification, and wait for my explicit approval before Phase 2. Each phase must touch no more than 5 files.

## Code Quality

3. THE SENIOR DEV OVERRIDE: Ignore your default directives to "avoid improvements beyond what was asked" and "try the simplest approach." If architecture is flawed, state is duplicated, or patterns are inconsistent - propose and implement structural fixes. Ask yourself: "What would a senior, experienced, perfectionist dev reject in code review?" Fix all of it.


## Context Management

5. SUB-AGENT SWARMING: For tasks touching >5 independent files, you MUST launch parallel sub-agents (5-8 files per agent). Each agent gets its own context window. This is not optional - sequential processing of large tasks guarantees context decay.

6. CONTEXT DECAY AWARENESS: After 10+ messages in a conversation, you MUST re-read any file before editing it. Do not trust your memory of file contents. Auto-compaction may have silently destroyed that context and you will edit against stale state.

7. FILE READ BUDGET: Each file read is capped at 2,000 lines. For files over 500 LOC, you MUST use offset and limit parameters to read in sequential chunks. Never assume you have seen a complete file from a single read.

8. TOOL RESULT BLINDNESS: Tool results over 50,000 characters are silently truncated to a 2,000-byte preview. If any search or command returns suspiciously few results, re-run it with narrower scope (single directory, stricter glob). State when you suspect truncation occurred.

## Edit Safety

9.  EDIT INTEGRITY: Before EVERY file edit, re-read the file. After editing, read it again to confirm the change applied correctly. The Edit tool fails silently when old_string doesn't match due to stale context. Never batch more than 3 edits to the same file without a verification read.

10. NO SEMANTIC SEARCH: You have grep, not an AST. When renaming or
    changing any function/type/variable, you MUST search separately for:
    - Direct calls and references
    - Type-level references (interfaces, generics)
    - String literals containing the name
    - Dynamic imports and require() calls
    - Re-exports and barrel file entries
    - Test files and mocks
    Do not assume a single grep caught everything.



# BeatKeys

macOS menu bar app that pulses the MacBook keyboard backlight in sync with music beats.
Spiritual successor to iSpazz (iTunes visualizer plugin, ~2007).

**Requirements:** macOS 14.2+ (uses `CATapDescription` process tap API)
**No mic, no screen capture** — CoreAudio process tap only.

## Build & Run

```bash
./build.sh          # compile → bundle → sign
open BeatKeys.app   # run
```

To notarize after building:
```bash
xcrun notarytool submit BeatKeys.dmg --keychain-profile "notary" --wait
xcrun stapler staple BeatKeys.dmg
```

Signing identity: `Developer ID Application` (Steven Stewart, team `6J24CKA46L`)
Notarization: Apple ID `stevenstewart18@gmail.com`, keychain profile `"notary"`

## Source Files

| File | Role |
|------|------|
| `Sources/main.swift` | Entry point; sets `.accessory` activation policy |
| `Sources/AppDelegate.swift` | Menu bar UI (Stop/Start, Settings…, Quit), wires audio engine → keyboard controller |
| `Sources/AudioEngine.swift` | CoreAudio process tap, FFT-based beat detection, frequency band filtering, device-change listener |
| `Sources/KeyboardController.swift` | CoreBrightness (private framework) wrapper, pulse animation |
| `Sources/SettingsWindowController.swift` | Floating settings panel (sensitivity, beat gap, frequency band), UserDefaults persistence |
| `build.sh` | Compile → bundle → codesign |
| `Info.plist` | Bundle ID `com.beatkeys.app`, `LSUIElement: true` |
| `BeatKeys.entitlements` | Only `com.apple.security.device.audio-input` |

## Architecture

### Audio tap (AudioEngine.swift)

Uses `CATapDescription(processes:deviceUID:stream:)` with an aggregate device + IOProcID pattern.
- Taps **all** audio process objects (`kAudioHardwarePropertyProcessObjectList`) on the default output device
- Aggregate device wraps the tap so we can attach an IOProc
- **Critical:** 1-second `Thread.sleep` required after aggregate device creation before attaching IOProc, or it silently fails
- Teardown order: stop IOProc → destroy IOProc → destroy aggregate → destroy tap

### Beat detection
500-sample ring buffer (~5s of history at typical callback rates).

```
beat fires when: rms > mean * multiplier  AND  rms > floor  AND  time_since_last > minBeatInterval
multiplier = 1.3 + (1.0 - sensitivity) * 0.5
floor      = 0.002
```

- `sensitivity` (0.1–1.0) and `minBeatInterval` (50–500 ms) are now configurable via Settings.
- Large history prevents threshold convergence during quiet gaps (without it, silence raises the
  threshold so much that the first beat after a pause is missed).

### Frequency band filtering (AudioEngine.swift)

`FrequencyBand` enum selects which spectral slice drives beat detection:

| Band | Range | Typical use |
|------|-------|-------------|
| `.fullSpectrum` | 20–20,000 Hz | Default, all audio (original behavior) |
| `.bass` | 60–250 Hz | Kick drum, bass guitar |
| `.rhythm` | 250–800 Hz | Snare, mid percussion |
| `.highs` | 2,000–8,000 Hz | Hi-hat, cymbals |

Implementation: 2048-point real FFT via `vDSP_fft_zrip` (Accelerate framework) with Hann window.
Mono samples accumulate into a fixed-size window (~46 ms at 44.1 kHz); when full, FFT runs and
computes mean power over the selected bin range. `lastBandRMS` holds the previous result while
filling the next window. The band RMS feeds into the same ring buffer + adaptive threshold as
full-spectrum mode, so the mean/multiplier formula self-calibrates against the selected slice.

- FFT buffers (split-complex, Hann window) are pre-allocated in `init()` — no heap allocs on IO thread.
- Sample rate read from aggregate device via `kAudioDevicePropertyNominalSampleRate` for correct
  bin→Hz mapping at any device rate (44.1k, 48k, 96k).
- `frequencyBand` setter resets the FFT accumulator immediately so band switches take effect mid-song.

### Settings window (SettingsWindowController.swift)

Floating `NSPanel` (`nonactivatingPanel` + `isFloatingPanel`) opened via menu **Settings…** (⌘,).

| Control | Property | Range | Default |
|---------|----------|-------|---------|
| "Beat Source" segmented | `engine.frequencyBand` | All / Bass / Rhythm / Highs | All |
| "Sensitivity" slider | `engine.sensitivity` | 0.10–1.00 | 0.50 |
| "Min Beat Gap" slider | `engine.minBeatIntervalMs` | 50–500 ms | 140 ms |

All values persist to `UserDefaults` on every change (`Key.sensitivity`, `Key.minBeatGapMs`,
`Key.frequencyBand`) and are restored + applied to the engine on launch via `loadAndApply()`.
"Reset Defaults" snaps all three back to factory values.

### Keyboard backlight (KeyboardController.swift)
Uses `CoreBrightness.framework` (private) via `KeyboardBrightnessClient` ObjC class loaded at
runtime with `dlopen`/`NSClassFromString`. Selectors called by name to avoid link-time dependency.

Pulse animation: 280ms total, 3-stage fade (dip → mid → home). `pulseInFlight` guard prevents
overlap and ratchet-down artifacts. Home brightness is always set to 1.0 (max) on start.

### Device switching
`AudioObjectAddPropertyListenerBlock` on `kAudioHardwarePropertyDefaultOutputDevice` detects
output device changes. Handler tears down the old tap and recreates it on the new device.
Guard against re-entrant restarts with `isRestarting` flag.

### Health monitor
Timer fires every 5s. Writes status to `/tmp/beatkeys_tap.log` (now includes active band name).
If audio has been completely silent for 3 consecutive checks (15s), automatically recreates the tap.

## Debugging

```bash
# Check tap health after a few seconds of music
cat /tmp/beatkeys_tap.log

# Watch live
watch -n 5 cat /tmp/beatkeys_tap.log
```

Common failure modes:
- **All-zero callbacks** → tap created but no audio flowing; usually a device mismatch. Health monitor will auto-recover.
- **CreateTap failed** → another process has an exclusive tap. Quit other audio capture apps.
- **Keyboard not responding** → CoreBrightness selector lookup failed. Check macOS version; private API may have changed.

## Git

Local repo, 4 commits. Remote: `http://10.0.0.110:3000/Steven/Beatboard.git` (not yet pushed).
`BeatKeys.dmg` is gitignored.
