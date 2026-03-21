// RecordMeTests/ZoomEngineTests.swift
import XCTest
@testable import RecordMe

final class ZoomEngineTests: XCTestCase {
    func testManualMarkersCreateRegions() {
        let events: [InputEvent] = [
            InputEvent(t: 2.0, type: .marker, x: 100, y: 200),
            InputEvent(t: 8.0, type: .marker, x: 300, y: 400),
        ]
        let timeline = ZoomEngine.process(events: events, defaultScale: 2.0, defaultDuration: 4.0, typingDetectionEnabled: false)
        XCTAssertEqual(timeline.regions.count, 2)
        XCTAssertEqual(timeline.regions[0].focalPoint.x, 100, accuracy: 0.01)
        XCTAssertEqual(timeline.regions[0].source, .manual)
        XCTAssertEqual(timeline.regions[0].duration, 4.0, accuracy: 0.01)
    }

    func testManualMarkerPriorityOverTyping() {
        var events: [InputEvent] = []
        for i in 0..<8 {
            events.append(InputEvent(t: 2.0 + Double(i) * 0.2, type: .key, x: 100, y: 100))
        }
        events.append(InputEvent(t: 2.5, type: .marker, x: 100, y: 100))
        let timeline = ZoomEngine.process(events: events, defaultScale: 2.0, defaultDuration: 4.0, typingDetectionEnabled: true)
        let manualRegions = timeline.regions.filter { $0.source == .manual }
        XCTAssertEqual(manualRegions.count, 1)
    }

    func testGapEnforcement() {
        let events: [InputEvent] = [
            InputEvent(t: 1.0, type: .marker, x: 100, y: 100),
            InputEvent(t: 2.0, type: .marker, x: 200, y: 200),
        ]
        let timeline = ZoomEngine.process(events: events, defaultScale: 2.0, defaultDuration: 1.0, typingDetectionEnabled: false)
        if timeline.regions.count == 2 {
            let gap = timeline.regions[1].startTime - timeline.regions[0].endTime
            XCTAssertGreaterThanOrEqual(gap, 1.5 - 0.01)
        }
    }

    func testNoEventsEmptyTimeline() {
        let timeline = ZoomEngine.process(events: [], defaultScale: 2.0, defaultDuration: 4.0, typingDetectionEnabled: true)
        XCTAssertTrue(timeline.regions.isEmpty)
    }

    func testTypingDisabledIgnoresKeyEvents() {
        var events: [InputEvent] = []
        for i in 0..<8 {
            events.append(InputEvent(t: 1.0 + Double(i) * 0.2, type: .key, x: 100, y: 100))
        }
        let timeline = ZoomEngine.process(events: events, defaultScale: 2.0, defaultDuration: 4.0, typingDetectionEnabled: false)
        XCTAssertTrue(timeline.regions.isEmpty)
    }
}
