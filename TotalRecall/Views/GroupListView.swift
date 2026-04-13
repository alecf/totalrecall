import TotalRecallCore
import SwiftUI

// MARK: - Tree Node

/// A single node in the outline tree. Can represent a group (top-level) or a process (leaf/branch).
struct TreeNode: Identifiable {
    let id: String
    let kind: Kind
    var children: [TreeNode]?

    enum Kind {
        case group(ProcessGroup)
        case subGroup(ProcessGroup)
        case process(ProcessSnapshot, classifierName: String)
    }
}

// MARK: - Tree Builder

/// Builds a flat or hierarchical tree of TreeNodes from ProcessGroups.
enum TreeBuilder {
    static func build(
        groups: [ProcessGroup],
        sortByResident: Bool,
        showTreeView: Bool
    ) -> [TreeNode] {
        groups.map { group in
            TreeNode(
                id: group.id,
                kind: .group(group),
                children: groupChildren(group, sortByResident: sortByResident, showTreeView: showTreeView)
            )
        }
    }

    private static func groupChildren(
        _ group: ProcessGroup,
        sortByResident: Bool,
        showTreeView: Bool
    ) -> [TreeNode]? {
        var nodes: [TreeNode] = []

        // Sub-groups first (e.g. Chrome profiles)
        if let subGroups = group.subGroups {
            for sub in subGroups {
                let subChildren = processNodes(
                    sub.processes, classifierName: group.classifierName,
                    sortByResident: sortByResident, showTreeView: false
                )
                nodes.append(TreeNode(
                    id: "sub:\(group.id):\(sub.id)",
                    kind: .subGroup(sub),
                    children: subChildren.isEmpty ? nil : subChildren
                ))
            }
        }

        // Direct processes — flat (sorted by size) or tree (parent-child)
        if showTreeView {
            nodes.append(contentsOf: treeProcessNodes(
                group.processes, classifierName: group.classifierName, sortByResident: sortByResident
            ))
        } else {
            nodes.append(contentsOf: processNodes(
                group.processes, classifierName: group.classifierName,
                sortByResident: sortByResident, showTreeView: false
            ))
        }

        // Single-process groups with no subgroups: no disclosure triangle needed.
        // Check processCount (not nodes.count) because tree view may nest 200 processes under 1 root.
        if group.processCount <= 1 && group.subGroups == nil {
            return nil
        }
        return nodes
    }

    /// Flat list of process nodes, sorted by memory.
    private static func processNodes(
        _ processes: [ProcessSnapshot],
        classifierName: String,
        sortByResident: Bool,
        showTreeView: Bool
    ) -> [TreeNode] {
        let sorted = processes.sorted {
            sortByResident ? $0.residentSize > $1.residentSize : $0.physFootprint > $1.physFootprint
        }
        return sorted.prefix(50).map { proc in
            TreeNode(
                id: "pid:\(proc.pid)",
                kind: .process(proc, classifierName: classifierName),
                children: nil
            )
        }
    }

    /// Hierarchical process nodes — root processes at the top, children nested.
    private static func treeProcessNodes(
        _ processes: [ProcessSnapshot],
        classifierName: String,
        sortByResident: Bool
    ) -> [TreeNode] {
        let pids = Set(processes.map(\.pid))
        let childrenByParent = Dictionary(grouping: processes, by: \.parentPid)

        // Roots: processes whose parent is not in this group
        let roots = processes.filter { !pids.contains($0.parentPid) }
            .sorted { sortByResident ? $0.residentSize > $1.residentSize : $0.physFootprint > $1.physFootprint }

        var renderedPIDs = Set<Int32>()

        func buildNode(_ proc: ProcessSnapshot) -> TreeNode {
            renderedPIDs.insert(proc.pid)
            let kids = (childrenByParent[proc.pid] ?? [])
                .sorted { sortByResident ? $0.residentSize > $1.residentSize : $0.physFootprint > $1.physFootprint }
                .map { buildNode($0) }
            return TreeNode(
                id: "pid:\(proc.pid)",
                kind: .process(proc, classifierName: classifierName),
                children: kids.isEmpty ? nil : kids
            )
        }

        var result = roots.map { buildNode($0) }

        // Orphans (cycle safety net)
        let orphans = processes.filter { !renderedPIDs.contains($0.pid) }
        result.append(contentsOf: orphans.map { proc in
            TreeNode(
                id: "pid:\(proc.pid)",
                kind: .process(proc, classifierName: classifierName),
                children: nil
            )
        })

        return result
    }
}

// MARK: - Group List View

/// The main scrollable outline tree of groups and their processes.
struct GroupListView: View {
    let groups: [ProcessGroup]
    let sortByResident: Bool
    let showTreeView: Bool
    @Binding var selectedGroupID: String?
    @Binding var hoveredGroupID: String?

    var body: some View {
        let tree = TreeBuilder.build(
            groups: groups,
            sortByResident: sortByResident,
            showTreeView: showTreeView
        )

        List(tree, children: \.children, selection: $selectedGroupID) { node in
            nodeView(node)
                .tag(node.id)
                .contextMenu { contextMenu(for: node) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private func nodeView(_ node: TreeNode) -> some View {
        switch node.kind {
        case .group(let group):
            GroupRowView(group: group, isHovered: hoveredGroupID == group.id)
        case .subGroup(let sub):
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
        case .process(let process, let classifierName):
            ProcessRowView(process: process, classifierName: classifierName)
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func contextMenu(for node: TreeNode) -> some View {
        switch node.kind {
        case .group(let group):
            groupContextMenu(for: group)
        case .subGroup(let sub):
            groupContextMenu(for: sub)
        case .process(let process, _):
            processContextMenu(for: process)
        }
    }

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
