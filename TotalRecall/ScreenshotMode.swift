import AppKit
import Foundation

/// CI/dev hook for capturing the inspection window via the `screencapture`
/// CLI. Activated by passing `--screenshot <path>` on the command line; the
/// app opens the inspection window, waits for one full data refresh cycle,
/// captures the entire main display to `<path>`, then quits.
enum ScreenshotMode {
    /// Wait long enough for `ProcessMonitor` to publish at least one snapshot
    /// before capturing — `AppState.startPolling` runs every 5s, plus an extra
    /// second to let SwiftUI commit the resulting layout.
    static let captureDelay: Duration = .seconds(8)

    static let outputPath: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--screenshot"),
              idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }()

    static var isActive: Bool { outputPath != nil }

    /// Spawn `/usr/sbin/screencapture -x -o <path>` (no sound, no shadow,
    /// full display) and terminate the app once it finishes.
    @MainActor
    static func captureAndExit() {
        guard let path = outputPath else { return }
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", url.path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                FileHandle.standardError.write(
                    Data("screencapture exited with status \(process.terminationStatus)\n".utf8)
                )
            }
        } catch {
            FileHandle.standardError.write(
                Data("screencapture failed: \(error)\n".utf8)
            )
        }

        NSApplication.shared.terminate(nil)
    }
}
