import TotalRecallCore
import SwiftUI

/// Detail panel shown when a group is selected. Displays memory breakdown and process info.
struct DetailPanelView: View {
    let group: ProcessGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let icon = group.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                        }
                        Text(group.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(classifierDescription)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    if let explanation = group.explanation, explanation != classifierDescription {
                        Text(explanation)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                // Memory breakdown
                let allProcs = collectAllProcesses(from: group)
                let rawFootprint = allProcs.reduce(0 as UInt64) { $0 + $1.physFootprint }
                let totalResident = allProcs.reduce(0 as UInt64) { $0 + $1.residentSize }
                let totalNonResident = rawFootprint > totalResident ? rawFootprint - totalResident : 0
                let sharedDeduction = rawFootprint > group.deduplicatedFootprint
                    ? rawFootprint - group.deduplicatedFootprint : 0

                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Processes", "\(group.processCount)")

                    // Memory bar for the whole group
                    HStack {
                        MemoryBarView(resident: totalResident, nonResident: totalNonResident)
                        Spacer()
                    }

                    Divider().foregroundStyle(Theme.textMuted)

                    // Raw breakdown — these numbers add up
                    detailRow("In RAM", MemoryFormatter.format(bytes: totalResident))
                    detailRow("Compressed / swapped", "~\(MemoryFormatter.format(bytes: totalNonResident))")

                    HStack(spacing: 0) {
                        Text("Sum: \(MemoryFormatter.format(bytes: rawFootprint))")
                            .font(Theme.processFont)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }

                    // Shared memory deduction (if applicable)
                    if sharedDeduction > 0 {
                        Divider().foregroundStyle(Theme.textMuted)
                        detailRow("Shared memory", "-\(MemoryFormatter.format(bytes: sharedDeduction))")
                        Text("Memory shared between processes in this group (counted once, not per-process).")
                            .font(Theme.explanationFont)
                            .foregroundStyle(Theme.textMuted)

                        Divider().foregroundStyle(Theme.textMuted)
                        HStack(spacing: 0) {
                            Text("Adjusted total")
                                .font(Theme.processFont.bold())
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(MemoryFormatter.format(bytes: group.deduplicatedFootprint))
                                .font(Theme.processNumberFont.bold())
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }

                    // Explain what's happening
                    if totalNonResident > totalResident {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Theme.swapWarn)
                            Text("Most of this app's memory is compressed or swapped to disk — it's been idle and macOS reclaimed its RAM for other apps. This memory isn't actively using your RAM.")
                                .font(Theme.explanationFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                // Sub-groups
                if let subGroups = group.subGroups, !subGroups.isEmpty {
                    Divider().foregroundStyle(Theme.textMuted)
                    Text("sub-groups")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textMuted)

                    ForEach(subGroups) { sub in
                        HStack {
                            Text(sub.name)
                                .font(Theme.processFont)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(MemoryFormatter.format(bytes: sub.deduplicatedFootprint))
                                .font(Theme.processNumberFont)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }

                // Process types
                Divider().foregroundStyle(Theme.textMuted)
                Text("processes")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)

                let typeCounts = processTypeCounts()
                ForEach(Array(typeCounts.sorted(by: { $0.value > $1.value })), id: \.key) { type, count in
                    HStack {
                        Text("\(count) \(type)")
                            .font(Theme.processFont)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                }
            }
            .padding()
        }
        .frame(width: 280)
        .background(Theme.bgVoid)
    }

    private var classifierDescription: String {
        switch group.classifierName {
        case "Chrome": return "Browser (Chrome-based)"
        case "Electron": return "Desktop app (Electron)"
        case "System": return "macOS system services"
        case "Claude Code": return "Claude Code CLI session"
        case "Generic": return "Application"
        default: return group.classifierName
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.processFont)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.processNumberFont)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func processTypeCounts() -> [String: Int] {
        let allProcs = collectAllProcesses(from: group)
        var counts: [String: Int] = [:]
        for process in allProcs {
            let type: String
            if let electronType = CommandLineParser.electronProcessType(from: process.commandLineArgs) {
                type = electronType.rawValue
            } else if group.classifierName == "System" {
                type = SystemServicesClassifier.displayName(for: process.name) ?? process.name
            } else if CommandLineParser.isVersionString(process.name),
                      let resolved = CommandLineParser.resolveVoltaShim(
                        processName: process.name, path: process.path, args: process.commandLineArgs) {
                type = resolved
            } else if let tool = CommandLineParser.resolveRuntimeTool(args: process.commandLineArgs) {
                type = tool
            } else {
                type = process.name
            }
            counts[type, default: 0] += 1
        }
        return counts
    }

    private func collectAllProcesses(from group: ProcessGroup) -> [ProcessSnapshot] {
        var all = group.processes
        if let subs = group.subGroups {
            for sub in subs {
                all.append(contentsOf: collectAllProcesses(from: sub))
            }
        }
        return all
    }
}
