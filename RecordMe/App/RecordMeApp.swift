import SwiftUI

@main
struct RecordMeApp: App {
    var body: some Scene {
        MenuBarExtra("RecordMe", systemImage: "record.circle") {
            Text("RecordMe")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
