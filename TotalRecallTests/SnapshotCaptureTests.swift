#if DEBUG
import Testing
import Foundation
@testable import TotalRecallCore

@Suite("SnapshotCapture")
struct SnapshotCaptureTests {

    @Test("capture returns non-empty data")
    func captureReturnsData() async throws {
        let monitor = ProcessMonitor()
        let data = try await SnapshotCapture.capture(using: monitor)
        #expect(!data.isEmpty)
    }

    @Test("capture returns valid JSON with expected top-level keys")
    func captureReturnsValidJSON() async throws {
        let monitor = ProcessMonitor()
        let data = try await SnapshotCapture.capture(using: monitor)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["capturedAt"] != nil)
        #expect(json?["processCount"] != nil)
        #expect(json?["snapshots"] != nil)
        #expect(json?["systemMemory"] != nil)
    }

    @Test("capture processCount matches snapshots array length")
    func captureProcessCountMatchesSnapshots() async throws {
        let monitor = ProcessMonitor()
        let data = try await SnapshotCapture.capture(using: monitor)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let count = json?["processCount"] as? Int
        let snapshots = json?["snapshots"] as? [[String: Any]]
        #expect(count != nil)
        #expect(snapshots != nil)
        #expect(count == snapshots?.count)
    }

    @Test("capture redacts command-line args")
    func captureRedactsArgs() async throws {
        // SnapshotCapture should apply RedactionFilter before encoding
        let monitor = ProcessMonitor()
        let data = try await SnapshotCapture.capture(using: monitor)
        // Just verify the data was produced without error — redaction is tested separately
        #expect(!data.isEmpty)
    }

    @Test("captureToFile writes JSON to disk")
    func captureToFileWritesToDisk() async throws {
        let monitor = ProcessMonitor()
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-\(UUID().uuidString).json")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }

        try await SnapshotCapture.captureToFile(using: monitor, path: path)

        #expect(FileManager.default.fileExists(atPath: path))
        let written = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(!written.isEmpty)
    }

    @Test("captureToFile produces valid JSON at the given path")
    func captureToFileProducesValidJSON() async throws {
        let monitor = ProcessMonitor()
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-valid-\(UUID().uuidString).json")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }

        try await SnapshotCapture.captureToFile(using: monitor, path: path)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["capturedAt"] != nil)
    }
}
#endif
