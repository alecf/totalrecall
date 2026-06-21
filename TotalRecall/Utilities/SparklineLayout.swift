import CoreGraphics

/// Maps a series of memory footprints to points inside a sparkline's drawing
/// rect. The newest sample sits at the right edge; values are normalized
/// against the series' own min/max so the shape — not the absolute scale —
/// is what reads at a glance.
public enum SparklineLayout {
    /// - Parameters:
    ///   - history: Footprints over time, oldest first, newest last.
    ///   - size: The drawing area. Points are inset by `lineWidth / 2` on the
    ///     vertical axis so a stroked line never clips at the top or bottom.
    ///   - lineWidth: Stroke width the caller will use for the line.
    /// - Returns: One point per sample, left-to-right. Empty when there is
    ///   nothing to draw; a single sample yields one point at the right edge.
    public static func points(
        history: [UInt64],
        size: CGSize,
        lineWidth: CGFloat = 1.5
    ) -> [CGPoint] {
        guard !history.isEmpty, size.width > 0, size.height > 0 else { return [] }

        let inset = lineWidth / 2
        let usableHeight = max(0, size.height - lineWidth)
        let minValue = history.min() ?? 0
        let maxValue = history.max() ?? 0
        let range = maxValue > minValue ? Double(maxValue - minValue) : 0

        // A single point pins to the right edge so it reads as "now".
        let stepX = history.count > 1 ? size.width / CGFloat(history.count - 1) : 0

        return history.enumerated().map { index, value in
            let x = history.count > 1 ? CGFloat(index) * stepX : size.width
            // Flat series (range 0) draws through the vertical center.
            let fraction = range > 0 ? Double(value - minValue) / range : 0.5
            // Larger memory should sit higher, so invert against the rect's
            // top-left origin.
            let y = inset + usableHeight * (1 - CGFloat(fraction))
            return CGPoint(x: x, y: y)
        }
    }
}
