# RecordMe Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar screen recorder with post-processed cinematic auto-zoom, manual zoom markers, a review/edit UI, and MP4 export.

**Architecture:** Two-pass pipeline — record screen to near-lossless H.264 intermediate + event log, then post-process with Metal zoom transforms and export via AVAssetWriter. SwiftUI menu bar app with native review window.

**Tech Stack:** Swift, SwiftUI, ScreenCaptureKit, Metal, AVFoundation, VideoToolbox, CGEvent

**Spec:** `README.md`

---

## Task 0: Xcode Project Setup

**Files:**
- Create: `RecordMe.xcodeproj` (via Xcode CLI)
- Create: `RecordMe/App/RecordMeApp.swift`
- Create: `RecordMe/Info.plist`
- Create: `RecordMe/RecordMe.entitlements`
- Create: `RecordMeTests/RecordMeTests.swift`

- [ ] **Step 1: Create Xcode project**

```bash
cd /Users/angus/Documents/Projects/RecordMe
# Create Swift package-based app project
mkdir -p RecordMe RecordMeTests
```

Use `swift package init` won't work for a macOS app — we need an Xcode project. Create it via the `xcodegen` approach or manually with a `Package.swift`-free structure.

Create the project with a minimal `project.yml` for XcodeGen:

```yaml
# project.yml
name: RecordMe
options:
  bundleIdPrefix: com.recordme
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
targets:
  RecordMe:
    type: application
    platform: macOS
    sources:
      - path: RecordMe
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.recordme.app
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SWIFT_VERSION: "5.9"
        CODE_SIGN_ENTITLEMENTS: RecordMe/RecordMe.entitlements
        INFOPLIST_FILE: RecordMe/Info.plist
    entitlements:
      path: RecordMe/RecordMe.entitlements
  RecordMeTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: RecordMeTests
    dependencies:
      - target: RecordMe
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.recordme.tests
```

Run: `brew install xcodegen && xcodegen generate`

- [ ] **Step 2: Create entitlements file**

```xml
<!-- RecordMe/RecordMe.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Create Info.plist with permission descriptions**

```xml
<!-- RecordMe/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>RecordMe needs microphone access to record voice narration with your screen recording.</string>
    <key>NSCameraUsageDescription</key>
    <string>RecordMe needs camera access for webcam overlay (future feature).</string>
</dict>
</plist>
```

Note: `LSUIElement = true` makes this a menu bar-only app (no dock icon).

- [ ] **Step 4: Create minimal app entry point**

```swift
// RecordMe/App/RecordMeApp.swift
import SwiftUI

@main
struct RecordMeApp: App {
    var body: some Scene {
        MenuBarExtra("RecordMe", systemImage: "record.circle") {
            Text("RecordMe")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 5: Create placeholder test**

```swift
// RecordMeTests/RecordMeTests.swift
import XCTest
@testable import RecordMe

final class RecordMeTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6: Build and verify**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMeTests -destination 'platform=macOS' test`
Expected: Test Suite passed

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: scaffold Xcode project with menu bar app shell"
```

---

## Task 1: Event Log Models & Serialization

**Files:**
- Create: `RecordMe/Capture/EventLog.swift`
- Create: `RecordMeTests/EventLogTests.swift`

Pure data models and JSONL read/write. Fully testable, no system dependencies.

- [ ] **Step 1: Write failing tests for event models and serialization**

```swift
// RecordMeTests/EventLogTests.swift
import XCTest
@testable import RecordMe

final class EventLogTests: XCTestCase {

    // MARK: - Encoding

    func testEncodeCursorEvent() throws {
        let event = InputEvent(t: 1.5, type: .cursor, x: 100, y: 200)
        let json = try event.toJSONLine()
        XCTAssertTrue(json.contains("\"type\":\"cursor\""))
        XCTAssertTrue(json.contains("\"x\":100"))
    }

    func testEncodeClickEvent() throws {
        let event = InputEvent(t: 2.0, type: .click, x: 50, y: 75, button: "left")
        let json = try event.toJSONLine()
        XCTAssertTrue(json.contains("\"button\":\"left\""))
    }

    func testEncodeKeyEvent() throws {
        let event = InputEvent(t: 3.0, type: .key, x: 200, y: 300)
        let json = try event.toJSONLine()
        XCTAssertFalse(json.contains("button"))
    }

    func testEncodeMarkerEvent() throws {
        let event = InputEvent(t: 5.0, type: .marker, x: 400, y: 500)
        let json = try event.toJSONLine()
        XCTAssertTrue(json.contains("\"type\":\"marker\""))
    }

    // MARK: - Decoding

    func testDecodeCursorEvent() throws {
        let json = #"{"t":1.5,"type":"cursor","x":100,"y":200}"#
        let event = try InputEvent.fromJSONLine(json)
        XCTAssertEqual(event.type, .cursor)
        XCTAssertEqual(event.x, 100)
        XCTAssertEqual(event.y, 200)
        XCTAssertEqual(event.t, 1.5)
    }

    func testDecodeClickEvent() throws {
        let json = #"{"t":2.0,"type":"click","x":50,"y":75,"button":"left"}"#
        let event = try InputEvent.fromJSONLine(json)
        XCTAssertEqual(event.type, .click)
        XCTAssertEqual(event.button, "left")
    }

    // MARK: - JSONL File I/O

    func testWriteAndReadEventsFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent("events.jsonl")

        let events = [
            InputEvent(t: 0.0, type: .cursor, x: 10, y: 20),
            InputEvent(t: 0.5, type: .click, x: 10, y: 20, button: "left"),
            InputEvent(t: 1.0, type: .marker, x: 30, y: 40),
        ]

        let writer = EventLogWriter(fileURL: file)
        try writer.open()
        for event in events {
            try writer.write(event)
        }
        writer.close()

        let loaded = try EventLogReader.read(from: file)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].type, .cursor)
        XCTAssertEqual(loaded[1].button, "left")
        XCTAssertEqual(loaded[2].type, .marker)

        try FileManager.default.removeItem(at: tmpDir)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RecordMe.xcodeproj -scheme RecordMeTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `InputEvent` not found

- [ ] **Step 3: Implement event log models**

```swift
// RecordMe/Capture/EventLog.swift
import Foundation

enum InputEventType: String, Codable {
    case cursor
    case click
    case key
    case marker
}

struct InputEvent: Codable {
    let t: Double
    let type: InputEventType
    let x: Double
    let y: Double
    var button: String?

    func toJSONLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }

    static func fromJSONLine(_ line: String) throws -> InputEvent {
        let data = Data(line.utf8)
        return try JSONDecoder().decode(InputEvent.self, from: data)
    }
}

final class EventLogWriter {
    private let fileURL: URL
    private var handle: FileHandle?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func open() throws {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try FileHandle(forWritingTo: fileURL)
    }

    func write(_ event: InputEvent) throws {
        let line = try event.toJSONLine() + "\n"
        handle?.write(Data(line.utf8))
    }

    func close() {
        handle?.closeFile()
        handle = nil
    }
}

enum EventLogReader {
    static func read(from fileURL: URL) throws -> [InputEvent] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try content
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .map { try InputEvent.fromJSONLine(String($0)) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RecordMe.xcodeproj -scheme RecordMeTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add RecordMe/Capture/EventLog.swift RecordMeTests/EventLogTests.swift
git commit -m "feat: event log models with JSONL serialization"
```

---

## Task 2: Zoom Models

**Files:**
- Create: `RecordMe/Zoom/ZoomRegion.swift`
- Create: `RecordMe/Zoom/ZoomState.swift`
- Create: `RecordMe/Export/ExportPreset.swift`
- Create: `RecordMeTests/ZoomModelTests.swift`

Pure data models. No logic beyond basic helpers.

- [ ] **Step 1: Write failing tests**

```swift
// RecordMeTests/ZoomModelTests.swift
import XCTest
@testable import RecordMe

final class ZoomModelTests: XCTestCase {

    func testZoomRegionDefaults() {
        let region = ZoomRegion(
            startTime: 1.0,
            endTime: 5.0,
            focalPoint: CGPoint(x: 100, y: 200),
            scale: 2.0,
            source: .manual
        )
        XCTAssertEqual(region.duration, 4.0)
        XCTAssertEqual(region.source, .manual)
    }

    func testZoomRegionOverlaps() {
        let a = ZoomRegion(startTime: 1.0, endTime: 5.0, focalPoint: .zero, scale: 2.0, source: .manual)
        let b = ZoomRegion(startTime: 4.0, endTime: 8.0, focalPoint: .zero, scale: 2.0, source: .typing)
        let c = ZoomRegion(startTime: 6.0, endTime: 9.0, focalPoint: .zero, scale: 2.0, source: .typing)
        XCTAssertTrue(a.overlaps(b))
        XCTAssertFalse(a.overlaps(c))
    }

    func testZoomStateIdentity() {
        let state = ZoomState.identity
        XCTAssertEqual(state.scale, 1.0)
        XCTAssertEqual(state.focalPoint, .zero)
        XCTAssertEqual(state.animationProgress, 0.0)
    }

    func testExportPresetResolutions() {
        let preset1080 = ExportPreset.hd1080p(codec: .hevc)
        XCTAssertEqual(preset1080.width, 1920)
        XCTAssertEqual(preset1080.height, 1080)

        let preset4k = ExportPreset.uhd4k(codec: .hevc)
        XCTAssertEqual(preset4k.width, 3840)
        XCTAssertEqual(preset4k.height, 2160)
    }

    func testExportPresetCodec() {
        let hevc = ExportPreset.hd1080p(codec: .hevc)
        let h264 = ExportPreset.hd1080p(codec: .h264)
        XCTAssertNotEqual(hevc.codec, h264.codec)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RecordMe.xcodeproj -scheme RecordMeTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Implement zoom models**

```swift
// RecordMe/Zoom/ZoomRegion.swift
import Foundation

enum ZoomSource: String, Codable {
    case manual
    case typing
}

struct ZoomRegion: Identifiable {
    let id = UUID()
    var startTime: Double
    var endTime: Double
    var focalPoint: CGPoint
    var scale: CGFloat
    var source: ZoomSource

    var duration: Double { endTime - startTime }

    func overlaps(_ other: ZoomRegion) -> Bool {
        startTime < other.endTime && endTime > other.startTime
    }
}
```

```swift
// RecordMe/Zoom/ZoomState.swift
import Foundation

struct ZoomState {
    var scale: CGFloat
    var focalPoint: CGPoint
    var animationProgress: CGFloat

    static let identity = ZoomState(scale: 1.0, focalPoint: .zero, animationProgress: 0.0)
}
```

```swift
// RecordMe/Export/ExportPreset.swift
import Foundation
import AVFoundation

enum VideoCodec: String {
    case h264
    case hevc

    var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

struct ExportPreset {
    let width: Int
    let height: Int
    let codec: VideoCodec
    let label: String

    static func hd1080p(codec: VideoCodec) -> ExportPreset {
        ExportPreset(width: 1920, height: 1080, codec: codec, label: "1080p")
    }

    static func uhd4k(codec: VideoCodec) -> ExportPreset {
        ExportPreset(width: 3840, height: 2160, codec: codec, label: "4K")
    }

    static func source(width: Int, height: Int, codec: VideoCodec) -> ExportPreset {
        ExportPreset(width: width, height: height, codec: codec, label: "Source")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RecordMe.xcodeproj -scheme RecordMeTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add RecordMe/Zoom/ZoomRegion.swift RecordMe/Zoom/ZoomState.swift RecordMe/Export/ExportPreset.swift RecordMeTests/ZoomModelTests.swift
git commit -m "feat: zoom region, zoom state, and export preset models"
```

---

## Task 3: Settings Manager

**Files:**
- Create: `RecordMe/Utils/Settings.swift`
- Create: `RecordMeTests/SettingsTests.swift`

UserDefaults wrapper with typed accessors for all preferences.

- [ ] **Step 1: Write failing tests**

```swift
// RecordMeTests/SettingsTests.swift
import XCTest
@testable import RecordMe

final class SettingsTests: XCTestCase {
    var settings: AppSettings!

    override func setUp() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        settings = AppSettings(defaults: defaults)
    }

    func testDefaultZoomLevel() {
        XCTAssertEqual(settings.defaultZoomLevel, 2.0)
    }

    func testDefaultZoomDuration() {
        XCTAssertEqual(settings.defaultZoomDuration, 4.0)
    }

    func testSetZoomLevel() {
        settings.defaultZoomLevel = 2.5
        XCTAssertEqual(settings.defaultZoomLevel, 2.5)
    }

    func testDefaultExportPresetLabel() {
        XCTAssertEqual(settings.defaultExportPresetLabel, "1080p")
    }

    func testDefaultCodec() {
        XCTAssertEqual(settings.defaultCodec, "hevc")
    }

    func testTypingDetectionEnabled() {
        XCTAssertTrue(settings.typingDetectionEnabled)
    }

    func testTypingDetectionSensitivity() {
        XCTAssertEqual(settings.typingDetectionSensitivity, "medium")
    }

    func testExportSaveLocation() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/RecordMe").path
        XCTAssertEqual(settings.exportSaveLocation, expected)
    }

    func testZoomHotkey() {
        XCTAssertEqual(settings.zoomHotkey, "cmd+shift+z")
    }

    func testStopHotkey() {
        XCTAssertEqual(settings.stopRecordingHotkey, "cmd+shift+s")
    }

    func testLaunchAtLogin() {
        XCTAssertFalse(settings.launchAtLogin)
        settings.launchAtLogin = true
        XCTAssertTrue(settings.launchAtLogin)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `AppSettings` not found

- [ ] **Step 3: Implement settings**

```swift
// RecordMe/Utils/Settings.swift
import Foundation

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        let exportPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/RecordMe").path
        defaults.register(defaults: [
            "defaultZoomLevel": 2.0,
            "defaultZoomDuration": 4.0,
            "defaultExportPresetLabel": "1080p",
            "defaultCodec": "hevc",
            "typingDetectionEnabled": true,
            "typingDetectionSensitivity": "medium",
            "exportSaveLocation": exportPath,
            "zoomHotkey": "cmd+shift+z",
            "stopRecordingHotkey": "cmd+shift+s",
            "launchAtLogin": false,
        ])
    }

    var defaultZoomLevel: CGFloat {
        get { defaults.double(forKey: "defaultZoomLevel") }
        set { defaults.set(newValue, forKey: "defaultZoomLevel") }
    }

    var defaultZoomDuration: Double {
        get { defaults.double(forKey: "defaultZoomDuration") }
        set { defaults.set(newValue, forKey: "defaultZoomDuration") }
    }

    var defaultExportPresetLabel: String {
        get { defaults.string(forKey: "defaultExportPresetLabel") ?? "1080p" }
        set { defaults.set(newValue, forKey: "defaultExportPresetLabel") }
    }

    var defaultCodec: String {
        get { defaults.string(forKey: "defaultCodec") ?? "hevc" }
        set { defaults.set(newValue, forKey: "defaultCodec") }
    }

    var typingDetectionEnabled: Bool {
        get { defaults.bool(forKey: "typingDetectionEnabled") }
        set { defaults.set(newValue, forKey: "typingDetectionEnabled") }
    }

    var typingDetectionSensitivity: String {
        get { defaults.string(forKey: "typingDetectionSensitivity") ?? "medium" }
        set { defaults.set(newValue, forKey: "typingDetectionSensitivity") }
    }

    var exportSaveLocation: String {
        get {
            defaults.string(forKey: "exportSaveLocation")
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Movies/RecordMe").path
        }
        set { defaults.set(newValue, forKey: "exportSaveLocation") }
    }

    var zoomHotkey: String {
        get { defaults.string(forKey: "zoomHotkey") ?? "cmd+shift+z" }
        set { defaults.set(newValue, forKey: "zoomHotkey") }
    }

    var stopRecordingHotkey: String {
        get { defaults.string(forKey: "stopRecordingHotkey") ?? "cmd+shift+s" }
        set { defaults.set(newValue, forKey: "stopRecordingHotkey") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add RecordMe/Utils/Settings.swift RecordMeTests/SettingsTests.swift
git commit -m "feat: app settings with UserDefaults persistence"
```

---

## Task 4: Zoom Animator

**Files:**
- Create: `RecordMe/Zoom/ZoomAnimator.swift`
- Create: `RecordMeTests/ZoomAnimatorTests.swift`

Pure math — cubic bezier easing and interpolation between zoom states. Fully testable.

- [ ] **Step 1: Write failing tests**

```swift
// RecordMeTests/ZoomAnimatorTests.swift
import XCTest
@testable import RecordMe

final class ZoomAnimatorTests: XCTestCase {

    func testCubicBezierAtZero() {
        let value = ZoomAnimator.cubicBezier(t: 0.0, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
        XCTAssertEqual(value, 0.0, accuracy: 0.001)
    }

    func testCubicBezierAtOne() {
        let value = ZoomAnimator.cubicBezier(t: 1.0, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
        XCTAssertEqual(value, 1.0, accuracy: 0.001)
    }

    func testCubicBezierMidpoint() {
        let value = ZoomAnimator.cubicBezier(t: 0.5, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
        // Should be > 0.5 due to ease-out curve
        XCTAssertGreaterThan(value, 0.5)
        XCTAssertLessThan(value, 1.0)
    }

    func testEaseInOut() {
        let value = ZoomAnimator.easeInOut(progress: 0.5)
        XCTAssertGreaterThan(value, 0.4)
        XCTAssertLessThan(value, 1.0)
    }

    func testZoomStateForTimestampBeforeRegion() {
        let region = ZoomRegion(
            startTime: 2.0, endTime: 6.0,
            focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual
        )
        let state = ZoomAnimator.zoomState(
            at: 0.5,
            regions: [region],
            zoomInDuration: 0.3,
            zoomOutDuration: 0.5
        )
        XCTAssertEqual(state.scale, 1.0, accuracy: 0.001)
    }

    func testZoomStateFullyInRegion() {
        let region = ZoomRegion(
            startTime: 2.0, endTime: 6.0,
            focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual
        )
        let state = ZoomAnimator.zoomState(
            at: 4.0,
            regions: [region],
            zoomInDuration: 0.3,
            zoomOutDuration: 0.5
        )
        XCTAssertEqual(state.scale, 2.0, accuracy: 0.001)
        XCTAssertEqual(state.focalPoint.x, 100, accuracy: 0.001)
    }

    func testZoomStateDuringZoomIn() {
        let region = ZoomRegion(
            startTime: 2.0, endTime: 6.0,
            focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual
        )
        // 0.3s zoom-in starts at 1.7 (startTime - 0.3)
        let state = ZoomAnimator.zoomState(
            at: 1.85, // midway through zoom-in
            regions: [region],
            zoomInDuration: 0.3,
            zoomOutDuration: 0.5
        )
        XCTAssertGreaterThan(state.scale, 1.0)
        XCTAssertLessThan(state.scale, 2.0)
    }

    func testZoomStateDuringZoomOut() {
        let region = ZoomRegion(
            startTime: 2.0, endTime: 6.0,
            focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual
        )
        // 0.5s zoom-out starts at endTime (6.0) and ends at 6.5
        let state = ZoomAnimator.zoomState(
            at: 6.25, // midway through zoom-out
            regions: [region],
            zoomInDuration: 0.3,
            zoomOutDuration: 0.5
        )
        XCTAssertGreaterThan(state.scale, 1.0)
        XCTAssertLessThan(state.scale, 2.0)
    }

    func testZoomStateAfterRegion() {
        let region = ZoomRegion(
            startTime: 2.0, endTime: 6.0,
            focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual
        )
        let state = ZoomAnimator.zoomState(
            at: 10.0,
            regions: [region],
            zoomInDuration: 0.3,
            zoomOutDuration: 0.5
        )
        XCTAssertEqual(state.scale, 1.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `ZoomAnimator` not found

- [ ] **Step 3: Implement zoom animator**

```swift
// RecordMe/Zoom/ZoomAnimator.swift
import Foundation

enum ZoomAnimator {

    /// Cubic bezier easing. Control points: (x1, y1), (x2, y2).
    /// Input t is normalized time [0, 1], output is eased value [0, 1].
    static func cubicBezier(t: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        // Newton's method to find parameter for given t on the x-curve,
        // then evaluate y-curve at that parameter.
        var guess = t
        for _ in 0..<8 {
            let xGuess = sampleCurve(guess, p1: x1, p2: x2)
            let slope = sampleCurveDerivative(guess, p1: x1, p2: x2)
            if abs(slope) < 1e-6 { break }
            guess -= (xGuess - t) / slope
        }
        return sampleCurve(guess, p1: y1, p2: y2)
    }

    private static func sampleCurve(_ t: Double, p1: Double, p2: Double) -> Double {
        ((1.0 - 3.0 * p2 + 3.0 * p1) * t + (3.0 * p2 - 6.0 * p1)) * t + 3.0 * p1 * t
    }

    // swiftlint:disable:next identifier_name
    private static func sampleCurveDerivative(_ t: Double, p1: Double, p2: Double) -> Double {
        (3.0 * (1.0 - 3.0 * p2 + 3.0 * p1)) * t * t + (2.0 * (3.0 * p2 - 6.0 * p1)) * t + 3.0 * p1
    }

    /// Default ease-in-out curve: cubic-bezier(0.25, 0.1, 0.25, 1.0)
    static func easeInOut(progress: Double) -> Double {
        cubicBezier(t: max(0, min(1, progress)), x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
    }

    /// Compute ZoomState for a given timestamp against an array of zoom regions.
    /// zoomInDuration: how long the zoom-in animation takes (starts before region.startTime)
    /// zoomOutDuration: how long the zoom-out animation takes (starts at region.endTime)
    static func zoomState(
        at timestamp: Double,
        regions: [ZoomRegion],
        zoomInDuration: Double = 0.3,
        zoomOutDuration: Double = 0.5
    ) -> ZoomState {
        for region in regions {
            let zoomInStart = region.startTime - zoomInDuration
            let zoomOutEnd = region.endTime + zoomOutDuration

            // Before this region's influence
            if timestamp < zoomInStart { continue }
            // After this region's influence
            if timestamp > zoomOutEnd { continue }

            // During zoom-in animation
            if timestamp < region.startTime {
                let progress = (timestamp - zoomInStart) / zoomInDuration
                let eased = easeInOut(progress: progress)
                let scale = 1.0 + (region.scale - 1.0) * eased
                return ZoomState(
                    scale: scale,
                    focalPoint: region.focalPoint,
                    animationProgress: eased
                )
            }

            // Fully zoomed in
            if timestamp <= region.endTime {
                return ZoomState(
                    scale: region.scale,
                    focalPoint: region.focalPoint,
                    animationProgress: 1.0
                )
            }

            // During zoom-out animation
            let progress = (timestamp - region.endTime) / zoomOutDuration
            let eased = easeInOut(progress: progress)
            let scale = region.scale - (region.scale - 1.0) * eased
            return ZoomState(
                scale: scale,
                focalPoint: region.focalPoint,
                animationProgress: 1.0 - eased
            )
        }

        return .identity
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add RecordMe/Zoom/ZoomAnimator.swift RecordMeTests/ZoomAnimatorTests.swift
git commit -m "feat: zoom animator with cubic bezier easing"
```

---

## Task 5: Typing Detector

**Files:**
- Create: `RecordMe/Zoom/TypingDetector.swift`
- Create: `RecordMeTests/TypingDetectorTests.swift`

Sliding window algorithm over event log. Fully testable, no system dependencies.

- [ ] **Step 1: Write failing tests**

```swift
// RecordMeTests/TypingDetectorTests.swift
import XCTest
@testable import RecordMe

final class TypingDetectorTests: XCTestCase {

    func testNoKeysNoRegions() {
        let events: [InputEvent] = [
            InputEvent(t: 0.0, type: .cursor, x: 100, y: 100),
            InputEvent(t: 1.0, type: .click, x: 100, y: 100, button: "left"),
        ]
        let regions = TypingDetector.detect(events: events)
        XCTAssertTrue(regions.isEmpty)
    }

    func testFewKeysNoRegion() {
        // Only 3 key events — below threshold of 6
        let events: [InputEvent] = [
            InputEvent(t: 1.0, type: .key, x: 100, y: 100),
            InputEvent(t: 1.2, type: .key, x: 100, y: 100),
            InputEvent(t: 1.4, type: .key, x: 100, y: 100),
        ]
        let regions = TypingDetector.detect(events: events)
        XCTAssertTrue(regions.isEmpty)
    }

    func testTypingBurstCreatesRegion() {
        // 8 key events within 2 seconds, same area
        let events = (0..<8).map { i in
            InputEvent(t: 1.0 + Double(i) * 0.2, x: 100, y: 100)
        }
        let regions = TypingDetector.detect(events: events)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].source, .typing)
        // Region starts 1s before first key, ends 1s after last key
        XCTAssertEqual(regions[0].startTime, 0.0, accuracy: 0.01) // 1.0 - 1.0
        XCTAssertEqual(regions[0].endTime, 3.4, accuracy: 0.01)   // 2.4 + 1.0
    }

    func testCursorMovementBreaksBurst() {
        // Keys spread across distant screen positions
        let events: [InputEvent] = [
            InputEvent(t: 1.0, type: .key, x: 100, y: 100),
            InputEvent(t: 1.2, type: .key, x: 100, y: 100),
            InputEvent(t: 1.4, type: .key, x: 100, y: 100),
            InputEvent(t: 1.6, type: .key, x: 500, y: 500), // jumped >100px
            InputEvent(t: 1.8, type: .key, x: 500, y: 500),
            InputEvent(t: 2.0, type: .key, x: 500, y: 500),
        ]
        let regions = TypingDetector.detect(events: events)
        // Neither cluster has 6+ events, so no regions
        XCTAssertTrue(regions.isEmpty)
    }

    func testOverlappingBurstsMerge() {
        // Two bursts close together that should merge
        var events: [InputEvent] = []
        // Burst 1: 8 keys at t=1.0-2.4
        for i in 0..<8 {
            events.append(InputEvent(t: 1.0 + Double(i) * 0.2, x: 100, y: 100))
        }
        // Burst 2: 8 keys at t=3.0-4.4 (overlaps with padding of burst 1)
        for i in 0..<8 {
            events.append(InputEvent(t: 3.0 + Double(i) * 0.2, x: 105, y: 105))
        }
        let regions = TypingDetector.detect(events: events)
        // Should merge because burst1 end+padding (3.4) overlaps burst2 start-padding (2.0)
        XCTAssertEqual(regions.count, 1)
    }

    func testSensitivityAdjustsThreshold() {
        // With low sensitivity, need more keys
        let events = (0..<8).map { i in
            InputEvent(t: 1.0 + Double(i) * 0.2, x: 100, y: 100)
        }
        let lowRegions = TypingDetector.detect(events: events, sensitivity: .low)
        let highRegions = TypingDetector.detect(events: events, sensitivity: .high)
        // High sensitivity should detect with fewer keys than low
        XCTAssertGreaterThanOrEqual(highRegions.count, lowRegions.count)
    }
}

private extension InputEvent {
    /// Convenience init for key events in tests
    init(t: Double, x: Double, y: Double) {
        self.init(t: t, type: .key, x: x, y: y)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `TypingDetector` not found

- [ ] **Step 3: Implement typing detector**

```swift
// RecordMe/Zoom/TypingDetector.swift
import Foundation

enum TypingSensitivity: String {
    case low     // 10 keys in 2s window
    case medium  // 6 keys in 2s window
    case high    // 4 keys in 2s window

    var minKeys: Int {
        switch self {
        case .low: return 10
        case .medium: return 6
        case .high: return 4
        }
    }
}

enum TypingDetector {

    private static let windowDuration: Double = 2.0
    private static let maxCursorDrift: Double = 100.0
    private static let padding: Double = 1.0

    static func detect(
        events: [InputEvent],
        sensitivity: TypingSensitivity = .medium,
        defaultScale: CGFloat = 2.0
    ) -> [ZoomRegion] {
        let keyEvents = events.filter { $0.type == .key }.sorted { $0.t < $1.t }
        guard keyEvents.count >= sensitivity.minKeys else { return [] }

        var bursts: [(start: Double, end: Double, centroidX: Double, centroidY: Double)] = []
        var i = 0

        while i < keyEvents.count {
            var j = i
            var clusterX = keyEvents[i].x
            var clusterY = keyEvents[i].y

            // Expand window while keys are within time window and spatial proximity
            while j + 1 < keyEvents.count {
                let next = keyEvents[j + 1]
                let timeDelta = next.t - keyEvents[i].t
                if timeDelta > windowDuration { break }
                let dist = hypot(next.x - clusterX, next.y - clusterY)
                if dist > maxCursorDrift { break }
                j += 1
                // Running average for centroid
                let count = Double(j - i + 1)
                clusterX = clusterX + (next.x - clusterX) / count
                clusterY = clusterY + (next.y - clusterY) / count
            }

            let count = j - i + 1
            if count >= sensitivity.minKeys {
                bursts.append((
                    start: keyEvents[i].t,
                    end: keyEvents[j].t,
                    centroidX: clusterX,
                    centroidY: clusterY
                ))
                i = j + 1
            } else {
                i += 1
            }
        }

        // Apply padding and merge overlapping bursts
        var regions: [ZoomRegion] = []
        for burst in bursts {
            let paddedStart = max(0, burst.start - padding)
            let paddedEnd = burst.end + padding

            if let last = regions.last, paddedStart <= last.endTime {
                // Merge: extend the last region
                var merged = regions.removeLast()
                merged.endTime = max(merged.endTime, paddedEnd)
                regions.append(merged)
            } else {
                regions.append(ZoomRegion(
                    startTime: paddedStart,
                    endTime: paddedEnd,
                    focalPoint: CGPoint(x: burst.centroidX, y: burst.centroidY),
                    scale: defaultScale,
                    source: .typing
                ))
            }
        }

        return regions
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add RecordMe/Zoom/TypingDetector.swift RecordMeTests/TypingDetectorTests.swift
git commit -m "feat: typing burst detector with sensitivity levels"
```

---

## Task 6: Zoom Engine

**Files:**
- Create: `RecordMe/Zoom/ZoomEngine.swift`
- Create: `RecordMeTests/ZoomEngineTests.swift`

Orchestrates marker extraction + typing detection → `ZoomTimeline` with conflict resolution. Depends on Tasks 1, 2, 4, 5.

- [ ] **Step 1: Write failing tests**

```swift
// RecordMeTests/ZoomEngineTests.swift
import XCTest
@testable import RecordMe

final class ZoomEngineTests: XCTestCase {

    func testManualMarkersCreateRegions() {
        let events: [InputEvent] = [
            InputEvent(t: 2.0, type: .marker, x: 100, y: 200),
            InputEvent(t: 8.0, type: .marker, x: 300, y: 400),
        ]
        let timeline = ZoomEngine.process(
            events: events,
            defaultScale: 2.0,
            defaultDuration: 4.0,
            typingDetectionEnabled: false
        )
        XCTAssertEqual(timeline.regions.count, 2)
        XCTAssertEqual(timeline.regions[0].focalPoint.x, 100, accuracy: 0.01)
        XCTAssertEqual(timeline.regions[0].source, .manual)
        XCTAssertEqual(timeline.regions[0].duration, 4.0, accuracy: 0.01)
    }

    func testManualMarkerPriorityOverTyping() {
        var events: [InputEvent] = []
        // Typing burst at t=2.0-3.4
        for i in 0..<8 {
            events.append(InputEvent(t: 2.0 + Double(i) * 0.2, type: .key, x: 100, y: 100))
        }
        // Manual marker overlapping the typing burst
        events.append(InputEvent(t: 2.5, type: .marker, x: 100, y: 100))

        let timeline = ZoomEngine.process(
            events: events,
            defaultScale: 2.0,
            defaultDuration: 4.0,
            typingDetectionEnabled: true
        )
        // Manual marker should be present, typing region should be removed or trimmed
        let manualRegions = timeline.regions.filter { $0.source == .manual }
        XCTAssertEqual(manualRegions.count, 1)
    }

    func testGapEnforcement() {
        let events: [InputEvent] = [
            InputEvent(t: 1.0, type: .marker, x: 100, y: 100),
            InputEvent(t: 2.0, type: .marker, x: 200, y: 200), // only 1s gap — too close
        ]
        let timeline = ZoomEngine.process(
            events: events,
            defaultScale: 2.0,
            defaultDuration: 1.0, // 1s duration so regions would be t=0.5-1.5 and t=1.5-2.5
            typingDetectionEnabled: false
        )
        // Second region should be adjusted to maintain 1.5s gap
        if timeline.regions.count == 2 {
            let gap = timeline.regions[1].startTime - timeline.regions[0].endTime
            XCTAssertGreaterThanOrEqual(gap, 1.5, accuracy: 0.01)
        }
    }

    func testNoEventsEmptyTimeline() {
        let timeline = ZoomEngine.process(
            events: [],
            defaultScale: 2.0,
            defaultDuration: 4.0,
            typingDetectionEnabled: true
        )
        XCTAssertTrue(timeline.regions.isEmpty)
    }

    func testTypingDisabledIgnoresKeyEvents() {
        var events: [InputEvent] = []
        for i in 0..<8 {
            events.append(InputEvent(t: 1.0 + Double(i) * 0.2, type: .key, x: 100, y: 100))
        }
        let timeline = ZoomEngine.process(
            events: events,
            defaultScale: 2.0,
            defaultDuration: 4.0,
            typingDetectionEnabled: false
        )
        XCTAssertTrue(timeline.regions.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `ZoomEngine` not found

- [ ] **Step 3: Implement zoom engine**

```swift
// RecordMe/Zoom/ZoomEngine.swift
import Foundation

struct ZoomTimeline {
    var regions: [ZoomRegion]

    func zoomState(at timestamp: Double) -> ZoomState {
        ZoomAnimator.zoomState(at: timestamp, regions: regions)
    }
}

enum ZoomEngine {
    private static let minimumGap: Double = 1.5

    static func process(
        events: [InputEvent],
        defaultScale: CGFloat,
        defaultDuration: Double,
        typingDetectionEnabled: Bool,
        typingSensitivity: TypingSensitivity = .medium
    ) -> ZoomTimeline {
        // 1. Extract manual markers
        var manualRegions = events
            .filter { $0.type == .marker }
            .map { event in
                ZoomRegion(
                    startTime: event.t - defaultDuration / 2,
                    endTime: event.t + defaultDuration / 2,
                    focalPoint: CGPoint(x: event.x, y: event.y),
                    scale: defaultScale,
                    source: .manual
                )
            }

        // 2. Detect typing regions if enabled
        var typingRegions: [ZoomRegion] = []
        if typingDetectionEnabled {
            typingRegions = TypingDetector.detect(
                events: events,
                sensitivity: typingSensitivity,
                defaultScale: defaultScale
            )
        }

        // 3. Resolve conflicts — manual wins
        typingRegions = typingRegions.filter { typing in
            !manualRegions.contains { $0.overlaps(typing) }
        }

        // 4. Merge and sort all regions by start time
        var allRegions = (manualRegions + typingRegions).sorted { $0.startTime < $1.startTime }

        // 5. Enforce minimum gap between regions
        allRegions = enforceGaps(allRegions)

        return ZoomTimeline(regions: allRegions)
    }

    private static func enforceGaps(_ regions: [ZoomRegion]) -> [ZoomRegion] {
        guard regions.count > 1 else { return regions }
        var result = [regions[0]]

        for i in 1..<regions.count {
            var region = regions[i]
            let prev = result[result.count - 1]
            let gap = region.startTime - prev.endTime

            if gap < minimumGap {
                // Push the start of this region forward
                let shift = minimumGap - gap
                region.startTime += shift
                region.endTime += shift
            }
            result.append(region)
        }

        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add RecordMe/Zoom/ZoomEngine.swift RecordMeTests/ZoomEngineTests.swift
git commit -m "feat: zoom engine with marker extraction, typing detection, and conflict resolution"
```

---

## Task 7: Permissions Helper

**Files:**
- Create: `RecordMe/Utils/Permissions.swift`

System API calls — not unit-testable, verify manually.

- [ ] **Step 1: Implement permissions helper**

```swift
// RecordMe/Utils/Permissions.swift
import AVFoundation
import ScreenCaptureKit

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum Permissions {

    // MARK: - Screen Recording

    static func checkScreenRecording() async -> PermissionStatus {
        do {
            // Requesting shareable content triggers the permission prompt if not yet granted
            _ = try await SCShareableContent.current
            return .granted
        } catch {
            return .denied
        }
    }

    // MARK: - Accessibility

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Microphone

    static func checkMicrophone() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/Utils/Permissions.swift
git commit -m "feat: permission check and request helpers"
```

---

## Task 8: Hotkey Manager

**Files:**
- Create: `RecordMe/Utils/HotkeyManager.swift`

Global hotkey registration via `NSEvent.addGlobalMonitorForEvents`. Not unit-testable, verify manually.

- [ ] **Step 1: Implement hotkey manager**

```swift
// RecordMe/Utils/HotkeyManager.swift
import Cocoa

final class HotkeyManager {
    private var monitors: [Any] = []

    typealias HotkeyHandler = () -> Void

    private var zoomHandler: HotkeyHandler?
    private var stopHandler: HotkeyHandler?

    // Parsed hotkey config: (modifiers, key character)
    private var zoomModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var zoomKey: String = "z"
    private var stopModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var stopKey: String = "s"

    func configure(settings: AppSettings) {
        (zoomModifiers, zoomKey) = parseHotkey(settings.zoomHotkey)
        (stopModifiers, stopKey) = parseHotkey(settings.stopRecordingHotkey)
    }

    func registerZoomHotkey(_ handler: @escaping HotkeyHandler) {
        zoomHandler = handler
    }

    func registerStopHotkey(_ handler: @escaping HotkeyHandler) {
        stopHandler = handler
    }

    func startListening() {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        if let monitor { monitors.append(monitor) }
    }

    func stopListening() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == zoomModifiers && key == zoomKey {
            zoomHandler?()
        }

        if flags == stopModifiers && key == stopKey {
            stopHandler?()
        }
    }

    /// Parse "cmd+shift+z" format into (ModifierFlags, key)
    private func parseHotkey(_ hotkey: String) -> (NSEvent.ModifierFlags, String) {
        let parts = hotkey.lowercased().split(separator: "+").map(String.init)
        var flags: NSEvent.ModifierFlags = []
        var key = ""
        for part in parts {
            switch part {
            case "cmd", "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "alt", "option": flags.insert(.option)
            case "ctrl", "control": flags.insert(.control)
            default: key = part
            }
        }
        return (flags, key)
    }

    deinit {
        stopListening()
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/Utils/HotkeyManager.swift
git commit -m "feat: global hotkey manager for zoom markers and stop recording"
```

---

## Task 9: Event Logger

**Files:**
- Create: `RecordMe/Capture/EventLogger.swift`

CGEvent tap for cursor/click/key tracking during recording. Writes to events.jsonl via `EventLogWriter` from Task 1. System-dependent, not unit-testable.

- [ ] **Step 1: Implement event logger**

```swift
// RecordMe/Capture/EventLogger.swift
import Cocoa

final class EventLogger {
    private var writer: EventLogWriter?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startTime: Double = 0
    private let cursorSampleInterval: Double = 0.05 // 50ms throttle
    private var lastCursorLogTime: Double = 0

    func start(fileURL: URL) throws {
        let w = EventLogWriter(fileURL: fileURL)
        try w.open()
        writer = w
        startTime = CACurrentMediaTime()
        lastCursorLogTime = 0
        startEventTap()
    }

    func stop() {
        stopEventTap()
        writer?.close()
        writer = nil
    }

    func logManualMarker() {
        let pos = NSEvent.mouseLocation
        let t = CACurrentMediaTime() - startTime
        let event = InputEvent(t: t, type: .marker, x: pos.x, y: pos.y)
        try? writer?.write(event)
    }

    // MARK: - CGEvent Tap

    private func startEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, cgEvent, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
            let logger = Unmanaged<EventLogger>.fromOpaque(userInfo).takeUnretainedValue()
            logger.handleCGEvent(type: type, event: cgEvent)
            return Unmanaged.passRetained(cgEvent)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("EventLogger: Failed to create event tap — Accessibility permission required")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        let t = CACurrentMediaTime() - startTime
        let location = event.location // screen coordinates

        switch type {
        case .mouseMoved:
            // Throttle cursor events
            guard t - lastCursorLogTime >= cursorSampleInterval else { return }
            lastCursorLogTime = t
            let inputEvent = InputEvent(t: t, type: .cursor, x: location.x, y: location.y)
            try? writer?.write(inputEvent)

        case .leftMouseDown:
            let inputEvent = InputEvent(t: t, type: .click, x: location.x, y: location.y, button: "left")
            try? writer?.write(inputEvent)

        case .rightMouseDown:
            let inputEvent = InputEvent(t: t, type: .click, x: location.x, y: location.y, button: "right")
            try? writer?.write(inputEvent)

        case .keyDown:
            // Log timestamp and cursor position only — no key content
            let cursorPos = NSEvent.mouseLocation
            let inputEvent = InputEvent(t: t, type: .key, x: cursorPos.x, y: cursorPos.y)
            try? writer?.write(inputEvent)

        default:
            break
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/Capture/EventLogger.swift
git commit -m "feat: CGEvent tap event logger with cursor throttling"
```

---

## Task 10: Screen Capture Manager

**Files:**
- Create: `RecordMe/Capture/ScreenCaptureManager.swift`

ScreenCaptureKit stream → near-lossless H.264 intermediate via AVAssetWriter. System-dependent.

- [ ] **Step 1: Implement screen capture manager**

```swift
// RecordMe/Capture/ScreenCaptureManager.swift
import AVFoundation
import ScreenCaptureKit

final class ScreenCaptureManager: NSObject {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var isRecording = false
    private var sessionStarted = false

    var intermediateFileURL: URL?
    private(set) var assetWriterExposed: AVAssetWriter? // Exposed for AudioCaptureManager

    /// sessionDir: the already-created session directory (e.g. ~/.recordme/recordings/<uuid>/)
    /// The intermediate file will be written as sessionDir/intermediate.mp4
    func startRecording(
        filter: SCContentFilter,
        sessionDir: URL
    ) async throws {
        let fileURL = sessionDir.appendingPathComponent("intermediate.mp4")
        intermediateFileURL = fileURL

        // Configure stream
        let config = SCStreamConfiguration()
        let display = try await SCShareableContent.current.displays.first!
        config.width = display.width * 2  // retina
        config.height = display.height * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.capturesAudio = false // mic is handled separately

        // Configure AVAssetWriter
        let writer = try AVAssetWriter(url: fileURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 120_000_000, // ~120 Mbps near-lossless
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)

        assetWriter = writer
        assetWriterExposed = writer
        videoInput = vInput

        // Start writing
        writer.startWriting()

        // Start capture stream
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try await s.startCapture()
        stream = s
        isRecording = true
    }

    func stopRecording() async throws -> URL {
        guard let stream, let writer = assetWriter else {
            throw RecordMeError.notRecording
        }
        isRecording = false

        try await stream.stopCapture()
        self.stream = nil

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        await writer.finishWriting()
        let url = writer.outputURL
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        sessionStarted = false

        return url
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("ScreenCaptureManager: stream stopped with error: \(error)")
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, type == .screen, let videoInput, videoInput.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        videoInput.append(sampleBuffer)
    }
}

enum RecordMeError: Error {
    case notRecording
    case exportFailed(String)
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/Capture/ScreenCaptureManager.swift
git commit -m "feat: screen capture manager with ScreenCaptureKit and AVAssetWriter"
```

---

## Task 11: Capture Source Picker

**Files:**
- Create: `RecordMe/Capture/CaptureSourcePicker.swift`

Queries `SCShareableContent` for available displays, windows, and apps. Provides `SCContentFilter` for the selected source.

- [ ] **Step 1: Implement capture source picker**

```swift
// RecordMe/Capture/CaptureSourcePicker.swift
import ScreenCaptureKit

enum CaptureSourceType {
    case display(SCDisplay)
    case window(SCWindow)
    case app(SCRunningApplication, SCDisplay)
}

@MainActor
final class CaptureSourcePicker: ObservableObject {
    @Published var displays: [SCDisplay] = []
    @Published var windows: [SCWindow] = []
    @Published var apps: [SCRunningApplication] = []
    @Published var selectedSource: CaptureSourceType?

    func refresh() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays
            windows = content.windows.filter { $0.isOnScreen && $0.frame.width > 50 }
            apps = content.applications.filter { !$0.applicationName.isEmpty }

            // Default to first display
            if selectedSource == nil, let display = displays.first {
                selectedSource = .display(display)
            }
        } catch {
            print("CaptureSourcePicker: Failed to get shareable content: \(error)")
        }
    }

    func buildFilter() -> SCContentFilter? {
        guard let source = selectedSource else { return nil }
        switch source {
        case .display(let display):
            return SCContentFilter(display: display, excludingWindows: [])
        case .window(let window):
            return SCContentFilter(desktopIndependentWindow: window)
        case .app(let app, let display):
            return SCContentFilter(display: display, includingApplications: [app], exceptingWindows: [])
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/Capture/CaptureSourcePicker.swift
git commit -m "feat: capture source picker for display, window, and app selection"
```

---

## Task 12: Audio Capture Manager

**Files:**
- Create: `RecordMe/Capture/AudioCaptureManager.swift`

AVAudioEngine mic input. Provides audio buffers that get written alongside video.

- [ ] **Step 1: Implement audio capture manager**

```swift
// RecordMe/Capture/AudioCaptureManager.swift
import AVFoundation

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var isRecording = false

    func attachToWriter(_ writer: AVAssetWriter) {
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) {
            writer.add(input)
        }
        audioInput = input
        assetWriter = writer
    }

    func startCapture() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.handleAudioBuffer(buffer, time: time)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stopCapture() {
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioInput?.markAsFinished()
        audioInput = nil
        assetWriter = nil
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard isRecording, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        guard let sampleBuffer = buffer.toCMSampleBuffer(time: time) else { return }
        audioInput.append(sampleBuffer)
    }
}

private extension AVAudioPCMBuffer {
    func toCMSampleBuffer(time: AVAudioTime) -> CMSampleBuffer? {
        let framesCount = CMItemCount(frameLength)
        let bytesPerFrame = CMItemCount(format.streamDescription.pointee.mBytesPerFrame)
        let blockSize = framesCount * bytesPerFrame

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: blockSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: blockSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else { return nil }

        guard CMBlockBufferReplaceDataBytes(
            with: audioBufferList.pointee.mBuffers.mData!,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: blockSize
        ) == noErr else { return nil }

        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: format.streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )

        var sampleBuffer: CMSampleBuffer?
        let sampleRate = format.sampleRate
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(frameLength), timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(
                seconds: AVAudioTime.seconds(forHostTime: time.hostTime),
                preferredTimescale: CMTimeScale(sampleRate)
            ),
            decodeTimeStamp: .invalid
        )

        guard let formatDesc else { return nil }
        var sampleSize = blockSize
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: framesCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/Capture/AudioCaptureManager.swift
git commit -m "feat: audio capture manager with AVAudioEngine mic input"
```

---

## Task 13: Metal Context & Zoom Shader

**Files:**
- Create: `RecordMe/Metal/MetalContext.swift`
- Create: `RecordMe/Metal/ZoomTransform.metal`

Shared Metal device/queue and the zoom transform compute shader.

- [ ] **Step 1: Create Metal context**

```swift
// RecordMe/Metal/MetalContext.swift
import Metal

final class MetalContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let zoomPipeline: MTLComputePipelineState

    static let shared: MetalContext = {
        do {
            return try MetalContext()
        } catch {
            fatalError("MetalContext: Failed to initialize Metal: \(error)")
        }
    }()

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RecordMeError.exportFailed("No Metal device available")
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw RecordMeError.exportFailed("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            throw RecordMeError.exportFailed("Failed to load Metal shader library")
        }
        self.library = library

        guard let function = library.makeFunction(name: "zoomTransform") else {
            throw RecordMeError.exportFailed("Failed to find zoomTransform function")
        }
        self.zoomPipeline = try device.makeComputePipelineState(function: function)
    }
}
```

- [ ] **Step 2: Create zoom transform shader**

```metal
// RecordMe/Metal/ZoomTransform.metal
#include <metal_stdlib>
using namespace metal;

struct ZoomParams {
    float scale;      // 1.0 = no zoom, 2.0 = 2x
    float focalX;     // focal point X in normalized coords [0, 1]
    float focalY;     // focal point Y in normalized coords [0, 1]
    uint outputWidth;
    uint outputHeight;
    uint sourceWidth;
    uint sourceHeight;
};

kernel void zoomTransform(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant ZoomParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.outputWidth || gid.y >= params.outputHeight) return;

    // Normalize output pixel position to [0, 1]
    float u = float(gid.x) / float(params.outputWidth);
    float v = float(gid.y) / float(params.outputHeight);

    // Apply inverse zoom: map output pixel back to source coordinates
    // Zoom is centered on focalPoint
    float srcU = params.focalX + (u - 0.5) / params.scale;
    float srcV = params.focalY + (v - 0.5) / params.scale;

    // Clamp to source bounds
    srcU = clamp(srcU, 0.0, 1.0);
    srcV = clamp(srcV, 0.0, 1.0);

    // Sample source texture
    uint srcX = uint(srcU * float(params.sourceWidth - 1));
    uint srcY = uint(srcV * float(params.sourceHeight - 1));

    float4 color = source.read(uint2(srcX, srcY));
    dest.write(color, gid);
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add RecordMe/Metal/MetalContext.swift RecordMe/Metal/ZoomTransform.metal
git commit -m "feat: Metal context and zoom transform compute shader"
```

---

## Task 14: Metal Zoom Renderer

**Files:**
- Create: `RecordMe/Export/MetalZoomRenderer.swift`

Takes a source `CVPixelBuffer`, applies zoom transform via Metal, outputs to destination buffer. Shared between review preview and export.

- [ ] **Step 1: Implement Metal zoom renderer**

```swift
// RecordMe/Export/MetalZoomRenderer.swift
import Metal
import CoreVideo
import CoreGraphics

final class MetalZoomRenderer {
    private let context: MetalContext
    private var textureCache: CVMetalTextureCache?

    init(context: MetalContext = .shared) {
        self.context = context
        CVMetalTextureCacheCreate(nil, nil, context.device, nil, &textureCache)
    }

    struct ZoomParams {
        var scale: Float
        var focalX: Float  // normalized [0, 1]
        var focalY: Float  // normalized [0, 1]
        var outputWidth: UInt32
        var outputHeight: UInt32
        var sourceWidth: UInt32
        var sourceHeight: UInt32
    }

    func render(
        source: CVPixelBuffer,
        destination: CVPixelBuffer,
        zoomState: ZoomState,
        sourceSize: CGSize
    ) {
        guard let cache = textureCache else { return }

        let srcWidth = CVPixelBufferGetWidth(source)
        let srcHeight = CVPixelBufferGetHeight(source)
        let dstWidth = CVPixelBufferGetWidth(destination)
        let dstHeight = CVPixelBufferGetHeight(destination)

        guard let srcTexture = makeTexture(from: source, cache: cache, usage: .shaderRead),
              let dstTexture = makeTexture(from: destination, cache: cache, usage: .shaderWrite) else {
            return
        }

        // Normalize focal point to [0, 1]
        let focalX = Float(zoomState.focalPoint.x / sourceSize.width)
        let focalY = Float(zoomState.focalPoint.y / sourceSize.height)

        var params = ZoomParams(
            scale: Float(zoomState.scale),
            focalX: focalX,
            focalY: focalY,
            outputWidth: UInt32(dstWidth),
            outputHeight: UInt32(dstHeight),
            sourceWidth: UInt32(srcWidth),
            sourceHeight: UInt32(srcHeight)
        )

        guard let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        encoder.setComputePipelineState(context.zoomPipeline)
        encoder.setTexture(srcTexture, index: 0)
        encoder.setTexture(dstTexture, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<ZoomParams>.size, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (dstWidth + 15) / 16,
            height: (dstHeight + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func makeTexture(
        from pixelBuffer: CVPixelBuffer,
        cache: CVMetalTextureCache,
        usage: MTLTextureUsage
    ) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        let texture = CVMetalTextureGetTexture(cvTexture)
        return texture
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/Export/MetalZoomRenderer.swift
git commit -m "feat: Metal zoom renderer for GPU-accelerated zoom transforms"
```

---

## Task 15: Export Pipeline

**Files:**
- Create: `RecordMe/Export/ExportPipeline.swift`

AVAssetReader → Metal zoom → AVAssetWriter. Reads intermediate, applies zoom per frame, encodes final output. Depends on Tasks 2, 6, 14.

- [ ] **Step 1: Implement export pipeline**

```swift
// RecordMe/Export/ExportPipeline.swift
import AVFoundation
import CoreVideo

final class ExportPipeline: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var isExporting = false

    private let renderer = MetalZoomRenderer()

    func export(
        intermediateURL: URL,
        outputURL: URL,
        timeline: ZoomTimeline,
        preset: ExportPreset,
        sourceSize: CGSize
    ) async throws {
        await MainActor.run { isExporting = true; progress = 0.0 }

        let asset = AVAsset(url: intermediateURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Reader
        let reader = try AVAssetReader(asset: asset)

        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
        let readerVideoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        reader.add(readerVideoOutput)

        // Audio passthrough
        var readerAudioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(audioOutput)
            readerAudioOutput = audioOutput
        }

        // Writer
        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: preset.codec.avCodecType,
            AVVideoWidthKey: preset.width,
            AVVideoHeightKey: preset.height,
        ]
        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerVideoInput.expectsMediaDataInRealTime = false

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerVideoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: preset.width,
                kCVPixelBufferHeightKey as String: preset.height,
            ]
        )
        writer.add(writerVideoInput)

        var writerAudioInput: AVAssetWriterInput?
        if readerAudioOutput != nil {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            writerAudioInput = audioInput
        }

        // Start
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Process video frames
        while let sampleBuffer = readerVideoOutput.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = CMTimeGetSeconds(timestamp)

            guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let zoomState = timeline.zoomState(at: seconds)

            // Create output pixel buffer
            var destPixelBuffer: CVPixelBuffer?
            guard let pool = pixelBufferAdaptor.pixelBufferPool else { continue }
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destPixelBuffer)
            guard let dest = destPixelBuffer else { continue }

            renderer.render(
                source: sourcePixelBuffer,
                destination: dest,
                zoomState: zoomState,
                sourceSize: sourceSize
            )

            while !writerVideoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            pixelBufferAdaptor.append(dest, withPresentationTime: timestamp)

            await MainActor.run { progress = seconds / durationSeconds }
        }

        // Copy audio
        if let audioOutput = readerAudioOutput, let audioInput = writerAudioInput {
            while let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                while !audioInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                audioInput.append(sampleBuffer)
            }
            audioInput.markAsFinished()
        }

        writerVideoInput.markAsFinished()
        await writer.finishWriting()
        reader.cancelReading()

        await MainActor.run { progress = 1.0; isExporting = false }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/Export/ExportPipeline.swift
git commit -m "feat: export pipeline with Metal zoom rendering and audio passthrough"
```

---

## Task 16: Menu Bar App Shell

**Files:**
- Modify: `RecordMe/App/RecordMeApp.swift`
- Create: `RecordMe/App/MenuBarView.swift`
- Create: `RecordMe/App/AppState.swift`

Central app state + menu bar UI in idle mode. Depends on Tasks 3, 11.

- [ ] **Step 1: Create app state**

```swift
// RecordMe/App/AppState.swift
import SwiftUI
import ScreenCaptureKit

enum RecordingPhase {
    case idle
    case countdown(Int)
    case recording(startTime: Date)
    case processing
    case reviewing
    case exporting(progress: Double)
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: RecordingPhase = .idle
    @Published var micEnabled = true

    let settings = AppSettings()
    let sourcePicker = CaptureSourcePicker()
    let hotkeyManager = HotkeyManager()
    let eventLogger = EventLogger()
    let screenCapture = ScreenCaptureManager()
    let audioCapture = AudioCaptureManager()
    let exportPipeline = ExportPipeline()

    var currentSessionDir: URL?
    var currentTimeline: ZoomTimeline?

    var recordingsBaseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".recordme/recordings")
    }
}
```

- [ ] **Step 2: Create menu bar view**

```swift
// RecordMe/App/MenuBarView.swift
import SwiftUI
import ScreenCaptureKit

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        switch state.phase {
        case .idle:
            idleView
        case .countdown(let count):
            countdownView(count)
        case .recording(let startTime):
            recordingView(startTime: startTime)
        case .processing:
            processingView
        case .reviewing, .exporting:
            Text("Review window open...")
                .padding()
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RecordMe").font(.headline)
            Divider()

            // Source picker
            sourcePickerSection

            Divider()

            // Mic toggle
            Toggle("Microphone", isOn: $state.micEnabled)

            Divider()

            Button("Start Recording") {
                Task { await startRecording() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Preferences...") {
                // TODO: open preferences window
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
        .task {
            await state.sourcePicker.refresh()
        }
    }

    private var sourcePickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Capture Source").font(.subheadline).foregroundColor(.secondary)

            if !state.sourcePicker.displays.isEmpty {
                Menu("Display") {
                    ForEach(state.sourcePicker.displays, id: \.displayID) { display in
                        Button("Display \(display.displayID) (\(display.width)x\(display.height))") {
                            state.sourcePicker.selectedSource = .display(display)
                        }
                    }
                }
            }

            if !state.sourcePicker.windows.isEmpty {
                Menu("Window") {
                    ForEach(state.sourcePicker.windows, id: \.windowID) { window in
                        Button("\(window.owningApplication?.applicationName ?? "Unknown") — \(window.title ?? "Untitled")") {
                            state.sourcePicker.selectedSource = .window(window)
                        }
                    }
                }
            }

            if !state.sourcePicker.apps.isEmpty {
                Menu("App") {
                    ForEach(state.sourcePicker.apps, id: \.processID) { app in
                        Button(app.applicationName) {
                            if let display = state.sourcePicker.displays.first {
                                state.sourcePicker.selectedSource = .app(app, display)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Countdown

    private func countdownView(_ count: Int) -> some View {
        VStack {
            Text("\(count)")
                .font(.system(size: 48, weight: .bold))
            Text("Recording starts...")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Recording

    private func recordingView(startTime: Date) -> some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text("Recording")
                    .font(.headline)
            }

            Text(startTime, style: .timer)
                .font(.system(.body, design: .monospaced))

            Button("Stop Recording") {
                Task { await stopRecording() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        .padding()
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack {
            ProgressView()
            Text("Processing zoom markers...")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Actions

    private func startRecording() async {
        // Countdown
        for i in stride(from: 3, through: 1, by: -1) {
            state.phase = .countdown(i)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Create session directory
        let sessionID = UUID().uuidString
        let sessionDir = state.recordingsBaseDir.appendingPathComponent(sessionID)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        state.currentSessionDir = sessionDir

        // Start event logger
        let eventsURL = sessionDir.appendingPathComponent("events.jsonl")
        try? state.eventLogger.start(fileURL: eventsURL)

        // Configure and register hotkeys
        state.hotkeyManager.configure(settings: state.settings)
        state.hotkeyManager.registerZoomHotkey { [weak state] in
            state?.eventLogger.logManualMarker()
        }
        state.hotkeyManager.registerStopHotkey { [weak state] in
            Task { @MainActor in
                guard case .recording = state?.phase else { return }
                await self.stopRecording()
            }
        }
        state.hotkeyManager.startListening()

        // Start screen capture
        guard let filter = state.sourcePicker.buildFilter() else { return }
        try? await state.screenCapture.startRecording(
            filter: filter,
            sessionDir: sessionDir
        )

        // Start mic capture if enabled
        if state.micEnabled, let writer = state.screenCapture.assetWriterExposed {
            state.audioCapture.attachToWriter(writer)
            try? state.audioCapture.startCapture()
        }

        state.phase = .recording(startTime: Date())
    }

    private func stopRecording() async {
        state.hotkeyManager.stopListening()
        state.eventLogger.stop()
        state.audioCapture.stopCapture()
        _ = try? await state.screenCapture.stopRecording()

        state.phase = .processing

        // Process zoom timeline
        guard let sessionDir = state.currentSessionDir else { return }
        let eventsURL = sessionDir.appendingPathComponent("events.jsonl")
        let events = (try? EventLogReader.read(from: eventsURL)) ?? []

        let timeline = ZoomEngine.process(
            events: events,
            defaultScale: state.settings.defaultZoomLevel,
            defaultDuration: state.settings.defaultZoomDuration,
            typingDetectionEnabled: state.settings.typingDetectionEnabled,
            typingSensitivity: TypingSensitivity(rawValue: state.settings.typingDetectionSensitivity) ?? .medium
        )
        state.currentTimeline = timeline
        state.phase = .reviewing

        // TODO: open review window (Task 20)
    }
}
```

- [ ] **Step 3: Update app entry point**

```swift
// RecordMe/App/RecordMeApp.swift
import SwiftUI

@main
struct RecordMeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: appState)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        switch appState.phase {
        case .recording:
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.multicolor)
        default:
            Image(systemName: "record.circle")
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add RecordMe/App/AppState.swift RecordMe/App/MenuBarView.swift RecordMe/App/RecordMeApp.swift
git commit -m "feat: menu bar app shell with recording flow and source picker"
```

---

## Task 17: Review Window — Video Preview & Timeline

**Files:**
- Create: `RecordMe/Review/ReviewWindow.swift`
- Create: `RecordMe/Review/VideoPreviewView.swift`
- Create: `RecordMe/Review/TimelineView.swift`
- Create: `RecordMe/Review/MarkerDetailView.swift`
- Create: `RecordMe/Review/ZoomTimelineController.swift`

The complete review UI. Depends on Tasks 2, 6, 14.

- [ ] **Step 1: Create zoom timeline controller**

```swift
// RecordMe/Review/ZoomTimelineController.swift
import SwiftUI
import AVFoundation

@MainActor
final class ZoomTimelineController: ObservableObject {
    @Published var timeline: ZoomTimeline
    @Published var selectedRegionID: UUID?
    @Published var currentTime: Double = 0.0
    @Published var isPlaying = false

    let intermediateURL: URL
    let duration: Double
    let sourceSize: CGSize

    var player: AVPlayer?

    init(timeline: ZoomTimeline, intermediateURL: URL, duration: Double, sourceSize: CGSize) {
        self.timeline = timeline
        self.intermediateURL = intermediateURL
        self.duration = duration
        self.sourceSize = sourceSize
        self.player = AVPlayer(url: intermediateURL)
    }

    var selectedRegion: ZoomRegion? {
        guard let id = selectedRegionID else { return nil }
        return timeline.regions.first { $0.id == id }
    }

    func selectRegion(_ region: ZoomRegion) {
        selectedRegionID = region.id
        seek(to: region.startTime)
    }

    func deleteSelectedRegion() {
        guard let id = selectedRegionID else { return }
        timeline.regions.removeAll { $0.id == id }
        selectedRegionID = nil
    }

    func addMarker(at time: Double) {
        let currentZoomState = timeline.zoomState(at: time)
        // Don't add if already in a zoom region
        guard currentZoomState.scale <= 1.01 else { return }

        let region = ZoomRegion(
            startTime: time - 2.0,
            endTime: time + 2.0,
            focalPoint: CGPoint(x: sourceSize.width / 2, y: sourceSize.height / 2),
            scale: 2.0,
            source: .manual
        )
        timeline.regions.append(region)
        timeline.regions.sort { $0.startTime < $1.startTime }
        selectedRegionID = region.id
    }

    func adjustScale(delta: CGFloat) {
        guard let id = selectedRegionID,
              let index = timeline.regions.firstIndex(where: { $0.id == id }) else { return }
        let newScale = max(1.5, min(3.0, timeline.regions[index].scale + delta))
        timeline.regions[index].scale = newScale
    }

    func adjustDuration(delta: Double) {
        guard let id = selectedRegionID,
              let index = timeline.regions.firstIndex(where: { $0.id == id }) else { return }
        let currentDuration = timeline.regions[index].duration
        let newDuration = max(1.0, min(10.0, currentDuration + delta))
        let center = (timeline.regions[index].startTime + timeline.regions[index].endTime) / 2
        timeline.regions[index].startTime = center - newDuration / 2
        timeline.regions[index].endTime = center + newDuration / 2
    }

    func seek(to time: Double) {
        currentTime = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }

    func jumpToNextMarker() {
        let next = timeline.regions.first { $0.startTime > currentTime + 0.1 }
        if let next {
            selectRegion(next)
        }
    }

    func jumpToPreviousMarker() {
        let prev = timeline.regions.last { $0.startTime < currentTime - 0.1 }
        if let prev {
            selectRegion(prev)
        }
    }
}
```

- [ ] **Step 2: Create timeline view**

```swift
// RecordMe/Review/TimelineView.swift
import SwiftUI

struct TimelineView: View {
    @ObservedObject var controller: ZoomTimelineController

    var body: some View {
        VStack(spacing: 4) {
            // Timeline strip
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                        .offset(y: 14)

                    // Zoom region highlights
                    ForEach(controller.timeline.regions) { region in
                        let startX = xPosition(for: region.startTime, in: geo.size.width)
                        let endX = xPosition(for: region.endTime, in: geo.size.width)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(region.source == .manual
                                ? Color.indigo.opacity(0.2)
                                : Color.orange.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(region.source == .manual
                                        ? Color.indigo.opacity(0.4)
                                        : Color.orange.opacity(0.4), lineWidth: 1)
                            )
                            .frame(width: max(4, endX - startX), height: 12)
                            .offset(x: startX, y: 8)
                    }

                    // Markers
                    ForEach(controller.timeline.regions) { region in
                        let x = xPosition(for: (region.startTime + region.endTime) / 2, in: geo.size.width)
                        Circle()
                            .fill(region.source == .manual ? Color.indigo : Color.orange)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(controller.selectedRegionID == region.id ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .offset(x: x - 7, y: 0)
                            .onTapGesture {
                                controller.selectRegion(region)
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let time = timePosition(for: value.location.x, in: geo.size.width)
                                        moveRegion(region, to: time)
                                    }
                            )
                    }

                    // Playhead
                    let playheadX = xPosition(for: controller.currentTime, in: geo.size.width)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 28)
                        .offset(x: playheadX - 1, y: 0)
                }
                .frame(height: 32)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let time = timePosition(for: location.x, in: geo.size.width)
                    controller.seek(to: time)
                }
            }
            .frame(height: 32)

            // Time labels
            HStack {
                Text(formatTime(0))
                Spacer()
                Text(formatTime(controller.duration))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
        }
    }

    private func xPosition(for time: Double, in width: CGFloat) -> CGFloat {
        guard controller.duration > 0 else { return 0 }
        return CGFloat(time / controller.duration) * width
    }

    private func timePosition(for x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return max(0, min(controller.duration, Double(x / width) * controller.duration))
    }

    private func moveRegion(_ region: ZoomRegion, to centerTime: Double) {
        guard let index = controller.timeline.regions.firstIndex(where: { $0.id == region.id }) else { return }
        let halfDuration = region.duration / 2
        controller.timeline.regions[index].startTime = centerTime - halfDuration
        controller.timeline.regions[index].endTime = centerTime + halfDuration
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

- [ ] **Step 3: Create marker detail view**

```swift
// RecordMe/Review/MarkerDetailView.swift
import SwiftUI

struct MarkerDetailView: View {
    @ObservedObject var controller: ZoomTimelineController

    var body: some View {
        if let region = controller.selectedRegion {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(region.source == .manual ? "Manual" : "Typing") Marker @ \(formatTime(region.startTime))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Text("Zoom:").foregroundColor(.secondary)
                            Text(String(format: "%.1fx", region.scale))
                            Text("← → to adjust")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 4) {
                            Text("Duration:").foregroundColor(.secondary)
                            Text(String(format: "%.1fs", region.duration))
                            Text("[ ] to adjust")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            controller.deleteSelectedRegion()
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .font(.system(size: 13))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

- [ ] **Step 4: Create video preview view**

```swift
// RecordMe/Review/VideoPreviewView.swift
import SwiftUI
import AVKit

/// Video preview that renders the intermediate video with Metal zoom transforms applied.
/// Uses AVPlayer for decoding and a CAMetalLayer for rendering zoomed frames.
struct VideoPreviewView: NSViewRepresentable {
    let player: AVPlayer?
    @ObservedObject var controller: ZoomTimelineController

    func makeNSView(context: Context) -> ZoomedPlayerNSView {
        let view = ZoomedPlayerNSView()
        view.setUp(player: player, controller: controller)
        return view
    }

    func updateNSView(_ nsView: ZoomedPlayerNSView, context: Context) {
        nsView.updateZoomState(controller.timeline.zoomState(at: controller.currentTime))
    }
}

/// NSView subclass that uses AVPlayerLayer + a Metal overlay to apply zoom transforms.
/// The AVPlayerLayer renders the raw video; a display link reads each frame,
/// applies the zoom transform via MetalZoomRenderer, and composites onto a CAMetalLayer.
///
/// For a simpler v1, we use AVPlayer's built-in video output with CVPixelBuffer access
/// via AVPlayerItemVideoOutput, then render the zoomed result to a CAMetalLayer.
final class ZoomedPlayerNSView: NSView {
    private var playerLayer: AVPlayerLayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CVDisplayLink?
    private var metalLayer: CAMetalLayer?
    private let renderer = MetalZoomRenderer()
    private weak var controller: ZoomTimelineController?

    func setUp(player: AVPlayer?, controller: ZoomTimelineController?) {
        self.controller = controller
        wantsLayer = true

        // Set up AVPlayerItemVideoOutput for pixel buffer access
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        player?.currentItem?.add(output)
        videoOutput = output

        // For v1, use a simple AVPlayerLayer — the zoom indicator overlay in ReviewWindow
        // shows the zoom level. Full Metal preview rendering can be enhanced in v2.
        // This approach shows the raw video with the zoom level indicator as a UI overlay.
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        self.layer = layer
        playerLayer = layer
    }

    func updateZoomState(_ state: ZoomState) {
        // Apply zoom as a layer transform on the AVPlayerLayer
        // This gives an approximate preview of the zoom effect
        guard let playerLayer else { return }
        guard let controller else { return }

        let sourceSize = controller.sourceSize
        let normalizedFocalX = state.focalPoint.x / sourceSize.width
        let normalizedFocalY = state.focalPoint.y / sourceSize.height

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.05) // smooth but responsive
        var transform = CATransform3DIdentity
        // Translate to focal point, scale, translate back
        let anchorX = normalizedFocalX
        let anchorY = normalizedFocalY
        playerLayer.anchorPoint = CGPoint(x: anchorX, y: 1.0 - anchorY) // flip Y
        transform = CATransform3DScale(transform, state.scale, state.scale, 1.0)
        playerLayer.transform = transform
        CATransaction.commit()
    }
}
```

- [ ] **Step 5: Create review window**

```swift
// RecordMe/Review/ReviewWindow.swift
import SwiftUI

struct ReviewWindow: View {
    @ObservedObject var controller: ZoomTimelineController
    @ObservedObject var exportPipeline: ExportPipeline
    let settings: AppSettings
    let onExport: (ExportPreset) -> Void
    let onDiscard: () -> Void

    @State private var selectedPresetIndex = 0

    private var presets: [ExportPreset] {
        [
            .hd1080p(codec: .hevc),
            .uhd4k(codec: .hevc),
            .source(width: Int(controller.sourceSize.width), height: Int(controller.sourceSize.height), codec: .hevc),
            .hd1080p(codec: .h264),
            .uhd4k(codec: .h264),
            .source(width: Int(controller.sourceSize.width), height: Int(controller.sourceSize.height), codec: .h264),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video preview
            VideoPreviewView(player: controller.player, controller: controller)
                .aspectRatio(controller.sourceSize.width / controller.sourceSize.height, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    let zoom = controller.timeline.zoomState(at: controller.currentTime)
                    if zoom.scale > 1.01 {
                        Text(String(format: "%.1fx", zoom.scale))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.8))
                            .cornerRadius(4)
                            .padding(12)
                    }
                }

            // Transport controls
            HStack(spacing: 12) {
                Button { controller.jumpToPreviousMarker() } label: {
                    Image(systemName: "backward.end.fill")
                }
                Button { controller.togglePlayback() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                }
                Button { controller.jumpToNextMarker() } label: {
                    Image(systemName: "forward.end.fill")
                }

                Text(formatTime(controller.currentTime) + " / " + formatTime(controller.duration))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Text("⏭ = Jump to next marker")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .buttonStyle(.plain)

            Divider()

            // Timeline
            TimelineView(controller: controller)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            // Legend
            HStack(spacing: 16) {
                Label("Manual marker", systemImage: "circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.indigo)
                Label("Typing detected", systemImage: "circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Marker detail
            MarkerDetailView(controller: controller)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Divider()

            // Action bar
            HStack {
                Button("+ Add Marker") {
                    controller.addMarker(at: controller.currentTime)
                }

                Button("Discard", role: .destructive) {
                    onDiscard()
                }

                Spacer()

                if exportPipeline.isExporting {
                    ProgressView(value: exportPipeline.progress)
                        .frame(width: 120)
                } else {
                    Picker("Preset", selection: $selectedPresetIndex) {
                        ForEach(presets.indices, id: \.self) { i in
                            Text("\(presets[i].label) — \(presets[i].codec == .hevc ? "HEVC" : "H.264")")
                                .tag(i)
                        }
                    }
                    .frame(width: 180)

                    Button("Export") {
                        onExport(presets[selectedPresetIndex])
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Keyboard handling (macOS 13 compatible, uses NSEvent local monitor)

    @State private var keyMonitor: Any?

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 49: // Space
                controller.togglePlayback(); return nil
            case 123: // Left arrow
                controller.adjustScale(delta: -0.5); return nil
            case 124: // Right arrow
                controller.adjustScale(delta: 0.5); return nil
            case 51: // Delete
                controller.deleteSelectedRegion(); return nil
            default: break
            }
            if event.charactersIgnoringModifiers == "[" {
                controller.adjustDuration(delta: -0.5); return nil
            }
            if event.charactersIgnoringModifiers == "]" {
                controller.adjustDuration(delta: 0.5); return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

- [ ] **Step 6: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add RecordMe/Review/
git commit -m "feat: review window with video preview, timeline, and marker editing"
```

---

## Task 18: Permissions View

**Files:**
- Create: `RecordMe/App/PermissionsView.swift`

First-launch welcome flow. Depends on Task 7.

- [ ] **Step 1: Implement permissions view**

```swift
// RecordMe/App/PermissionsView.swift
import SwiftUI

struct PermissionsView: View {
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var checkTimer: Timer?

    let onComplete: () -> Void

    var allGranted: Bool {
        screenRecordingGranted && accessibilityGranted
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to RecordMe")
                .font(.title)

            Text("RecordMe needs a few permissions to work.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    title: "Screen Recording",
                    description: "Required to capture your screen",
                    granted: screenRecordingGranted,
                    action: {
                        Task {
                            let status = await Permissions.checkScreenRecording()
                            screenRecordingGranted = status == .granted
                        }
                    },
                    buttonLabel: "Grant"
                )

                permissionRow(
                    title: "Accessibility",
                    description: "Required to track cursor and detect typing",
                    granted: accessibilityGranted,
                    action: {
                        Permissions.promptAccessibility()
                    },
                    buttonLabel: "Open Settings"
                )

                permissionRow(
                    title: "Microphone",
                    description: "Optional, for voice narration",
                    granted: microphoneGranted,
                    action: {
                        Task {
                            microphoneGranted = await Permissions.requestMicrophone()
                        }
                    },
                    buttonLabel: "Grant"
                )
            }
            .padding()

            if allGranted {
                Button("Get Started") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(width: 450)
        .onAppear {
            // Poll for accessibility changes
            checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                accessibilityGranted = Permissions.isAccessibilityGranted
            }
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }

    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void,
        buttonLabel: String
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .secondary)
                .font(.title2)

            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            if !granted {
                Button(buttonLabel, action: action)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/App/PermissionsView.swift
git commit -m "feat: first-launch permissions flow"
```

---

## Task 19: Preferences Window

**Files:**
- Create: `RecordMe/App/PreferencesView.swift`

Settings UI bound to AppSettings. Depends on Task 3.

- [ ] **Step 1: Implement preferences view**

```swift
// RecordMe/App/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings

    private let zoomLevels: [CGFloat] = [1.5, 2.0, 2.5, 3.0]
    private let zoomDurations: [Double] = [2.0, 4.0, 6.0]
    private let sensitivities = ["low", "medium", "high"]

    var body: some View {
        Form {
            Section("Zoom") {
                Picker("Default zoom level", selection: Binding(
                    get: { settings.defaultZoomLevel },
                    set: { settings.defaultZoomLevel = $0 }
                )) {
                    ForEach(zoomLevels, id: \.self) { level in
                        Text(String(format: "%.1fx", level)).tag(level)
                    }
                }

                Picker("Default zoom duration", selection: Binding(
                    get: { settings.defaultZoomDuration },
                    set: { settings.defaultZoomDuration = $0 }
                )) {
                    ForEach(zoomDurations, id: \.self) { dur in
                        Text(String(format: "%.0fs", dur)).tag(dur)
                    }
                }

                Toggle("Typing detection", isOn: Binding(
                    get: { settings.typingDetectionEnabled },
                    set: { settings.typingDetectionEnabled = $0 }
                ))

                if settings.typingDetectionEnabled {
                    Picker("Typing sensitivity", selection: Binding(
                        get: { settings.typingDetectionSensitivity },
                        set: { settings.typingDetectionSensitivity = $0 }
                    )) {
                        ForEach(sensitivities, id: \.self) { s in
                            Text(s.capitalized).tag(s)
                        }
                    }
                }
            }

            Section("Hotkeys") {
                HStack {
                    Text("Zoom marker")
                    Spacer()
                    Text(settings.zoomHotkey)
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Text("Stop recording")
                    Spacer()
                    Text(settings.stopRecordingHotkey)
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section("Export") {
                Picker("Default preset", selection: Binding(
                    get: { settings.defaultExportPresetLabel },
                    set: { settings.defaultExportPresetLabel = $0 }
                )) {
                    Text("1080p").tag("1080p")
                    Text("4K").tag("4K")
                    Text("Source").tag("Source")
                }

                Picker("Default codec", selection: Binding(
                    get: { settings.defaultCodec },
                    set: { settings.defaultCodec = $0 }
                )) {
                    Text("HEVC").tag("hevc")
                    Text("H.264").tag("h264")
                }

                HStack {
                    Text("Save location")
                    Spacer()
                    Text(settings.exportSaveLocation)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change...") {
                        chooseExportLocation()
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    Text(Permissions.isAccessibilityGranted ? "Granted" : "Not granted")
                        .foregroundColor(Permissions.isAccessibilityGranted ? .green : .red)
                }

                if !Permissions.isAccessibilityGranted {
                    Text("Enable Accessibility for typing detection and cursor tracking.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
    }

    private func chooseExportLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportSaveLocation = url.path
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RecordMe/App/PreferencesView.swift
git commit -m "feat: preferences window with all settings"
```

---

## Task 20: Integration — Wire Review Window & Export

**Files:**
- Modify: `RecordMe/App/RecordMeApp.swift`
- Modify: `RecordMe/App/AppState.swift`
- Modify: `RecordMe/App/MenuBarView.swift`

Connect the review window to the app lifecycle. Wire export to the export pipeline. Full end-to-end flow.

- [ ] **Step 1: Add review window scene to RecordMeApp**

Update `RecordMeApp.swift` to open the review window and preferences as separate windows:

```swift
// RecordMe/App/RecordMeApp.swift
import SwiftUI

@main
struct RecordMeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: appState)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Window("Review Recording", id: "review") {
            if let controller = appState.reviewController {
                ReviewWindow(
                    controller: controller,
                    exportPipeline: appState.exportPipeline,
                    settings: appState.settings,
                    onExport: { preset in
                        Task { await appState.startExport(preset: preset) }
                    },
                    onDiscard: {
                        appState.discardRecording()
                    }
                )
            }
        }

        Window("Preferences", id: "preferences") {
            PreferencesView(settings: appState.settings)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        switch appState.phase {
        case .recording:
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.multicolor)
        default:
            Image(systemName: "record.circle")
        }
    }
}
```

- [ ] **Step 2: Add review controller and export methods to AppState**

Add to `AppState.swift`:

```swift
// Add these properties and methods to AppState

@Published var reviewController: ZoomTimelineController?

func openReviewWindow(timeline: ZoomTimeline) async {
    guard let sessionDir = currentSessionDir else { return }
    let intermediateURL = sessionDir.appendingPathComponent("intermediate.mp4")

    let asset = AVAsset(url: intermediateURL)
    let duration = (try? await asset.load(.duration)) ?? .zero
    let durationSeconds = CMTimeGetSeconds(duration)

    let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
    var sourceSize = CGSize(width: 1920, height: 1080)
    if let track = tracks.first {
        sourceSize = (try? await track.load(.naturalSize)) ?? sourceSize
    }

    reviewController = ZoomTimelineController(
        timeline: timeline,
        intermediateURL: intermediateURL,
        duration: durationSeconds,
        sourceSize: sourceSize
    )
    phase = .reviewing
}

func startExport(preset: ExportPreset) async {
    guard let controller = reviewController, let sessionDir = currentSessionDir else { return }

    let exportDir = URL(fileURLWithPath: settings.exportSaveLocation)
    try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let filename = "RecordMe-\(dateFormatter.string(from: Date())).mp4"
    let outputURL = exportDir.appendingPathComponent(filename)

    let intermediateURL = sessionDir.appendingPathComponent("intermediate.mp4")

    phase = .exporting(progress: 0)

    do {
        try await exportPipeline.export(
            intermediateURL: intermediateURL,
            outputURL: outputURL,
            timeline: controller.timeline,
            preset: preset,
            sourceSize: controller.sourceSize
        )
        // Open in Finder
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        phase = .idle
        reviewController = nil
    } catch {
        print("Export failed: \(error)")
        phase = .reviewing
    }
}

func discardRecording() {
    if let sessionDir = currentSessionDir {
        try? FileManager.default.removeItem(at: sessionDir)
    }
    currentSessionDir = nil
    currentTimeline = nil
    reviewController = nil
    phase = .idle
}
```

- [ ] **Step 3: Update MenuBarView to open review and preferences windows**

In `MenuBarView.swift`, update the `stopRecording()` method to call `openReviewWindow()`, and add preferences button action:

```swift
// In stopRecording(), replace the TODO line:
state.phase = .reviewing
// with:
Task { await state.openReviewWindow(timeline: timeline) }

// For preferences button, use:
Button("Preferences...") {
    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run all tests**

Run: `xcodebuild test -project RecordMe.xcodeproj -scheme RecordMeTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add RecordMe/App/
git commit -m "feat: wire review window and export pipeline into app lifecycle"
```

---

## Task 21: End-to-End Manual Test & Polish

**Files:**
- Potentially any files for bug fixes discovered during testing

- [ ] **Step 1: Build and run the app**

Run: `xcodebuild -project RecordMe.xcodeproj -scheme RecordMe build`
Then open the built app from the build products directory.

- [ ] **Step 2: Manual test checklist**

Verify each step of the full flow:

- [ ] Menu bar icon appears
- [ ] Click opens the panel with source picker, mic toggle, start button
- [ ] Display/window/app source selection works
- [ ] Start recording → 3-second countdown → recording state (red icon, timer, stop button)
- [ ] Cmd+Shift+Z drops zoom markers during recording
- [ ] Stop recording → processing → review window opens
- [ ] Review window shows video preview with timeline
- [ ] Manual markers appear as purple dots, typing markers as amber
- [ ] Click marker → selects it, shows detail panel
- [ ] Drag marker → repositions
- [ ] ← → keys adjust zoom level
- [ ] [ ] keys adjust duration
- [ ] Delete removes marker
- [ ] Click empty timeline → adds marker
- [ ] Space plays/pauses
- [ ] Export with 1080p HEVC preset → MP4 file created → Finder opens
- [ ] Preferences window opens and settings persist
- [ ] Quit works

- [ ] **Step 3: Fix any issues found**

Address bugs discovered during manual testing.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "fix: address issues found during end-to-end testing"
```

- [ ] **Step 5: Push to GitHub**

```bash
git push origin main
```
