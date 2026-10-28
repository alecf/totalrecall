import { useEffect, useState } from 'react';
import { colors } from '../theme';
import styles from './MemoryRiver.module.css';

/** Height of the fixed resident band, and the scale factor for stub depth. */
const BAND_HEIGHT = 32;
/**
 * Deepest a stub may hang before it clips: past `nonResident / width > 1.5`
 * the stub is drawn short and fades out. Matches `Theme.riverMaxDepth`.
 */
const DEPTH_CAP = 48;
/** The reserved depth snaps to multiples of this. Matches `riverDepthQuantum`. */
const DEPTH_QUANTUM = 12;

interface Segment {
  label: string;
  /** Percentage of the bar this segment occupies — in-RAM memory. */
  baseWidth: number;
  /** How much the width drifts between refreshes. */
  variance: number;
  /**
   * Compressed/swapped bytes over in-RAM bytes. Drives stub depth, which is
   * `BAND_HEIGHT × ratio` capped at `DEPTH_CAP` — so past 1.5 the stub is drawn
   * short and fades out. Matches `RiverLayout.computeDepths`.
   */
  swapRatio: number;
}

/**
 * A stylized, animated stand-in for the app's Memory River. It mirrors the real
 * encoding: the bar splits at a midline, every app fills the same resident blue
 * above it, and each hangs an amber stub below it for what has been compressed
 * or swapped out. Width is in-RAM bytes, so stub depth makes each rectangle's
 * area the memory it holds. After the apps come the measured system segments —
 * Other, Kernel, Available — which hang no stub. It shows the app's default
 * view, where the compressor pool is shared out into the apps' widths rather
 * than drawn as a segment of its own. Color never encodes identity — see
 * `MemoryRiverView.swift`.
 *
 * It carries the app's two labelling affordances as well as its geometry: the
 * left gutter naming the halves, each word in the color of the band beside it,
 * and the key below spelling out what the two colors mean. The point of the
 * whole visualization is the gap between what an app is charged for and what it
 * actually occupies in RAM, and that does not survive being left to inference —
 * so the stand-in that sells the app has to say it in words, exactly as the app
 * does.
 */
// Ratios are in the range real apps actually occupy on a busy machine, so the
// stand-in shows both a deep stub that still renders in full and one past the
// cap that fades.
const segments: Segment[] = [
  { label: 'Chrome', baseWidth: 24, variance: 4, swapRatio: 0.96 },
  { label: 'VS Code', baseWidth: 15, variance: 3, swapRatio: 0.54 },
  { label: 'Claude Code', baseWidth: 11, variance: 2, swapRatio: 2.04 },
  { label: 'System', baseWidth: 10, variance: 2, swapRatio: 0.35 },
  { label: 'Docker', baseWidth: 12, variance: 3, swapRatio: 2.27 },
  { label: 'Other', baseWidth: 4, variance: 1, swapRatio: 0 },
  { label: 'Kernel', baseWidth: 9, variance: 1, swapRatio: 0 },
  { label: 'Available', baseWidth: 15, variance: 4, swapRatio: 0 },
];

const systemSegments = new Set(['Other', 'Kernel']);

const segmentColor = (label: string) => {
  if (label === 'Available') return colors.riverFree;
  if (systemSegments.has(label)) return colors.riverOther;
  return colors.memoryResident;
};

const depthOf = (swapRatio: number) => Math.min(swapRatio * BAND_HEIGHT, DEPTH_CAP);
const isClipped = (swapRatio: number) => swapRatio * BAND_HEIGHT > DEPTH_CAP;

/**
 * Reserved depth below the midline. Ratios are fixed here while only widths
 * drift, so this is constant across refreshes and the page never reflows.
 */
const reservedDepth =
  Math.ceil(Math.max(...segments.map((s) => depthOf(s.swapRatio))) / DEPTH_QUANTUM) *
  DEPTH_QUANTUM;

export default function MemoryRiver() {
  const [widths, setWidths] = useState(segments.map((s) => s.baseWidth));

  useEffect(() => {
    const interval = setInterval(() => {
      setWidths(
        segments.map((s) => {
          const drift = (Math.random() - 0.5) * 2 * s.variance;
          return Math.max(4, s.baseWidth + drift);
        }),
      );
    }, 3000);
    return () => clearInterval(interval);
  }, []);

  const total = widths.reduce((a, b) => a + b, 0);

  return (
    <div className={styles.wrapper}>
      <div className={styles.riverRow}>
        {/* Fixed-width gutter, so the bar's left edge and the key beneath it
            line up whatever the labels say. Mirrors `riverAxisLabelWidth`. */}
        <div className={styles.gutter} aria-hidden="true">
          <span className={styles.gutterResident} style={{ height: `${BAND_HEIGHT}px` }}>
            In RAM
          </span>
          <span className={styles.gutterCompressed}>Compressed</span>
        </div>
        <div
          className={styles.bar}
          style={{ height: `${BAND_HEIGHT + reservedDepth}px` }}
          role="img"
          aria-label="Animated memory usage visualization. Blue is memory really in physical RAM; amber hanging below the midline is memory macOS has compressed or swapped out."
        >
          {segments.map((seg, i) => {
            const depth = depthOf(seg.swapRatio);
            return (
              <div
                key={seg.label}
                className={styles.column}
                style={{ width: `${(widths[i] / total) * 100}%` }}
              >
                <div
                  className={styles.band}
                  style={{
                    height: `${BAND_HEIGHT}px`,
                    backgroundColor: segmentColor(seg.label),
                    borderRadius: depth > 0 ? '2px 2px 0 0' : '2px',
                  }}
                >
                  <span className={styles.label}>{seg.label}</span>
                </div>
                {depth > 0 && (
                  <span
                    className={isClipped(seg.swapRatio) ? styles.stubClipped : styles.stub}
                    style={{ height: `${depth}px` }}
                    aria-hidden="true"
                  />
                )}
              </div>
            );
          })}
        </div>
      </div>
      <div className={styles.legend}>
        <span className={styles.keyResident}>
          <i className={styles.swatch} style={{ backgroundColor: colors.memoryResident }} />
          In RAM
          <em>— really in physical memory</em>
        </span>
        <span className={styles.keyCompressed}>
          <i className={styles.swatch} style={{ backgroundColor: colors.memoryCompressed }} />
          Compressed / swapped
          <em>— moved out of RAM by macOS</em>
        </span>
      </div>
      <div className={styles.caption}>
        <span className={styles.captionDot} />
        Memory River &mdash; width is what&rsquo;s in RAM, depth is what isn&rsquo;t
      </div>
    </div>
  );
}
