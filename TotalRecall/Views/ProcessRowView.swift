import TotalRecallCore
import SwiftUI

/// An individual process within an expanded group.
struct ProcessRowView: View {
    let process: ProcessSnapshot
    let classifierName: String

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: String(process.pid))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, alignment: .trailing)

            Text(displayName)
                .font(Theme.processFont)
                .foregroundStyle(process.exitedAt != nil ? Theme.textMuted : Theme.textSecondary)
                .italic(process.exitedAt != nil)
                .lineLimit(1)

            if process.exitedAt != nil {
                Text("(exited)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }

            if let explanation = explanation {
                Text("— \(explanation)")
                    .font(Theme.explanationFont)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            MemoryBarView(process: process)

            Text(MemoryFormatter.format(bytes: process.physFootprint))
                .font(Theme.processNumberFont)
                .foregroundStyle(process.exitedAt != nil ? Theme.textMuted : Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: Theme.memoryColumnWidth, alignment: .trailing)
        }
        .padding(.leading, Theme.processRowIndent)
        .opacity(process.exitedAt != nil ? 0.4 : 1.0)
    }

    private var displayName: String {
        if classifierName == "System" {
            return SystemServicesClassifier.displayName(for: process.name) ?? process.name
        }
        if let type = CommandLineParser.electronProcessType(from: process.commandLineArgs) {
            return type.rawValue
        }
        // For volta-shimmed runtimes, resolve to real tool name
        if CommandLineParser.isVersionString(process.name) {
            if let resolved = CommandLineParser.resolveVoltaShim(
                processName: process.name, path: process.path, args: process.commandLineArgs) {
                return resolved
            }
        }
        // volta-shim / mise shim: the process name is "volta-shim" but args[0] is the real command
        if process.name == "volta-shim" || CommandLineParser.isShimProcess(process.name, path: process.path) {
            return CommandLineParser.resolveShimDisplayName(args: process.commandLineArgs) ?? process.name
        }
        // For node/python/npx, try to identify what they're running
        let execName = CommandLineParser.executableName(from: process.path)
        if ["node", "npx", "python3", "python", "bun"].contains(execName) || execName == process.name {
            if let tool = CommandLineParser.resolveRuntimeTool(args: process.commandLineArgs) {
                return "\(execName) (\(tool))"
            }
        }
        return process.name
    }

    private var explanation: String? {
        if classifierName == "System" {
            return SystemServicesClassifier.explanation(for: process.name)
        }
        // Show working directory for CLI processes as context
        if let cwd = process.workingDirectory, cwd != "/", classifierName == "Claude Code" {
            let dirName = (cwd as NSString).lastPathComponent
            return "in \(dirName)"
        }
        return nil
    }
}
