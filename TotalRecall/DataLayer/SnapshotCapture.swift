#if DEBUG
import Foundation

/// Debug-only tool for dumping the current process snapshot to JSON.
/// NEVER available in release builds — process args may contain secrets
/// even after redaction (RedactionFilter is best-effort).
public enum SnapshotCapture {
    struct SnapshotEnvelope: Codable {
        let capturedAt: Date
        let processCount: Int
        let systemMemory: SystemMemoryInfo
        let snapshots: [ProcessSnapshot]
    }

    public static func capture(using monitor: ProcessMonitor) async throws -> Data {
        let result = await monitor.collectSnapshot(mode: .full)

        // Redact command-line args before writing to disk — they may contain secrets
        let redactedSnapshots = result.snapshots.map { snapshot in
            ProcessSnapshot(
                pid: snapshot.pid, name: snapshot.name, path: snapshot.path,
                commandLineArgs: RedactionFilter.redact(snapshot.commandLineArgs),
                parentPid: snapshot.parentPid, responsiblePid: snapshot.responsiblePid,
                bundleIdentifier: snapshot.bundleIdentifier, workingDirectory: snapshot.workingDirectory,
                physFootprint: snapshot.physFootprint, residentSize: snapshot.residentSize,
                sharedMemory: snapshot.sharedMemory, startTimeSec: snapshot.startTimeSec,
                startTimeUsec: snapshot.startTimeUsec, firstSeen: snapshot.firstSeen,
                lastSeen: snapshot.lastSeen, exitedAt: snapshot.exitedAt,
                isPartialData: snapshot.isPartialData
            )
        }

        let envelope = SnapshotEnvelope(
            capturedAt: Date(),
            processCount: redactedSnapshots.count,
            systemMemory: result.systemMemory,
            snapshots: redactedSnapshots
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func captureToFile(using monitor: ProcessMonitor, path: String) async throws {
        let data = try await capture(using: monitor)
        try data.write(to: URL(fileURLWithPath: path))
        print("Snapshot captured: \(path) (\(data.count) bytes)")
    }
}
#endif
