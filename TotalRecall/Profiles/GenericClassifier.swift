import AppKit

/// Catch-all classifier: groups remaining processes by responsible PID and bundle ID.
/// Always runs last in the registry.
public struct GenericClassifier: ProcessClassifier {
    public let name = "Generic"

    public func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        guard !processes.isEmpty else { return .empty }

        // Group by .app bundle path (most reliable), then bundle ID, then parent PID, then exec name
        var groups: [String: [ProcessSnapshot]] = [:]

        for process in processes {
            let key = groupingKey(for: process, allProcesses: processes)
            groups[key, default: []].append(process)
        }

        let claimedPIDs = Set(processes.map(\.pid))

        let processGroups = groups.map { (key, procs) -> ProcessGroup in
            let groupName = deriveGroupName(key: key, processes: procs)
            let icon = deriveIcon(processes: procs)
            let stableId = "generic:\(key)"

            return ProcessGroup(
                stableIdentifier: stableId,
                name: groupName,
                icon: icon,
                classifierName: name,
                explanation: nil,
                processes: procs,
                subGroups: nil,
                deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: procs),
                nonResidentMemory: procs.reduce(0) { $0 + $1.nonResidentMemory }
            )
        }.sorted { $0.deduplicatedFootprint > $1.deduplicatedFootprint }

        return ClassificationResult(groups: processGroups, claimedPIDs: claimedPIDs)
    }

    /// Determine the grouping key for a process.
    /// Priority: .app bundle path > bundle ID > parent PID tree > executable name
    private func groupingKey(for process: ProcessSnapshot, allProcesses: [ProcessSnapshot]) -> String {
        // 1. Group by .app bundle path (catches Firefox, Slack helpers, etc.)
        if let appPath = extractAppBundlePath(from: process.path) {
            return "app:\(appPath)"
        }

        // 2. Group by bundle ID
        if let bundleId = process.bundleIdentifier {
            return "bundle:\(bundleId)"
        }

        // 3. Walk up the parent chain to find a parent with a known .app path
        if let parentKey = findParentAppKey(for: process, allProcesses: allProcesses) {
            return parentKey
        }

        // 4. Walk up the parent chain to find a known CLI tool (claude, docker, etc.)
        if let cliKey = findParentCLIKey(for: process, allProcesses: allProcesses) {
            return cliKey
        }

        // 5. For shell/utility processes, try harder to find ANY parent grouping
        let execName = CommandLineParser.executableName(from: process.path)
        let baseName = execName.isEmpty ? process.name : execName
        if Self.shellProcesses.contains(baseName) {
            if let parentKey = findAnyParentKey(for: process, allProcesses: allProcesses) {
                return parentKey
            }
        }

        // 6. Fall back to executable name
        return "exec:\(baseName)"
    }

    /// Extract the .app bundle path: "/Applications/Firefox.app/Contents/..." → "/Applications/Firefox.app"
    private func extractAppBundlePath(from path: String) -> String? {
        if let range = path.range(of: ".app/") {
            return String(path[path.startIndex..<range.lowerBound]) + ".app"
        }
        if path.hasSuffix(".app") {
            return path
        }
        return nil
    }

    /// Walk up the parent PID chain to find a process that belongs to a .app bundle.
    private func findParentAppKey(for process: ProcessSnapshot, allProcesses: [ProcessSnapshot]) -> String? {
        let byPID = Dictionary(allProcesses.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var current = process
        var visited: Set<Int32> = [process.pid]

        for _ in 0..<10 {  // max depth to prevent cycles
            guard current.parentPid > 1, !visited.contains(current.parentPid) else { break }
            visited.insert(current.parentPid)

            guard let parent = byPID[current.parentPid] else { break }
            if let appPath = extractAppBundlePath(from: parent.path) {
                return "app:\(appPath)"
            }
            current = parent
        }
        return nil
    }

    /// Known CLI tools whose children should be grouped with them.
    private static let knownCLITools: [String: String] = [
        "claude": "Claude Code",
        "docker": "Docker",
        "podman": "Podman",
    ]

    /// Processes that are shell/utility processes which should try to group with their parent app.
    private static let shellProcesses: Set<String> = [
        "bash", "sh", "zsh", "fish", "dash",
        "less", "more", "cat", "grep", "sed", "awk",
        "git", "volta-shim", "npx", "caffeinate",
    ]

    /// Walk up the parent PID chain to find a known CLI tool.
    private func findParentCLIKey(for process: ProcessSnapshot, allProcesses: [ProcessSnapshot]) -> String? {
        let byPID = Dictionary(allProcesses.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        // Check self first
        let selfExec = CommandLineParser.executableName(from: process.path)
        if Self.knownCLITools[selfExec] != nil {
            return "cli:\(selfExec):\(process.pid)"
        }

        // Walk up
        var current = process
        var visited: Set<Int32> = [process.pid]

        for _ in 0..<10 {
            guard current.parentPid > 1, !visited.contains(current.parentPid) else { break }
            visited.insert(current.parentPid)

            guard let parent = byPID[current.parentPid] else { break }
            let execName = CommandLineParser.executableName(from: parent.path)
            if Self.knownCLITools[execName] != nil {
                return "cli:\(execName):\(parent.pid)"
            }
            current = parent
        }
        return nil
    }

    /// Walk up the parent PID chain to find any non-shell parent's grouping key.
    /// Used for shell processes (bash, sh, less, git, etc.) to group them with their parent app.
    private func findAnyParentKey(for process: ProcessSnapshot, allProcesses: [ProcessSnapshot]) -> String? {
        let byPID = Dictionary(allProcesses.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var current = process
        var visited: Set<Int32> = [process.pid]

        for _ in 0..<10 {
            guard current.parentPid > 1, !visited.contains(current.parentPid) else { break }
            visited.insert(current.parentPid)

            guard let parent = byPID[current.parentPid] else { break }

            // If parent has a .app path, group with it
            if let appPath = extractAppBundlePath(from: parent.path) {
                return "app:\(appPath)"
            }

            // If parent is a known CLI tool, group with it
            let parentExec = CommandLineParser.executableName(from: parent.path)
            if Self.knownCLITools[parentExec] != nil {
                return "cli:\(parentExec):\(parent.pid)"
            }

            // If parent is NOT a shell itself, use the parent's exec name as the group
            if !Self.shellProcesses.contains(parentExec) && !parentExec.isEmpty {
                return "exec:\(parentExec)"
            }

            current = parent
        }
        return nil
    }

    private func deriveGroupName(key: String, processes: [ProcessSnapshot]) -> String {
        if key.hasPrefix("cli:") {
            // "cli:claude:12345" → "Claude Code"
            let parts = key.components(separatedBy: ":")
            if parts.count >= 2, let displayName = Self.knownCLITools[parts[1]] {
                return displayName
            }
            return parts.count >= 2 ? parts[1] : key
        }

        if key.hasPrefix("app:") {
            let appPath = String(key.dropFirst("app:".count))
            return CommandLineParser.appNameFromPath(appPath) ?? (appPath as NSString).lastPathComponent
        }

        if key.hasPrefix("bundle:") {
            if let appName = processes.first.flatMap({ CommandLineParser.appNameFromPath($0.path) }) {
                return appName
            }
            let bundleId = String(key.dropFirst("bundle:".count))
            return bundleId.components(separatedBy: ".").last ?? bundleId
        }

        if key.hasPrefix("exec:") {
            let execName = String(key.dropFirst("exec:".count))
            // Resolve runtime processes to more descriptive names
            return resolveRuntimeName(execName: execName, processes: processes)
        }

        return processes.first?.name ?? "Unknown"
    }

    /// For node/python/ruby processes, try to identify what they're actually running.
    private func resolveRuntimeName(execName: String, processes: [ProcessSnapshot]) -> String {
        guard ["node", "python3", "python", "ruby"].contains(execName) else {
            return execName
        }

        // Look at the first arg after the executable to identify the tool
        if let process = processes.first, process.commandLineArgs.count > 1 {
            let scriptArg = process.commandLineArgs[1]
            return identifyToolFromArg(execName: execName, arg: scriptArg)
        }

        return execName
    }

    /// Identify a tool from the script argument passed to a runtime (node, python, etc.)
    private func identifyToolFromArg(execName: String, arg: String) -> String {
        let lower = arg.lowercased()

        // Known tools by script path patterns
        if lower.contains("tsserver") || lower.contains("typescript/lib/ts") { return "\(execName) (TypeScript Server)" }
        if lower.contains("vtsls") || lower.contains("language-server") { return "\(execName) (Language Server)" }
        if lower.contains("webpack") { return "\(execName) (Webpack)" }
        if lower.contains("next") { return "\(execName) (Next.js)" }
        if lower.contains("vite") { return "\(execName) (Vite)" }
        if lower.contains("eslint") { return "\(execName) (ESLint)" }
        if lower.contains("prettier") { return "\(execName) (Prettier)" }
        if lower.contains("jest") { return "\(execName) (Jest)" }
        if lower.contains("tailwindcss") || lower.contains("tailwind") { return "\(execName) (Tailwind CSS)" }
        if lower.contains("copilot") { return "\(execName) (Copilot)" }
        if lower.contains("playwright") { return "\(execName) (Playwright)" }
        if lower.contains("mcp") { return "\(execName) (MCP Server)" }
        if lower.contains("jupyter") { return "\(execName) (Jupyter)" }
        if lower.contains("django") { return "\(execName) (Django)" }
        if lower.contains("flask") { return "\(execName) (Flask)" }
        if lower.contains("rails") { return "\(execName) (Rails)" }
        if lower.contains("npx") { return "\(execName) (npx)" }

        // Fall back to the script filename
        let scriptName = (arg as NSString).lastPathComponent
        if !scriptName.isEmpty && scriptName != execName {
            return "\(execName) (\(scriptName))"
        }

        return execName
    }

    private func deriveIcon(processes: [ProcessSnapshot]) -> NSImage? {
        // Prefer the process with a bundle ID (main app process)
        let withBundleId = processes.filter { $0.bundleIdentifier != nil }
        for process in withBundleId {
            if let bundleId = process.bundleIdentifier,
               let icon = SystemProbe.iconFromBundleID(bundleId) {
                return icon
            }
        }
        // Sort by PID ascending — main process usually has the lowest PID in a group
        let sorted = processes.sorted { $0.pid < $1.pid }
        for process in sorted {
            if !process.path.isEmpty, let icon = SystemProbe.iconFromPath(process.path) {
                return icon
            }
        }
        return nil
    }
}
