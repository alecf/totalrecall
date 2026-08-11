import Testing
@testable import TotalRecallCore

@Suite("Instance Merger")
struct InstanceMergerTests {
    private func instanceGroup(
        stableIdentifier: String, name: String, footprint: UInt64, pid: Int32,
        explanation: String? = nil
    ) -> ProcessGroup {
        let process = FixtureBuilder.genericProcess(pid: pid, name: name, footprint: footprint)
        return ProcessGroup(
            stableIdentifier: stableIdentifier,
            name: name,
            icon: nil,
            classifierName: "Test",
            explanation: explanation,
            processes: [process],
            subGroups: nil,
            deduplicatedFootprint: process.physFootprint,
            nonResidentMemory: process.nonResidentMemory
        )
    }

    // MARK: - appKey(from:)

    @Test("Strips a trailing numeric PID from the identifier")
    func stripsTrailingPID() {
        #expect(InstanceMerger.appKey(from: "tool:27527") == "tool")
    }

    @Test("Keeps non-numeric sub-keys intact")
    func keepsNonNumericSubKeys() {
        #expect(InstanceMerger.appKey(from: "chrome:Default") == "chrome:Default")
    }

    @Test("Identifiers without a colon are returned unchanged")
    func identifierWithoutColonUnchanged() {
        #expect(InstanceMerger.appKey(from: "chrome") == "chrome")
    }

    @Test("Identifiers with extra colons keep the full suffix when non-numeric")
    func identifierWithExtraColonsKeepsSuffix() {
        #expect(InstanceMerger.appKey(from: "generic:app:/Applications/Foo.app") == "generic:app:/Applications/Foo.app")
    }

    // MARK: - mergeInstances

    @Test("Single-instance groups pass through unchanged")
    func singleInstancePassesThrough() {
        let group = instanceGroup(stableIdentifier: "tool:1000", name: "tool", footprint: 50 * 1024 * 1024, pid: 1000)
        let merged = InstanceMerger.mergeInstances([group])

        #expect(merged.count == 1)
        #expect(merged[0].id == "tool:1000")
        #expect(merged[0].subGroups == nil)
    }

    @Test("Multiple instances of the same app merge into sub-groups")
    func multipleInstancesMergeIntoSubGroups() {
        let a = instanceGroup(stableIdentifier: "tool:1000", name: "tool", footprint: 50 * 1024 * 1024, pid: 1000)
        let b = instanceGroup(stableIdentifier: "tool:2000", name: "tool", footprint: 30 * 1024 * 1024, pid: 2000)

        let merged = InstanceMerger.mergeInstances([a, b])

        #expect(merged.count == 1)
        let group = merged[0]
        #expect(group.id == "tool")
        #expect(group.processes.isEmpty)
        #expect(group.subGroups?.count == 2)
        #expect(group.subGroups?.map(\.name).sorted() == ["tool #1", "tool #2"])
    }

    @Test("Merged footprint matches the deduplicated sum across instances")
    func mergedFootprintIsDeduplicatedSum() {
        let a = instanceGroup(stableIdentifier: "tool:1000", name: "tool", footprint: 50 * 1024 * 1024, pid: 1000)
        let b = instanceGroup(stableIdentifier: "tool:2000", name: "tool", footprint: 30 * 1024 * 1024, pid: 2000)

        let merged = InstanceMerger.mergeInstances([a, b])
        let expected = ProcessGroup.computeDeduplicatedFootprint(for: [a.processes[0], b.processes[0]])

        #expect(merged[0].deduplicatedFootprint == expected)
    }

    @Test("Merged group drops per-instance explanations that disagree")
    func mergedGroupDropsDivergentExplanations() {
        let a = instanceGroup(stableIdentifier: "tool:1000", name: "tool", footprint: 50 * 1024 * 1024, pid: 1000,
                              explanation: "in project-a")
        let b = instanceGroup(stableIdentifier: "tool:2000", name: "tool", footprint: 30 * 1024 * 1024, pid: 2000,
                              explanation: "in project-b")

        let merged = InstanceMerger.mergeInstances([a, b])

        #expect(merged[0].explanation == nil)
        #expect(merged[0].subGroups?.map(\.name).sorted() == ["tool #1 - in project-a", "tool #2 - in project-b"])
    }

    @Test("Merged group keeps an explanation all instances share")
    func mergedGroupKeepsSharedExplanation() {
        let a = instanceGroup(stableIdentifier: "tool:1000", name: "tool", footprint: 50 * 1024 * 1024, pid: 1000,
                              explanation: "Electron app")
        let b = instanceGroup(stableIdentifier: "tool:2000", name: "tool", footprint: 30 * 1024 * 1024, pid: 2000,
                              explanation: "Electron app")

        let merged = InstanceMerger.mergeInstances([a, b])

        #expect(merged[0].explanation == "Electron app")
    }

    @Test("Groups with different app keys are not merged")
    func differentAppKeysNotMerged() {
        let chrome = instanceGroup(stableIdentifier: "chrome:Default", name: "Google Chrome", footprint: 100 * 1024 * 1024, pid: 1000)
        let tool = instanceGroup(stableIdentifier: "tool:2000", name: "tool", footprint: 30 * 1024 * 1024, pid: 2000)

        let merged = InstanceMerger.mergeInstances([chrome, tool])

        #expect(merged.count == 2)
        #expect(Set(merged.map(\.id)) == ["chrome:Default", "tool:2000"])
    }

    @Test("Result is sorted by deduplicated footprint, largest first")
    func resultSortedByFootprint() {
        let small = instanceGroup(stableIdentifier: "small", name: "Small", footprint: 10 * 1024 * 1024, pid: 1000)
        let large = instanceGroup(stableIdentifier: "large", name: "Large", footprint: 500 * 1024 * 1024, pid: 2000)

        let merged = InstanceMerger.mergeInstances([small, large])

        #expect(merged.map(\.id) == ["large", "small"])
    }

    // MARK: - labelSeparateInstances

    @Test("A single instance is not numbered")
    func singleInstanceNotNumbered() {
        let group = instanceGroup(stableIdentifier: "tool:1000", name: "tool", footprint: 50 * 1024 * 1024, pid: 1000)
        let labeled = InstanceMerger.labelSeparateInstances([group])

        #expect(labeled.count == 1)
        #expect(labeled[0].name == "tool")
    }

    @Test("Multiple instances are numbered and kept separate")
    func multipleInstancesAreNumbered() {
        let a = instanceGroup(stableIdentifier: "tool:1000", name: "tool", footprint: 50 * 1024 * 1024, pid: 1000)
        let b = instanceGroup(stableIdentifier: "tool:2000", name: "tool", footprint: 30 * 1024 * 1024, pid: 2000)

        let labeled = InstanceMerger.labelSeparateInstances([a, b])

        #expect(labeled.count == 2)
        #expect(Set(labeled.map(\.name)) == ["tool #1", "tool #2"])
        #expect(Set(labeled.map(\.id)) == ["tool:1000", "tool:2000"])
    }
}
