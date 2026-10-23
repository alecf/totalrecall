import Foundation

/// Turns each process's lifetime swap-in counter (`task_vm_info.ledger_swapins`)
/// into a rate over the last refresh.
///
/// The counter alone says little — a process that thrashed an hour ago carries
/// the total forever. Its change between refreshes is the useful part: an exact,
/// per-process "this app is waiting on disk right now", which is when swap
/// actually costs the user something. No estimate is involved: it's the
/// kernel's own ledger, differenced.
public struct SwapActivityTracker: Sendable {
    struct Sample: Sendable, Equatable {
        let startTime: Date
        let swapins: UInt64
        let at: Date
    }

    private(set) var samples: [Int32: Sample] = [:]

    public init() {}

    /// Record this refresh's counter and return bytes per second since the
    /// previous one, or `nil` for a first sighting, a recycled PID, or a
    /// counter that went backwards.
    public mutating func rate(pid: Int32, startTime: Date, swapins: UInt64, now: Date) -> Double? {
        let previous = samples[pid]
        samples[pid] = Sample(startTime: startTime, swapins: swapins, at: now)
        guard let previous, previous.startTime == startTime, swapins >= previous.swapins else { return nil }
        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return nil }
        return Double(swapins - previous.swapins) / elapsed
    }

    /// Drop samples for processes that are gone.
    public mutating func retain(pids: Set<Int32>) {
        samples = samples.filter { pids.contains($0.key) }
    }
}
