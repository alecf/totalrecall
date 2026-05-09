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

    /// Backstop deadline measured from `applicationDidFinishLaunching`. If the
    /// happy-path capture hasn't fired by then, the AppDelegate forces it.
    /// Must comfortably exceed `captureDelay` plus any window-mount latency.
    static let hardDeadline: TimeInterval = 25

    static let outputPath: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--screenshot"),
              idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }()

    static var isActive: Bool { outputPath != nil }

    /// Emit a stderr breadcrumb tagged so CI logs are easy to scan.
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("[screenshot] \(message)\n".utf8))
    }

    /// Spawn `/usr/sbin/screencapture -x -o <path>` (no sound, no shadow,
    /// full display) and terminate the app once it finishes. Idempotent —
    /// if both the happy path and the AppDelegate backstop fire, the second
    /// call is a no-op.
    @MainActor
    static func captureAndExit() {
        guard let path = outputPath else { return }
        guard !didCapture else {
            log("captureAndExit skipped (already captured)")
            return
        }
        didCapture = true

        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        // Target the inspection window directly so overlapping dialogs from
        // other apps (Chrome's first-run prompt, etc.) don't appear in the
        // capture. screencapture -l grabs the window's compositor contents,
        // not the visible screen region, so it works even when occluded.
        // Prefer the main window; fall back to the first visible window with
        // a reasonable frame so we don't grab a hidden helper.
        let window = NSApp.mainWindow
            ?? NSApp.windows.first { $0.isVisible && $0.frame.width > 200 }

        var args = ["-x", "-o"]
        if let window {
            log("targeting window #\(window.windowNumber) \"\(window.title)\" \(window.frame)")
            args += ["-l", String(window.windowNumber)]
        } else {
            log("no inspection window found — falling back to full-display capture")
        }
        args.append(url.path)

        log("running screencapture \(args.joined(separator: " "))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
            log("screencapture exited with status \(process.terminationStatus)")
        } catch {
            log("screencapture failed to launch: \(error)")
        }

        log("calling NSApplication.terminate")
        NSApplication.shared.terminate(nil)
        // Belt-and-suspenders: if SwiftUI swallows the terminate (rare, but
        // documented in some menubar configurations), exit() guarantees we
        // don't leave the CI runner waiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            log("terminate did not exit process; calling exit(0)")
            exit(0)
        }
    }

    @MainActor private static var didCapture = false
}
