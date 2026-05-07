import Sparkle
import SwiftUI

/// Owns the Sparkle updater controller. Bridges Sparkle's KVO-based
/// `canCheckForUpdates` into an `@Observable` value SwiftUI can read.
@MainActor
@Observable
final class Updater {
    private let controller: SPUStandardUpdaterController
    private(set) var canCheckForUpdates: Bool = false
    private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in
                self?.canCheckForUpdates = value
            }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
