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
