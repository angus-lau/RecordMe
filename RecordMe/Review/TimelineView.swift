import SwiftUI

struct TimelineView: View {
    @ObservedObject var controller: ZoomTimelineController
    @State private var dragTarget: DragTarget? = nil

    private enum DragTarget {
        case trimStart
        case trimEnd
        case marker(UUID)
        case scrub
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    let trimStartX = xPosition(for: controller.trimStart, in: geo.size.width)
                    let trimEndX = xPosition(for: controller.trimEnd, in: geo.size.width)

                    // Left dimmed area
                    if trimStartX > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: trimStartX, height: 32)
                    }

                    // Right dimmed area
                    if trimEndX < geo.size.width {
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: geo.size.width - trimEndX, height: 32)
                            .offset(x: trimEndX)
                    }

                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                        .offset(y: 14)

                    // Active track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: max(0, trimEndX - trimStartX), height: 4)
                        .offset(x: trimStartX, y: 14)

                    // Zoom region highlights
                    ForEach(controller.timeline.regions) { region in
                        let startX = xPosition(for: region.startTime, in: geo.size.width)
                        let endX = xPosition(for: region.endTime, in: geo.size.width)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(region.source == .manual ? Color.indigo.opacity(0.2) : Color.orange.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(region.source == .manual ? Color.indigo.opacity(0.4) : Color.orange.opacity(0.4), lineWidth: 1)
                            )
                            .frame(width: max(4, endX - startX), height: 12)
                            .offset(x: startX, y: 8)
                            .allowsHitTesting(false)
                    }

                    // Markers (visual only — interaction handled by unified gesture)
                    ForEach(controller.timeline.regions) { region in
                        let x = xPosition(for: (region.startTime + region.endTime) / 2, in: geo.size.width)
                        Circle()
                            .fill(region.source == .manual ? Color.indigo : Color.orange)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(controller.selectedRegionID == region.id ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .offset(x: x - 9, y: -2)
                            .allowsHitTesting(false)
                    }

                    // Trim handles (visual only)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.yellow)
                        .frame(width: 6, height: 32)
                        .offset(x: trimStartX - 3)
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.yellow)
                        .frame(width: 6, height: 32)
                        .offset(x: trimEndX - 3)
                        .allowsHitTesting(false)

                    // Playhead
                    let playheadX = xPosition(for: controller.currentTime, in: geo.size.width)
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: 22)
                    }
                    .offset(x: playheadX - 5, y: -3)
                    .allowsHitTesting(false)
                }
                .frame(height: 32)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragTarget == nil {
                                dragTarget = identifyTarget(at: value.startLocation, in: geo.size.width)
                            }
                            let time = timePosition(for: value.location.x, in: geo.size.width)
                            handleDrag(time: time)
                        }
                        .onEnded { _ in
                            dragTarget = nil
                        }
                )
            }
            .frame(height: 32)

            // Time labels
            HStack {
                Text(formatTime(controller.trimStart))
                Spacer()
                if controller.trimStart > 0 || controller.trimEnd < controller.duration {
                    Text("Trimmed: \(formatTime(controller.trimEnd - controller.trimStart))")
                        .foregroundColor(.yellow)
                }
                Spacer()
                Text(formatTime(controller.trimEnd))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
        }
    }

    /// Determine what the user started dragging based on proximity
    private func identifyTarget(at point: CGPoint, in width: CGFloat) -> DragTarget {
        let trimStartX = xPosition(for: controller.trimStart, in: width)
        let trimEndX = xPosition(for: controller.trimEnd, in: width)

        // Check trim handles first (12px hit zone)
        if abs(point.x - trimStartX) < 12 { return .trimStart }
        if abs(point.x - trimEndX) < 12 { return .trimEnd }

        // Check markers (20px hit zone)
        for region in controller.timeline.regions {
            let markerX = xPosition(for: (region.startTime + region.endTime) / 2, in: width)
            if abs(point.x - markerX) < 20 {
                controller.selectedRegionID = region.id
                return .marker(region.id)
            }
        }

        // Default: scrub playhead
        return .scrub
    }

    private func handleDrag(time: Double) {
        switch dragTarget {
        case .trimStart:
            controller.trimStart = max(0, min(time, controller.trimEnd - 0.5))
        case .trimEnd:
            controller.trimEnd = min(controller.duration, max(time, controller.trimStart + 0.5))
        case .marker(let id):
            if let region = controller.timeline.regions.first(where: { $0.id == id }) {
                controller.moveRegion(region, to: time)
            }
        case .scrub:
            controller.seek(to: time)
        case nil:
            break
        }
    }

    private func xPosition(for time: Double, in width: CGFloat) -> CGFloat {
        guard controller.duration > 0 else { return 0 }
        return CGFloat(time / controller.duration) * width
    }

    private func timePosition(for x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return max(0, min(controller.duration, Double(x / width) * controller.duration))
    }

    private func formatTime(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
