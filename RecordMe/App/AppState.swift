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

    func startRecording() async {
        guard case .idle = phase else { return }

        for i in stride(from: 3, through: 1, by: -1) {
            phase = .countdown(i)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let sessionID = UUID().uuidString
        let sessionDir = recordingsBaseDir.appendingPathComponent(sessionID)
        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create session directory: \(error)")
            phase = .idle
            return
        }
        currentSessionDir = sessionDir

        let eventsURL = sessionDir.appendingPathComponent("events.jsonl")
        try? eventLogger.start(fileURL: eventsURL)

        hotkeyManager.configure(settings: settings)
        hotkeyManager.registerZoomHotkey { [weak self] in
            self?.eventLogger.logManualMarker()
        }
        hotkeyManager.registerStopHotkey { [weak self] in
            Task { @MainActor in
                guard case .recording = self?.phase else { return }
                await self?.stopRecording()
            }
        }
        hotkeyManager.startListening()

        guard let filter = sourcePicker.buildFilter() else {
            phase = .idle
            return
        }
        do {
            try await screenCapture.startRecording(
                filter: filter,
                sessionDir: sessionDir
            )
        } catch {
            print("Failed to start screen capture: \(error)")
            phase = .idle
            return
        }

        if micEnabled {
            try? audioCapture.startCapture(sessionDir: sessionDir)
        }

        phase = .recording(startTime: Date())

        // Dismiss the menu bar panel so it's not covering the screen during recording
        NSApp.keyWindow?.close()
    }

    func stopRecording() async {
        hotkeyManager.stopListening()
        eventLogger.stop()
        audioCapture.stopCapture()
        _ = try? await screenCapture.stopRecording()

        phase = .processing

        guard let sessionDir = currentSessionDir else { return }
        let eventsURL = sessionDir.appendingPathComponent("events.jsonl")
        let events = (try? EventLogReader.read(from: eventsURL)) ?? []

        let timeline = ZoomEngine.process(
            events: events,
            defaultScale: settings.defaultZoomLevel,
            defaultDuration: settings.defaultZoomDuration,
            typingDetectionEnabled: settings.typingDetectionEnabled,
            typingSensitivity: TypingSensitivity(rawValue: settings.typingDetectionSensitivity) ?? .medium
        )
        currentTimeline = timeline
        Task { await openReviewWindow(timeline: timeline) }
    }

    func openReviewWindow(timeline: ZoomTimeline) async {
        guard let sessionDir = currentSessionDir else { return }
        let intermediateURL = sessionDir.appendingPathComponent("intermediate.mp4")

        let asset = AVAsset(url: intermediateURL)
        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationSeconds = CMTimeGetSeconds(duration)

        // Use screen point size (not video pixel size) because cursor coordinates are in points
        var sourceSize = screenCapture.screenPointSize
        if sourceSize == .zero {
            // Fallback: derive from naturalSize / scale factor
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            if let track = tracks.first {
                let naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                sourceSize = CGSize(width: naturalSize.width / scale, height: naturalSize.height / scale)
            } else {
                sourceSize = CGSize(width: 1920, height: 1080)
            }
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
