import Testing
@testable import TotalRecallCore

@Suite("Classifier Engine Tests")
struct ClassifierTests {
    let registry = ClassifierRegistry.default
    let fixtures = FixtureBuilder.devWorkstation()

    // MARK: - Full Registry

    @Test("All processes are classified into groups")
    func fullClassification() {
        let groups = registry.classify(snapshots: fixtures)
        let totalClassified = groups.reduce(0) { $0 + $1.processes.count + ($1.subGroups?.reduce(0) { $0 + $1.processes.count } ?? 0) }
        #expect(totalClassified == fixtures.count)
    }

    @Test("Groups are sorted by memory (largest first)")
    func groupsSortedByMemory() {
        let groups = registry.classify(snapshots: fixtures)
        for i in 0..<groups.count - 1 {
            #expect(groups[i].deduplicatedFootprint >= groups[i + 1].deduplicatedFootprint)
        }
    }

    @Test("No PID is claimed by multiple groups")
    func noDuplicatePIDs() {
        let groups = registry.classify(snapshots: fixtures)
        var seenPIDs: Set<Int32> = []
        for group in groups {
            let allPIDs = collectPIDs(from: group)
            let overlap = seenPIDs.intersection(allPIDs)
            #expect(overlap.isEmpty, "PIDs \(overlap) claimed by multiple groups")
            seenPIDs.formUnion(allPIDs)
        }
    }

    // MARK: - Chrome Classifier

    @Test("Chrome processes grouped together")
    func chromeGrouping() throws {
        let groups = registry.classify(snapshots: fixtures)
        let chrome = try #require(groups.first { $0.stableIdentifier == "chrome" })
        #expect(chrome.name == "Google Chrome")
        #expect(chrome.classifierName == "Chrome")
    }

    @Test("Chrome has sub-groups by profile")
    func chromeProfiles() throws {
        let groups = registry.classify(snapshots: fixtures)
        let chrome = try #require(groups.first { $0.stableIdentifier == "chrome" })
        let subGroups = try #require(chrome.subGroups)
        #expect(subGroups.count == 2)  // Default + Profile 1

        let defaultProfile = subGroups.first { $0.stableIdentifier == "chrome:Default" }
        let profile1 = subGroups.first { $0.stableIdentifier == "chrome:Profile 1" }
        #expect(defaultProfile != nil)
        #expect(profile1 != nil)
    }

    @Test("Chrome Default profile has 3 renderers")
    func chromeDefaultRenderers() throws {
        let groups = registry.classify(snapshots: fixtures)
        let chrome = try #require(groups.first { $0.stableIdentifier == "chrome" })
        let defaultProfile = try #require(chrome.subGroups?.first { $0.stableIdentifier == "chrome:Default" })
        #expect(defaultProfile.processes.count == 3)  // 3 renderers
    }

    // MARK: - Electron Classifier

    @Test("VS Code grouped as Electron app")
    func vscodeGrouping() throws {
        let groups = registry.classify(snapshots: fixtures)
        let vscode = try #require(groups.first { $0.stableIdentifier == "electron:visual studio code" })
        #expect(vscode.name == "Visual Studio Code")
        #expect(vscode.processes.count == 3)  // main + 2 renderers
    }

    // MARK: - System Services Classifier

    @Test("System services grouped together")
    func systemServices() throws {
        let groups = registry.classify(snapshots: fixtures)
        let system = try #require(groups.first { $0.stableIdentifier == "system" })
        #expect(system.name == "System Services")

        let names = Set(system.processes.map(\.name))
        #expect(names.contains("kernel_task"))
        #expect(names.contains("WindowServer"))
        #expect(names.contains("mds_stores"))
    }

    @Test("System service explanations available")
    func systemExplanations() {
        #expect(SystemServicesClassifier.explanation(for: "WindowServer") != nil)
        #expect(SystemServicesClassifier.explanation(for: "mds_stores") != nil)
        #expect(SystemServicesClassifier.explanation(for: "nonexistent_process") == nil)
    }

    // MARK: - Generic Classifier

    @Test("Unclaimed processes caught by generic classifier")
    func genericCatchAll() {
        let groups = registry.classify(snapshots: fixtures)
        let genericGroups = groups.filter { $0.classifierName == "Generic" }
        #expect(!genericGroups.isEmpty)

        // Safari and Mail should be in generic groups
        let allGenericProcesses = genericGroups.flatMap(\.processes)
        let names = Set(allGenericProcesses.map(\.name))
        #expect(names.contains("Safari"))
        #expect(names.contains("Mail"))
    }

    // MARK: - RSHRD Deduplication

    @Test("Deduplicated footprint is less than or equal to raw sum")
    func deduplicationReducesTotal() {
        let groups = registry.classify(snapshots: fixtures)
        for group in groups {
            let allProcs = collectAllProcesses(from: group)
            guard allProcs.count > 1 else { continue }
            let rawSum = allProcs.reduce(0 as UInt64) { $0 + $1.physFootprint }
            #expect(group.deduplicatedFootprint <= rawSum,
                    "Group '\(group.name)' deduplicated (\(group.deduplicatedFootprint)) > raw sum (\(rawSum))")
        }
    }

    // MARK: - Helpers

    private func collectPIDs(from group: ProcessGroup) -> Set<Int32> {
        var pids = Set(group.processes.map(\.pid))
        if let subGroups = group.subGroups {
            for sub in subGroups {
                pids.formUnion(collectPIDs(from: sub))
            }
        }
        return pids
    }

    private func collectAllProcesses(from group: ProcessGroup) -> [ProcessSnapshot] {
        var all = group.processes
        if let subGroups = group.subGroups {
            for sub in subGroups {
                all.append(contentsOf: collectAllProcesses(from: sub))
            }
        }
        return all
    }
}

@Suite("RedactionFilter Tests")
struct RedactionFilterTests {
    @Test("Masks password flags")
    func passwordFlags() {
        let args = ["mysql", "-u", "root", "-p", "MySecret123"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["mysql", "-u", "root", "-p", "[REDACTED]"])
    }

    @Test("Masks --password=value")
    func passwordEqualsValue() {
        let args = ["app", "--password=hunter2"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--password=[REDACTED]"])
    }

    @Test("Masks environment variables with secrets")
    func envVarSecrets() {
        let args = ["docker", "run", "-e", "AWS_SECRET_KEY=abc123"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[3] == "[REDACTED]")
    }

    @Test("Masks Authorization headers")
    func authHeaders() {
        let args = ["curl", "-H", "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[2] == "[REDACTED]")
    }

    @Test("Masks long base64-like strings")
    func longBase64() {
        let token = String(repeating: "abcdefghABCDEFGH12345678", count: 3)  // 72 chars
        let args = ["app", token]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[1] == "[REDACTED]")
    }

    @Test("Does not redact normal args")
    func normalArgs() {
        let args = ["node", "server.js", "--port", "3000", "--verbose"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == args)
    }
}
