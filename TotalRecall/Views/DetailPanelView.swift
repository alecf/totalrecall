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

                // Stats
                VStack(alignment: .leading, spacing: 6) {
                    detailRow("Processes", "\(group.processCount)")
                    detailRow("Non-resident", "~\(MemoryFormatter.format(bytes: group.nonResidentMemory))")

                    if group.processes.count > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                            Text("Adjusted for shared memory between processes")
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
        var counts: [String: Int] = [:]
        for process in group.processes {
            let type: String
            if let electronType = CommandLineParser.electronProcessType(from: process.commandLineArgs) {
                type = electronType.rawValue
            } else if group.classifierName == "System" {
                type = SystemServicesClassifier.displayName(for: process.name) ?? process.name
            } else {
                type = process.name
            }
            counts[type, default: 0] += 1
        }
        return counts
    }
}
