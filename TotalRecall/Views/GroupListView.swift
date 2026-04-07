import TotalRecallCore
import SwiftUI

/// The main scrollable list of smart groups with expandable disclosure sections.
struct GroupListView: View {
    let groups: [ProcessGroup]
    let sortByResident: Bool
    let showTreeView: Bool
    @Binding var selectedGroupID: String?
    @Binding var hoveredGroupID: String?
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        List(selection: $selectedGroupID) {
            ForEach(groups) { group in
                if group.processes.count <= 1 && group.subGroups == nil {
                    // Single-process group: no chevron, just the row
                    GroupRowView(group: group, isHovered: hoveredGroupID == group.id)
                        .tag(group.id)
                        .contextMenu { groupContextMenu(for: group) }
                } else {
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
                                    ForEach(Array(sub.processes.sorted(by: { processSortKey($0) > processSortKey($1) }).prefix(20))) { process in
                                        processRow(process, classifierName: group.classifierName)
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
                                        MemoryBarView(group: sub)
                                        Text(MemoryFormatter.format(bytes: sub.deduplicatedFootprint))
                                            .font(Theme.processNumberFont)
                                            .foregroundStyle(Theme.textPrimary)
                                            .monospacedDigit()
                                            .frame(width: Theme.memoryColumnWidth, alignment: .trailing)
                                    }
                                    .padding(.leading, 12)
                                }
                            }
                        }

                        // Direct child processes
                        if showTreeView {
                            treeProcessList(group.processes, classifierName: group.classifierName)
                        } else {
                            ForEach(Array(group.processes.sorted(by: { processSortKey($0) > processSortKey($1) }).prefix(20))) { process in
                                processRow(process, classifierName: group.classifierName)
                            }
                            if group.processes.count > 20 {
                                moreButton(count: group.processes.count - 20)
                            }
                        }
                    } label: {
                        GroupRowView(group: group, isHovered: hoveredGroupID == group.id)
                            .tag(group.id)
                            .contextMenu { groupContextMenu(for: group) }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    /// A process row with its own context menu, wrapped in a separate
    /// selectable item so right-click highlights just this row.
    @ViewBuilder
    private func processRow(_ process: ProcessSnapshot, classifierName: String) -> some View {
        ProcessRowView(process: process, classifierName: classifierName)
            .tag(process.pid)
            .contextMenu { processContextMenu(for: process) }
    }

    private func processSortKey(_ process: ProcessSnapshot) -> UInt64 {
        sortByResident ? process.residentSize : process.physFootprint
    }

    private func moreButton(count: Int) -> some View {
        Text("+ \(count) more processes")
            .font(Theme.explanationFont)
            .foregroundStyle(Theme.textMuted)
            .padding(.leading, Theme.processRowIndent)
    }

    // MARK: - Tree View

    /// Render processes as a parent-child tree. Root processes (whose parent isn't in
    /// this group) are shown at the top level, with children indented beneath them.
    @ViewBuilder
    private func treeProcessList(_ processes: [ProcessSnapshot], classifierName: String) -> some View {
        let pids = Set(processes.map(\.pid))
        let childrenByParent = Dictionary(grouping: processes, by: \.parentPid)

        // Roots: processes whose parent is not in this group
        let roots = processes.filter { !pids.contains($0.parentPid) }
            .sorted(by: { processSortKey($0) > processSortKey($1) })

        ForEach(roots) { root in
            processRow(root, classifierName: classifierName)
            treeChildren(of: root.pid, childrenByParent: childrenByParent, classifierName: classifierName, depth: 1)
        }

        // Orphans: processes in a cycle or whose root got cut off (safety net)
        let rendered = collectTreePIDs(roots: roots, childrenByParent: childrenByParent)
        let orphans = processes.filter { !rendered.contains($0.pid) }
        ForEach(orphans) { process in
            processRow(process, classifierName: classifierName)
        }
    }

    /// Recursively render children at increasing indent depth.
    /// Uses AnyView to break the recursive opaque return type.
    private func treeChildren(of parentPid: Int32, childrenByParent: [Int32: [ProcessSnapshot]], classifierName: String, depth: Int) -> AnyView {
        guard let children = childrenByParent[parentPid], depth < 8 else {
            return AnyView(EmptyView())
        }
        return AnyView(
            ForEach(children.sorted(by: { processSortKey($0) > processSortKey($1) })) { child in
                ProcessRowView(process: child, classifierName: classifierName)
                    .padding(.leading, CGFloat(depth) * 16)
                    .tag(child.pid)
                    .contextMenu { processContextMenu(for: child) }
                treeChildren(of: child.pid, childrenByParent: childrenByParent, classifierName: classifierName, depth: depth + 1)
            }
        )
    }

    /// Collect all PIDs reachable from roots via parent-child links.
    private func collectTreePIDs(roots: [ProcessSnapshot], childrenByParent: [Int32: [ProcessSnapshot]]) -> Set<Int32> {
        var result = Set<Int32>()
        var queue = roots.map(\.pid)
        while !queue.isEmpty {
            let pid = queue.removeFirst()
            result.insert(pid)
            if let children = childrenByParent[pid] {
                queue.append(contentsOf: children.map(\.pid))
            }
        }
        return result
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func processContextMenu(for process: ProcessSnapshot) -> some View {
        Button("Copy PID \(String(process.pid))") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(process.pid), forType: .string)
        }
        Divider()
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
