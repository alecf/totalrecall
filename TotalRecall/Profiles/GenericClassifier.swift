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
            let icon = deriveIcon(key: key, processes: procs)
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

        // 5. For Node.js ecosystem processes, find the framework tree root
        let execName = CommandLineParser.executableName(from: process.path)
        let baseName = execName.isEmpty ? process.name : execName
        if Self.nodeEcosystemProcesses.contains(baseName) || process.name == "next-server" {
            if let frameworkKey = findNodeFrameworkKey(for: process, allProcesses: allProcesses) {
                return frameworkKey
            }
        }

        // 6. Walk up the full parent chain (including OS-level intermediaries like `login`)
        //    looking for a terminal .app or CLI tool. This groups terminal-launched processes
        //    with their terminal. Processes reparented to launchd (pid 1) fall through.
        if let parentKey = findAnyParentKey(for: process, allProcesses: allProcesses) {
            return parentKey
        }

        // 7. Fall back to executable name
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
    /// Only walks through processes in our snapshot — does NOT query the OS for intermediaries.
    /// This prevents non-shell processes (e.g. Node.js apps) from being absorbed by their
    /// terminal app via intermediaries like `login`.
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

    /// Shell and session processes that form boundaries when walking Node.js process trees.
    /// Used by findNodeFrameworkKey to know when to stop walking up — these are the
    /// "ceiling" above which a Node.js framework tree doesn't extend.
    private static let shellBoundaryProcesses: Set<String> = [
        "bash", "sh", "zsh", "fish", "dash", "login",
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

    /// Walk up the full parent chain looking for a .app bundle or known CLI tool.
    /// Walks through ALL intermediary processes (shells, login, sudo, etc.) — does not
    /// stop at non-shell processes. Falls back to querying the OS for processes not in
    /// our snapshot (e.g. `login` between a terminal and its shells).
    ///
    /// Returns nil if the chain reaches launchd (pid 1) without finding an .app,
    /// which means the process is a daemon/background service.
    private func findAnyParentKey(for process: ProcessSnapshot, allProcesses: [ProcessSnapshot]) -> String? {
        let byPID = Dictionary(allProcesses.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var currentPid = process.parentPid
        var visited: Set<Int32> = [process.pid]

        for _ in 0..<15 {
            guard currentPid > 1, !visited.contains(currentPid) else { break }
            visited.insert(currentPid)

            // Try to find this PID in our snapshot first
            if let parent = byPID[currentPid] {
                if let appPath = extractAppBundlePath(from: parent.path) {
                    return "app:\(appPath)"
                }
                let parentExec = CommandLineParser.executableName(from: parent.path)
                if Self.knownCLITools[parentExec] != nil {
                    return "cli:\(parentExec):\(parent.pid)"
                }
                // Keep walking — don't stop at intermediate processes
                currentPid = parent.parentPid
                continue
            }

            // Parent not in snapshot — query the OS to keep walking
            if let path = SystemProbe.getProcessPath(pid: currentPid),
               let appPath = extractAppBundlePath(from: path) {
                return "app:\(appPath)"
            }
            // Get parent PID via getBSDInfo, falling back to sysctl for privileged processes
            if let bsdInfo = SystemProbe.getBSDInfo(pid: currentPid) {
                currentPid = bsdInfo.parentPid
            } else if let ppid = SystemProbe.getParentPid(pid: currentPid) {
                currentPid = ppid
            } else {
                break
            }
        }
        return nil
    }

    /// Processes that belong to the Node.js ecosystem and should be checked for framework signals.
    private static let nodeEcosystemProcesses: Set<String> = [
        "node", "npm", "npx", "volta-shim", "turbo", "tsx", "ts-node",
    ]

    /// Framework signals detected from process name or command-line args/path.
    /// Each entry: (pattern to match, display name).
    private static let nodeFrameworkSignals: [(pattern: String, name: String)] = [
        ("next-server", "Next.js"),
        ("/next", "Next.js"),
        ("/nest", "NestJS"),
    ]

    /// For a Node.js ecosystem process, walk the full tree (parents + descendants) to find
    /// a framework signal. Returns a key like "node-fw:Next.js:31876" keyed by the framework
    /// root PID so each instance stays separate.
    private func findNodeFrameworkKey(for process: ProcessSnapshot, allProcesses: [ProcessSnapshot]) -> String? {
        let byPID = Dictionary(allProcesses.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        // Collect the full ancestor chain (up to shell/init)
        var ancestors: [ProcessSnapshot] = []
        var current = process
        var visited: Set<Int32> = [process.pid]
        for _ in 0..<15 {
            guard current.parentPid > 1, !visited.contains(current.parentPid) else { break }
            visited.insert(current.parentPid)
            guard let parent = byPID[current.parentPid] else { break }
            let parentExec = CommandLineParser.executableName(from: parent.path)
            // Stop at shell boundaries — don't walk into the terminal
            if Self.shellBoundaryProcesses.contains(parentExec) { break }
            ancestors.append(parent)
            current = parent
        }

        // Collect all descendants via BFS
        var descendants: [ProcessSnapshot] = []
        let childrenByParent = Dictionary(grouping: allProcesses, by: \.parentPid)
        var queue = childrenByParent[process.pid] ?? []
        var visitedDesc: Set<Int32> = [process.pid]
        while !queue.isEmpty {
            let child = queue.removeFirst()
            guard !visitedDesc.contains(child.pid) else { continue }
            visitedDesc.insert(child.pid)
            descendants.append(child)
            queue.append(contentsOf: childrenByParent[child.pid] ?? [])
        }

        // Search all processes in the tree for a framework signal
        let treeProcesses = ancestors.reversed() + [process] + descendants
        for proc in treeProcesses {
            if let signal = detectFrameworkSignal(proc) {
                // The framework root is the signal-bearing process
                return "node-fw:\(signal.name):\(proc.pid)"
            }
        }

        return nil
    }

    /// Check a single process for a framework signal.
    private func detectFrameworkSignal(_ process: ProcessSnapshot) -> (name: String, pid: Int32)? {
        // Check process name first (e.g. "next-server")
        for signal in Self.nodeFrameworkSignals {
            if process.name == signal.pattern {
                return (signal.name, process.pid)
            }
        }

        // Check executable path and args for path-based patterns (e.g. ".bin/next", ".bin/nest")
        let argsToCheck = [process.path] + process.commandLineArgs
        for arg in argsToCheck {
            for signal in Self.nodeFrameworkSignals where signal.pattern.hasPrefix("/") {
                // Match against path components: look for the pattern as a path segment
                // e.g. "/next" matches ".bin/next" or "node_modules/.bin/next"
                if arg.contains("/.bin\(signal.pattern)") || arg.contains("/node_modules\(signal.pattern)") {
                    return (signal.name, process.pid)
                }
                // Also match "next-server" style process names embedded in args
                if signal.pattern == "/next" && arg.contains("next-server") {
                    return (signal.name, process.pid)
                }
            }
        }

        // Check for direct command patterns like "nest start"
        let joined = process.commandLineArgs.joined(separator: " ")
        if joined.contains("nest start") || joined.contains("nest build") {
            return ("NestJS", process.pid)
        }

        return nil
    }

    private func deriveGroupName(key: String, processes: [ProcessSnapshot]) -> String {
        if key.hasPrefix("node-fw:") {
            // "node-fw:Next.js:31876" → "Next.js"
            let parts = key.components(separatedBy: ":")
            return parts.count >= 2 ? parts[1] : key
        }

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

    private func deriveIcon(key: String, processes: [ProcessSnapshot]) -> NSImage? {
        // For app: groups, use the .app bundle path directly — this works even when
        // the main app process isn't in our snapshot (e.g. terminal groups where
        // only child shells are captured, but the terminal .app path is known)
        if key.hasPrefix("app:") {
            let appPath = String(key.dropFirst("app:".count))
            if let icon = SystemProbe.iconFromPath(appPath) {
                return icon
            }
        }

        // Try NSRunningApplication for each process
        for process in processes {
            if let app = NSRunningApplication(processIdentifier: process.pid), let icon = app.icon {
                return icon
            }
        }
        // Fallback: try bundle ID
        for process in processes {
            if let bundleId = process.bundleIdentifier,
               let icon = SystemProbe.iconFromBundleID(bundleId) {
                return icon
            }
        }
        // Last resort: .app bundle path from process paths
        let sorted = processes.sorted { $0.pid < $1.pid }
        for process in sorted {
            if !process.path.isEmpty, let icon = SystemProbe.iconFromPath(process.path) {
                return icon
            }
        }
        return nil
    }
}
