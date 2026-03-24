# RecordMe

A lightweight macOS menu bar screen recorder with automatic cinematic zoom effects. Drop zoom markers while you record, tweak them in a review window, and export a polished MP4 — no timeline editor needed.

Think Screen Studio but stripped down: record, zoom, export.

## Install

**Requirements:** macOS 13+ (Ventura) and [Xcode](https://apps.apple.com/app/xcode/id497799835)

```bash
git clone https://github.com/angus-lau/RecordMe.git
cd RecordMe
make run
```

Or `make install` to copy to /Applications.

## Permissions

On first launch, grant these in System Settings > Privacy & Security:

| Permission | Why | Required? |
|---|---|---|
| Screen Recording | Capture your screen | Yes |
| Accessibility | Track cursor + detect typing for auto-zoom | Yes |
| Microphone | Voice narration | Optional |

You may need to restart the app after granting Screen Recording.

## Usage

### Record

1. Click the **RecordMe** icon in your menu bar
2. Pick a capture source — full display, a specific window, or an app
3. Toggle mic on/off
4. Hit **Start Recording** (3-second countdown)
5. While recording, press **Cmd+Shift+Z** wherever you want a zoom effect
6. Press **Cmd+Shift+S** to stop

### Review

A review window opens automatically after you stop recording.

| Action | What it does |
|---|---|
| Click a marker on the timeline | Select it |
| Click the video preview | Set where the selected marker zooms into |
| Drag a marker | Reposition it in time |
| **← →** keys | Adjust zoom level (1.5x – 3.0x) |
| **[ ]** keys | Adjust zoom duration |
| **Delete** | Remove selected marker |
| **+ Add Marker** button | Add a new zoom point at the current time |
| Drag yellow trim handles | Trim the start/end of your recording |
| **Space** | Play/pause |

### Export

Pick a preset (1080p / 4K / Source, HEVC or H.264) and click **Export**. The finished MP4 opens in Finder.

Default save location: `~/Movies/RecordMe/`

## How it works

RecordMe uses a two-pass approach:

1. **Record** — captures your screen to a near-lossless H.264 intermediate at 60fps, while logging all cursor movement, clicks, and key events to a separate file
2. **Post-process** — reads the event log to compute zoom animations (with look-ahead for smooth transitions), then renders each frame through a Metal GPU shader that applies the zoom transform

This means the zoom animations can start *before* your click — something real-time approaches can't do.

### Zoom sources

- **Manual markers** — press Cmd+Shift+Z during recording
- **Typing detection** — automatically detects sustained typing and zooms in (configurable sensitivity, or disable entirely)

Manual markers always take priority over auto-detected typing regions.

## Preferences

Open from the menu bar panel gear icon:

- Default zoom level and duration
- Typing detection sensitivity (low / medium / high / off)
- Hotkey bindings
- Export preset and save location

## Tech stack

- **Swift / SwiftUI** — menu bar app + review UI
- **ScreenCaptureKit** — screen capture (macOS 13+)
- **Metal** — GPU-accelerated zoom transform shader
- **AVFoundation** — video encoding/decoding, audio capture
- **VideoToolbox** — hardware H.264/HEVC encoding

## Project structure

```
RecordMe/
├── App/          # Menu bar app, state management, preferences, permissions
├── Capture/      # ScreenCaptureKit, event logging, audio, source picker
├── Zoom/         # Zoom engine, typing detector, animator, models
├── Review/       # Review window, timeline, marker editing, video preview
├── Export/       # Export pipeline, Metal zoom renderer, presets
├── Metal/        # Shared Metal context + zoom transform shader
└── Utils/        # Permissions, hotkeys, settings
```

## Roadmap

- [ ] Camera/webcam overlay (picture-in-picture)
- [ ] System audio capture
- [ ] Pre-built releases (DMG download)

## License

MIT
