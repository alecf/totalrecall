import Foundation

/// Identity tuple used for PID-reuse verification before kill actions
/// and for cache invalidation when a PID is recycled.
public struct ProcessIdentity: Equatable, Hashable, Codable, Sendable {
    public let pid: Int32
    public let executablePath: String
    public let startTimeSec: UInt64
    public let startTimeUsec: UInt64
}

/// A point-in-time capture of a single process's metadata and memory metrics.
/// Shared across: data collection, exited process retention, and test fixtures.
public struct ProcessSnapshot: Identifiable, Codable, Sendable {
    public var id: Int32 { pid }

    // Identity
    public let pid: Int32
    public let name: String
    public let path: String
    public let commandLineArgs: [String]  // Redacted at capture time by RedactionFilter
    public let parentPid: Int32
    public let responsiblePid: Int32
    public let bundleIdentifier: String?

    // Memory metrics
    public let physFootprint: UInt64       // phys_footprint — the canonical metric
    public let residentSize: UInt64        // ri_resident_size
    public let sharedMemory: UInt64        // RSHRD — real shared memory

    // Timing
    public let startTimeSec: UInt64        // pbi_start_tvsec
    public let startTimeUsec: UInt64       // pbi_start_tvusec
    public let firstSeen: Date
    public let lastSeen: Date
    public let exitedAt: Date?

    // Data quality
    public let isPartialData: Bool         // True if some fields couldn't be read (permission denied)

    public var processIdentity: ProcessIdentity {
        ProcessIdentity(
            pid: pid,
            executablePath: path,
            startTimeSec: startTimeSec,
            startTimeUsec: startTimeUsec
        )
    }

    /// Approximate non-resident memory (compressed + swapped).
    /// This conflates compressed and swapped — label as "non-resident" in UI.
    public var nonResidentMemory: UInt64 {
        physFootprint > residentSize ? physFootprint - residentSize : 0
    }
}
