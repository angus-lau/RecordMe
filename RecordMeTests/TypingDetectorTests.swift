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
        let events: [InputEvent] = [
            InputEvent(t: 1.0, type: .key, x: 100, y: 100),
            InputEvent(t: 1.2, type: .key, x: 100, y: 100),
            InputEvent(t: 1.4, type: .key, x: 100, y: 100),
        ]
        let regions = TypingDetector.detect(events: events)
        XCTAssertTrue(regions.isEmpty)
    }

    func testTypingBurstCreatesRegion() {
        let events = (0..<8).map { i in
            InputEvent(t: 1.0 + Double(i) * 0.2, type: .key, x: 100, y: 100)
        }
        let regions = TypingDetector.detect(events: events)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].source, .typing)
        XCTAssertEqual(regions[0].startTime, 0.0, accuracy: 0.01)
        XCTAssertEqual(regions[0].endTime, 3.4, accuracy: 0.01)
    }

    func testCursorMovementBreaksBurst() {
        let events: [InputEvent] = [
            InputEvent(t: 1.0, type: .key, x: 100, y: 100),
            InputEvent(t: 1.2, type: .key, x: 100, y: 100),
            InputEvent(t: 1.4, type: .key, x: 100, y: 100),
            InputEvent(t: 1.6, type: .key, x: 500, y: 500),
            InputEvent(t: 1.8, type: .key, x: 500, y: 500),
            InputEvent(t: 2.0, type: .key, x: 500, y: 500),
        ]
        let regions = TypingDetector.detect(events: events)
        XCTAssertTrue(regions.isEmpty)
    }

    func testOverlappingBurstsMerge() {
        var events: [InputEvent] = []
        for i in 0..<8 {
            events.append(InputEvent(t: 1.0 + Double(i) * 0.2, type: .key, x: 100, y: 100))
        }
        for i in 0..<8 {
            events.append(InputEvent(t: 3.0 + Double(i) * 0.2, type: .key, x: 105, y: 105))
        }
        let regions = TypingDetector.detect(events: events)
        XCTAssertEqual(regions.count, 1)
    }

    func testSensitivityAdjustsThreshold() {
        let events = (0..<8).map { i in
            InputEvent(t: 1.0 + Double(i) * 0.2, type: .key, x: 100, y: 100)
        }
        let lowRegions = TypingDetector.detect(events: events, sensitivity: .low)
        let highRegions = TypingDetector.detect(events: events, sensitivity: .high)
        XCTAssertGreaterThanOrEqual(highRegions.count, lowRegions.count)
    }
}
