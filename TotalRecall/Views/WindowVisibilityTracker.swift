import TotalRecallCore
import SwiftUI
import AppKit

/// Bridges NSWindow notifications to SwiftUI for detecting window visibility.
/// Used to drive the two-tier refresh strategy.
///
/// Also configures the window's `frameAutosaveName` if one is provided, so
/// AppKit persists position + size across launches. Setting it from here
/// keeps all window-level wiring in one place.
struct WindowVisibilityTracker: NSViewRepresentable {
    let frameAutosaveName: String?
    let onVisibilityChanged: @Sendable (Bool) -> Void

    init(
        frameAutosaveName: String? = nil,
        onVisibilityChanged: @escaping @Sendable (Bool) -> Void
    ) {
        self.frameAutosaveName = frameAutosaveName
        self.onVisibilityChanged = onVisibilityChanged
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let autosaveName = frameAutosaveName
        // Defer to next runloop so the view is in a window
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            if let autosaveName {
                window.setFrameAutosaveName(autosaveName)
            }

            let nc = NotificationCenter.default

            nc.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { _ in onVisibilityChanged(true) }

            nc.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in onVisibilityChanged(false) }

            nc.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { _ in onVisibilityChanged(false) }

            nc.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { _ in onVisibilityChanged(true) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
