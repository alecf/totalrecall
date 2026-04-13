import Foundation

/// Shared utility for extracting process roles and metadata from command-line arguments.
/// Consumed by classifiers to avoid duplicating arg-parsing logic.
public enum CommandLineParser {

    /// Electron/Chrome process types from --type= flag.
    public enum ProcessType: String, Sendable {
        case renderer
        case gpu = "gpu-process"
        case utility
        case broker
        case zygote
        case crashpad = "crashpad-handler"
    }

    /// Extract --type= value from args (Chrome, Electron).
    public static func electronProcessType(from args: [String]) -> ProcessType? {
        for arg in args {
            if arg.hasPrefix("--type=") {
                let value = String(arg.dropFirst("--type=".count))
                return ProcessType(rawValue: value)
            }
        }
        return nil
    }

    /// Extract --profile-directory= value from Chrome args.
    public static func chromeProfileDirectory(from args: [String]) -> String? {
        for arg in args {
            if arg.hasPrefix("--profile-directory=") {
                return String(arg.dropFirst("--profile-directory=".count))
            }
        }
        return nil
    }

    /// Check if a path contains a specific framework name.
    public static func pathContainsFramework(_ path: String, named frameworkName: String) -> Bool {
        path.contains("\(frameworkName).framework") || path.contains("\(frameworkName).app")
    }

    /// Extract the app name from a macOS bundle path.
    /// "/Applications/Google Chrome.app/Contents/..." → "Google Chrome"
    public static func appNameFromPath(_ path: String) -> String? {
        let components = path.components(separatedBy: "/")
        for component in components {
            if component.hasSuffix(".app") {
                return String(component.dropLast(4))
            }
        }
        return nil
    }

    /// Extract the last path component (executable name).
    public static func executableName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }

    // MARK: - Volta / Version Manager Shim Resolution

    /// Check if a process name looks like a version string (e.g., "2.1.89").
    /// This happens with volta shims where the process name becomes the package version.
    public static func isVersionString(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    /// Check if a path is a volta shim or volta-managed binary.
    public static func isVoltaPath(_ path: String) -> Bool {
        path.contains(".volta/")
    }

    /// Resolve the actual tool name from a volta-shimmed process.
    /// Checks args for the real command, since the process name is just the version.
    /// Returns nil if it can't determine the tool.
    public static func resolveVoltaShim(processName: String, path: String, args: [String]) -> String? {
        // If the process name is a version string, look at args[0] for the real name
        if isVersionString(processName) && !args.isEmpty {
            let firstArg = executableName(from: args[0])
            if !firstArg.isEmpty && !isVersionString(firstArg) {
                return firstArg
            }
        }

        // If the path is a volta path, extract the tool name
        // e.g., "/Users/foo/.volta/tools/image/node/22.21.0/bin/node" → "node"
        if isVoltaPath(path) {
            let exec = executableName(from: path)
            if !exec.isEmpty && !isVersionString(exec) {
                return exec
            }
        }

        return nil
    }

    // MARK: - Shim Resolution (volta, mise, asdf, etc.)

    /// Check if a process is a version-manager shim based on its name or path.
    /// Covers volta, mise (formerly rtx), asdf, and similar tools.
    public static func isShimProcess(_ name: String, path: String) -> Bool {
        if name == "volta-shim" { return true }
        // mise/asdf shims live in ~/.local/share/mise/shims/ or ~/.asdf/shims/
        if path.contains("/mise/shims/") || path.contains("/asdf/shims/") { return true }
        return false
    }

    /// Resolve a shim process's display name from its command-line args.
    /// args[0] contains the actual command the shim is proxying (e.g., "npm", "npx", "node").
    /// Chains with resolveRuntimeTool for further detail.
    public static func resolveShimDisplayName(args: [String]) -> String? {
        guard let first = args.first, !first.isEmpty else { return nil }

        // args[0] is the shimmed command — extract just the name
        let toolName = executableName(from: first)
        guard !toolName.isEmpty, toolName != "volta-shim" else { return nil }

        // For runtimes, try to resolve what they're running
        if ["node", "npx", "bun"].contains(toolName) {
            if let detail = resolveRuntimeTool(args: args) {
                return "\(toolName) (\(detail))"
            }
        }

        // For npm/yarn/pnpm, show the subcommand (e.g., "npm run dev:api")
        if ["npm", "yarn", "pnpm"].contains(toolName), args.count > 1 {
            let subcommand = args.dropFirst().prefix(3).joined(separator: " ")
            return "\(toolName) \(subcommand)"
        }

        return toolName
    }

    /// Resolve what a node/bun/npx process is actually running from its args.
    /// Returns a human-readable label like "TypeScript Server" or "webpack".
    public static func resolveRuntimeTool(args: [String]) -> String? {
        guard args.count > 1 else { return nil }

        // Check the script argument (usually args[1] for the script path)
        for arg in args.dropFirst() {
            if arg.hasPrefix("-") { continue }  // Skip flags

            let lower = arg.lowercased()
            if lower.contains("tsserver") || lower.contains("typescript/lib/ts") { return "TypeScript Server" }
            if lower.contains("vtsls") || lower.contains("language-server") { return "Language Server" }
            if lower.contains("webpack") { return "Webpack" }
            if lower.contains("next") && lower.contains("server") { return "Next.js" }
            if lower.contains("vite") { return "Vite" }
            if lower.contains("eslint") { return "ESLint" }
            if lower.contains("prettier") { return "Prettier" }
            if lower.contains("jest") { return "Jest" }
            if lower.contains("tailwindcss") || lower.contains("tailwind") { return "Tailwind CSS" }
            if lower.contains("copilot") { return "Copilot" }
            if lower.contains("playwright") { return "Playwright" }
            if lower.contains("mcp") { return "MCP Server" }
            if lower.contains("jupyter") { return "Jupyter" }

            // Return the script filename if nothing else matches
            let scriptName = executableName(from: arg)
            if !scriptName.isEmpty && scriptName != "node" && scriptName != "npx" && !scriptName.hasPrefix("-") {
                return scriptName
            }
        }

        return nil
    }
}
