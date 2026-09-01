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
    /// Glossed if it fits, bare terms if not.
    ///
    /// The glossed row measures ~523 pt in `secondaryFont`, but the inspection
    /// window's own `minWidth` of 600 leaves this row only ~488 pt once the
    /// horizontal padding and the river's left gutter are taken out — so at the
    /// smallest size the user can drag to, the glosses do not fit. Dropping to
    /// the bare terms (~202 pt) keeps the swatches and the two words, which are
    /// the part that actually keys the colors; the glosses are the elaboration
    /// and are the right thing to lose first. Truncating instead would cut the
    /// second entry's *term*, which is the one thing that must survive.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(withGlosses: true)
            row(withGlosses: false)
        }
        .accessibilityElement(children: .combine)
        // Always the full wording, whichever row was drawn — VoiceOver has no
        // width to run out of.
        .accessibilityLabel(accessibilityText)
    }

    private func row(withGlosses: Bool) -> some View {
        HStack(spacing: 14) {
            entry(
                color: Theme.memoryResident,
                term: Theme.residentLabel,
                gloss: withGlosses ? Theme.residentGloss : nil
            )
            entry(
                color: Theme.memoryCompressed,
                term: Theme.nonResidentLabelLong,
                gloss: withGlosses ? Theme.nonResidentGloss : nil
            )
        }
    }

    private func entry(color: Color, term: String, gloss: String?) -> some View {
        HStack(spacing: 5) {
            MemorySwatch(color: color)
            Text(term)
                .font(Theme.secondaryFont)
                .foregroundStyle(color)
            if let gloss {
                Text("— \(gloss)")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .lineLimit(1)
        // Each row reports its true width so `ViewThatFits` can reject the
        // glossed one instead of silently squeezing it.
        .fixedSize()
    }

    private var accessibilityText: String {
        "Key: blue is \(Theme.residentLabel), \(Theme.residentGloss). "
            + "Amber is \(Theme.nonResidentLabelLong), \(Theme.nonResidentGloss)."
    }
}
