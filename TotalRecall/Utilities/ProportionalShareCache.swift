import Foundation

/// Per-process proportional set size (PSS) as a share of resident memory,
/// measured a few processes at a time and reused between measurements.
///
/// A process's resident size counts every shared page it maps, so summing
/// resident sizes counts a system library once per process that loads it.
/// Counting only private pages is wrong the other way: it drops memory a group
/// shares with itself — Chrome's renderers and GPU process share memory, and a
/// VM's guest RAM is a shared mapping — which is most of what those apps hold.
/// PSS charges each shared object's resident pages evenly to the processes
/// mapping it: Chrome's shared memory lands in Chrome, a library mapped by 500
/// processes is spread thin, and PSS summed over every process is the physical
/// total.
///
/// Mapper counts come from the cached walks themselves: each walk records the
/// shared objects it saw (`SystemProbe.walkResidentPages`), and an object's
/// pages are split across every cached process that maps it. Walking every
/// process costs about 2 s of CPU on a busy machine, so the monitor spends a
/// fixed budget per refresh; each process's share (PSS ÷ resident) is applied to
/// its fresh resident size until the next walk.
///
/// The same walk counts each region's compressed pages, so compressed memory
/// gets the same accounting: private compressed pages plus each shared
/// object's compressed pages split across the processes mapping it. Summed
/// over every process, that counts each compressed page once. Between walks a
/// process's figure moves by however much the kernel's own compressed count
/// for it (`task_vm_info.compressed`) has changed since the walk.
///
/// The walk also marks which pages are mapped from files, so the cache can
/// total the file-backed memory walked processes hold (`mappedFileBytes`):
/// pages the kernel counts as cached files, but that apps are using.
///
/// Scheduling: processes younger than `cooloff` are never walked — build steps
/// and other short-lived processes would cost a walk each and be gone before it
/// mattered. Of the rest, half the budget goes to processes never measured,
/// newest first, and half to the ones measured longest ago, so a burst of new
/// processes can't starve the old ones. Until every process has been measured
/// once (`isWarm`), the never-measured ones go first, largest first, ahead of
/// any re-walk: the big groups dominate the bar, so they get real shares within
/// a refresh or two.
public struct ProportionalShareCache: Sendable {
    /// What one walk of a process's VM map found.
    public struct Walk: Sendable, Equatable {
        public let privateBytes: UInt64
        /// Resident bytes of each shared memory object it maps, by object ID.
        public let sharedBytes: [UInt32: UInt64]
        /// Compressed bytes (at uncompressed size) in private regions.
        public let privateCompressedBytes: UInt64
        /// Compressed bytes of each shared memory object it maps, by object ID.
        public let sharedCompressedBytes: [UInt32: UInt64]
        /// The part of `privateBytes` that is mapped from files.
        public let privateFileBytes: UInt64
        /// The shared objects in `sharedBytes` that are mapped from files.
        public let fileObjects: Set<UInt32>

        public init(privateBytes: UInt64, sharedBytes: [UInt32: UInt64],
                    privateCompressedBytes: UInt64 = 0, sharedCompressedBytes: [UInt32: UInt64] = [:],
                    privateFileBytes: UInt64 = 0, fileObjects: Set<UInt32> = []) {
            self.privateBytes = privateBytes
            self.sharedBytes = sharedBytes
            self.privateCompressedBytes = privateCompressedBytes
            self.sharedCompressedBytes = sharedCompressedBytes
            self.privateFileBytes = privateFileBytes
            self.fileObjects = fileObjects
        }
    }

    struct Entry: Sendable, Equatable {
        /// `nil` when the walk failed (another user's process); such a process
        /// uses `defaultShare`, but still counts as measured for scheduling.
        var walk: Walk?
        var measuredAt: Date
        /// Start time when measured, so a recycled PID reads as new.
        var startTime: Date
        /// Resident size at the walk, the denominator of the share.
        var residentSize: UInt64
        /// The kernel's compressed count at the walk, the baseline the
        /// compressed figure moves from. `nil` when it couldn't be read.
        var compressedSize: UInt64?
    }

    private(set) var entries: [Int32: Entry] = [:]
    /// How many cached walks map each shared object with resident pages.
    private var mappers: [UInt32: Int] = [:]
    /// How many cached walks map each shared object with compressed pages.
    private var compressedMappers: [UInt32: Int] = [:]

    /// Set once a refresh finds nothing left that has never been measured.
    public private(set) var isWarm = false

    public init() {}

    /// A live process the cache may schedule.
    public struct Candidate: Sendable, Equatable {
        public let pid: Int32
        public let startTime: Date
        public let residentSize: UInt64
        public let compressedSize: UInt64?

        public init(pid: Int32, startTime: Date, residentSize: UInt64 = 0, compressedSize: UInt64? = nil) {
            self.pid = pid
            self.startTime = startTime
            self.residentSize = residentSize
            self.compressedSize = compressedSize
        }
    }

    /// Drop entries for processes that are gone or whose PID was recycled.
    public mutating func retain(_ candidates: [Candidate]) {
        let live = Dictionary(candidates.map { ($0.pid, $0.startTime) }, uniquingKeysWith: { first, _ in first })
        for (pid, entry) in entries where live[pid] != entry.startTime {
            remove(pid)
        }
    }

    /// Walk order for this refresh: never-measured processes past the cooloff
    /// interleaved with measured ones (stalest first). Walking in this order
    /// until the budget runs out splits it evenly between the two, and gives
    /// either all of it when the other is empty.
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

        // Warm-up spends its whole budget on processes never measured, so the
        // bar has real shares for everything as soon as possible.
        if !isWarm { return fresh.map(\.pid) + stale.map(\.pid) }

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

    /// Record a walk (`nil` when it failed) and the process's resident size
    /// and kernel compressed count at the time.
    public mutating func record(pid: Int32, startTime: Date, walk: Walk?, residentSize: UInt64,
                                compressedSize: UInt64? = nil, now: Date) {
        remove(pid)
        entries[pid] = Entry(walk: walk, measuredAt: now, startTime: startTime,
                             residentSize: residentSize, compressedSize: compressedSize)
        for object in walk?.sharedBytes.keys ?? [:].keys {
            mappers[object, default: 0] += 1
        }
        for object in walk?.sharedCompressedBytes.keys ?? [:].keys {
            compressedMappers[object, default: 0] += 1
        }
    }

    private mutating func remove(_ pid: Int32) {
        guard let old = entries.removeValue(forKey: pid) else { return }
        Self.release(old.walk?.sharedBytes.keys, from: &mappers)
        Self.release(old.walk?.sharedCompressedBytes.keys, from: &compressedMappers)
    }

    private static func release(_ objects: Dictionary<UInt32, UInt64>.Keys?, from counts: inout [UInt32: Int]) {
        for object in objects ?? [:].keys {
            if let count = counts[object], count > 1 {
                counts[object] = count - 1
            } else {
                counts.removeValue(forKey: object)
            }
        }
    }

    /// PSS ÷ resident for every successfully walked process, against the
    /// current mapper counts. Compute once per refresh — it touches every
    /// cached shared object.
    public func shares() -> Shares {
        var byPID: [Int32: (startTime: Date, share: Double)] = [:]
        var compressedByPID: [Int32: (startTime: Date, bytes: UInt64, baseline: UInt64)] = [:]
        var pssTotal = 0.0
        var residentTotal = 0.0
        var mappedFiles = 0.0
        for (pid, entry) in entries {
            guard let walk = entry.walk else { continue }
            mappedFiles += Double(walk.privateFileBytes)
            for object in walk.fileObjects {
                mappedFiles += Double(walk.sharedBytes[object] ?? 0) / Double(max(1, mappers[object] ?? 1))
            }
            if let baseline = entry.compressedSize {
                var compressed = Double(walk.privateCompressedBytes)
                for (object, bytes) in walk.sharedCompressedBytes {
                    compressed += Double(bytes) / Double(max(1, compressedMappers[object] ?? 1))
                }
                compressedByPID[pid] = (entry.startTime, UInt64(compressed), baseline)
            }
            guard entry.residentSize > 0 else { continue }
            var pss = Double(walk.privateBytes)
            for (object, bytes) in walk.sharedBytes {
                pss += Double(bytes) / Double(max(1, mappers[object] ?? 1))
            }
            let resident = Double(entry.residentSize)
            byPID[pid] = (entry.startTime, min(1, pss / resident))
            pssTotal += min(pss, resident)
            residentTotal += resident
        }
        let fallback = residentTotal > 0 ? min(1, pssTotal / residentTotal) : 1
        return Shares(byPID: byPID, compressedByPID: compressedByPID, defaultShare: fallback,
                      mappedFileBytes: UInt64(mappedFiles))
    }

    /// A snapshot of every process's share, for one refresh.
    public struct Shares: Sendable {
        let byPID: [Int32: (startTime: Date, share: Double)]
        let compressedByPID: [Int32: (startTime: Date, bytes: UInt64, baseline: UInt64)]
        /// Resident-weighted share across every successful walk — the best
        /// guess for a process not yet measured, or one that can't be. `1`
        /// (resident as-is) before anything has been measured.
        public let defaultShare: Double
        /// File-backed resident memory mapped by walked processes, each page
        /// counted once: the file part of their summed PSS, split by the same
        /// mapper counts. It sits inside the kernel's cached files, and it's
        /// already in these processes' proportional resident memory.
        public let mappedFileBytes: UInt64

        /// Proportional resident bytes: the process's share (or the default)
        /// applied to its current resident size.
        public func proportionalResident(pid: Int32, startTime: Date, residentSize: UInt64) -> UInt64 {
            let entry = byPID[pid].flatMap { $0.startTime == startTime ? $0 : nil }
            return UInt64(Double(residentSize) * (entry?.share ?? defaultShare))
        }

        /// Proportional compressed bytes: the walk's figure, moved by however
        /// much the kernel's compressed count has changed since. `nil` for a
        /// process never walked, or without a kernel count now or at the walk.
        ///
        /// The change is added, not applied as a ratio: a process whose own
        /// count was near zero at its walk can still carry a large share of a
        /// shared object, and a ratio would multiply that by any growth.
        public func proportionalCompressed(pid: Int32, startTime: Date, compressedSize: UInt64?) -> UInt64? {
            guard let compressedSize,
                  let entry = compressedByPID[pid], entry.startTime == startTime else { return nil }
            let moved = Int64(clamping: entry.bytes) + Int64(clamping: compressedSize) - Int64(clamping: entry.baseline)
            return UInt64(max(0, moved))
        }
    }
}
