import SwiftUI

struct ReviewWindow: View {
    @ObservedObject var controller: ZoomTimelineController
    @ObservedObject var exportPipeline: ExportPipeline
    let settings: AppSettings
    let onExport: (ExportPreset) -> Void
    let onDiscard: () -> Void

    @State private var selectedPresetIndex = 0  // Default to Source HEVC
    @State private var keyMonitor: Any?

    private var presets: [ExportPreset] {
        let aspect = controller.videoSize.width / controller.videoSize.height
        let vidW = Int(controller.videoSize.width)
        let vidH = Int(controller.videoSize.height)
        return [
            .source(width: vidW, height: vidH, codec: .hevc),
            .hd1080p(codec: .hevc, sourceAspect: aspect),
            .uhd4k(codec: .hevc, sourceAspect: aspect),
            .source(width: vidW, height: vidH, codec: .h264),
            .hd1080p(codec: .h264, sourceAspect: aspect),
            .uhd4k(codec: .h264, sourceAspect: aspect),
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
            .aspectRatio(controller.videoSize.width / controller.videoSize.height, contentMode: .fit)
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
                    Picker("", selection: $selectedPresetIndex) {
                        ForEach(presets.indices, id: \.self) { i in
                            let p = presets[i]
                            let codec = p.codec == .hevc ? "HEVC" : "H.264"
                            Text("\(p.label) (\(p.width)x\(p.height)) \(codec)").tag(i)
                        }
                    }
                    .frame(width: 280)
                    Button("Export") { onExport(presets[selectedPresetIndex]) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear { installKeyMonitor() }
        .onDisappear {
            removeKeyMonitor()
            controller.cleanup()
        }
    }

    /// Compute offset to pan toward the focal point during zoom.
    /// scaleEffect scales from the view center. We need to shift so the focal point ends up at center.
    private func zoomOffset(in viewSize: CGSize) -> CGSize {
        let zoom = currentZoomState
        guard zoom.scale > 1.01 else { return .zero }

        // Focal point as fraction of view [0, 1]
        let focalNormX = zoom.focalPoint.x / controller.sourceSize.width
        let focalNormY = zoom.focalPoint.y / controller.sourceSize.height

        // After scaleEffect(scale) from center, the point that was at focalNorm
        // is now at: center + (focalNorm - 0.5) * scale * viewSize
        // We want it at the center of the view, so offset = -(focalNorm - 0.5) * scale * viewSize
        // But offset is applied AFTER scale, in the parent coordinate space,
        // so we don't multiply by scale — the scaled view moves in parent coords.
        let offsetX = -(focalNormX - 0.5) * viewSize.width * zoom.scale
        let offsetY = -(focalNormY - 0.5) * viewSize.height * zoom.scale

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
