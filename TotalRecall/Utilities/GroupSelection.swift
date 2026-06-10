import Foundation

/// Resolves a selection ID from the group list's outline tree back to the
/// `ProcessGroup` it refers to.
///
/// The tree (built by `TreeBuilder`) uses three ID shapes:
/// - A group's own `stableIdentifier` — direct match.
/// - `"pid:<pid>"` — a process row; resolves to the group (or sub-group's
///   parent) containing that PID.
/// - `"sub:<groupID>\u{0}<subGroupID>"` — a sub-group row; resolves to the
///   parent group.
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

        if selectedID.hasPrefix("pid:"), let pidStr = selectedID.split(separator: ":").last,
           let pid = Int32(pidStr) {
            return groups.first { group in
                group.processes.contains(where: { $0.pid == pid }) ||
                (group.subGroups?.contains(where: { $0.processes.contains(where: { $0.pid == pid }) }) ?? false)
            }
        }

        if selectedID.hasPrefix("sub:") {
            let remainder = selectedID.dropFirst("sub:".count)
            if let groupID = remainder.split(separator: subGroupSeparator, maxSplits: 1).first {
                return groups.first(where: { $0.id == String(groupID) })
            }
        }

        return nil
    }
}
