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
                Task { await state.startRecording() }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
        .task(id: "refresh") {
            await state.sourcePicker.forceRefresh()
        }
    }

    private var sourcePickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Capture Source").font(.subheadline).foregroundColor(.secondary)

            if state.sourcePicker.displays.isEmpty && state.sourcePicker.windows.isEmpty {
                Text("Grant Screen Recording permission to see sources")
                    .font(.caption)
                    .foregroundColor(.orange)
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                .font(.caption)
            } else {
                // Current selection
                Text(currentSourceLabel)
                    .font(.caption)
                    .foregroundColor(.green)

                HStack(spacing: 8) {
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
        }
    }

    private var currentSourceLabel: String {
        guard let source = state.sourcePicker.selectedSource else { return "None selected" }
        switch source {
        case .display(let d): return "Display \(d.displayID)"
        case .window(let w): return "\(w.owningApplication?.applicationName ?? "Window") — \(w.title ?? "Untitled")"
        case .app(let a, _): return "App: \(a.applicationName)"
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
                Task { await state.stopRecording() }
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

}
