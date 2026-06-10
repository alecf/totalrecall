import TotalRecallCore
import SwiftUI
import AppKit

// MARK: - Entry point

/// SceneBuilder doesn't support `if/else`, so the screenshot variant is a
/// separate App type and we dispatch at `main()` based on argv.
@main
enum TotalRecallEntry {
    static func main() {
        if ScreenshotMode.isActive {
            ScreenshotApp.main()
        } else {
            TotalRecallApp.main()
        }
    }
}

// MARK: - Normal (menu bar) App

struct TotalRecallApp: App {
    @State private var appState = AppState()
    @State private var updater = Updater()

    init() {
        // Force accessory activation policy regardless of how we're launched.
        // The Info.plist's LSUIElement only applies when launched from a .app
        // bundle; `swift run` launches the bare binary, which defaults to
        // .regular and causes SwiftUI MenuBarExtra(.menu) buttons to render
        // disabled. Setting this explicitly fixes both launch paths.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState, updater: updater)
        } label: {
            MenuBarLabel(appState: appState)
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

// MARK: - Menu Bar Label

/// The view inside the MenuBarExtra label. Pulled out so it has its own
/// environment scope — that lets us use `@Environment(\.openWindow)` to
/// restore the inspection window at launch if it was open the last time
/// the app quit.
private struct MenuBarLabel: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.pressureColor(for: appState.systemMemory.memoryPressure))
                .frame(width: 8, height: 8)
            Text(appState.menuBarLabel)
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
        }
        .task {
            // Restore the inspection window if it was open at last quit.
            // Runs once when the menu bar icon first mounts, which happens
            // at app launch — before any user interaction.
            if WindowPersistence.wasOpenOnQuit {
                openWindow(id: "inspection")
            }
        }
    }
}

// MARK: - Screenshot App (CI capture mode)

/// Replaces the menu-bar UI with a single auto-opening WindowGroup so the
/// inspection view actually mounts under `--screenshot`. Drives the capture
/// from the view's `.task` and falls back to `AppDelegate`'s hard deadline
/// if anything stalls.
struct ScreenshotApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // .regular so the window can take focus and the dock is visible
        // in the captured image.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Total Recall") {
            ThemedInspectionWindow(appState: appState)
        }
        .defaultSize(width: 780, height: 560)
    }
}

// MARK: - App Delegate (screenshot safety net)

/// Hard timeout backstop for `--screenshot` mode. If anything in the SwiftUI
/// flow stalls (window doesn't mount, Task never resumes, etc.), this fires
/// after `ScreenshotMode.hardDeadline` so CI never hangs indefinitely.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ScreenshotMode.log("applicationDidFinishLaunching")
        DispatchQueue.main.asyncAfter(deadline: .now() + ScreenshotMode.hardDeadline) {
            ScreenshotMode.log("hard deadline reached — forcing capture")
            ScreenshotMode.captureAndExit()
        }
    }
}

// MARK: - Menu Bar Dropdown

struct MenuBarContentView: View {
    let appState: AppState
    let updater: Updater
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

        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)

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
                groups: appState.memoryRiverGroups,
                systemMemory: appState.systemMemory,
                hoveredGroupID: $hoveredGroupID,
                selectedGroupID: $appState.selectedGroupID
            )
            .padding(.horizontal)
            .padding(.top, 16)

            // Summary stats — click to deselect
            SummaryBarView(systemMemory: appState.systemMemory)
                .contentShape(Rectangle())
                .onTapGesture { appState.selectedGroupID = nil }

            // Breathing room — click to deselect
            Spacer()
                .frame(height: Theme.breathingRoom)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { appState.selectedGroupID = nil }

            // Main content: list + optional detail panel
            HStack(spacing: 0) {
                GroupListView(
                    groups: appState.sortedGroups,
                    sortByResident: appState.sortByResident,
                    showTreeView: appState.showTreeView,
                    selectedGroupID: $appState.selectedGroupID,
                    hoveredGroupID: $hoveredGroupID
                )
                // Opt the list out of the parent's animation context.
                // SwiftUI's List is NSOutlineView-backed; propagating an
                // animation that fires from inside the selection delegate
                // (when selectedGroupID changes via a row tap) causes
                // "Application performed a reentrant operation in its
                // NSTableView delegate" warnings.
                .transaction { $0.animation = nil }

                if let selectedGroup = resolveSelectedGroup() {
                    DetailPanelView(group: selectedGroup)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.default, value: appState.selectedGroupID)

            // Status bar with instance toggle
            HStack(spacing: 12) {
                if !appState.retainedExited.isEmpty {
                    Text("\(appState.retainedExited.count) exited")
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                // Tree/flat toggle
                Button {
                    appState.showTreeView.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.showTreeView ? "list.triangle" : "list.number")
                            .font(.caption)
                        Text(appState.showTreeView ? "Tree" : "By size")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(appState.showTreeView
                    ? "Showing subprocesses as parent-child tree. Click for flat list sorted by size."
                    : "Showing subprocesses sorted by size. Click for parent-child tree view.")

                // Sort toggle
                Button {
                    appState.sortByResident.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                        Text(appState.sortByResident ? "By resident" : "By footprint")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(appState.sortByResident
                    ? "Sorting by resident memory (in RAM now). Click to sort by total footprint."
                    : "Sorting by total footprint (includes compressed/swapped). Click to sort by resident.")

                // Instance grouping toggle
                Button {
                    appState.mergeInstances.toggle()
                    appState.refreshNow()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.mergeInstances ? "rectangle.stack" : "rectangle.split.3x1")
                            .font(.caption)
                        Text(appState.mergeInstances ? "Merged" : "Separate")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(appState.mergeInstances
                    ? "Showing multiple instances of the same app as one group. Click to show separately."
                    : "Showing each app instance separately. Click to merge.")

                Text("\(appState.groups.reduce(0) { $0 + $1.processCount }) processes in \(appState.groups.count) groups")
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
            WindowVisibilityTracker(
                frameAutosaveName: WindowPersistence.inspectionFrameAutosaveName
            ) { visible in
                Task { @MainActor in
                    appState.setWindowVisible(visible)
                }
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            // startPolling is now driven from AppState.init() so the menu
            // bar populates immediately at launch; here we just bump
            // polling into the visible-window tier.
            appState.setWindowVisible(true)
            if ScreenshotMode.isActive {
                ScreenshotMode.log("ThemedInspectionWindow.onAppear")
            }
        }
        .task {
            guard ScreenshotMode.isActive else { return }
            ScreenshotMode.log("ThemedInspectionWindow.task — sleeping for capture delay")
            try? await Task.sleep(for: ScreenshotMode.captureDelay)
            ScreenshotMode.log("capture delay elapsed — capturing")
            ScreenshotMode.captureAndExit()
        }
    }

    /// Resolve the selected ID to a ProcessGroup. Handles direct group IDs,
    /// "pid:123" process selections, and "sub:" sub-group row selections.
    private func resolveSelectedGroup() -> ProcessGroup? {
        guard let selectedID = appState.selectedGroupID else { return nil }
        return GroupSelection.resolve(selectedID: selectedID, in: appState.sortedGroups)
    }
}
