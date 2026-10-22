import Foundation

/// Per-process private share of resident memory, measured a few processes at a
/// time and reused between measurements.
///
/// A process's resident size counts every shared page it maps — system
/// libraries, the dyld shared cache — so summing resident sizes counts those
/// pages once per process. The private part comes from walking the process's
/// VM regions (`SystemProbe.getPrivateResident`), which costs about 2 s of CPU
/// for every process on a busy machine. So the monitor spends a fixed time
/// budget per refresh, and each process's share (private ÷ resident) is cached
/// and applied to its fresh resident size until the next walk. Shares move
/// slowly; resident sizes don't.
///
/// Scheduling: processes younger than `cooloff` are never walked — build steps
/// and other short-lived processes would cost a walk each and be gone before it
/// mattered. Of the rest, half the budget goes to processes never measured,
/// newest first, and half to the ones measured longest ago, so a burst of new
/// processes can't starve the old ones. Until every process has been measured
/// once (`isWarm`), the never-measured ones go largest first instead: the big
/// groups dominate the bar, so they get real shares within a refresh or two.
public struct PrivateShareCache: Sendable {
    public struct Entry: Sendable, Equatable {
        /// `nil` when the walk failed (another user's process); such a process
        /// uses `defaultShare`, but still counts as measured for scheduling.
        public var share: Double?
        public var measuredAt: Date
        /// Start time when measured, so a recycled PID reads as new.
        public var startTime: Date
        var privateBytes: UInt64
        var residentBytes: UInt64
    }

    public private(set) var entries: [Int32: Entry] = [:]

    /// Set once a refresh finds nothing left that has never been measured.
    public private(set) var isWarm = false

    public init() {}

    /// A live process the cache may schedule.
    public struct Candidate: Sendable, Equatable {
        public let pid: Int32
        public let startTime: Date
        public let residentSize: UInt64

        public init(pid: Int32, startTime: Date, residentSize: UInt64 = 0) {
            self.pid = pid
            self.startTime = startTime
            self.residentSize = residentSize
        }
    }

    /// Drop entries for processes that are gone or whose PID was recycled.
    public mutating func retain(_ candidates: [Candidate]) {
        let live = Dictionary(candidates.map { ($0.pid, $0.startTime) }, uniquingKeysWith: { first, _ in first })
        entries = entries.filter { pid, entry in live[pid] == entry.startTime }
    }

    /// Walk order for this refresh: never-measured processes past the cooloff
    /// (newest first) interleaved with measured ones (stalest first). Walking
    /// in this order until the budget runs out splits it evenly between the
    /// two, and gives either all of it when the other is empty.
    public mutating func walkOrder(_ candidates: [Candidate], now: Date, cooloff: TimeInterval) -> [Int32] {
        var fresh: [Candidate] = []
        var stale: [(pid: Int32, measuredAt: Date)] = []
        for candidate in candidates where now.timeIntervalSince(candidate.startTime) >= cooloff {
            if let entry = entries[candidate.pid], entry.startTime == candidate.startTime {
                stale.append((candidate.pid, entry.measuredAt))
            } else {
                fresh.append(candidate)
            }
        }
        if fresh.isEmpty { isWarm = true }
        if isWarm {
            fresh.sort { $0.startTime > $1.startTime }
        } else {
            fresh.sort { $0.residentSize > $1.residentSize }
        }
        stale.sort { $0.measuredAt < $1.measuredAt }

        var order: [Int32] = []
        order.reserveCapacity(fresh.count + stale.count)
        var f = fresh.makeIterator(), s = stale.makeIterator()
        var nextFresh = f.next(), nextStale = s.next()
        while nextFresh != nil || nextStale != nil {
            if let candidate = nextFresh {
                order.append(candidate.pid)
                nextFresh = f.next()
            }
            if let candidate = nextStale {
                order.append(candidate.pid)
                nextStale = s.next()
            }
        }
        return order
    }

    /// Record a walk: the private bytes it found (`nil` when it failed) and
    /// the process's resident size at the time. The share is taken against
    /// that resident size, not the walk's own resident total — region counts
    /// include shared mappings again and run well above it.
    public mutating func record(
        pid: Int32,
        startTime: Date,
        privateBytes: UInt64?,
        residentSize: UInt64,
        now: Date
    ) {
        let share: Double? = privateBytes.flatMap { bytes in
            residentSize > 0 ? min(1, Double(bytes) / Double(residentSize)) : nil
        }
        entries[pid] = Entry(
            share: share,
            measuredAt: now,
            startTime: startTime,
            privateBytes: share == nil ? 0 : min(privateBytes ?? 0, residentSize),
            residentBytes: share == nil ? 0 : residentSize
        )
    }

    /// Private share across every successful walk, weighted by resident size —
    /// the best guess for a process not yet measured. `1` (resident as-is)
    /// before anything has been measured.
    public var defaultShare: Double {
        var privateTotal: UInt64 = 0
        var residentTotal: UInt64 = 0
        for entry in entries.values where entry.share != nil {
            privateTotal += entry.privateBytes
            residentTotal += entry.residentBytes
        }
        guard residentTotal > 0 else { return 1 }
        return min(1, Double(privateTotal) / Double(residentTotal))
    }

    /// Private resident bytes for a process: its measured share (or the default)
    /// applied to its current resident size.
    public func privateResident(pid: Int32, startTime: Date, residentSize: UInt64, defaultShare: Double) -> UInt64 {
        let entry = entries[pid].flatMap { $0.startTime == startTime ? $0 : nil }
        let share = entry?.share ?? defaultShare
        return UInt64(Double(residentSize) * share)
    }
}
