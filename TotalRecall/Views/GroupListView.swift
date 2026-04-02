import TotalRecallCore
import SwiftUI

/// The main scrollable list of smart groups with expandable disclosure sections.
struct GroupListView: View {
    let groups: [ProcessGroup]
    @Binding var selectedGroupID: String?
    @Binding var hoveredGroupID: String?
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        List(selection: $selectedGroupID) {
            ForEach(groups) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedGroups.contains(group.id) },
                        set: { expanded in
                            if expanded {
                                expandedGroups.insert(group.id)
                            } else {
                                expandedGroups.remove(group.id)
                            }
                        }
                    )
                ) {
                    // Sub-groups first (e.g., Chrome profiles)
                    if let subGroups = group.subGroups {
                        ForEach(subGroups) { sub in
                            DisclosureGroup {
                                ForEach(sub.processes.prefix(20)) { process in
                                    ProcessRowView(process: process, classifierName: group.classifierName)
                                        .contextMenu { processContextMenu(for: process) }
                                }
                                if sub.processes.count > 20 {
                                    moreButton(count: sub.processes.count - 20)
                                }
                            } label: {
                                HStack {
                                    Text(sub.name)
                                        .font(Theme.labelFont)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(MemoryFormatter.format(bytes: sub.deduplicatedFootprint))
                                        .font(Theme.processNumberFont)
                                        .foregroundStyle(Theme.textPrimary)
                                        .monospacedDigit()
                                }
                                .padding(.leading, 12)
                            }
                        }
                    }

                    // Direct child processes (un-subgrouped)
                    ForEach(group.processes.prefix(20)) { process in
                        ProcessRowView(process: process, classifierName: group.classifierName)
                            .contextMenu { processContextMenu(for: process) }
                    }
                    if group.processes.count > 20 {
                        moreButton(count: group.processes.count - 20)
                    }
                } label: {
                    GroupRowView(group: group, isHovered: hoveredGroupID == group.id)
                        .tag(group.id)
                        .contextMenu { groupContextMenu(for: group) }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func moreButton(count: Int) -> some View {
        Text("+ \(count) more processes")
            .font(Theme.explanationFont)
            .foregroundStyle(Theme.textMuted)
            .padding(.leading, Theme.processRowIndent)
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func processContextMenu(for process: ProcessSnapshot) -> some View {
        Button("Quit") {
            try? ProcessActions.sendSignal(SIGTERM, to: process.processIdentity)
        }
        Button("Force Quit") {
            try? ProcessActions.sendSignal(SIGKILL, to: process.processIdentity)
        }
    }

    @ViewBuilder
    private func groupContextMenu(for group: ProcessGroup) -> some View {
        if ProcessActions.isGroupKillable(group) {
            Button("Quit All (\(group.processCount) processes)") {
                _ = ProcessActions.sendSignalToAll(SIGTERM, in: group)
            }
            Button("Force Quit All") {
                _ = ProcessActions.sendSignalToAll(SIGKILL, in: group)
            }
        } else {
            Text("System processes cannot be bulk-killed")
        }
    }
}
