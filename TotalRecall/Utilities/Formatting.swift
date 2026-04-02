import Foundation

public enum MemoryFormatter {
    public static func format(bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.0f KB", kb)
        }
    }

    public static func formatCompact(bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1f", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }

    /// Format as "12.4 / 16.0 GB" for the menu bar.
    public static func formatUsedTotal(used: UInt64, total: UInt64) -> String {
        let usedGB = Double(used) / (1024 * 1024 * 1024)
        let totalGB = Double(total) / (1024 * 1024 * 1024)
        return String(format: "%.1f / %.0f GB", usedGB, totalGB)
    }
}
