import TotalRecallCore
import SwiftUI

/// Detail panel shown when a group is selected. Displays memory breakdown and process info.
struct DetailPanelView: View {
    let group: ProcessGroup

    @State private var selectedTab: PanelTab = .overview

    private enum PanelTab: String, CaseIterable {
        case overview = "Overview"
        case regions  = "Regions"
    }

    /// The single PID to inspect in the Regions tab.
    /// Only set when the group contains exactly one unique process.
    private var singlePID: pid_t? {
        let procs = group.uniqueProcesses
        return procs.count == 1 ? procs.first?.pid : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if singlePID != nil {
                Picker("", selection: $selectedTab) {
                    ForEach(PanelTab.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if selectedTab == .regions, let pid = singlePID {
                        VMRegionsView(pid: pid)
                    } else {
                        overviewContent
                    }
                }
                .padding()
            }
        }
        .frame(width: 280)
        .background(Theme.bgVoid)
        .onChange(of: group.id) {
            selectedTab = .overview
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        // Header
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let icon = group.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                }
                GroupNameText(
                    group: group,
                    baseFont: .system(size: 16, weight: .semibold),
                    contextFont: .system(size: 13)
                )
            }
            Text(classifierDescriptionWithPID)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
            if let explanation = group.explanation, explanation != classifierDescription {
                Text(explanation)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }

        // Memory breakdown
        let rawFootprint = group.totalFootprint
        let totalResident = group.residentMemory
        let totalNonResident = group.rawNonResidentMemory
        let sharedDeduction = rawFootprint > group.deduplicatedFootprint
            ? rawFootprint - group.deduplicatedFootprint : 0
        let residentPct = rawFootprint > 0
            ? Int(Double(totalResident) * 100 / Double(rawFootprint)) : 100

        VStack(alignment: .leading, spacing: 8) {
            detailRow("Processes", "\(group.processCount)")

            // Memory bar for the whole group
            HStack {
                MemoryBarView(resident: totalResident, nonResident: totalNonResident)
                Spacer()
            }

            Divider().foregroundStyle(Theme.textMuted)
            Text("what we know per-process")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textMuted)

            // Per-process metrics — these are what the OS tells us. Each row
            // carries the swatch of the tone it names, so the composition bar
            // directly above it needs no separate legend: the blue and amber
            // in the bar are the blue and amber against these two numbers.
            detailRow(
                Theme.residentLabel,
                "\(MemoryFormatter.format(bytes: totalResident)) (\(residentPct)%)",
                swatch: Theme.memoryResident
            )
            detailRow(
                Theme.nonResidentLabelLong,
                "~\(MemoryFormatter.format(bytes: totalNonResident)) (\(100 - residentPct)%)",
                swatch: Theme.memoryCompressed
            )

            Text("macOS reports each process's total footprint and how much is currently resident in RAM. The rest is compressed in-place or written to swap — we can't distinguish which without privileged access.")
                .font(Theme.explanationFont)
                .foregroundStyle(Theme.textMuted)

            // Shared memory (if applicable)
            if sharedDeduction > 0 {
                Divider().foregroundStyle(Theme.textMuted)
                Text("shared memory")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)

                detailRow("Shared between processes", "~\(MemoryFormatter.format(bytes: sharedDeduction))")
                Text("Multiple processes in this group share code and frameworks. The group total (\(MemoryFormatter.format(bytes: group.deduplicatedFootprint))) counts shared pages once instead of per-process. We can't determine whether shared pages are in RAM or compressed.")
                    .font(Theme.explanationFont)
                    .foregroundStyle(Theme.textMuted)
            }

            // Status message
            if totalNonResident > totalResident {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.swapWarn)
                    Text("Most of this app's memory has been reclaimed by macOS — it's compressed or on disk. It's not actively consuming your RAM, but returning to it may feel slow due to decompression or swap I/O.")
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

    /// Classifier description with the main PID appended if the group has a single root process.
    private var classifierDescriptionWithPID: String {
        let allProcs = group.uniqueProcesses
        let pids = Set(allProcs.map(\.pid))
        // A root process is one whose parent is not in this group
        let roots = allProcs.filter { !pids.contains($0.parentPid) }
        if let mainPID = roots.count == 1 ? roots.first?.pid : nil {
            return "\(classifierDescription) (PID \(mainPID))"
        }
        return classifierDescription
    }

    /// A label/value pair. Passing `swatch` prefixes it with a memory-tone chip
    /// and tints the label to match, turning the row into its own key.
    private func detailRow(_ label: String, _ value: String, swatch: Color? = nil) -> some View {
        HStack {
            if let swatch {
                MemorySwatch(color: swatch)
            }
            Text(label)
                .font(Theme.processFont)
                .foregroundStyle(swatch ?? Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.processNumberFont)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func processTypeCounts() -> [String: Int] {
        let allProcs = group.uniqueProcesses
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
}
