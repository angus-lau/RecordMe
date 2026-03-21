import Cocoa

final class EventLogger {
    private var writer: EventLogWriter?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startTime: Double = 0
    private let cursorSampleInterval: Double = 0.05
    private var lastCursorLogTime: Double = 0

    func start(fileURL: URL) throws {
        let w = EventLogWriter(fileURL: fileURL)
        try w.open()
        writer = w
        startTime = CACurrentMediaTime()
        lastCursorLogTime = 0
        startEventTap()
    }

    func stop() {
        stopEventTap()
        writer?.close()
        writer = nil
    }

    func logManualMarker() {
        let pos = NSEvent.mouseLocation
        let t = CACurrentMediaTime() - startTime
        let event = InputEvent(t: t, type: .marker, x: pos.x, y: pos.y)
        try? writer?.write(event)
    }

    private func startEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, cgEvent, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
            let logger = Unmanaged<EventLogger>.fromOpaque(userInfo).takeUnretainedValue()
            logger.handleCGEvent(type: type, event: cgEvent)
            return Unmanaged.passRetained(cgEvent)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: eventMask, callback: callback, userInfo: selfPtr
        ) else {
            // Accessibility permission not granted — event tap unavailable
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        let t = CACurrentMediaTime() - startTime
        let location = event.location

        switch type {
        case .mouseMoved:
            guard t - lastCursorLogTime >= cursorSampleInterval else { return }
            lastCursorLogTime = t
            try? writer?.write(InputEvent(t: t, type: .cursor, x: location.x, y: location.y))
        case .leftMouseDown:
            try? writer?.write(InputEvent(t: t, type: .click, x: location.x, y: location.y, button: "left"))
        case .rightMouseDown:
            try? writer?.write(InputEvent(t: t, type: .click, x: location.x, y: location.y, button: "right"))
        case .keyDown:
            let cursorPos = NSEvent.mouseLocation
            try? writer?.write(InputEvent(t: t, type: .key, x: cursorPos.x, y: cursorPos.y))
        default: break
        }
    }
}
