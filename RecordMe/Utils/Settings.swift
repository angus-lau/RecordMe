// RecordMe/Utils/Settings.swift
import Foundation

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        let exportPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/RecordMe").path
        defaults.register(defaults: [
            "defaultZoomLevel": 2.0,
            "defaultZoomDuration": 4.0,
            "defaultExportPresetLabel": "1080p",
            "defaultCodec": "hevc",
            "typingDetectionEnabled": true,
            "typingDetectionSensitivity": "medium",
            "exportSaveLocation": exportPath,
            "zoomHotkey": "cmd+shift+z",
            "stopRecordingHotkey": "cmd+shift+s",
            "launchAtLogin": false,
        ])
    }

    var defaultZoomLevel: CGFloat {
        get { defaults.double(forKey: "defaultZoomLevel") }
        set { defaults.set(newValue, forKey: "defaultZoomLevel") }
    }
    var defaultZoomDuration: Double {
        get { defaults.double(forKey: "defaultZoomDuration") }
        set { defaults.set(newValue, forKey: "defaultZoomDuration") }
    }
    var defaultExportPresetLabel: String {
        get { defaults.string(forKey: "defaultExportPresetLabel") ?? "1080p" }
        set { defaults.set(newValue, forKey: "defaultExportPresetLabel") }
    }
    var defaultCodec: String {
        get { defaults.string(forKey: "defaultCodec") ?? "hevc" }
        set { defaults.set(newValue, forKey: "defaultCodec") }
    }
    var typingDetectionEnabled: Bool {
        get { defaults.bool(forKey: "typingDetectionEnabled") }
        set { defaults.set(newValue, forKey: "typingDetectionEnabled") }
    }
    var typingDetectionSensitivity: String {
        get { defaults.string(forKey: "typingDetectionSensitivity") ?? "medium" }
        set { defaults.set(newValue, forKey: "typingDetectionSensitivity") }
    }
    var exportSaveLocation: String {
        get { defaults.string(forKey: "exportSaveLocation")
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/RecordMe").path }
        set { defaults.set(newValue, forKey: "exportSaveLocation") }
    }
    var zoomHotkey: String {
        get { defaults.string(forKey: "zoomHotkey") ?? "cmd+shift+z" }
        set { defaults.set(newValue, forKey: "zoomHotkey") }
    }
    var stopRecordingHotkey: String {
        get { defaults.string(forKey: "stopRecordingHotkey") ?? "cmd+shift+s" }
        set { defaults.set(newValue, forKey: "stopRecordingHotkey") }
    }
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }
}
