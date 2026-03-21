import SwiftUI
import ScreenCaptureKit

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        switch state.phase {
        case .idle:
            idleView
        case .countdown(let count):
            countdownView(count)
        case .recording(let startTime):
            recordingView(startTime: startTime)
        case .processing:
            processingView
        case .reviewing, .exporting:
            Text("Review window open...")
                .padding()
        }
    }

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RecordMe").font(.headline)
            Divider()
            sourcePickerSection
            Divider()
            Toggle("Microphone", isOn: $state.micEnabled)
            Divider()
            Button("Start Recording") {
                Task { await startRecording() }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
        .task {
            await state.sourcePicker.refresh()
        }
    }

    private var sourcePickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Capture Source").font(.subheadline).foregroundColor(.secondary)

            if !state.sourcePicker.displays.isEmpty {
                Menu("Display") {
                    ForEach(state.sourcePicker.displays, id: \.displayID) { display in
                        Button("Display \(display.displayID) (\(display.width)x\(display.height))") {
                            state.sourcePicker.selectedSource = .display(display)
                        }
                    }
                }
            }

            if !state.sourcePicker.windows.isEmpty {
                Menu("Window") {
                    ForEach(state.sourcePicker.windows, id: \.windowID) { window in
                        Button("\(window.owningApplication?.applicationName ?? "Unknown") — \(window.title ?? "Untitled")") {
                            state.sourcePicker.selectedSource = .window(window)
                        }
                    }
                }
            }

            if !state.sourcePicker.apps.isEmpty {
                Menu("App") {
                    ForEach(state.sourcePicker.apps, id: \.processID) { app in
                        Button(app.applicationName) {
                            if let display = state.sourcePicker.displays.first {
                                state.sourcePicker.selectedSource = .app(app, display)
                            }
                        }
                    }
                }
            }
        }
    }

    private func countdownView(_ count: Int) -> some View {
        VStack {
            Text("\(count)")
                .font(.system(size: 48, weight: .bold))
            Text("Recording starts...")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func recordingView(startTime: Date) -> some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text("Recording").font(.headline)
            }
            Text(startTime, style: .timer)
                .font(.system(.body, design: .monospaced))
            Button("Stop Recording") {
                Task { await stopRecording() }
            }
        }
        .padding()
    }

    private var processingView: some View {
        VStack {
            ProgressView()
            Text("Processing zoom markers...")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func startRecording() async {
        for i in stride(from: 3, through: 1, by: -1) {
            state.phase = .countdown(i)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let sessionID = UUID().uuidString
        let sessionDir = state.recordingsBaseDir.appendingPathComponent(sessionID)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        state.currentSessionDir = sessionDir

        let eventsURL = sessionDir.appendingPathComponent("events.jsonl")
        try? state.eventLogger.start(fileURL: eventsURL)

        state.hotkeyManager.configure(settings: state.settings)
        state.hotkeyManager.registerZoomHotkey { [weak state] in
            state?.eventLogger.logManualMarker()
        }
        state.hotkeyManager.registerStopHotkey { [weak state] in
            Task { @MainActor in
                guard case .recording = state?.phase else { return }
                // Stop will be called by the user via button or this hotkey
            }
        }
        state.hotkeyManager.startListening()

        guard let filter = state.sourcePicker.buildFilter() else { return }
        try? await state.screenCapture.startRecording(
            filter: filter,
            sessionDir: sessionDir
        )

        if state.micEnabled {
            try? state.audioCapture.startCapture(sessionDir: sessionDir)
        }

        state.phase = .recording(startTime: Date())

        // Dismiss the menu bar panel so it's not covering the screen during recording
        NSApp.keyWindow?.close()
    }

    private func stopRecording() async {
        state.hotkeyManager.stopListening()
        state.eventLogger.stop()
        state.audioCapture.stopCapture()
        _ = try? await state.screenCapture.stopRecording()

        state.phase = .processing

        guard let sessionDir = state.currentSessionDir else { return }
        let eventsURL = sessionDir.appendingPathComponent("events.jsonl")
        let events = (try? EventLogReader.read(from: eventsURL)) ?? []

        let timeline = ZoomEngine.process(
            events: events,
            defaultScale: state.settings.defaultZoomLevel,
            defaultDuration: state.settings.defaultZoomDuration,
            typingDetectionEnabled: state.settings.typingDetectionEnabled,
            typingSensitivity: TypingSensitivity(rawValue: state.settings.typingDetectionSensitivity) ?? .medium
        )
        state.currentTimeline = timeline
        Task { await state.openReviewWindow(timeline: timeline) }
    }
}
