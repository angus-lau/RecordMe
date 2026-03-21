// RecordMe/Zoom/ZoomAnimator.swift
import Foundation

enum ZoomAnimator {
    static func cubicBezier(t: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        var guess = t
        for _ in 0..<8 {
            let xGuess = sampleCurve(guess, p1: x1, p2: x2)
            let slope = sampleCurveDerivative(guess, p1: x1, p2: x2)
            if abs(slope) < 1e-6 { break }
            guess -= (xGuess - t) / slope
        }
        let yValue = sampleCurve(guess, p1: y1, p2: y2)
        return yValue > 1.0 ? sampleCurve(t, p1: y1, p2: y2) : yValue
    }

    private static func sampleCurve(_ t: Double, p1: Double, p2: Double) -> Double {
        ((1.0 - 3.0 * p2 + 3.0 * p1) * t + (3.0 * p2 - 6.0 * p1)) * t + 3.0 * p1 * t
    }

    private static func sampleCurveDerivative(_ t: Double, p1: Double, p2: Double) -> Double {
        (3.0 * (1.0 - 3.0 * p2 + 3.0 * p1)) * t * t + (2.0 * (3.0 * p2 - 6.0 * p1)) * t + 3.0 * p1
    }

    static func easeInOut(progress: Double) -> Double {
        cubicBezier(t: max(0, min(1, progress)), x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
    }

    static func zoomState(
        at timestamp: Double, regions: [ZoomRegion],
        zoomInDuration: Double = 0.3, zoomOutDuration: Double = 0.5
    ) -> ZoomState {
        for region in regions {
            let zoomInStart = region.startTime - zoomInDuration
            let zoomOutEnd = region.endTime + zoomOutDuration
            if timestamp < zoomInStart { continue }
            if timestamp > zoomOutEnd { continue }
            if timestamp < region.startTime {
                let progress = (timestamp - zoomInStart) / zoomInDuration
                let eased = easeInOut(progress: progress)
                let scale = 1.0 + (region.scale - 1.0) * eased
                return ZoomState(scale: scale, focalPoint: region.focalPoint, animationProgress: eased)
            }
            if timestamp <= region.endTime {
                return ZoomState(scale: region.scale, focalPoint: region.focalPoint, animationProgress: 1.0)
            }
            let progress = (timestamp - region.endTime) / zoomOutDuration
            let eased = easeInOut(progress: progress)
            let scale = region.scale - (region.scale - 1.0) * eased
            return ZoomState(scale: scale, focalPoint: region.focalPoint, animationProgress: 1.0 - eased)
        }
        return .identity
    }
}
