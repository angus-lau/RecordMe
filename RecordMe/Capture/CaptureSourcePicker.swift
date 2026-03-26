import ScreenCaptureKit

enum CaptureSourceType {
    case display(SCDisplay)
    case window(SCWindow)
    case app(SCRunningApplication, SCDisplay)
}

@MainActor
final class CaptureSourcePicker: ObservableObject {
    @Published var displays: [SCDisplay] = []
    @Published var windows: [SCWindow] = []
    @Published var apps: [SCRunningApplication] = []
    @Published var selectedSource: CaptureSourceType?
    private var hasRefreshed = false

    @Published var lastError: String?

    func refresh() async {
        do {
            let content = try await SCShareableContent.current
            displays = content.displays
            windows = content.windows.filter { $0.isOnScreen && $0.frame.width > 50 }
            apps = content.applications.filter { !$0.applicationName.isEmpty }
            if selectedSource == nil, let display = displays.first {
                selectedSource = .display(display)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func forceRefresh() async {
        await refresh()
    }

    /// Returns the pixel dimensions for SCStreamConfiguration
    var selectedSourcePixelSize: CGSize? {
        guard let source = selectedSource else { return nil }
        switch source {
        case .display(let display):
            // SCDisplay.width/height are in pixels
            return CGSize(width: display.width, height: display.height)
        case .window(let window):
            // SCWindow.frame is in points — multiply by scale factor for pixels
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            return CGSize(width: window.frame.width * scale, height: window.frame.height * scale)
        case .app(_, let display):
            return CGSize(width: display.width, height: display.height)
        }
    }

    /// Returns the point-size for coordinate normalization (cursor events are in points)
    var selectedSourcePointSize: CGSize? {
        guard let source = selectedSource else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        switch source {
        case .display(let display):
            // SCDisplay.width/height are pixels — divide by scale for points
            return CGSize(width: CGFloat(display.width) / scale, height: CGFloat(display.height) / scale)
        case .window(let window):
            // SCWindow.frame is already in points
            return window.frame.size
        case .app(_, let display):
            return CGSize(width: CGFloat(display.width) / scale, height: CGFloat(display.height) / scale)
        }
    }

    func buildFilter() -> SCContentFilter? {
        guard let source = selectedSource else { return nil }
        switch source {
        case .display(let display):
            return SCContentFilter(display: display, excludingWindows: [])
        case .window(let window):
            return SCContentFilter(desktopIndependentWindow: window)
        case .app(let app, let display):
            return SCContentFilter(display: display, including: [app], exceptingWindows: [])
        }
    }
}
