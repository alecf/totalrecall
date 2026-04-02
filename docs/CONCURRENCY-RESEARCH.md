# Budgeted, Non-Blocking Background Work in Swift macOS Apps

Research on Swift Concurrency best practices for a system monitor app that calls
libproc APIs (`proc_pid_rusage`, `proc_pidinfo`, `proc_pidpath`, sysctl
`KERN_PROCARGS2`) for 500-1000+ processes every 5 seconds.

---

## 1. Task.yield() -- Does It Actually Help?

### Answer: Yes, but only within the cooperative thread pool.

`Task.yield()` is a **suspension point** that tells the Swift runtime "I am
willing to give up my thread so other tasks in the cooperative pool can run."
It does **not** yield to arbitrary OS threads or GCD queues -- it only allows
other Swift Concurrency tasks (including those queued on the same actor) to be
scheduled.

**How it works mechanically:**
- When you `await Task.yield()`, the current task suspends.
- The cooperative thread pool executor checks its ready queue.
- If higher-priority (or same-priority) tasks are waiting, they get a turn.
- If nothing is waiting, the yielding task resumes immediately (near-zero cost).

**When it helps your use case:**
- If the `ProcessMonitor` actor is iterating over 800 PIDs calling
  `proc_pid_rusage` in a tight loop (synchronous C calls, no natural
  suspension points), the actor holds its thread for the entire duration.
- Inserting `await Task.yield()` every N iterations creates suspension points,
  allowing other tasks queued on the cooperative pool to run.
- This is especially important if the UI or timer tasks need to schedule work
  while collection is in progress.

**When it does NOT help:**
- It does not help if the blocking work is a single long C call (you cannot
  yield mid-syscall).
- It does not yield to GCD queues or other non-Swift-Concurrency work.

**Recommended pattern for your loop:**

```swift
actor ProcessMonitor {
    func collectAll(pids: [pid_t]) async -> [ProcessSnapshot] {
        var results: [ProcessSnapshot] = []
        results.reserveCapacity(pids.count)

        for (index, pid) in pids.enumerated() {
            // Yield every 50 iterations to let other tasks run
            if index.isMultiple(of: 50) {
                await Task.yield()
            }

            let snapshot = readProcessInfo(pid: pid) // synchronous C call
            results.append(snapshot)
        }
        return results
    }
}
```

The yield interval (every 50 iterations) is a tuning parameter. At ~1-5us per
`proc_pid_rusage` call, 50 iterations = 50-250us of uninterrupted work, which
is reasonable. For the more expensive `KERN_PROCARGS2`, yield more frequently.

### Sources
- [Yielding and debouncing in Swift Concurrency (Swift with Majid, Feb 2025)](https://swiftwithmajid.com/2025/02/18/yielding-and-debouncing-in-swift-concurrency/)
- [SE-0304: Structured Concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
- [Task.yield() (Grokipedia)](https://grokipedia.com/page/Taskyield_Swift)

---

## 2. QoS / Task Priority

### Answer: Yes, use `.utility` for the polling task. Use `Task.detached` to avoid inheriting the caller's priority.

**Priority levels available:**
| TaskPriority | GCD QoS Equivalent | Use Case |
|---|---|---|
| `.high` / `.userInitiated` | `.userInitiated` | User-triggered actions |
| `.medium` | `.default` | Default, inherited |
| `.low` / `.utility` | `.utility` | Long-running background work |
| `.background` | `.background` | Maintenance, not time-sensitive |

**Key rules:**
1. `Task { }` (unstructured task) **inherits** the priority and actor context
   of the caller. If called from a `@MainActor` context, the child task
   inherits `.userInitiated` priority.
2. `Task.detached(priority:) { }` does **not** inherit priority or actor
   context. Use this when you want explicit control.
3. **Priority escalation**: If a high-priority task awaits a result from a
   `.utility` actor method, the runtime may temporarily escalate the actor's
   effective priority. This is a feature, not a bug -- it prevents priority
   inversion.

**Recommended pattern:**

```swift
@MainActor
final class AppState {
    let monitor = ProcessMonitor()
    private var pollingTask: Task<Void, Never>?

    func startPolling() {
        // Use .detached to avoid inheriting @MainActor and its high priority
        pollingTask = Task.detached(priority: .utility) { [monitor] in
            while !Task.isCancelled {
                let snapshot = await monitor.collectAll()

                // Hop back to MainActor to update UI state
                await MainActor.run {
                    self.updateGroups(from: snapshot)
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
    }
}
```

**How priority interacts with actors:**
- An actor does not have an inherent priority. The priority of work running on
  an actor is determined by the priority of the task that called the actor method.
- If multiple tasks are queued waiting for actor access, the runtime serves
  higher-priority tasks first (the actor's mailbox is priority-ordered).
- This means your `.utility` polling task will naturally defer to any
  `.userInitiated` task that needs the same actor.

**Recommendation for Total Recall:**
- Use `.utility` (not `.background`) for the polling task. `.background` is
  too low -- macOS may defer it significantly under load, causing stale data.
- Use `Task.detached` to prevent inheriting `@MainActor` priority.

### Sources
- [TaskPriority (Apple Developer Documentation)](https://developer.apple.com/documentation/swift/taskpriority)
- [How to control the priority of a task (Hacking with Swift)](https://www.hackingwithswift.com/quick-start/concurrency/how-to-control-the-priority-of-a-task)
- [Swift Concurrency Part 1: Tasks, Executors, and Priority Escalation (Nick Vasilev)](https://nsvasilev.medium.com/swift-concurrency-part-1-e1d0c7c4abbc)

---

## 3. ContinuousClock and Elapsed Time Budgeting

### Answer: Use `ContinuousClock` (not `SuspendingClock`) to measure wall-clock time, including time spent suspended.

**Why ContinuousClock:**
- `ContinuousClock` keeps ticking even when the system sleeps. It measures
  real wall-clock time.
- `SuspendingClock` pauses when the system sleeps. Not suitable for
  user-perceived latency budgeting.

**Two approaches to budgeted collection:**

### Approach A: Measure elapsed time, bail out when budget exceeded

```swift
actor ProcessMonitor {
    /// Collect process info with a time budget.
    /// Returns partial results if the budget is exceeded.
    func collectWithBudget(
        pids: [pid_t],
        budget: Duration = .milliseconds(50)
    ) async -> (snapshots: [ProcessSnapshot], completed: Bool) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        var results: [ProcessSnapshot] = []
        results.reserveCapacity(pids.count)

        for (index, pid) in pids.enumerated() {
            // Check budget every 20 iterations (avoid clock overhead per-pid)
            if index.isMultiple(of: 20) {
                if clock.now >= deadline {
                    return (results, completed: false)
                }
                await Task.yield()
            }

            // Check cancellation less frequently
            if index.isMultiple(of: 100), Task.isCancelled {
                return (results, completed: false)
            }

            let snapshot = readProcessInfo(pid: pid)
            results.append(snapshot)
        }
        return (results, completed: true)
    }
}
```

### Approach B: Use ContinuousClock.measure to profile the whole operation

```swift
let clock = ContinuousClock()
let elapsed = await clock.measure {
    snapshots = await monitor.collectAll(pids: pids)
}
logger.info("Collection took \(elapsed)")  // e.g., "0.023 seconds"

// Adjust next interval based on how long collection took
let nextInterval = max(Duration.seconds(5) - elapsed, .seconds(1))
```

### Approach C: Measure individual phases

```swift
let clock = ContinuousClock()

let rusageTime = await clock.measure {
    await collectRusage(pids: pids)
}
let pidInfoTime = await clock.measure {
    await collectPidInfo(pids: newPids)
}

logger.debug("""
    rusage: \(rusageTime), \
    pidinfo: \(pidInfoTime), \
    total pids: \(pids.count)
    """)
```

**Cost of clock reads:** `ContinuousClock.now` maps to
`clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` on macOS, which is ~20-50ns. Safe
to call every 20 iterations without meaningful overhead.

### Sources
- [ContinuousClock (Apple Developer Documentation)](https://developer.apple.com/documentation/swift/continuousclock)
- [Clock, Instant, and Duration (Hacking with Swift)](https://www.hackingwithswift.com/swift/5.7/clock)
- [SE-0329: Clock, Instant, Duration](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0329-clock-instant-duration.md)

---

## 4. Cooperative Cancellation

### Answer: Yes, and you should check for it. Swift never force-stops a task.

Swift uses a **cooperative cancellation** model. Calling `task.cancel()` sets a
flag but does not interrupt the task. The task must check for cancellation and
decide how to respond.

**Three mechanisms:**

| Mechanism | Behavior | Use When |
|---|---|---|
| `Task.isCancelled` | Returns `Bool`, non-throwing | You want to return partial results |
| `try Task.checkCancellation()` | Throws `CancellationError` | You want to propagate cancellation as an error |
| `withTaskCancellationHandler` | Runs a synchronous closure when cancellation occurs | You need side effects on cancel (e.g., abort a network request) |

**Recommended pattern for Total Recall:**

```swift
actor ProcessMonitor {
    func collectAll(pids: [pid_t]) async -> [ProcessSnapshot] {
        var results: [ProcessSnapshot] = []
        results.reserveCapacity(pids.count)

        for (index, pid) in pids.enumerated() {
            // Check cancellation periodically (not every iteration -- it's cheap
            // but the branch adds up over 800 iterations)
            if index.isMultiple(of: 50) {
                if Task.isCancelled {
                    // Return whatever we have so far
                    return results
                }
                await Task.yield()
            }

            let snapshot = readProcessInfo(pid: pid)
            results.append(snapshot)
        }
        return results
    }
}
```

**Window close cancellation pattern:**

```swift
struct InspectionWindowView: View {
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        ProcessListView()
            .task {
                // .task automatically cancels when the view disappears
                while !Task.isCancelled {
                    await refreshData()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
    }
}
```

The SwiftUI `.task` modifier is ideal here -- it automatically cancels the task
when the view is removed from the hierarchy (e.g., when the window closes).
`Task.sleep` also responds to cancellation by throwing `CancellationError`,
which exits the `while` loop.

**withTaskCancellationHandler for cleanup:**

```swift
func collectWithCancellation(pids: [pid_t]) async -> [ProcessSnapshot] {
    var shouldStop = false

    return await withTaskCancellationHandler {
        var results: [ProcessSnapshot] = []
        for pid in pids {
            if shouldStop || Task.isCancelled { break }
            results.append(readProcessInfo(pid: pid))
        }
        return results
    } onCancel: {
        // Runs immediately on the cancelling thread (synchronous, Sendable)
        // Can set a flag or signal, but cannot access actor state
        shouldStop = true
    }
}
```

Note: The `onCancel` closure runs synchronously on whatever thread calls
`cancel()`. It must be `@Sendable` and cannot access actor-isolated state.
For your use case, `Task.isCancelled` checks in the loop are simpler and
sufficient.

### Sources
- [Task Cancellation in Swift Concurrency (Swift with Majid, Feb 2025)](https://swiftwithmajid.com/2025/02/11/task-cancellation-in-swift-concurrency/)
- [How to cancel a Task (Hacking with Swift)](https://www.hackingwithswift.com/quick-start/concurrency/how-to-cancel-a-task)
- [Mastering Modern Concurrency Part 7: Cancellation & Error Handling](https://medium.com/@alokupadhyay1192/mastering-modern-concurrency-in-swift-part-7-cancellation-error-handling-523ee97a4e27)

---

## 5. DispatchQueue.global(qos:) vs Actor Isolation

### Answer: For your specific case (many fast synchronous C calls), an actor is fine. But know the trade-offs.

**The core tension:**
- Swift actors run on the **cooperative thread pool**. This pool is sized to
  the number of CPU cores (e.g., 10 threads on an M1 Pro).
- The cooperative pool expects tasks to yield frequently. A task that blocks
  (I/O, locks, long computation) without yielding **starves** other tasks.
- `proc_pid_rusage` is a fast syscall (~1-5us). 800 calls = ~0.8-4ms. This is
  **not** blocking in the traditional sense -- it is short synchronous work.
- `KERN_PROCARGS2` via `sysctl` can be slower (10-100us+ per call, involves
  copying variable-length data from kernel). For 800 processes, this could be
  8-80ms.

**Decision framework:**

| Scenario | Recommendation |
|---|---|
| `proc_pid_rusage` loop (800 x 1-5us) | Actor is fine. Insert `Task.yield()` every 50 iterations. Total ~4ms. |
| `proc_pidinfo` loop (800 x 2-10us) | Actor is fine. Same yield pattern. |
| `KERN_PROCARGS2` for new PIDs only (cached) | Actor is fine if only ~20-50 new PIDs per cycle. |
| `KERN_PROCARGS2` for ALL PIDs (cold start) | Consider offloading to GCD. 800 x 50us = 40ms of blocking. |
| Future: concurrent collection of multiple APIs | Use `withTaskExecutorPreference` or GCD. |

### Option A: Stay on the actor (recommended for MVP)

```swift
actor ProcessMonitor {
    // Fast path: cached process info
    private var pidCache: [pid_t: CachedProcessInfo] = [:]

    func collect(pids: [pid_t]) async -> [ProcessSnapshot] {
        var results: [ProcessSnapshot] = []
        let newPids = pids.filter { pidCache[$0] == nil }

        // Phase 1: Fast rusage for all PIDs (on actor, ~4ms for 800 PIDs)
        for (i, pid) in pids.enumerated() {
            if i.isMultiple(of: 50) { await Task.yield() }
            results.append(readRusage(pid: pid))
        }

        // Phase 2: Expensive KERN_PROCARGS2 only for new PIDs (on actor)
        for (i, pid) in newPids.enumerated() {
            if i.isMultiple(of: 10) { await Task.yield() }
            pidCache[pid] = readCommandLineArgs(pid: pid)
        }

        return results
    }
}
```

### Option B: Offload blocking work to GCD via withCheckedContinuation

```swift
actor ProcessMonitor {
    private let syscallQueue = DispatchQueue(
        label: "com.totalrecall.syscalls",
        qos: .utility,
        attributes: .concurrent
    )

    func collectExpensive(pids: [pid_t]) async -> [CommandLineInfo] {
        await withCheckedContinuation { continuation in
            syscallQueue.async {
                // This runs on GCD, NOT the cooperative pool
                var results: [CommandLineInfo] = []
                for pid in pids {
                    results.append(self.readCommandLineArgs(pid: pid))
                }
                continuation.resume(returning: results)
            }
        }
    }
}
```

**Warning:** The `readCommandLineArgs` call inside the GCD block cannot access
actor-isolated state without a data race. You would need to make
`readCommandLineArgs` a `nonisolated` method or a free function.

### Option C: withTaskExecutorPreference (Swift 6+, SE-0417)

This is the modern approach for offloading blocking work while staying in the
structured concurrency world:

```swift
import Dispatch

// Create a GCD-backed executor for blocking work
let blockingExecutor = DispatchQueue(
    label: "com.totalrecall.blocking",
    qos: .utility
)

func collectOnDedicatedQueue(pids: [pid_t]) async -> [ProcessSnapshot] {
    await withTaskExecutorPreference(blockingExecutor) {
        // This closure runs on the DispatchQueue, not the cooperative pool.
        // But it still participates in structured concurrency (cancellation,
        // priority, task-local values).
        var results: [ProcessSnapshot] = []
        for pid in pids {
            results.append(readProcessInfo(pid: pid))
        }
        return results
    }
}
```

**Note:** `withTaskExecutorPreference` requires the executor to conform to
`TaskExecutor`. As of Swift 6, `DispatchSerialQueue` conforms to
`TaskExecutor`. For concurrent dispatch queues, you may need a wrapper.

### Recommendation for Total Recall

Start with **Option A** (actor + yield). Your fast-path syscalls
(`proc_pid_rusage`, `proc_pidinfo`) are fast enough. Cache `KERN_PROCARGS2`
aggressively so only new PIDs trigger the expensive call. Monitor actual
collection times with `ContinuousClock.measure`. If collection consistently
exceeds 30-50ms, move to Option C.

### Sources
- [Actors, the cooperative pool and concurrency (try Code)](https://trycombine.com/posts/swift-actor-dispatch-queues-concurrency/)
- [SE-0417: Task Executor Preference](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0417-task-executor-preference.md)
- [Swift Concurrency Under Your Control (Mateusz Kosikowski)](https://medium.com/@mateusz.kosikowski/swift-concurrency-under-your-control-crafting-thread-pinned-and-pool-bound-executors-baecafcfa2e5)
- [How to currently offload stateless blocking work? (Swift Forums)](https://forums.swift.org/t/how-to-currently-offload-stateless-blocking-work-hidden-executor-api/59128)
- [withTaskExecutorPreference (Apple Developer Documentation)](https://developer.apple.com/documentation/swift/withtaskexecutorpreference(_:isolation:operation:))

---

## 6. Batching Syscalls

### Answer: Each proc_* call is independent. Batching does not reduce kernel overhead, but strategic ordering and caching matters.

**Key facts about the libproc APIs:**

1. **`proc_pid_rusage`**: One syscall per PID. There is no batch API. Each call
   enters the kernel, looks up the task struct, copies out rusage_info. ~1-5us
   per call. For 800 PIDs: ~0.8-4ms total. This is cheap enough to call for
   every PID every cycle.

2. **`proc_pidinfo`**: One syscall per PID per flavor. Same as above. ~2-10us.

3. **`proc_pidpath`**: One syscall per PID. Returns the executable path. ~5-20us.
   **Cache this** -- a process's path never changes during its lifetime.

4. **`sysctl KERN_PROCARGS2`**: One syscall per PID. The most expensive call
   (~10-100us) because it copies variable-length argument data from kernel
   space. **Must be cached** -- arguments do not change after exec.

5. **`proc_listallpids`**: One syscall that returns all PIDs. ~50-200us for
   500-1000 PIDs. Call once per cycle.

**Can multiple be issued concurrently?**

Yes, but with caveats:
- The calls are thread-safe (they read kernel state, no process-side mutation).
- You could use `withTaskGroup` to issue calls concurrently:

```swift
func collectConcurrently(pids: [pid_t]) async -> [ProcessSnapshot] {
    await withTaskGroup(of: ProcessSnapshot?.self) { group in
        for pid in pids {
            group.addTask {
                readProcessInfo(pid: pid) // synchronous, but very fast
            }
        }

        var results: [ProcessSnapshot] = []
        for await snapshot in group {
            if let snapshot { results.append(snapshot) }
        }
        return results
    }
}
```

**However, this is likely counterproductive for your case:**
- Each `proc_pid_rusage` call takes ~1-5us. The overhead of creating a child
  task, scheduling it, and collecting results is comparable to the call itself.
- Task creation overhead is ~1-2us per task.
- For 800 tasks of 1-5us each, you spend as much time on task management as
  on the actual syscalls.
- The cooperative pool has ~10 threads. You cannot actually run 800 syscalls
  in parallel.

**Recommended strategy: Sequential with smart caching**

```swift
actor ProcessMonitor {
    // Cache stable data (path, args) -- only fetch for new PIDs
    private var processCache: [pid_t: CachedProcessInfo] = [:]
    private var knownPids: Set<pid_t> = []

    struct CachedProcessInfo {
        let path: String
        let commandLineArgs: [String]
        let firstSeen: ContinuousClock.Instant
    }

    func collect() async -> CollectionResult {
        let clock = ContinuousClock()

        // Phase 1: Enumerate all PIDs (~100us)
        let allPids = listAllPids()
        let currentPidSet = Set(allPids)
        let newPids = currentPidSet.subtracting(knownPids)
        let exitedPids = knownPids.subtracting(currentPidSet)

        // Phase 2: Fast rusage for ALL PIDs (~4ms for 800 PIDs)
        // This is the hot path -- do it every cycle
        var snapshots: [ProcessSnapshot] = []
        for (i, pid) in allPids.enumerated() {
            if i.isMultiple(of: 50) { await Task.yield() }
            if Task.isCancelled { break }
            snapshots.append(readRusage(pid: pid))
        }

        // Phase 3: Expensive metadata for NEW PIDs only
        // Typically 10-50 new PIDs per cycle after initial cold start
        for (i, pid) in newPids.enumerated() {
            if i.isMultiple(of: 10) { await Task.yield() }
            if Task.isCancelled { break }

            let path = readPidPath(pid: pid)
            let args = readCommandLineArgs(pid: pid)
            processCache[pid] = CachedProcessInfo(
                path: path,
                commandLineArgs: args,
                firstSeen: clock.now
            )
        }

        // Phase 4: Clean up exited PIDs from cache
        for pid in exitedPids {
            processCache.removeValue(forKey: pid)
        }
        knownPids = currentPidSet

        return CollectionResult(snapshots: snapshots, newPids: newPids)
    }
}
```

**Why sequential is better than concurrent here:**
1. Syscalls are fast enough that parallelism overhead exceeds the benefit.
2. Sequential access has better cache locality (kernel data structures).
3. An actor serializes access anyway, so internal parallelism would require
   leaving the actor.
4. Budget checking and cancellation are simpler in a sequential loop.

### Sources
- [proc_pidinfo library (GitHub)](https://github.com/mmastrac/proc_pidinfo)
- [ProcInfo (Objective-See)](https://github.com/objective-see/ProcInfo)
- [Obtaining CPU usage by process (Apple Developer Forums)](https://developer.apple.com/forums/thread/655349)

---

## 7. Memory Pressure Awareness

### Answer: Yes. Use `DispatchSource.makeMemoryPressureSource` to detect system memory pressure and adjust polling.

macOS provides kernel-level memory pressure notifications via
`DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`. Three levels:

| Level | Constant | Meaning |
|---|---|---|
| Normal | `DISPATCH_MEMORYPRESSURE_NORMAL` | System is fine |
| Warning | `DISPATCH_MEMORYPRESSURE_WARN` | Moderate pressure, start reducing |
| Critical | `DISPATCH_MEMORYPRESSURE_CRITICAL` | Heavy pressure, reduce aggressively |

**Implementation:**

```swift
@Observable
final class MemoryPressureMonitor {
    enum PressureLevel: Sendable {
        case normal, warning, critical
    }

    private(set) var currentLevel: PressureLevel = .normal
    private var source: DispatchSourceMemoryPressure?

    init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let event = source.data
            if event.contains(.critical) {
                self.currentLevel = .critical
            } else if event.contains(.warning) {
                self.currentLevel = .warning
            }
        }

        source?.setCancelHandler { [weak self] in
            self?.currentLevel = .normal
        }

        source?.activate()
    }

    deinit {
        source?.cancel()
    }
}
```

**Integrating with the polling loop:**

```swift
@MainActor
final class AppState {
    let pressureMonitor = MemoryPressureMonitor()
    let processMonitor = ProcessMonitor()

    var pollingInterval: Duration {
        switch pressureMonitor.currentLevel {
        case .normal:   return .seconds(5)
        case .warning:  return .seconds(10)   // Reduce frequency
        case .critical: return .seconds(30)   // Minimal polling
        }
    }

    func startPolling() {
        Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await self.pollingInterval
                await self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }
}
```

**Important caveat:** The dispatch source only fires on *transitions*. If the
app launches while the system is already under pressure, the handler will NOT
fire. To handle this, also check pressure at launch:

```swift
import Darwin

func getCurrentMemoryPressure() -> MemoryPressureMonitor.PressureLevel {
    // Use host_statistics64 to check current VM stats
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return .normal }

    // Heuristic: if free + inactive pages < 10% of total, we're under pressure
    let pageSize = UInt64(vm_kernel_page_size)
    let free = UInt64(stats.free_count) * pageSize
    let inactive = UInt64(stats.inactive_count) * pageSize
    let total = ProcessInfo.processInfo.physicalMemory
    let availableRatio = Double(free + inactive) / Double(total)

    if availableRatio < 0.05 { return .critical }
    if availableRatio < 0.15 { return .warning }
    return .normal
}
```

**Additional strategy -- reduce Total Recall's own memory during pressure:**

```swift
actor ProcessMonitor {
    private var pidCache: [pid_t: CachedProcessInfo] = [:]

    func reduceMemoryFootprint() {
        // Drop the cache -- will be rebuilt on next cycle
        pidCache.removeAll(keepingCapacity: false)
    }
}
```

### Sources
- [DISPATCH_SOURCE_TYPE_MEMORYPRESSURE (Apple Developer Documentation)](https://developer.apple.com/documentation/dispatch/dispatch_source_type_memorypressure)
- [DispatchSourceMemoryPressure (Apple Developer Documentation)](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure)
- [makeMemoryPressureSource (Apple Developer Documentation)](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:))
- [Memory Pressure source example (GitHub Gist)](https://gist.github.com/steipete/33af275cc1cb419b0f01)

---

## Putting It All Together

Here is a complete skeleton showing all seven concerns integrated:

```swift
import Foundation
import os

// MARK: - Memory Pressure Monitor

@Observable
final class MemoryPressureMonitor: @unchecked Sendable {
    enum Level: Sendable { case normal, warning, critical }
    private(set) var level: Level = .normal
    private var source: DispatchSourceMemoryPressure?

    init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source?.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            if source.data.contains(.critical) {
                self.level = .critical
            } else if source.data.contains(.warning) {
                self.level = .warning
            } else {
                self.level = .normal
            }
        }
        source?.activate()
    }

    deinit { source?.cancel() }
}

// MARK: - Process Monitor Actor

actor ProcessMonitor {
    private let logger = Logger(
        subsystem: "com.totalrecall", category: "ProcessMonitor"
    )
    private var pidCache: [pid_t: CachedProcessInfo] = [:]
    private var knownPids: Set<pid_t> = []

    struct CachedProcessInfo: Sendable {
        let path: String
        let args: [String]
    }

    struct CollectionResult: Sendable {
        let snapshots: [ProcessSnapshot]
        let elapsed: Duration
        let completed: Bool
        let pidCount: Int
    }

    /// Collect process data with time budget and cancellation support.
    func collect(budget: Duration = .milliseconds(80)) async -> CollectionResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        let startTime = clock.now

        // Phase 1: Enumerate PIDs
        let allPids = listAllPids()
        let pidSet = Set(allPids)
        let newPids = pidSet.subtracting(knownPids)
        let exitedPids = knownPids.subtracting(pidSet)

        // Clean exited PIDs from cache
        for pid in exitedPids { pidCache.removeValue(forKey: pid) }
        knownPids = pidSet

        // Phase 2: Fast rusage scan (hot path, every cycle)
        var snapshots: [ProcessSnapshot] = []
        snapshots.reserveCapacity(allPids.count)
        var completed = true

        for (i, pid) in allPids.enumerated() {
            if i.isMultiple(of: 50) {
                // Budget check + cancellation + yield
                if Task.isCancelled || clock.now >= deadline {
                    completed = false
                    break
                }
                await Task.yield()
            }
            snapshots.append(readRusage(pid: pid))
        }

        // Phase 3: Expensive metadata for new PIDs only
        if completed {
            for (i, pid) in newPids.enumerated() {
                if i.isMultiple(of: 10) {
                    if Task.isCancelled || clock.now >= deadline {
                        completed = false
                        break
                    }
                    await Task.yield()
                }
                let path = readPidPath(pid: pid)
                let args = readCommandLineArgs(pid: pid)
                pidCache[pid] = CachedProcessInfo(path: path, args: args)
            }
        }

        let elapsed = clock.now - startTime
        logger.debug(
            "Collected \(snapshots.count)/\(allPids.count) PIDs in \(elapsed)"
        )

        return CollectionResult(
            snapshots: snapshots,
            elapsed: elapsed,
            completed: completed,
            pidCount: allPids.count
        )
    }

    func dropCaches() {
        pidCache.removeAll(keepingCapacity: false)
    }
}

// MARK: - App State (UI-facing)

@MainActor @Observable
final class AppState {
    private(set) var groups: [SmartGroup] = []
    private(set) var lastCollectionTime: Duration = .zero
    private(set) var isCollecting = false

    let monitor = ProcessMonitor()
    let pressureMonitor = MemoryPressureMonitor()
    private var pollingTask: Task<Void, Never>?

    var pollingInterval: Duration {
        switch pressureMonitor.level {
        case .normal:   .seconds(5)
        case .warning:  .seconds(10)
        case .critical: .seconds(30)
        }
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await self.pollingInterval

                let result = await self.monitor.collect()

                await MainActor.run {
                    self.lastCollectionTime = result.elapsed
                    self.groups = ProfileRegistry.classify(
                        snapshots: result.snapshots
                    )
                }

                // If memory pressure is critical, also drop caches
                if await self.pressureMonitor.level == .critical {
                    await self.monitor.dropCaches()
                }

                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
```

---

## Summary of Recommendations

| Question | Recommendation |
|---|---|
| **Task.yield()** | Use it every ~50 iterations in the PID loop. It is cheap when nothing is waiting, and creates necessary suspension points for the cooperative pool. |
| **Task priority** | Use `Task.detached(priority: .utility)` for the polling loop. Do NOT use `Task { }` from `@MainActor` context (inherits high priority). |
| **Time budgeting** | Use `ContinuousClock` to measure elapsed time. Check budget every ~20 iterations. Return partial results if exceeded. |
| **Cancellation** | Check `Task.isCancelled` every ~50 iterations. Use SwiftUI `.task` modifier for automatic cancellation on view disappearance. Return partial results rather than throwing. |
| **Actor vs GCD** | Start with an actor for MVP. The fast syscalls (rusage, pidinfo) are fine on the cooperative pool. Cache KERN_PROCARGS2 so only new PIDs trigger it. Upgrade to `withTaskExecutorPreference` if profiling shows starvation. |
| **Batching syscalls** | Do not parallelize -- sequential with smart caching is better. Task creation overhead exceeds the syscall time. Cache paths and args; refresh rusage every cycle. |
| **Memory pressure** | Use `DispatchSource.makeMemoryPressureSource` to detect pressure. Increase polling interval under warning/critical. Drop caches under critical pressure. Also check pressure at launch via `host_statistics64`. |
