import SwiftUI

struct TimelineView: View {
    @ObservedObject var controller: ZoomTimelineController
    @State private var draggingTrim: TrimHandle? = nil
    @State private var draggingMarker = false

    private enum TrimHandle {
        case start, end
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Dimmed regions outside trim range
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

                    // Track background (full width)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                        .offset(y: 14)

                    // Active track (trim range)
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
                    }

                    // Markers — tap to select, drag to move (larger hit target, high priority gesture)
                    ForEach(controller.timeline.regions) { region in
                        let x = xPosition(for: (region.startTime + region.endTime) / 2, in: geo.size.width)
                        Circle()
                            .fill(region.source == .manual ? Color.indigo : Color.orange)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(controller.selectedRegionID == region.id ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .padding(8) // extra hit area
                            .contentShape(Circle().inset(by: -8))
                            .offset(x: x - 17, y: -8)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 2)
                                    .onChanged { value in
                                        draggingMarker = true
                                        controller.selectedRegionID = region.id
                                        let time = timePosition(for: value.location.x + x - 17, in: geo.size.width)
                                        controller.moveRegion(region, to: time)
                                    }
                                    .onEnded { _ in
                                        draggingMarker = false
                                    }
                            )
                            .onTapGesture { controller.selectRegion(region) }
                    }

                    // Trim start handle
                    trimHandle(at: trimStartX, color: .yellow)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let time = timePosition(for: value.location.x, in: geo.size.width)
                                    controller.trimStart = max(0, min(time, controller.trimEnd - 0.5))
                                }
                        )

                    // Trim end handle
                    trimHandle(at: trimEndX - 6, color: .yellow)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let time = timePosition(for: value.location.x, in: geo.size.width)
                                    controller.trimEnd = min(controller.duration, max(time, controller.trimStart + 0.5))
                                }
                        )

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
                }
                .frame(height: 32)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Don't scrub while dragging a marker
                            guard !draggingMarker else { return }

                            // Check if near trim handles first
                            let trimStartX = xPosition(for: controller.trimStart, in: geo.size.width)
                            let trimEndX = xPosition(for: controller.trimEnd, in: geo.size.width)

                            if draggingTrim == nil {
                                if abs(value.startLocation.x - trimStartX) < 15 {
                                    draggingTrim = .start
                                } else if abs(value.startLocation.x - trimEndX) < 15 {
                                    draggingTrim = .end
                                }
                            }

                            let time = timePosition(for: value.location.x, in: geo.size.width)
                            switch draggingTrim {
                            case .start:
                                controller.trimStart = max(0, min(time, controller.trimEnd - 0.5))
                            case .end:
                                controller.trimEnd = min(controller.duration, max(time, controller.trimStart + 0.5))
                            case nil:
                                // Scrub playhead
                                controller.seek(to: time)
                            }
                        }
                        .onEnded { _ in
                            draggingTrim = nil
                        }
                )
            }
            .frame(height: 32)

            // Time labels showing trim range
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

    private func trimHandle(at x: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 6, height: 32)
            .offset(x: x - 3)
            .contentShape(Rectangle().inset(by: -8))
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
