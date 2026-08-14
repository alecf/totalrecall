import { useEffect, useState } from 'react';
import { colors } from '../theme';
import styles from './MemoryRiver.module.css';

/** Height of the fixed resident band, and the cap on stub depth, in px. */
const BAND_HEIGHT = 48;
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
   * `BAND_HEIGHT × ratio` — so above 1 the stub is drawn short and fades out.
   * Matches `RiverLayout.computeDepths`.
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
const segments: Segment[] = [
  { label: 'Chrome', baseWidth: 24, variance: 4, swapRatio: 0.22 },
  { label: 'VS Code', baseWidth: 17, variance: 3, swapRatio: 0.58 },
  { label: 'Claude Code', baseWidth: 9, variance: 2, swapRatio: 0.11 },
  { label: 'System', baseWidth: 14, variance: 2, swapRatio: 0.35 },
  { label: 'Docker', baseWidth: 10, variance: 3, swapRatio: 1.35 },
  { label: 'Other', baseWidth: 8, variance: 1, swapRatio: 0 },
  { label: 'Free', baseWidth: 18, variance: 5, swapRatio: 0 },
];

const segmentColor = (label: string) => {
  if (label === 'Free') return colors.riverFree;
  if (label === 'Other') return colors.riverOther;
  return colors.memoryResident;
};

const depthOf = (swapRatio: number) => Math.min(1, swapRatio) * BAND_HEIGHT;

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
                  className={seg.swapRatio > 1 ? styles.stubClipped : styles.stub}
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
