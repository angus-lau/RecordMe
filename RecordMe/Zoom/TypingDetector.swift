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

            while j + 1 < keyEvents.count {
                let next = keyEvents[j + 1]
                let timeDelta = next.t - keyEvents[i].t
                if timeDelta > windowDuration { break }
                let dist = hypot(next.x - clusterX, next.y - clusterY)
                if dist > maxCursorDrift { break }
                j += 1
                let count = Double(j - i + 1)
                clusterX = clusterX + (next.x - clusterX) / count
                clusterY = clusterY + (next.y - clusterY) / count
            }

            let count = j - i + 1
            if count >= sensitivity.minKeys {
                bursts.append((start: keyEvents[i].t, end: keyEvents[j].t, centroidX: clusterX, centroidY: clusterY))
                i = j + 1
            } else {
                i += 1
            }
        }

        var regions: [ZoomRegion] = []
        for burst in bursts {
            let paddedStart = max(0, burst.start - padding)
            let paddedEnd = burst.end + padding

            if let last = regions.last, paddedStart <= last.endTime {
                var merged = regions.removeLast()
                merged.endTime = max(merged.endTime, paddedEnd)
                regions.append(merged)
            } else {
                regions.append(ZoomRegion(
                    startTime: paddedStart, endTime: paddedEnd,
                    focalPoint: CGPoint(x: burst.centroidX, y: burst.centroidY),
                    scale: defaultScale, source: .typing
                ))
            }
        }
        return regions
    }
}
