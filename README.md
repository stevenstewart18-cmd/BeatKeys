# BeatKeys

**BeatKeys** is a lightweight macOS menu bar app that makes your MacBook's keyboard backlight pulse in sync with whatever music you're playing — no microphone needed.

Using Apple's CoreAudio process tap API, BeatKeys taps directly into your system audio output to detect beats in real time, then drives the keyboard backlight through fluid brightness animations that follow the rhythm. It works with any audio source — Spotify, Apple Music, YouTube, a DAW — anything producing sound on your Mac.

## A Nod to iSpazz

BeatKeys is a spiritual successor to **iSpazz**, the beloved iTunes visualizer plugin from the late 2000s that first brought music-reactive keyboard lighting to MacBooks. iSpazz stopped working years ago as Apple evolved macOS and retired the iTunes plugin architecture. BeatKeys picks up where it left off, rebuilt from scratch for modern macOS using CoreAudio's native process tap framework — no screen capture permissions, no microphone access, just clean system audio tapping.

## Features

### Beat Detection
- **Spectral flux detection** — fires on transients (drum hits, note attacks) rather than sustained loudness, so pads and reverb tails don't trigger false beats
- **Frequency band selector** — choose which spectral range drives detection: All (full spectrum), Bass (60–250 Hz), Rhythm (250–800 Hz), Highs (2–8 kHz), or **Multi** (weighted fusion of all three bands simultaneously)
- **Auto sensitivity calibration** — hit Calibrate in Settings, play music for 10 seconds, and BeatKeys automatically tunes sensitivity to your audio
- **Beat intensity scaling** — loud kicks dip the backlight deeper; quiet hi-hats produce a shallower flash
- **BPM display** — estimates tempo from the last 16 inter-beat intervals, shown live in Settings
- **Live beat strength meter** — real-time bar in Settings showing what the detector sees on every beat

### Keyboard Animation
- **Four pulse patterns** — choose the animation style that suits you:
  - *Pulse* — smooth dip-and-recover (original behavior)
  - *Strobe* — hard snap to black and back
  - *Wave* — slow sine fade down and back up
  - *Throb* — deep dip with a long glowing tail
- **Breathing animation** — after 2 seconds of silence the backlight slowly pulses in a sine-wave pattern; the next detected beat snaps it back immediately

### Menu Bar
- Runs entirely in the menu bar — no dock icon, no windows
- **Icon modes** — Full (keycap + music note, flashes orange on beat) or Minimal (small square dot: gray when idle, green when active, orange on beat)
- Start/Stop beat sync from the menu, or with ⌘, to open Settings

### Screen Flash
- **Screen edge flash** — optional white gradient overlay that flashes along all four screen edges on each beat; useful when your keyboard isn't in view

### Audio Source Targeting
- **Per-app targeting** — select a specific app (Spotify, Music, browser, DAW) as the audio source instead of tapping all system audio; reduces false beats from notification sounds and system effects
- Automatically follows audio device switches (speakers, AirPods, Bluetooth)
- Auto-recovers if the audio tap goes silent

### Settings (⌘,)
| Control | What it does |
|---------|-------------|
| Audio Source | Pick a specific app to tap, or leave on All Apps |
| Icon Style | Full or Minimal menu bar icon |
| Pulse Pattern | Pulse / Strobe / Wave / Throb |
| Beat Source | All / Bass / Rhythm / Highs / Multi |
| Sensitivity | How easily beats fire (+ Calibrate button) |
| Min Beat Gap | Minimum time between beats (caps max BPM) |
| Screen Flash | Toggle screen edge flash |
| Estimated BPM | Live tempo readout |
| Beat Strength | Live intensity meter |

All settings persist across launches.

## Requirements

- macOS 14.2 or later (uses `CATapDescription` process tap API)
- MacBook with a keyboard backlight

## Install

Download `BeatKeys.dmg`, open it, and drag BeatKeys to Applications.

## ⚠️ Private API Notice

BeatKeys controls the keyboard backlight via **CoreBrightness.framework**, a private Apple framework accessed through the Objective-C runtime. It is not a public API and carries no stability guarantee — Apple could rename, restructure, or remove it in any future macOS release, which would break the backlight control feature. Everything else in the app (audio tapping, beat detection, menu bar UI) uses fully public APIs and will continue to work regardless.

## Built With Claude

BeatKeys was built collaboratively with [Claude](https://claude.ai) by Anthropic — from the CoreAudio tap architecture and beat detection algorithm to the custom menu bar icon and build pipeline. A human–AI pair programming project from start to finish.

## Demo

https://github.com/user-attachments/assets/e7cff279-d372-40f9-baf4-90d80557a26b

> *The video doesn't do it justice — seeing it live on your keyboard is something else.*
