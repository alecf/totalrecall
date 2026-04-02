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
                    .fill(pressureColor)
                    .frame(width: 8, height: 8)
                Text(appState.menuBarLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.menu)

        Window("Total Recall", id: "inspection") {
            InspectionWindowView(appState: appState)
        }
        .defaultSize(width: 780, height: 560)
        .commandsRemoved()
    }

    private var pressureColor: Color {
        switch appState.systemMemory.memoryPressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

// MARK: - Menu Bar Dropdown Content

struct MenuBarContentView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Memory: \(appState.menuBarLabel)")
        Text("Pressure: \(appState.systemMemory.memoryPressure.rawValue.capitalized)")

        if appState.systemMemory.swapUsed > 0 {
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

        Divider()

        Button("Quit Total Recall") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Basic Inspection Window (Phase 3a — plain list, no design)

struct InspectionWindowView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Summary
            HStack {
                Text(MemoryFormatter.formatUsedTotal(
                    used: appState.systemMemory.used,
                    total: appState.systemMemory.totalPhysical
                ))
                .font(.system(size: 20, design: .monospaced).bold())

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(pressureColor)
                        .frame(width: 10, height: 10)
                    Text(appState.systemMemory.memoryPressure.rawValue.capitalized)
                        .font(.headline)
                }

                if appState.systemMemory.swapUsed > 1024 * 1024 {
                    Text("Swap: \(MemoryFormatter.format(bytes: appState.systemMemory.swapUsed))")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Group list
            List(appState.groups, selection: $appState.selectedGroupID) { group in
                DisclosureGroup {
                    ForEach(group.processes.prefix(20)) { process in
                        HStack {
                            Text(processLabel(process, in: group))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(MemoryFormatter.format(bytes: process.physFootprint))
                                .font(.system(.body, design: .monospaced))
                                .monospacedDigit()
                        }
                        .contextMenu {
                            processContextMenu(for: process)
                        }
                    }
                    if group.processes.count > 20 {
                        Text("+ \(group.processes.count - 20) more processes")
                            .foregroundStyle(.tertiary)
                    }
                } label: {
                    HStack {
                        if let icon = group.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app.dashed")
                                .frame(width: 20, height: 20)
                        }

                        Text(group.name)
                            .fontWeight(.medium)

                        if let subGroups = group.subGroups {
                            Text("(\(subGroups.count) sub-groups)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }

                        Spacer()

                        Text(MemoryFormatter.format(bytes: group.deduplicatedFootprint))
                            .font(.system(.body, design: .monospaced).bold())
                            .monospacedDigit()

                        trendIndicator(group.trend)
                    }
                    .contextMenu {
                        groupContextMenu(for: group)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            // Status bar
            HStack {
                if !appState.retainedExited.isEmpty {
                    Text("\(appState.retainedExited.count) exited")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(appState.groups.reduce(0) { $0 + $1.processCount }) processes")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
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

    private var pressureColor: Color {
        switch appState.systemMemory.memoryPressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    @ViewBuilder
    private func trendIndicator(_ trend: Trend) -> some View {
        switch trend {
        case .up:
            Text("▲").foregroundStyle(.red).font(.caption)
        case .down:
            Text("▼").foregroundStyle(.green).font(.caption)
        case .stable:
            Text("─").foregroundStyle(.secondary).font(.caption)
        case .unknown:
            Text("─").foregroundStyle(.quaternary).font(.caption)
        }
    }

    private func processLabel(_ process: ProcessSnapshot, in group: ProcessGroup) -> String {
        if group.classifierName == "System" {
            return SystemServicesClassifier.displayName(for: process.name) ?? process.name
        }
        if let type = CommandLineParser.electronProcessType(from: process.commandLineArgs) {
            return type.rawValue
        }
        return process.name
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func processContextMenu(for process: ProcessSnapshot) -> some View {
        Button("Quit (SIGTERM)") {
            killProcess(process, signal: SIGTERM)
        }
        Button("Force Quit (SIGKILL)") {
            killProcess(process, signal: SIGKILL)
        }
    }

    @ViewBuilder
    private func groupContextMenu(for group: ProcessGroup) -> some View {
        if ProcessActions.isGroupKillable(group) {
            Button("Quit All (SIGTERM)") {
                let errors = ProcessActions.sendSignalToAll(SIGTERM, in: group)
                if !errors.isEmpty {
                    print("Kill errors: \(errors.map { "\($0.0.pid): \($0.1.localizedDescription)" })")
                }
            }
            Button("Force Quit All (SIGKILL)") {
                let errors = ProcessActions.sendSignalToAll(SIGKILL, in: group)
                if !errors.isEmpty {
                    print("Kill errors: \(errors.map { "\($0.0.pid): \($0.1.localizedDescription)" })")
                }
            }
        } else {
            Text("System processes cannot be bulk-killed")
                .foregroundStyle(.secondary)
        }
    }

    private func killProcess(_ process: ProcessSnapshot, signal: Int32) {
        do {
            try ProcessActions.sendSignal(signal, to: process.processIdentity)
        } catch {
            print("Kill failed: \(error.localizedDescription)")
        }
    }
}
