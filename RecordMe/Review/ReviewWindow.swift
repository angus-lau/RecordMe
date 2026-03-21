import SwiftUI

struct ReviewWindow: View {
    @ObservedObject var controller: ZoomTimelineController
    @ObservedObject var exportPipeline: ExportPipeline
    let settings: AppSettings
    let onExport: (ExportPreset) -> Void
    let onDiscard: () -> Void

    @State private var selectedPresetIndex = 0
    @State private var keyMonitor: Any?

    private var presets: [ExportPreset] {
        [
            .hd1080p(codec: .hevc), .uhd4k(codec: .hevc),
            .source(width: Int(controller.sourceSize.width), height: Int(controller.sourceSize.height), codec: .hevc),
            .hd1080p(codec: .h264), .uhd4k(codec: .h264),
            .source(width: Int(controller.sourceSize.width), height: Int(controller.sourceSize.height), codec: .h264),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPreviewView(player: controller.player)
                .aspectRatio(controller.sourceSize.width / controller.sourceSize.height, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    let zoom = controller.timeline.zoomState(at: controller.currentTime)
                    if zoom.scale > 1.01 {
                        Text(String(format: "%.1fx", zoom.scale))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.8))
                            .cornerRadius(4).padding(12)
                    }
                }

            HStack(spacing: 12) {
                Button { controller.jumpToPreviousMarker() } label: { Image(systemName: "backward.end.fill") }
                Button { controller.togglePlayback() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18))
                }
                Button { controller.jumpToNextMarker() } label: { Image(systemName: "forward.end.fill") }
                Text(formatTime(controller.currentTime) + " / " + formatTime(controller.duration))
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .buttonStyle(.plain)

            Divider()

            TimelineView(controller: controller)
                .padding(.horizontal, 20).padding(.vertical, 12)

            HStack(spacing: 16) {
                Label("Manual marker", systemImage: "circle.fill").font(.system(size: 11)).foregroundColor(.indigo)
                Label("Typing detected", systemImage: "circle.fill").font(.system(size: 11)).foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            MarkerDetailView(controller: controller)
                .padding(.horizontal, 20).padding(.bottom, 8)

            Divider()

            HStack {
                Button("+ Add Marker") { controller.addMarker(at: controller.currentTime) }
                Button("Discard", role: .destructive) { onDiscard() }
                Spacer()

                if exportPipeline.isExporting {
                    ProgressView(value: exportPipeline.progress).frame(width: 120)
                } else {
                    Picker("Preset", selection: $selectedPresetIndex) {
                        ForEach(presets.indices, id: \.self) { i in
                            Text("\(presets[i].label) — \(presets[i].codec == .hevc ? "HEVC" : "H.264")").tag(i)
                        }
                    }
                    .frame(width: 180)
                    Button("Export") { onExport(presets[selectedPresetIndex]) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 49: controller.togglePlayback(); return nil
            case 123: controller.adjustScale(delta: -0.5); return nil
            case 124: controller.adjustScale(delta: 0.5); return nil
            case 51: controller.deleteSelectedRegion(); return nil
            default: break
            }
            if event.charactersIgnoringModifiers == "[" { controller.adjustDuration(delta: -0.5); return nil }
            if event.charactersIgnoringModifiers == "]" { controller.adjustDuration(delta: 0.5); return nil }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
    }

    private func formatTime(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
