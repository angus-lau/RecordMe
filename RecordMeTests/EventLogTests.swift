// RecordMeTests/EventLogTests.swift
import XCTest
@testable import RecordMe

final class EventLogTests: XCTestCase {
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
