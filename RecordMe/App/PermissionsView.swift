import SwiftUI

struct PermissionsView: View {
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var checkTimer: Timer?

    let onComplete: () -> Void

    var allGranted: Bool { screenRecordingGranted && accessibilityGranted }

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to RecordMe").font(.title)
            Text("RecordMe needs a few permissions to work.").foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(title: "Screen Recording", description: "Required to capture your screen",
                    granted: screenRecordingGranted, buttonLabel: "Grant") {
                    Task { screenRecordingGranted = await Permissions.checkScreenRecording() == .granted }
                }
                permissionRow(title: "Accessibility", description: "Required to track cursor and detect typing",
                    granted: accessibilityGranted, buttonLabel: "Open Settings") {
                    Permissions.promptAccessibility()
                }
                permissionRow(title: "Microphone", description: "Optional, for voice narration",
                    granted: microphoneGranted, buttonLabel: "Grant") {
                    Task { microphoneGranted = await Permissions.requestMicrophone() }
                }
            }
            .padding()

            if allGranted {
                Button("Get Started") { onComplete() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(40)
        .frame(width: 450)
        .onAppear {
            checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                accessibilityGranted = Permissions.isAccessibilityGranted
            }
        }
        .onDisappear { checkTimer?.invalidate() }
    }

    private func permissionRow(title: String, description: String, granted: Bool, buttonLabel: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .secondary).font(.title2)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if !granted { Button(buttonLabel, action: action) }
        }
    }
}
