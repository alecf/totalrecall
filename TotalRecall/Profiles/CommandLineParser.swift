import Foundation

/// Shared utility for extracting process roles and metadata from command-line arguments.
/// Consumed by classifiers to avoid duplicating arg-parsing logic.
enum CommandLineParser {

    /// Electron/Chrome process types from --type= flag.
    enum ProcessType: String, Sendable {
        case renderer
        case gpu = "gpu-process"
        case utility
        case broker
        case zygote
        case crashpad = "crashpad-handler"
    }

    /// Extract --type= value from args (Chrome, Electron).
    static func electronProcessType(from args: [String]) -> ProcessType? {
        for arg in args {
            if arg.hasPrefix("--type=") {
                let value = String(arg.dropFirst("--type=".count))
                return ProcessType(rawValue: value)
            }
        }
        return nil
    }

    /// Extract --profile-directory= value from Chrome args.
    static func chromeProfileDirectory(from args: [String]) -> String? {
        for arg in args {
            if arg.hasPrefix("--profile-directory=") {
                return String(arg.dropFirst("--profile-directory=".count))
            }
        }
        return nil
    }

    /// Check if a path contains a specific framework name.
    static func pathContainsFramework(_ path: String, named frameworkName: String) -> Bool {
        path.contains("\(frameworkName).framework") || path.contains("\(frameworkName).app")
    }

    /// Extract the app name from a macOS bundle path.
    /// "/Applications/Google Chrome.app/Contents/..." → "Google Chrome"
    static func appNameFromPath(_ path: String) -> String? {
        let components = path.components(separatedBy: "/")
        for component in components {
            if component.hasSuffix(".app") {
                return String(component.dropLast(4))
            }
        }
        return nil
    }

    /// Extract the last path component (executable name).
    static func executableName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
