import { useEffect, useState } from 'react';
import { colors } from '../theme';
import styles from './MemoryRiver.module.css';

/** Height of the fixed resident band, and the scale factor for stub depth. */
const BAND_HEIGHT = 32;
/**
 * Deepest a stub may hang before it clips. Larger than the band on purpose, so
 * the cap bites at `nonResident / resident > 1.5` rather than at 1.0 — enough
 * real apps run just past 1.0 that pinning the two together made the fade the
 * rule instead of the exception. Matches `Theme.riverMaxDepth`.
 */
const DEPTH_CAP = 48;
/** The reserved depth snaps to multiples of this. Matches `riverDepthQuantum`. */
const DEPTH_QUANTUM = 12;

interface Segment {
  label: string;
  /** Percentage of the bar this segment occupies — resident memory. */
  baseWidth: number;
  /** How much the width drifts between refreshes. */
  variance: number;
  /**
   * Compressed/swapped bytes over resident bytes. Drives stub depth, which is
   * `BAND_HEIGHT × ratio` capped at `DEPTH_CAP` — so past 1.5 the stub is drawn
   * short and fades out. Matches `RiverLayout.computeDepths`.
   */
  swapRatio: number;
}

/**
 * A stylized, animated stand-in for the app's Memory River. It mirrors the real
 * encoding: the bar splits at a midline, every app fills the same resident blue
 * above it, and each hangs an amber stub below it for what has been compressed
 * or swapped out. Width is resident bytes, so stub depth makes each rectangle's
 * area the memory it holds. Color never encodes identity — see
 * `MemoryRiverView.swift`.
 */
// Ratios are in the range real apps actually occupy on a busy machine, so the
// stand-in shows both a deep stub that still renders in full and one past the
// cap that fades.
const segments: Segment[] = [
  { label: 'Chrome', baseWidth: 24, variance: 4, swapRatio: 1.1 },
  { label: 'VS Code', baseWidth: 17, variance: 3, swapRatio: 0.58 },
  { label: 'Claude Code', baseWidth: 9, variance: 2, swapRatio: 2.81 },
  { label: 'System', baseWidth: 14, variance: 2, swapRatio: 0.35 },
  { label: 'Docker', baseWidth: 10, variance: 3, swapRatio: 3.02 },
  { label: 'Other', baseWidth: 8, variance: 1, swapRatio: 0 },
  { label: 'Free', baseWidth: 18, variance: 5, swapRatio: 0 },
];

const segmentColor = (label: string) => {
  if (label === 'Free') return colors.riverFree;
  if (label === 'Other') return colors.riverOther;
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
      <div
        className={styles.bar}
        style={{ height: `${BAND_HEIGHT + reservedDepth}px` }}
        role="img"
        aria-label="Animated memory usage visualization"
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
      <div className={styles.caption}>
        <span className={styles.captionDot} />
        Memory River — width is resident, amber depth is compressed or swapped
      </div>
    </div>
  );
}
