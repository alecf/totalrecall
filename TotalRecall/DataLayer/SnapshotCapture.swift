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

        let envelope = SnapshotEnvelope(
            capturedAt: Date(),
            processCount: result.snapshots.count,
            systemMemory: result.systemMemory,
            snapshots: result.snapshots
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
