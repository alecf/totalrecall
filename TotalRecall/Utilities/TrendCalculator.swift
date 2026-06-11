import Foundation

/// Computes a `Trend` direction by comparing a group's current memory
/// footprint against the oldest sample in its rolling history window.
public enum TrendCalculator {
    /// Footprint change ratio beyond which a trend is considered up/down
    /// rather than stable.
    public static let changeThreshold = 0.05

    /// - Parameters:
    ///   - currentFootprint: The group's deduplicated footprint this snapshot.
    ///   - history: Footprints from previous snapshots, oldest first.
    ///   - windowSize: Maximum number of samples considered from `history`.
    public static func computeTrend(currentFootprint: UInt64, history: [UInt64], windowSize: Int) -> Trend {
        guard history.count >= 2 else { return .unknown }

        let recent = history.suffix(windowSize)
        guard let oldest = recent.first else { return .unknown }
        guard oldest > 0 else { return .unknown }

        let changeRatio = Double(currentFootprint) / Double(oldest) - 1.0

        if changeRatio > changeThreshold { return .up }
        if changeRatio < -changeThreshold { return .down }
        return .stable
    }
}
