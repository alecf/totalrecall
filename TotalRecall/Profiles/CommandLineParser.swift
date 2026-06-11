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
        if path.contains("/mise/shims/") || path.contains("/.asdf/shims/") { return true }
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

        if let serverName = mcpServerName(from: args) {
            return "MCP Server: \(serverName)"
        }

        // Check script/package arguments by exact path components, not arbitrary substrings.
        for arg in args.dropFirst() {
            if arg.hasPrefix("-") { continue }  // Skip flags

            if let tool = runtimeToolName(from: arg) {
                return tool
            }

            if pathComponentNames(from: arg).contains("mcp") {
                if let serverName = mcpServerName(from: args) {
                    return "MCP Server: \(serverName)"
                }
                return "MCP Server"
            }

            // Return the script filename if nothing else matches
            let scriptName = executableName(from: arg)
            if !scriptName.isEmpty && scriptName != "node" && scriptName != "npx" && !scriptName.hasPrefix("-") {
                return scriptName
            }
        }

        return nil
    }

    private struct RuntimeToolSignal {
        let label: String
        let components: Set<String>
    }

    private static let runtimeToolSignals: [RuntimeToolSignal] = [
        RuntimeToolSignal(label: "TypeScript Server", components: ["tsserver"]),
        RuntimeToolSignal(label: "Language Server", components: ["vtsls", "language-server", "typescript-language-server"]),
        RuntimeToolSignal(label: "Webpack", components: ["webpack"]),
        RuntimeToolSignal(label: "Next.js", components: ["next", "next-server"]),
        RuntimeToolSignal(label: "Vite", components: ["vite"]),
        RuntimeToolSignal(label: "ESLint", components: ["eslint"]),
        RuntimeToolSignal(label: "Prettier", components: ["prettier"]),
        RuntimeToolSignal(label: "Jest", components: ["jest"]),
        RuntimeToolSignal(label: "Tailwind CSS", components: ["tailwindcss", "tailwind"]),
        RuntimeToolSignal(label: "Copilot", components: ["copilot"]),
        RuntimeToolSignal(label: "Playwright", components: ["playwright"]),
        RuntimeToolSignal(label: "Jupyter", components: ["jupyter"]),
    ]

    private static func runtimeToolName(from arg: String) -> String? {
        let components = pathComponentNames(from: arg)
        for signal in runtimeToolSignals {
            if !components.intersection(signal.components).isEmpty {
                return signal.label
            }
        }
        return nil
    }

    static func pathComponentNames(from arg: String) -> Set<String> {
        let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let rawComponents = trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)

        return Set(rawComponents.flatMap { raw -> [String] in
            let component = stripPackageVersion(raw).lowercased()
            guard !component.isEmpty else { return [] }

            var names = [component]
            let stem = (component as NSString).deletingPathExtension
            if !stem.isEmpty, stem != component {
                names.append(stem)
            }
            return names
        })
    }

    /// Extract a concrete MCP server name from runtime args.
    /// Examples:
    /// - `npx @modelcontextprotocol/server-filesystem` -> `Filesystem`
    /// - `node .../node_modules/@modelcontextprotocol/server-github/dist/index.js` -> `GitHub`
    /// - `npx @playwright/mcp` -> `Playwright`
    public static func mcpServerName(from args: [String]) -> String? {
        guard args.count > 1 else { return nil }

        for arg in args.dropFirst() {
            guard !arg.hasPrefix("-") else { continue }
            if let name = mcpServerName(fromArgument: arg) {
                return name
            }
        }

        return nil
    }

    private static func mcpServerName(fromArgument arg: String) -> String? {
        let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pathParts = trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)

        for (index, rawPart) in pathParts.enumerated() {
            let part = stripPackageVersion(rawPart)
            let lower = part.lowercased()
            let previous = index > 0 ? stripPackageVersion(pathParts[index - 1]).lowercased() : nil
            let next = index + 1 < pathParts.count ? stripPackageVersion(pathParts[index + 1]) : nil

            if lower == "@modelcontextprotocol", let next {
                let nextLower = next.lowercased()
                if nextLower.hasPrefix("server-") {
                    return humanizeMCPServerName(String(next.dropFirst("server-".count)))
                }
            }

            if lower.hasPrefix("@modelcontextprotocol/server-") {
                return humanizeMCPServerName(String(part.dropFirst("@modelcontextprotocol/server-".count)))
            }

            if lower.hasPrefix("mcp-server-") {
                return humanizeMCPServerName(String(part.dropFirst("mcp-server-".count)))
            }

            if lower.hasPrefix("server-"), previous == "@modelcontextprotocol" {
                return humanizeMCPServerName(String(part.dropFirst("server-".count)))
            }

            if lower == "mcp", let previous, previous.hasPrefix("@") {
                return humanizeMCPServerName(String(previous.dropFirst()))
            }

            if lower.hasPrefix("mcp-") {
                return humanizeMCPServerName(String(part.dropFirst("mcp-".count)))
            }
        }

        return nil
    }

    private static func stripPackageVersion(_ component: String) -> String {
        guard component.hasPrefix("@") else {
            return component.split(separator: "@", maxSplits: 1).first.map(String.init) ?? component
        }

        // Keep npm scopes (`@scope/package`) intact, but drop versions from
        // combined scoped specs such as `@scope/package@1.2.3`.
        guard let slash = component.firstIndex(of: "/") else { return component }
        let packageStart = component.index(after: slash)
        if let versionSeparator = component[packageStart...].firstIndex(of: "@") {
            return String(component[..<versionSeparator])
        }
        return component
    }

    private static func humanizeMCPServerName(_ raw: String) -> String? {
        let words = raw
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty && $0.lowercased() != "server" && $0.lowercased() != "mcp" }

        guard !words.isEmpty else { return nil }

        return words.map { word in
            let lower = word.lowercased()
            switch lower {
            case "github": return "GitHub"
            case "gitlab": return "GitLab"
            case "sentry": return "Sentry"
            case "filesystem": return "Filesystem"
            default:
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
        }.joined(separator: " ")
    }
}
