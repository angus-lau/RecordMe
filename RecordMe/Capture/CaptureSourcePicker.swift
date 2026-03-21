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

    func refresh() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays
            windows = content.windows.filter { $0.isOnScreen && $0.frame.width > 50 }
            apps = content.applications.filter { !$0.applicationName.isEmpty }
            if selectedSource == nil, let display = displays.first {
                selectedSource = .display(display)
            }
        } catch {
            print("CaptureSourcePicker: Failed to get shareable content: \(error)")
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
