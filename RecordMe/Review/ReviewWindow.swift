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

    private var currentZoomState: ZoomState {
        controller.timeline.zoomState(at: controller.currentTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video preview with zoom applied — click to set focal point
            GeometryReader { geo in
                VideoPreviewView(player: controller.player)
                    .scaleEffect(currentZoomState.scale)
                    .offset(zoomOffset(in: geo.size))
                    .clipped()
                    .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: currentZoomState.scale)
                    .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: currentZoomState.focalPoint.x)
                    .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: currentZoomState.focalPoint.y)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // Map click position to source coordinates
                        let normalizedX = location.x / geo.size.width
                        let normalizedY = location.y / geo.size.height
                        let sourceX = normalizedX * controller.sourceSize.width
                        let sourceY = normalizedY * controller.sourceSize.height
                        controller.setFocalPoint(CGPoint(x: sourceX, y: sourceY))
                    }
            }
            .aspectRatio(controller.sourceSize.width / controller.sourceSize.height, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if currentZoomState.scale > 1.01 {
                    Text(String(format: "%.1fx", currentZoomState.scale))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.indigo.opacity(0.8))
                        .cornerRadius(4).padding(12)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if controller.selectedRegionID != nil {
                    Text("Click video to set zoom target")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4).padding(12)
                }
            }

            // Transport controls
            HStack(spacing: 12) {
                Button { controller.jumpToPreviousMarker() } label: {
                    Image(systemName: "backward.end.fill").foregroundColor(.white)
                }
                Button { controller.togglePlayback() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18)).foregroundColor(.white)
                }
                Button { controller.jumpToNextMarker() } label: {
                    Image(systemName: "forward.end.fill").foregroundColor(.white)
                }
                Text(formatTime(controller.currentTime) + " / " + formatTime(controller.duration))
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .buttonStyle(.plain)

            Divider()

            // Timeline with drag support
            TimelineView(controller: controller)
                .padding(.horizontal, 20).padding(.vertical, 12)

            // Legend
            HStack(spacing: 16) {
                Label("Manual marker", systemImage: "circle.fill").font(.system(size: 11)).foregroundColor(.indigo)
                Label("Typing detected", systemImage: "circle.fill").font(.system(size: 11)).foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            // Marker detail
            MarkerDetailView(controller: controller)
                .padding(.horizontal, 20).padding(.bottom, 8)

            Divider()

            // Action bar
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

    /// Compute offset to pan toward the focal point during zoom
    private func zoomOffset(in viewSize: CGSize) -> CGSize {
        let zoom = currentZoomState
        guard zoom.scale > 1.01 else { return .zero }

        // Normalize focal point to [-0.5, 0.5] range (0,0 = center)
        let normalizedX = (zoom.focalPoint.x / controller.sourceSize.width) - 0.5
        let normalizedY = (zoom.focalPoint.y / controller.sourceSize.height) - 0.5

        // Offset proportional to zoom level — pan toward focal point
        let offsetX = -normalizedX * viewSize.width * (zoom.scale - 1.0)
        let offsetY = -normalizedY * viewSize.height * (zoom.scale - 1.0)

        return CGSize(width: offsetX, height: offsetY)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 49: controller.togglePlayback(); return nil       // Space
            case 123: controller.adjustScale(delta: -0.5); return nil  // Left arrow
            case 124: controller.adjustScale(delta: 0.5); return nil   // Right arrow
            case 51: controller.deleteSelectedRegion(); return nil     // Delete
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
