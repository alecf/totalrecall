import TotalRecallCore
import SwiftUI

/// A tiny line chart of a group's deduplicated memory footprint over the last
/// ~2 minutes. The shape is the signal: a sawtooth reads as GC churn, a steady
/// ramp as a likely leak, a step as a discrete event, a spike-and-recover as a
/// transient. Values are normalized to the series' own min/max, so this shows
/// the *shape* of change, not the absolute scale (the memory number does that).
struct SparklineView: View {
    let history: [UInt64]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let points = SparklineLayout.points(
                history: history,
                size: size,
                lineWidth: Theme.sparklineLineWidth
            )

            guard points.count >= 2 else {
                drawBaseline(in: &context, size: size)
                return
            }

            var line = Path()
            line.addLines(points)

            // Soft fill under the line for body, then the line itself on top.
            var area = line
            area.addLine(to: CGPoint(x: points.last!.x, y: size.height))
            area.addLine(to: CGPoint(x: points.first!.x, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .color(color.opacity(0.18)))
            context.stroke(
                line,
                with: .color(color),
                style: StrokeStyle(lineWidth: Theme.sparklineLineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: Theme.sparklineWidth, height: Theme.sparklineHeight)
        .help(tooltip)
    }

    /// Fewer than two samples: nothing to chart yet, so show a faint baseline
    /// rather than an empty gap while history accumulates.
    private func drawBaseline(in context: inout GraphicsContext, size: CGSize) {
        var baseline = Path()
        let midY = size.height / 2
        baseline.move(to: CGPoint(x: 0, y: midY))
        baseline.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(
            baseline,
            with: .color(color.opacity(0.3)),
            style: StrokeStyle(lineWidth: Theme.sparklineLineWidth, lineCap: .round)
        )
    }

    private var tooltip: String {
        guard let first = history.first, let last = history.last, history.count >= 2 else {
            return "Memory history (collecting…)"
        }
        let from = MemoryFormatter.format(bytes: first)
        let to = MemoryFormatter.format(bytes: last)
        return "Memory over the last \(history.count) samples: \(from) → \(to)"
    }
}

extension SparklineView {
    /// Build from a group. The line is drawn in the resident tone rather than
    /// varying by memory state: a sparkline carries its meaning in its shape,
    /// and tinting it would mean blending the two memory tones — which is the
    /// muddy middle the river's two-tone fill exists to avoid.
    init(group: ProcessGroup) {
        self.init(
            history: group.footprintHistory,
            color: Theme.memoryResident
        )
    }
}
