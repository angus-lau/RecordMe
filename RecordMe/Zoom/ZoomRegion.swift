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
