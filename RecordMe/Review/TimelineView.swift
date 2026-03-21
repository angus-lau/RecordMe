import SwiftUI

struct TimelineView: View {
    @ObservedObject var controller: ZoomTimelineController

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                        .offset(y: 14)

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

                    // Markers
                    ForEach(controller.timeline.regions) { region in
                        let x = xPosition(for: (region.startTime + region.endTime) / 2, in: geo.size.width)
                        Circle()
                            .fill(region.source == .manual ? Color.indigo : Color.orange)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().stroke(controller.selectedRegionID == region.id ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .offset(x: x - 7, y: 0)
                            .onTapGesture { controller.selectRegion(region) }
                    }

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
                            let time = timePosition(for: value.location.x, in: geo.size.width)
                            controller.seek(to: time)
                        }
                )
            }
            .frame(height: 32)

            // Time labels
            HStack {
                Text(formatTime(0))
                Spacer()
                Text(formatTime(controller.duration))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
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
