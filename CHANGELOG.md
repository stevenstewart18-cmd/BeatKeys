# BeatKeys Changelog

---

## [0.2.0] — 2026-04-09

### New Features
- **Menu bar icon modes** — Choose between Full (keycap + music note) and Minimal (small rounded square dot) in Settings. Minimal mode avoids confusion with macOS mic/camera indicator badges.
- **Multiple pulse patterns** — Four keyboard backlight animations: Pulse (original dip-and-recover), Strobe (hard snap to black and back), Wave (slow sine fade), and Throb (deep dip with long tail recovery).
- **Multi-band fusion** — New "Multi" beat source option that combines spectral flux from bass (60–250 Hz), rhythm (250–800 Hz), and highs (2–8 kHz) with weighted blending (0.5/0.3/0.2). Catches more beat types without false positives from any single band.
- **Auto sensitivity calibration** — "Calibrate" button in Settings listens for 10 seconds, analyzes the flux distribution, and automatically tunes the sensitivity slider to your music. Shows an alert if no audio is detected during calibration.
- **Screen edge flash** — Optional white-to-transparent gradient overlay that flashes along all four screen edges on each beat. Useful when keyboard isn't visible (e.g., external display). Toggle via Settings checkbox.
- **Per-app audio targeting** — Audio Source popup in Settings lists all apps currently producing audio. Select a specific app (e.g., Spotify, Music) to tap only that process instead of all system audio. Includes a refresh button to re-scan. Persists across launches.

### Improvements
- Settings window expanded to accommodate all new controls (530px tall, 10 rows).
- Screen flash color changed to white with gradient fade (previously orange solid border).
- Minimal icon changed to rounded square to avoid confusion with Apple's green mic/camera badges.
- `make_dmg.sh` script added: builds a distributable DMG with drag-to-install layout, Applications folder symlink, and a generated dark-themed background image. Run `./make_dmg.sh` then notarize with `xcrun notarytool`.

---

## [0.1.0] — 2026-04-09

### New Features
- **BPM display** — Estimated BPM shown in Settings, updated every 500ms from inter-beat interval median.
- **Beat strength meter** — Live NSProgressIndicator in Settings showing real-time beat intensity.
- **Spectral flux detection** — Replaced RMS-based detection with half-wave-rectified spectral flux via 2048-point FFT (Accelerate framework). Fires on transients rather than sustained energy; much more accurate on percussion-heavy music.
- **Beat intensity scaling** — Pulse dip depth scales with beat strength (floor at 0.3 so weak beats are still visible).
- **Breathing animation** — Keyboard backlight slowly pulses (~0.35 Hz sine wave) when no beats fire for 2+ seconds.
- **Animated menu bar icon** — Icon flashes orange on each beat, returns to normal after 120ms.
- **Version shown in menu** — App version displayed as a disabled menu item at the top of the status menu.

### Changes
- Removed beat prediction (was causing false positives and complexity with no UX benefit).
- Bumped version from 0.0.5 to 0.1.0.

---

## [0.0.5] — 2026-03-XX

### Initial Release
- CoreAudio process tap via `CATapDescription` — no microphone, no screen capture.
- Adaptive threshold beat detection: RMS ring buffer (500 samples), fires when `rms > mean × multiplier AND rms > floor AND time_since_last > minBeatInterval`.
- **Settings panel** — Floating NSPanel with sensitivity slider, min beat gap slider, and frequency band selector (All / Bass / Rhythm / Highs).
- **FFT frequency-band filtering** — 2048-point real FFT (vDSP) with Hann window. Four selectable bands: Full Spectrum (20–20k Hz), Bass (60–250 Hz), Rhythm (250–800 Hz), Highs (2–8 kHz).
- **Keyboard backlight pulse** — CoreBrightness private framework via runtime `dlopen`/`NSClassFromString`. 280ms 3-stage fade animation (dip → mid → home).
- **Device switching** — Automatically recreates tap when default output device changes.
- **Health monitor** — Timer fires every 5s; auto-recreates tap after 15s of total silence.
- All settings persist via UserDefaults and are restored on launch.
- Requires macOS 14.2+ (uses `CATapDescription` process tap API).
