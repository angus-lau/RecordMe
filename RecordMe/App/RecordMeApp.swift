import SwiftUI

@main
struct RecordMeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: appState)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Window("Review Recording", id: "review") {
            if let controller = appState.reviewController {
                ReviewWindow(
                    controller: controller,
                    exportPipeline: appState.exportPipeline,
                    settings: appState.settings,
                    onExport: { preset in Task { await appState.startExport(preset: preset) } },
                    onDiscard: { appState.discardRecording() }
                )
            }
        }

        Window("Preferences", id: "preferences") {
            PreferencesView(settings: appState.settings)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        switch appState.phase {
        case .recording:
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.multicolor)
        default:
            Image(systemName: "record.circle")
        }
    }
}
