import SwiftUI
import AppKit

/// Bridges NSWindow notifications to SwiftUI for detecting window visibility.
/// Used to drive the two-tier refresh strategy.
struct WindowVisibilityTracker: NSViewRepresentable {
    let onVisibilityChanged: @Sendable (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer to next runloop so the view is in a window
        DispatchQueue.main.async {
            guard let window = view.window else { return }

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
