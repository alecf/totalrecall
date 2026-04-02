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
                    if let explanation = group.explanation {
                        Text(explanation)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                // Hero number card
                VStack(spacing: 4) {
                    Text(MemoryFormatter.format(bytes: group.deduplicatedFootprint))
                        .font(Theme.numberFontHero)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("total footprint")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.bgSurface, in: RoundedRectangle(cornerRadius: 12))

                // Memory breakdown
                VStack(alignment: .leading, spacing: 6) {
                    detailRow("Processes", "\(group.processCount)")

                    Divider().foregroundStyle(Theme.textMuted)
                    Text("memory breakdown")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textMuted)

                    let allProcs = collectAllProcesses(from: group)
                    let totalResident = allProcs.reduce(0 as UInt64) { $0 + $1.residentSize }
                    let totalNonResident = group.nonResidentMemory

                    detailRow("In RAM (resident)", MemoryFormatter.format(bytes: totalResident))
                    detailRow("Compressed + swapped", "~\(MemoryFormatter.format(bytes: totalNonResident))")

                    // Explain the relationship
                    if totalNonResident > totalResident {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Theme.swapWarn)
                            Text("Most of this app's memory is compressed or swapped to disk. This suggests it has been idle and macOS reclaimed its RAM for other apps.")
                                .font(Theme.explanationFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else if totalNonResident > 0 {
                        Text("Non-resident memory is compressed in RAM or written to swap. The footprint counts both.")
                            .font(Theme.explanationFont)
                            .foregroundStyle(Theme.textMuted)
                    }

                    if group.processCount > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                            Text("Group total adjusted for shared memory. Individual processes may sum to more.")
                                .font(Theme.explanationFont)
                                .foregroundStyle(Theme.textMuted)
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
