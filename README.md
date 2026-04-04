# BeatKeys

**BeatKeys** is a lightweight macOS menu bar app that makes your MacBook's keyboard backlight pulse in sync with whatever music you're playing — no microphone needed.

Using Apple's CoreAudio process tap API, BeatKeys taps directly into your system audio output to detect beats in real time, then drives the keyboard backlight through fluid brightness animations that follow the rhythm. It works with any audio source — Spotify, Apple Music, YouTube, a DAW — anything producing sound on your Mac.

## A Nod to iSpazz

BeatKeys is a spiritual successor to **iSpazz**, the beloved iTunes visualizer plugin from the late 2000s that first brought music-reactive keyboard lighting to MacBooks. iSpazz stopped working years ago as Apple evolved macOS and retired the iTunes plugin architecture. BeatKeys picks up where it left off, rebuilt from scratch for modern macOS using CoreAudio's native process tap framework — no screen capture permissions, no microphone access, just clean system audio tapping.

## Features

- Keyboard backlight pulses to the beat of any system audio
- Runs entirely in the menu bar — no dock icon, no windows
- Three sensitivity levels (Low, Medium, High)
- Automatically follows audio device switches (speakers, AirPods, Bluetooth)
- Auto-recovers if audio goes silent
- Requires macOS 14.2 or later

## Built With Claude

BeatKeys was built collaboratively with [Claude](https://claude.ai) by Anthropic — from the CoreAudio tap architecture and beat detection algorithm to the custom menu bar icon and build pipeline. A human–AI pair programming project from start to finish.
