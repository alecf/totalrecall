import Testing
@testable import TotalRecallCore

@Suite("Group Selection Resolution")
struct GroupSelectionTests {
    // Mirrors the real shape from ChromeClassifier: the top-level group's
    // stableIdentifier ("chrome") itself contains no colon, but its
    // sub-group identifiers do ("chrome:Default", "chrome:Profile 1").
    private func chromeGroup() -> ProcessGroup {
        let process = FixtureBuilder.chromeRenderer()
        let defaultProfile = ProcessGroup(
            stableIdentifier: "chrome:Default",
            name: "Default Profile",
            icon: nil,
            classifierName: "Chrome",
            explanation: nil,
            processes: [process],
            subGroups: nil,
            deduplicatedFootprint: process.physFootprint,
            nonResidentMemory: process.nonResidentMemory
        )
        return ProcessGroup(
            stableIdentifier: "chrome",
            name: "Google Chrome",
            icon: nil,
            classifierName: "Chrome",
            explanation: nil,
            processes: [],
            subGroups: [defaultProfile],
            deduplicatedFootprint: process.physFootprint,
            nonResidentMemory: process.nonResidentMemory
        )
    }

    @Test("Direct group ID resolves to itself")
    func directGroupID() {
        let chrome = chromeGroup()
        let resolved = GroupSelection.resolve(selectedID: "chrome", in: [chrome])
        #expect(resolved?.id == "chrome")
    }

    @Test("pid: selection resolves to the owning group, including sub-groups")
    func pidSelectionResolvesOwningGroup() {
        let chrome = chromeGroup()
        let pid = chrome.subGroups![0].processes[0].pid
        let resolved = GroupSelection.resolve(selectedID: "pid:\(pid)", in: [chrome])
        #expect(resolved?.id == "chrome")
    }

    // Regression: the sub-group row's selection ID is built from the parent
    // group's ID *and* the sub-group's ID. When the parent ID itself
    // contains no colon but the sub-group ID does (the real Chrome shape),
    // naively splitting the whole selection ID on ":" must not produce a
    // mangled parent ID like "chrome:chrome".
    @Test("sub: selection resolves to the parent group, even when IDs contain colons")
    func subGroupSelectionResolvesParentGroup() {
        let chrome = chromeGroup()
        let subGroup = chrome.subGroups![0]
        let selectionID = GroupSelection.subGroupSelectionID(groupID: chrome.id, subGroupID: subGroup.id)

        let resolved = GroupSelection.resolve(selectedID: selectionID, in: [chrome])
        #expect(resolved?.id == "chrome")
    }

    @Test("Unknown selection ID resolves to nil")
    func unknownSelectionResolvesToNil() {
        let chrome = chromeGroup()
        #expect(GroupSelection.resolve(selectedID: "does-not-exist", in: [chrome]) == nil)
        #expect(GroupSelection.resolve(selectedID: "pid:99999", in: [chrome]) == nil)
    }
}
