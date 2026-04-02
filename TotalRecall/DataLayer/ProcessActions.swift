import Foundation
import os.log

private let logger = Logger(subsystem: "com.totalrecall.app", category: "ProcessActions")

/// Safe process termination with PID-reuse verification and denylist.
public enum ProcessActions {

    public enum KillError: Error, LocalizedError {
        case processExited
        case pidRecycled
        case permissionDenied
        case protectedProcess(String)
        case selfKill
        case unknownError(Int32)

        public var errorDescription: String? {
            switch self {
            case .processExited: return "Process has already exited."
            case .pidRecycled: return "Process ID was reused by a different process."
            case .permissionDenied: return "Permission denied. Cannot terminate system processes."
            case .protectedProcess(let name): return "'\(name)' is a protected system process."
            case .selfKill: return "Cannot terminate Total Recall itself."
            case .unknownError(let code): return "Failed to terminate process (error \(code))."
            }
        }
    }

    /// Protected process names that should never be killed.
    private static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow",
        "opendirectoryd", "diskarbitrationd", "CoreServicesUIAgent",
        "runningboardd",
    ]

    /// Send a signal to a process after verifying its identity.
    /// - Parameters:
    ///   - signal: SIGTERM (15) or SIGKILL (9)
    ///   - identity: The ProcessIdentity captured at snapshot time
    public static func sendSignal(_ signal: Int32, to identity: ProcessIdentity) throws {
        // Self-protection
        guard identity.pid != ProcessInfo.processInfo.processIdentifier else {
            throw KillError.selfKill
        }

        // Check denylist
        let execName = (identity.executablePath as NSString).lastPathComponent
        if protectedNames.contains(execName) {
            throw KillError.protectedProcess(execName)
        }

        // PID 0 (kernel) and PID 1 (launchd) are always protected
        if identity.pid <= 1 {
            throw KillError.protectedProcess(execName.isEmpty ? "PID \(identity.pid)" : execName)
        }

        // Verify PID hasn't been recycled by checking identity
        guard let currentBSD = SystemProbe.getBSDInfo(pid: identity.pid) else {
            throw KillError.processExited
        }

        if currentBSD.startTimeSec != identity.startTimeSec ||
           currentBSD.startTimeUsec != identity.startTimeUsec {
            throw KillError.pidRecycled
        }

        // Check we're not trying to kill a different user's process
        if currentBSD.uid != getuid() {
            throw KillError.permissionDenied
        }

        // Send the signal
        let signalName = signal == SIGTERM ? "SIGTERM" : signal == SIGKILL ? "SIGKILL" : "signal(\(signal))"
        logger.info("Sending \(signalName) to PID \(identity.pid) (\(execName))")

        let result = kill(identity.pid, signal)
        if result != 0 {
            let err = errno
            logger.error("kill() failed for PID \(identity.pid): errno=\(err)")
            switch err {
            case ESRCH: throw KillError.processExited
            case EPERM: throw KillError.permissionDenied
            default: throw KillError.unknownError(err)
            }
        }

        logger.info("Successfully sent \(signalName) to PID \(identity.pid) (\(execName))")
    }

    /// Send a signal to all processes in a group.
    public static func sendSignalToAll(_ signal: Int32, in group: ProcessGroup) -> [(ProcessIdentity, KillError)] {
        var errors: [(ProcessIdentity, KillError)] = []

        for process in group.processes {
            do {
                try sendSignal(signal, to: process.processIdentity)
            } catch let error as KillError {
                errors.append((process.processIdentity, error))
            } catch {
                errors.append((process.processIdentity, .unknownError(-1)))
            }
        }

        return errors
    }

    /// Check if kill actions should be available for a group.
    public static func isGroupKillable(_ group: ProcessGroup) -> Bool {
        group.classifierName != "System"
    }
}
