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

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(timeline: ZoomTimeline, intermediateURL: URL, duration: Double, sourceSize: CGSize) {
        self.timeline = timeline
        self.intermediateURL = intermediateURL
        self.duration = duration
        self.sourceSize = sourceSize

        let player = AVPlayer(url: intermediateURL)
        self.player = player

        // Update currentTime during playback (~30 fps)
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(time)
            }
        }

        // Handle end of playback
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
    }

    deinit {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
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
        // Start at scale 1.0 — user clicks video to set focal point, which activates zoom
        let region = ZoomRegion(
            startTime: max(0, time - 2.0), endTime: time + 2.0,
            focalPoint: CGPoint(x: sourceSize.width / 2, y: sourceSize.height / 2),
            scale: 1.0, source: .manual
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

    func setFocalPoint(_ point: CGPoint) {
        guard let id = selectedRegionID,
              let index = timeline.regions.firstIndex(where: { $0.id == id }) else { return }
        timeline.regions[index].focalPoint = point
        // If marker was just added (scale 1.0), activate zoom to default level
        if timeline.regions[index].scale < 1.5 {
            timeline.regions[index].scale = 2.0
        }
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
        guard let player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // If at the end, seek to beginning first
            if currentTime >= duration - 0.1 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func jumpToNextMarker() {
        if let next = timeline.regions.first(where: { $0.startTime > currentTime + 0.1 }) {
            selectRegion(next)
        } else {
            // No next marker — jump forward 5 seconds
            seek(to: min(duration, currentTime + 5.0))
        }
    }

    func jumpToPreviousMarker() {
        if let prev = timeline.regions.last(where: { $0.startTime < currentTime - 0.1 }) {
            selectRegion(prev)
        } else {
            // No previous marker — jump back 5 seconds
            seek(to: max(0, currentTime - 5.0))
        }
    }
}
