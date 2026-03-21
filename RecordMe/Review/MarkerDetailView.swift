import SwiftUI

struct MarkerDetailView: View {
    @ObservedObject var controller: ZoomTimelineController

    var body: some View {
        if let region = controller.selectedRegion {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(region.source == .manual ? "Manual" : "Typing") Marker @ \(formatTime(region.startTime))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Text("Zoom:").foregroundColor(.secondary)
                            Text(String(format: "%.1fx", region.scale))
                            Text("← → to adjust").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text("Duration:").foregroundColor(.secondary)
                            Text(String(format: "%.1fs", region.duration))
                            Text("[ ] to adjust").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            controller.deleteSelectedRegion()
                        } label: {
                            Label("Delete", systemImage: "trash").font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .font(.system(size: 13))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
