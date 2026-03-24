# RecordMe

Lightweight macOS menu bar app that records your screen and applies cinematic auto-zoom effects in post-processing. Record → review zoom markers → export polished MP4.

## Quick Start

**Requirements:** macOS 13+ and Xcode (install from the App Store)

```bash
git clone https://github.com/angus-lau/RecordMe.git
cd RecordMe
make run
```

That's it. The app will build and launch in your menu bar.

**Other commands:**
- `make build` — build without launching
- `make install` — copy to /Applications
- `make clean` — remove build artifacts

**First launch:** Grant Screen Recording and Accessibility permissions when prompted. You may need to restart the app after granting Screen Recording.

## How to Use

1. Click the RecordMe icon in your menu bar
2. Select a capture source (display, window, or app)
3. Click **Start Recording**
4. Press **Cmd+Shift+Z** to drop zoom markers at points of interest
5. Press **Cmd+Shift+S** or click Stop to end recording
6. In the review window:
   - **Click a marker** to select it, **click the video** to set where it zooms
   - **Drag markers** along the timeline to reposition
   - **← → keys** adjust zoom level, **[ ] keys** adjust duration
   - **Drag yellow trim handles** to trim start/end
   - **Delete** to remove a marker
7. Pick an export preset and click **Export**

---

## Design Spec

**Target:** macOS 13+ (Ventura), Apple Silicon primary. Direct distribution via GitHub.

---

## Architecture Overview

Two-pass post-processing pipeline:

1. **Recording pass** — capture screen to a near-lossless H.264 intermediate + log all cursor/click/key events with timestamps
2. **Review** — user previews recording with zoom applied, adjusts/removes/adds zoom markers
3. **Export pass** — decode intermediate → apply Metal zoom transforms per frame → encode final H.264/HEVC MP4

### Why two-pass?

Post-processing allows the zoom engine to look ahead in the event stream, starting zoom animations *before* the triggering event for smoother cinematic transitions. It also lets the user review and edit zoom points before committing to a final render.

---

## Recording Pipeline

When the user hits "Start Recording":

1. **ScreenCaptureKit** captures the selected source (display, window, or app) at native retina resolution, 60fps
2. Each `CMSampleBuffer` frame is immediately encoded to a **high-bitrate H.264 intermediate** (~100-150 Mbps for 4K) via `AVAssetWriter` with VideoToolbox hardware encoder
3. **Mic audio** captured via `AVAudioEngine`, written as AAC track in the same intermediate file
4. **Event logger** runs in parallel via CGEvent tap:
   - `mouseMoved` → logs `(timestamp, x, y)`
   - `mouseDown` → logs `(timestamp, x, y, button)`
   - `keyDown` → logs `(timestamp, cursorX, cursorY)` — timestamps only, no key content
   - Hotkey press → logs `(timestamp, cursorX, cursorY, type: "manual_marker")`

**No system audio.** Mic only.

**No camera overlay** in v1. Planned as fast-follow.

### Recording output

```
~/.recordme/recordings/<session-id>/
├── intermediate.mp4    # Near-lossless H.264 + AAC mic audio
└── events.jsonl        # Cursor positions, clicks, key timings, manual markers
```

### Capture source selection

Three modes, selectable in the menu bar panel:

- **Full display** — `SCContentFilter(display:excludingWindows:)`
- **Specific window** — `SCContentFilter(desktopIndependentWindow:)`, selected from list of open windows grouped by app
- **Specific app** — `SCContentFilter(display:includingApplications:exceptingWindows:)`

When capturing a single window, cursor positions in the event log are stored relative to the window frame.

### Why H.264 intermediate over ProRes?

High-bitrate H.264 via VideoToolbox is hardware-accelerated on all Apple Silicon, produces excellent quality at ~100-150 Mbps, and AVPlayer handles it natively for the review UI. ProRes gives marginally better quality but significantly larger files and requires specific hardware support for encoding.

---

## Event Log Format

```jsonl
{"t": 0.000, "type": "cursor", "x": 512, "y": 384}
{"t": 0.250, "type": "click", "x": 510, "y": 382, "button": "left"}
{"t": 1.102, "type": "key", "x": 515, "y": 390}
{"t": 1.150, "type": "key", "x": 515, "y": 390}
{"t": 5.800, "type": "marker", "x": 800, "y": 600}
```

Timestamps are seconds from recording start, matching the intermediate video's timebase.

---

## Zoom Computation

The zoom engine processes the full event log after recording to produce a `ZoomTimeline` — an array of zoom regions:

```swift
struct ZoomRegion {
    let startTime: Double      // when zoom-in animation begins
    let endTime: Double        // when zoom-out animation begins
    let focalPoint: CGPoint    // center of zoom in screen coords
    let scale: CGFloat         // 1.5x–3x, default 2.0x
    let source: ZoomSource     // .manual or .typing
}
```

### Zoom sources

**Manual markers:** Each `"marker"` event becomes a `ZoomRegion` centered on cursor position. Default duration: 4 seconds (configurable). Default scale: 2.0x.

**Typing detection:** Sliding window scans for `"key"` events. 6+ key events within a 2-second window in a localized area (cursor hasn't moved >100px) triggers a typing burst. Region spans first-to-last key event + 1s padding on each end. Overlapping typing bursts merge.

### Conflict resolution

- Manual markers take priority over typing regions when they overlap (typing regions trimmed or removed)
- Minimum 1.5 seconds between zoom regions to avoid jarring rapid zoom in/out

### Animation timing

- **Zoom-in:** starts 300ms *before* the region's `startTime` (look-ahead)
- **Zoom-out:** eases out over 500ms after `endTime`
- **Easing:** cubic bezier `(0.25, 0.1, 0.25, 1.0)`
- **Between regions:** scale = 1.0 (full screen, no zoom)

### Per-frame state

```swift
struct ZoomState {
    var scale: CGFloat        // 1.0 = no zoom, 2.0 = 2x
    var focalPoint: CGPoint   // center of zoom in screen coordinates
    var animationProgress: CGFloat
}
```

---

## Review UI

Opens automatically after recording stops. Single-purpose: preview and adjust zoom points before export.

### Layout (top to bottom)

1. **Video preview** — AVPlayer playing the intermediate with Metal zoom transforms applied in real-time. Zoom level indicator overlay in corner.
2. **Transport controls** — play/pause, jump to prev/next marker, current time display
3. **Timeline strip** — horizontal bar with zoom markers as colored dots (purple = manual, amber = typing). Shaded regions show where zoom is active. Draggable white playhead.
4. **Selected marker panel** — appears when a marker is clicked. Shows zoom level and duration with keyboard controls to adjust.
5. **Action bar** — add marker button, discard button, export preset dropdown, export button.

### Interactions

| Action | Result |
|--------|--------|
| Click marker | Select it, show detail panel, jump playhead |
| Drag marker | Reposition in time |
| ← → keys | Adjust selected marker zoom level (1.5x → 2.0x → 2.5x → 3.0x) |
| [ ] keys | Adjust selected marker duration (shorter / longer) |
| Delete / ⌫ | Remove selected marker |
| Click empty timeline | Add new manual marker at that timestamp |
| ⏭ button | Jump playhead to next marker |
| Space | Play/pause preview |

### Implementation

- Video preview: `AVPlayer` with `AVPlayerLayer`, Metal overlay for zoom transform preview
- Timeline: custom SwiftUI view with drag gestures
- All native SwiftUI — no web views

---

## Export Pipeline

When the user clicks Export:

1. `AVAssetReader` decodes frames from intermediate
2. For each frame, compute `ZoomState` from the (possibly edited) `ZoomTimeline`
3. Metal render pass: sample source texture with zoom transform (scale + translate), clamped to screen bounds
4. `AVAssetWriter` with VideoToolbox hardware encoder writes final MP4
5. Mic audio track copied directly from intermediate (no re-encoding)

### Export presets

| Preset | Resolution | Notes |
|--------|-----------|-------|
| 1080p | 1920x1080 (1920x1200 for 16:10) | Smallest file |
| 4K | 3840x2160 (3840x2400 for 16:10) | High quality |
| Source | Native retina resolution | Largest file |

Codec: HEVC default, H.264 option. Aspect ratio always preserved.

### Performance

Hardware decode + Metal + hardware encode = real-time or faster on Apple Silicon. A 2-minute recording should export in under 2 minutes on M1+. Progress bar shown in the review window.

### Output location

Default: `~/Movies/RecordMe/`. Configurable in preferences. Finder opens to exported file on completion.

---

## Menu Bar App & UX Flow

### Menu bar panel

- Capture source picker: Display / Window / App tabs
- Mic selector dropdown
- Zoom hotkey display (click to rebind)
- "Start Recording" button
- Recent recordings list (last 5)
- Settings gear → preferences window

### Recording state

- Menu bar icon pulses red during recording
- Panel collapses to: stop button + elapsed time
- Hotkey to stop recording (configurable, default `Cmd+Shift+S`)

### Full flow

```
Click menu bar icon
  → Select capture source (display/window/app)
  → Toggle mic on/off
  → Click "Start Recording"
    → 3-second countdown overlay
    → Recording starts
    → Icon turns red
    → User works, presses hotkey to drop zoom markers
    → Stop via button or hotkey
  → Zoom engine processes event log (~1-2 seconds)
  → Review window opens
    → Preview, adjust/remove/add markers
    → Select export preset
    → Export
    → Progress bar → done → Finder opens
```

### Preferences window

- Zoom hotkey binding
- Stop recording hotkey binding
- Default zoom level (1.5x / 2.0x / 2.5x / 3.0x)
- Default zoom duration (2s / 4s / 6s)
- Typing detection sensitivity (low / medium / high) or on/off
- Default export preset
- Export save location
- Launch at login toggle

---

## Permissions & First Launch

### Required permissions

| Permission | Needed for | Required? |
|-----------|-----------|-----------|
| Screen Recording | ScreenCaptureKit capture | Yes |
| Accessibility | CGEvent tap (cursor/click/key tracking) | Yes for typing detection + cursor logging |
| Microphone | AVAudioEngine mic input | Optional (only if mic enabled) |

### First launch flow

Welcome window walks user through each permission:

1. **Screen Recording** — triggered automatically by ScreenCaptureKit
2. **Accessibility** — "Open Settings" button → System Settings > Privacy > Accessibility. App polls `AXIsProcessTrusted()` to detect when granted.
3. **Microphone** — `AVCaptureDevice.requestAccess(for: .audio)`, only if user enables mic

### Graceful degradation

If Accessibility is denied: recording still works, manual hotkey markers still work (`NSEvent.addGlobalMonitorForEvents` doesn't require Accessibility), but typing detection and cursor position logging are disabled. Note shown in preferences.

### Runtime checks

Before every recording start, verify Screen Recording and Accessibility are still granted. Alert if revoked.

---

## File Structure

```
RecordMe/
├── App/
│   ├── RecordMeApp.swift              # Menu bar app entry point
│   ├── MenuBarView.swift              # Menu bar panel
│   ├── PreferencesView.swift          # Settings window
│   └── PermissionsView.swift          # First-launch permission flow
├── Capture/
│   ├── CaptureSourcePicker.swift      # Display/window/app selection
│   ├── ScreenCaptureManager.swift     # ScreenCaptureKit → intermediate
│   ├── AudioCaptureManager.swift      # AVAudioEngine mic input
│   └── EventLogger.swift             # CGEvent tap → events.jsonl
├── Zoom/
│   ├── ZoomEngine.swift               # Processes event log → ZoomTimeline
│   ├── ZoomRegion.swift               # ZoomRegion model
│   ├── ZoomState.swift                # Per-frame zoom state
│   ├── TypingDetector.swift           # Key-event clustering
│   └── ZoomAnimator.swift            # Easing curves, interpolation
├── Review/
│   ├── ReviewWindow.swift             # Review window container
│   ├── VideoPreviewView.swift         # AVPlayer + Metal zoom preview
│   ├── TimelineView.swift             # Timeline strip with markers
│   ├── MarkerDetailView.swift         # Selected marker editing
│   └── ZoomTimelineController.swift   # Bridges UI edits ↔ ZoomTimeline
├── Export/
│   ├── ExportPipeline.swift           # AVAssetReader → Metal → AVAssetWriter
│   ├── MetalZoomRenderer.swift        # GPU zoom transform pass
│   └── ExportPreset.swift             # Resolution + codec presets
├── Metal/
│   ├── ZoomTransform.metal            # Scale + translate shader
│   └── MetalContext.swift             # Shared MTLDevice, command queue
├── Utils/
│   ├── Permissions.swift              # Permission check/request helpers
│   ├── HotkeyManager.swift           # Global hotkey registration
│   └── Settings.swift                 # UserDefaults wrapper
└── Resources/
    └── Assets.xcassets                # Menu bar icon, app icon
```

### Architectural boundaries

- **Capture/** knows nothing about zoom. Records raw intermediate + events.
- **Zoom/** knows nothing about UI or Metal. Processes event logs into `ZoomTimeline` data.
- **Review/** owns the editing UI. Uses `AVPlayer` for preview, talks to `MetalZoomRenderer` for live zoom preview.
- **Export/** consumes `ZoomTimeline` + intermediate → final MP4. Reuses `MetalZoomRenderer`.
- **Metal/** shared between Review (live preview) and Export (final render) — same shader, same renderer, different output targets.

---

## Out of Scope (v1)

- Camera/webcam overlay (planned fast-follow)
- System audio capture
- Video trimming / cutting
- Multiple export formats (MP4 only)
- Cloud storage / sharing
- App Store distribution
