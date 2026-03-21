// RecordMeTests/SettingsTests.swift
import XCTest
@testable import RecordMe

final class SettingsTests: XCTestCase {
    var settings: AppSettings!

    override func setUp() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        settings = AppSettings(defaults: defaults)
    }

    func testDefaultZoomLevel() { XCTAssertEqual(settings.defaultZoomLevel, 2.0) }
    func testDefaultZoomDuration() { XCTAssertEqual(settings.defaultZoomDuration, 4.0) }
    func testSetZoomLevel() { settings.defaultZoomLevel = 2.5; XCTAssertEqual(settings.defaultZoomLevel, 2.5) }
    func testDefaultExportPresetLabel() { XCTAssertEqual(settings.defaultExportPresetLabel, "1080p") }
    func testDefaultCodec() { XCTAssertEqual(settings.defaultCodec, "hevc") }
    func testTypingDetectionEnabled() { XCTAssertTrue(settings.typingDetectionEnabled) }
    func testTypingDetectionSensitivity() { XCTAssertEqual(settings.typingDetectionSensitivity, "medium") }
    func testExportSaveLocation() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/RecordMe").path
        XCTAssertEqual(settings.exportSaveLocation, expected)
    }
    func testZoomHotkey() { XCTAssertEqual(settings.zoomHotkey, "cmd+shift+z") }
    func testStopHotkey() { XCTAssertEqual(settings.stopRecordingHotkey, "cmd+shift+s") }
    func testLaunchAtLogin() {
        XCTAssertFalse(settings.launchAtLogin)
        settings.launchAtLogin = true
        XCTAssertTrue(settings.launchAtLogin)
    }
}
