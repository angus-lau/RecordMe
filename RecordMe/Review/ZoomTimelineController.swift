import SwiftUI
import AVFoundation

@MainActor
final class ZoomTimelineController: ObservableObject {
    @Published var timeline: ZoomTimeline
    @Published var selectedRegionID: UUID?
    @Published var currentTime: Double = 0.0
    @Published var isPlaying = false

    let intermediateURL: URL
    let duration: Double
    let sourceSize: CGSize
    var player: AVPlayer?

    init(timeline: ZoomTimeline, intermediateURL: URL, duration: Double, sourceSize: CGSize) {
        self.timeline = timeline
        self.intermediateURL = intermediateURL
        self.duration = duration
        self.sourceSize = sourceSize
        self.player = AVPlayer(url: intermediateURL)
    }

    var selectedRegion: ZoomRegion? {
        guard let id = selectedRegionID else { return nil }
        return timeline.regions.first { $0.id == id }
    }

    func selectRegion(_ region: ZoomRegion) {
        selectedRegionID = region.id
        seek(to: region.startTime)
    }

    func deleteSelectedRegion() {
        guard let id = selectedRegionID else { return }
        timeline.regions.removeAll { $0.id == id }
        selectedRegionID = nil
    }

    func addMarker(at time: Double) {
        let region = ZoomRegion(
            startTime: max(0, time - 2.0), endTime: time + 2.0,
            focalPoint: CGPoint(x: sourceSize.width / 2, y: sourceSize.height / 2),
            scale: 2.0, source: .manual
        )
        timeline.regions.append(region)
        timeline.regions.sort { $0.startTime < $1.startTime }
        selectedRegionID = region.id
    }

    func adjustScale(delta: CGFloat) {
        guard let id = selectedRegionID,
              let index = timeline.regions.firstIndex(where: { $0.id == id }) else { return }
        timeline.regions[index].scale = max(1.5, min(3.0, timeline.regions[index].scale + delta))
    }

    func adjustDuration(delta: Double) {
        guard let id = selectedRegionID,
              let index = timeline.regions.firstIndex(where: { $0.id == id }) else { return }
        let currentDuration = timeline.regions[index].duration
        let newDuration = max(1.0, min(10.0, currentDuration + delta))
        let center = (timeline.regions[index].startTime + timeline.regions[index].endTime) / 2
        timeline.regions[index].startTime = center - newDuration / 2
        timeline.regions[index].endTime = center + newDuration / 2
    }

    func seek(to time: Double) {
        currentTime = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        if isPlaying { player?.pause() } else { player?.play() }
        isPlaying.toggle()
    }

    func jumpToNextMarker() {
        if let next = timeline.regions.first(where: { $0.startTime > currentTime + 0.1 }) {
            selectRegion(next)
        }
    }

    func jumpToPreviousMarker() {
        if let prev = timeline.regions.last(where: { $0.startTime < currentTime - 0.1 }) {
            selectRegion(prev)
        }
    }
}
