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
        var manualRegions = events
            .filter { $0.type == .marker }
            .map { event in
                ZoomRegion(
                    startTime: event.t - defaultDuration / 2,
                    endTime: event.t + defaultDuration / 2,
                    focalPoint: CGPoint(x: event.x, y: event.y),
                    scale: defaultScale, source: .manual
                )
            }

        var typingRegions: [ZoomRegion] = []
        if typingDetectionEnabled {
            typingRegions = TypingDetector.detect(events: events, sensitivity: typingSensitivity, defaultScale: defaultScale)
        }

        typingRegions = typingRegions.filter { typing in
            !manualRegions.contains { $0.overlaps(typing) }
        }

        var allRegions = (manualRegions + typingRegions).sorted { $0.startTime < $1.startTime }
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
                let shift = minimumGap - gap
                region.startTime += shift
                region.endTime += shift
            }
            result.append(region)
        }
        return result
    }
}
