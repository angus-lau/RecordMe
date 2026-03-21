import Cocoa

final class HotkeyManager {
    private var monitors: [Any] = []
    typealias HotkeyHandler = () -> Void
    private var zoomHandler: HotkeyHandler?
    private var stopHandler: HotkeyHandler?
    private var zoomModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var zoomKey: String = "z"
    private var stopModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var stopKey: String = "s"

    func configure(settings: AppSettings) {
        (zoomModifiers, zoomKey) = parseHotkey(settings.zoomHotkey)
        (stopModifiers, stopKey) = parseHotkey(settings.stopRecordingHotkey)
    }

    func registerZoomHotkey(_ handler: @escaping HotkeyHandler) { zoomHandler = handler }
    func registerStopHotkey(_ handler: @escaping HotkeyHandler) { stopHandler = handler }

    func startListening() {
        stopListening()
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        if let monitor { monitors.append(monitor) }
    }

    func stopListening() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == zoomModifiers && key == zoomKey { zoomHandler?() }
        if flags == stopModifiers && key == stopKey { stopHandler?() }
    }

    private func parseHotkey(_ hotkey: String) -> (NSEvent.ModifierFlags, String) {
        let parts = hotkey.lowercased().split(separator: "+").map(String.init)
        var flags: NSEvent.ModifierFlags = []
        var key = ""
        for part in parts {
            switch part {
            case "cmd", "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "alt", "option": flags.insert(.option)
            case "ctrl", "control": flags.insert(.control)
            default: key = part
            }
        }
        return (flags, key)
    }

    deinit { stopListening() }
}
