import TotalRecallCore
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Refresh interval", selection: $appState.refreshInterval) {
                    Text("3 seconds").tag(Duration.seconds(3))
                    Text("5 seconds").tag(Duration.seconds(5))
                    Text("10 seconds").tag(Duration.seconds(10))
                    Text("30 seconds").tag(Duration.seconds(30))
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350)
        .padding()
        .onAppear { refreshLaunchAtLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLoginStatus()
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at Login error: \(error)")
            refreshLaunchAtLoginStatus()
        }
    }
}
