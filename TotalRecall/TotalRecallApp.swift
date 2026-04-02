import SwiftUI

@main
struct TotalRecallApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.pressureColor(for: appState.systemMemory.memoryPressure))
                    .frame(width: 8, height: 8)
                Text(appState.menuBarLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.menu)

        Window("Total Recall", id: "inspection") {
            ThemedInspectionWindow(appState: appState)
        }
        .defaultSize(width: 780, height: 560)
        .commandsRemoved()

        Settings {
            SettingsView(appState: appState)
        }
    }
}

// MARK: - Menu Bar Dropdown

struct MenuBarContentView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Memory: \(appState.menuBarLabel)")
        Text("Pressure: \(appState.systemMemory.memoryPressure.rawValue.capitalized)")

        if appState.systemMemory.swapUsed > 1024 * 1024 {
            Text("Swap: \(MemoryFormatter.format(bytes: appState.systemMemory.swapUsed))")
        }

        if let top = appState.topConsumer {
            Text("Top: \(top.name) — \(MemoryFormatter.format(bytes: top.deduplicatedFootprint))")
        }

        Divider()

        Button("Open Total Recall") {
            openWindow(id: "inspection")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])

        SettingsLink {
            Text("Preferences...")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Total Recall") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Themed Inspection Window

struct ThemedInspectionWindow: View {
    @Bindable var appState: AppState
    @State private var hoveredGroupID: String?

    var body: some View {
        VStack(spacing: 0) {
            // Memory River
            MemoryRiverView(
                groups: appState.groups,
                totalUsed: appState.systemMemory.used,
                hoveredGroupID: $hoveredGroupID,
                selectedGroupID: $appState.selectedGroupID
            )
            .padding(.horizontal)
            .padding(.top, 16)

            // Summary stats
            SummaryBarView(systemMemory: appState.systemMemory)

            // Breathing room
            Spacer()
                .frame(height: Theme.breathingRoom)

            // Main content: list + optional detail panel
            HStack(spacing: 0) {
                GroupListView(
                    groups: appState.groups,
                    selectedGroupID: $appState.selectedGroupID,
                    hoveredGroupID: $hoveredGroupID
                )

                if let selectedID = appState.selectedGroupID,
                   let selectedGroup = appState.groups.first(where: { $0.id == selectedID }) {
                    DetailPanelView(group: selectedGroup)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.default, value: appState.selectedGroupID)

            // Status bar
            HStack {
                if !appState.retainedExited.isEmpty {
                    Text("\(appState.retainedExited.count) exited")
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Text("\(appState.groups.reduce(0) { $0 + $1.processCount }) processes")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .background(Theme.bgVoid)
        .preferredColorScheme(.dark)
        .frame(minWidth: 600, minHeight: 400)
        .background {
            WindowVisibilityTracker { visible in
                Task { @MainActor in
                    appState.setWindowVisible(visible)
                }
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            appState.setWindowVisible(true)
            appState.startPolling()
        }
    }
}
