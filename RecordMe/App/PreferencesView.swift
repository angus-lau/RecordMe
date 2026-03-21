import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings

    private let zoomLevels: [CGFloat] = [1.5, 2.0, 2.5, 3.0]
    private let zoomDurations: [Double] = [2.0, 4.0, 6.0]
    private let sensitivities = ["low", "medium", "high"]

    var body: some View {
        Form {
            Section("Zoom") {
                Picker("Default zoom level", selection: Binding(
                    get: { settings.defaultZoomLevel }, set: { settings.defaultZoomLevel = $0 }
                )) { ForEach(zoomLevels, id: \.self) { Text(String(format: "%.1fx", $0)).tag($0) } }

                Picker("Default zoom duration", selection: Binding(
                    get: { settings.defaultZoomDuration }, set: { settings.defaultZoomDuration = $0 }
                )) { ForEach(zoomDurations, id: \.self) { Text(String(format: "%.0fs", $0)).tag($0) } }

                Toggle("Typing detection", isOn: Binding(
                    get: { settings.typingDetectionEnabled }, set: { settings.typingDetectionEnabled = $0 }
                ))

                if settings.typingDetectionEnabled {
                    Picker("Typing sensitivity", selection: Binding(
                        get: { settings.typingDetectionSensitivity }, set: { settings.typingDetectionSensitivity = $0 }
                    )) { ForEach(sensitivities, id: \.self) { Text($0.capitalized).tag($0) } }
                }
            }

            Section("Hotkeys") {
                HStack { Text("Zoom marker"); Spacer(); Text(settings.zoomHotkey).foregroundColor(.secondary).font(.system(.body, design: .monospaced)) }
                HStack { Text("Stop recording"); Spacer(); Text(settings.stopRecordingHotkey).foregroundColor(.secondary).font(.system(.body, design: .monospaced)) }
            }

            Section("Export") {
                Picker("Default preset", selection: Binding(
                    get: { settings.defaultExportPresetLabel }, set: { settings.defaultExportPresetLabel = $0 }
                )) { Text("1080p").tag("1080p"); Text("4K").tag("4K"); Text("Source").tag("Source") }

                Picker("Default codec", selection: Binding(
                    get: { settings.defaultCodec }, set: { settings.defaultCodec = $0 }
                )) { Text("HEVC").tag("hevc"); Text("H.264").tag("h264") }

                HStack {
                    Text("Save location"); Spacer()
                    Text(settings.exportSaveLocation).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Change...") { chooseExportLocation() }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }
                ))
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility"); Spacer()
                    Text(Permissions.isAccessibilityGranted ? "Granted" : "Not granted")
                        .foregroundColor(Permissions.isAccessibilityGranted ? .green : .red)
                }
                if !Permissions.isAccessibilityGranted {
                    Text("Enable Accessibility for typing detection and cursor tracking.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
    }

    private func chooseExportLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { settings.exportSaveLocation = url.path }
    }
}
