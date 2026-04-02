import Foundation

/// Identity tuple used for PID-reuse verification before kill actions
/// and for cache invalidation when a PID is recycled.
struct ProcessIdentity: Equatable, Hashable, Codable, Sendable {
    let pid: Int32
    let executablePath: String
    let startTimeSec: UInt64
    let startTimeUsec: UInt64
}

/// A point-in-time capture of a single process's metadata and memory metrics.
/// Shared across: data collection, exited process retention, and test fixtures.
struct ProcessSnapshot: Identifiable, Codable, Sendable {
    var id: Int32 { pid }

    // Identity
    let pid: Int32
    let name: String
    let path: String
    let commandLineArgs: [String]  // Redacted at capture time by RedactionFilter
    let parentPid: Int32
    let responsiblePid: Int32
    let bundleIdentifier: String?

    // Memory metrics
    let physFootprint: UInt64       // phys_footprint — the canonical metric
    let residentSize: UInt64        // ri_resident_size
    let sharedMemory: UInt64        // RSHRD — real shared memory

    // Timing
    let startTimeSec: UInt64        // pbi_start_tvsec
    let startTimeUsec: UInt64       // pbi_start_tvusec
    let firstSeen: Date
    let lastSeen: Date
    let exitedAt: Date?

    // Data quality
    let isPartialData: Bool         // True if some fields couldn't be read (permission denied)

    var processIdentity: ProcessIdentity {
        ProcessIdentity(
            pid: pid,
            executablePath: path,
            startTimeSec: startTimeSec,
            startTimeUsec: startTimeUsec
        )
    }

    /// Approximate non-resident memory (compressed + swapped).
    /// This conflates compressed and swapped — label as "non-resident" in UI.
    var nonResidentMemory: UInt64 {
        physFootprint > residentSize ? physFootprint - residentSize : 0
    }
}
