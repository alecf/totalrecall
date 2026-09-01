import TotalRecallCore
import SwiftUI

/// A chip in one of the two memory tones, drawn beside the word it names.
///
/// Shaped like a miniature river segment — a small rounded rectangle, not a
/// dot. Circles already mean memory pressure in the summary stats, and a
/// swatch that echoes the bar it explains is easier to match back to the bar.
struct MemorySwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.keySwatchCornerRadius)
            .fill(color)
            .frame(width: Theme.keySwatchSize, height: Theme.keySwatchSize)
    }
}

/// The window's key: blue is memory the app is holding in physical RAM right
/// now, amber is memory macOS has compressed or written to swap.
///
/// Only two colors ever appear in the app, and both of them carry the one
/// distinction the app exists to show — so the key is a fixture of the main
/// window rather than something to hunt for in a menu. It occupies the row
/// beneath the Memory River that the hover readout already reserves, so it
/// costs no layout: the key stands there until you hover a segment, at which
/// point the readout answers the same question with that segment's numbers.
struct MemoryKeyView: View {
    /// Drop the glosses where the surrounding text already explains the split
    /// (the detail panel) or where the row is too narrow to carry them.
    var showGlosses = true

    var body: some View {
        HStack(spacing: 14) {
            entry(
                color: Theme.memoryResident,
                term: Theme.residentLabel,
                gloss: Theme.residentGloss
            )
            entry(
                color: Theme.memoryCompressed,
                term: Theme.nonResidentLabelLong,
                gloss: Theme.nonResidentGloss
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func entry(color: Color, term: String, gloss: String) -> some View {
        HStack(spacing: 5) {
            MemorySwatch(color: color)
            Text(term)
                .font(Theme.secondaryFont)
                .foregroundStyle(color)
            if showGlosses {
                Text("— \(gloss)")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var accessibilityText: String {
        "Key: blue is \(Theme.residentLabel), \(Theme.residentGloss). "
            + "Amber is \(Theme.nonResidentLabelLong), \(Theme.nonResidentGloss)."
    }
}
