import Foundation

enum ZoomAnimator {
    /// Simple smooth ease-in-out using smoothstep (no overshoot).
    /// Input t in [0, 1], output in [0, 1].
    static func easeInOut(progress: Double) -> Double {
        let t = max(0, min(1, progress))
        // Smoothstep: 3t² - 2t³
        return t * t * (3.0 - 2.0 * t)
    }

    /// Compute ZoomState for a given timestamp against zoom regions.
    static func zoomState(
        at timestamp: Double, regions: [ZoomRegion],
        zoomInDuration: Double = 0.3, zoomOutDuration: Double = 0.5
    ) -> ZoomState {
        for region in regions {
            let zoomInStart = region.startTime - zoomInDuration
            let zoomOutEnd = region.endTime + zoomOutDuration

            if timestamp < zoomInStart { continue }
            if timestamp > zoomOutEnd { continue }

            // During zoom-in
            if timestamp < region.startTime {
                let progress = (timestamp - zoomInStart) / zoomInDuration
                let eased = easeInOut(progress: progress)
                let scale = 1.0 + (region.scale - 1.0) * eased
                return ZoomState(scale: scale, focalPoint: region.focalPoint, animationProgress: eased)
            }

            // Fully zoomed in
            if timestamp <= region.endTime {
                return ZoomState(scale: region.scale, focalPoint: region.focalPoint, animationProgress: 1.0)
            }

            // During zoom-out
            let progress = (timestamp - region.endTime) / zoomOutDuration
            let eased = easeInOut(progress: progress)
            let scale = 1.0 + (region.scale - 1.0) * (1.0 - eased)
            return ZoomState(scale: scale, focalPoint: region.focalPoint, animationProgress: 1.0 - eased)
        }
        return .identity
    }
}
