import Foundation

/// Resolves a selection ID from the group list's outline tree back to the
/// `ProcessGroup` it refers to.
///
/// Resolution always lands on the *most specific* group the row belongs to, so
/// selecting one instance of a merged multi-instance app (Claude Code #6) shows
/// that instance rather than the whole app.
///
/// The tree (built by `TreeBuilder`) uses three ID shapes:
/// - A group's own `stableIdentifier` — direct match.
/// - `"pid:<pid>"` — a process row; resolves to the sub-group owning that PID,
///   or the top-level group when no sub-group does.
/// - `"sub:<groupID>\u{0}<subGroupID>"` — a sub-group row; resolves to that
///   sub-group.
///
/// Sub-group IDs are joined with a NUL separator (rather than `:`) because
/// `stableIdentifier`s themselves may contain colons (e.g. Chrome's
/// "chrome:Default"), which would make a `:`-delimited ID ambiguous to
/// split back apart.
public enum GroupSelection {
    private static let subGroupSeparator: Character = "\u{0}"

    /// Build the selection ID for a sub-group row, given its parent group's ID.
    public static func subGroupSelectionID(groupID: String, subGroupID: String) -> String {
        "sub:\(groupID)\(subGroupSeparator)\(subGroupID)"
    }

    /// Resolve a selection ID to the `ProcessGroup` it refers to, or `nil` if
    /// nothing in `groups` matches.
    public static func resolve(selectedID: String, in groups: [ProcessGroup]) -> ProcessGroup? {
        if let group = groups.first(where: { $0.id == selectedID }) {
            return group
        }

        if selectedID.hasPrefix("pid:"), let pid = Int32(selectedID.dropFirst("pid:".count)) {
            return groups.lazy.compactMap { owner(of: pid, in: $0) }.first
        }

        if selectedID.hasPrefix("sub:") {
            let remainder = selectedID.dropFirst("sub:".count)
            let parts = remainder.split(separator: subGroupSeparator, maxSplits: 1)
            guard let groupID = parts.first,
                  let parent = groups.first(where: { $0.id == String(groupID) }) else { return nil }
            guard parts.count == 2 else { return parent }
            let subGroupID = String(parts[1])
            return parent.subGroups?.first(where: { $0.id == subGroupID }) ?? parent
        }

        return nil
    }

    /// The most specific group holding `pid`: the sub-group that owns it when
    /// there is one, otherwise the group itself.
    private static func owner(of pid: Int32, in group: ProcessGroup) -> ProcessGroup? {
        if let sub = group.subGroups?.first(where: { $0.processes.contains(where: { $0.pid == pid }) }) {
            return sub
        }
        return group.processes.contains(where: { $0.pid == pid }) ? group : nil
    }
}
