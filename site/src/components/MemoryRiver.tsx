import { useEffect, useState } from 'react';
import { colors } from '../theme';
import styles from './MemoryRiver.module.css';

interface Segment {
  label: string;
  /** Percentage of the bar this segment occupies — resident memory. */
  baseWidth: number;
  /** How much the width drifts between refreshes. */
  variance: number;
  /**
   * Share of the segment filled amber from the bottom: how much of the app is
   * compressed or swapped rather than in RAM. Matches `Theme.hiddenFraction`.
   */
  hidden: number;
}

/**
 * A stylized, animated stand-in for the app's Memory River. It mirrors the real
 * encoding: every app segment is the same resident blue, and the amber that
 * rises inside it is the share of that app which is compressed or swapped.
 * Color never encodes identity — see `MemoryRiverView.swift`.
 */
const segments: Segment[] = [
  { label: 'Chrome', baseWidth: 24, variance: 4, hidden: 0.18 },
  { label: 'VS Code', baseWidth: 17, variance: 3, hidden: 0.42 },
  { label: 'Claude Code', baseWidth: 9, variance: 2, hidden: 0.1 },
  { label: 'System', baseWidth: 14, variance: 2, hidden: 0.3 },
  { label: 'Docker', baseWidth: 10, variance: 3, hidden: 0.66 },
  { label: 'Other', baseWidth: 8, variance: 1, hidden: 0 },
  { label: 'Free', baseWidth: 18, variance: 5, hidden: 0 },
];

const segmentColor = (label: string) => {
  if (label === 'Free') return colors.riverFree;
  if (label === 'Other') return colors.riverOther;
  return colors.memoryResident;
};

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
      <div className={styles.bar} role="img" aria-label="Animated memory usage visualization">
        {segments.map((seg, i) => (
          <div
            key={seg.label}
            className={styles.segment}
            style={{
              width: `${(widths[i] / total) * 100}%`,
              backgroundColor: segmentColor(seg.label),
            }}
          >
            {seg.hidden > 0 && (
              <span
                className={styles.hidden}
                style={{ height: `${seg.hidden * 100}%` }}
                aria-hidden="true"
              />
            )}
            <span className={styles.label}>{seg.label}</span>
          </div>
        ))}
      </div>
      <div className={styles.caption}>
        <span className={styles.captionDot} />
        Memory River — width is resident, amber is compressed or swapped
      </div>
    </div>
  );
}
