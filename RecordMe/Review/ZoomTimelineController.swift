// Temporary stub — will be replaced in Task 17: Review Window
import Foundation

@MainActor
final class ZoomTimelineController: ObservableObject {
    var timeline: ZoomTimeline
    let intermediateURL: URL
    let duration: Double
    let sourceSize: CGSize

    init(timeline: ZoomTimeline, intermediateURL: URL, duration: Double, sourceSize: CGSize) {
        self.timeline = timeline
        self.intermediateURL = intermediateURL
        self.duration = duration
        self.sourceSize = sourceSize
    }
}
