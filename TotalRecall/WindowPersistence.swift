import Foundation

/// UserDefaults storage for window state that should survive across launches.
/// Position and size are handled by AppKit's `setFrameAutosaveName` (set on
/// the inspection window via `WindowVisibilityTracker`); this enum owns the
/// "was the window open?" flag and the autosave name constant.
enum WindowPersistence {
    private static let wasOpenKey = "totalrecall.inspection.wasOpen"

    /// Whether the inspection window was open the last time the app quit.
    /// Read at launch to decide whether to reopen it. UserDefaults is
    /// thread-safe per Apple's docs but doesn't carry the Sendable bit;
    /// touching `.standard` directly inside the accessor keeps the static
    /// surface concurrency-clean.
    static var wasOpenOnQuit: Bool {
        get { UserDefaults.standard.bool(forKey: wasOpenKey) }
        set { UserDefaults.standard.set(newValue, forKey: wasOpenKey) }
    }

    /// Autosave name set on the inspection NSWindow so AppKit persists
    /// position + size automatically across launches. Stored under
    /// `NSWindow Frame totalrecall.inspection` in the user defaults.
    static let inspectionFrameAutosaveName = "totalrecall.inspection"
}
