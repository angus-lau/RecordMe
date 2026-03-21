import SwiftUI
import AVFoundation
import ScreenCaptureKit

enum RecordingPhase {
    case idle
    case countdown(Int)
    case recording(startTime: Date)
    case processing
    case reviewing
    case exporting(progress: Double)
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: RecordingPhase = .idle
    @Published var micEnabled = true
    @Published var reviewController: ZoomTimelineController?

    /// Set by RecordMeApp to allow opening windows programmatically
    var openWindow: ((String) -> Void)?

    let settings = AppSettings()
    let sourcePicker = CaptureSourcePicker()
    let hotkeyManager = HotkeyManager()
    let eventLogger = EventLogger()
    let screenCapture = ScreenCaptureManager()
    let audioCapture = AudioCaptureManager()
    let exportPipeline = ExportPipeline()

    var currentSessionDir: URL?
    var currentTimeline: ZoomTimeline?

    var recordingsBaseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".recordme/recordings")
    }

    func openReviewWindow(timeline: ZoomTimeline) async {
        guard let sessionDir = currentSessionDir else { return }
        let intermediateURL = sessionDir.appendingPathComponent("intermediate.mp4")

        let asset = AVAsset(url: intermediateURL)
        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationSeconds = CMTimeGetSeconds(duration)

        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        var sourceSize = CGSize(width: 1920, height: 1080)
        if let track = tracks.first {
            sourceSize = (try? await track.load(.naturalSize)) ?? sourceSize
        }

        reviewController = ZoomTimelineController(
            timeline: timeline,
            intermediateURL: intermediateURL,
            duration: durationSeconds,
            sourceSize: sourceSize
        )
        phase = .reviewing
        openWindow?("review")
    }

    func startExport(preset: ExportPreset) async {
        guard let controller = reviewController, let sessionDir = currentSessionDir else { return }

        let exportDir = URL(fileURLWithPath: settings.exportSaveLocation)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "RecordMe-\(dateFormatter.string(from: Date())).mp4"
        let outputURL = exportDir.appendingPathComponent(filename)

        let intermediateURL = sessionDir.appendingPathComponent("intermediate.mp4")

        phase = .exporting(progress: 0)

        do {
            try await exportPipeline.export(
                intermediateURL: intermediateURL,
                outputURL: outputURL,
                timeline: controller.timeline,
                preset: preset,
                sourceSize: controller.sourceSize,
                trimStart: controller.trimStart,
                trimEnd: controller.trimEnd
            )
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            phase = .idle
            reviewController = nil
        } catch {
            print("Export failed: \(error)")
            phase = .reviewing
        }
    }

    func discardRecording() {
        if let sessionDir = currentSessionDir {
            try? FileManager.default.removeItem(at: sessionDir)
        }
        currentSessionDir = nil
        currentTimeline = nil
        reviewController = nil
        phase = .idle
    }
}
