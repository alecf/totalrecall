import SwiftUI

@main
struct TotalRecallApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Total Recall — loading...")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Text("TR")
        }
        .menuBarExtraStyle(.menu)
    }
}
