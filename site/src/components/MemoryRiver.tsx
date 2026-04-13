import { useEffect, useState } from 'react';
import styles from './MemoryRiver.module.css';

interface Segment {
  label: string;
  color: string;
  baseWidth: number; // percentage
  variance: number; // how much it drifts
}

const segments: Segment[] = [
  { label: 'Chrome', color: 'rgb(86, 126, 211)', baseWidth: 28, variance: 4 },
  { label: 'VS Code', color: 'rgb(129, 102, 208)', baseWidth: 20, variance: 3 },
  { label: 'Claude Code', color: 'rgb(75, 160, 130)', baseWidth: 10, variance: 2 },
  { label: 'System', color: 'rgb(209, 107, 56)', baseWidth: 18, variance: 2 },
  { label: 'Docker', color: 'rgb(160, 110, 180)', baseWidth: 12, variance: 3 },
  { label: 'Other', color: 'rgb(115, 117, 128)', baseWidth: 12, variance: 1 },
];

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
              backgroundColor: seg.color,
            }}
          >
            <span className={styles.label}>{seg.label}</span>
          </div>
        ))}
      </div>
      <div className={styles.caption}>
        <span className={styles.captionDot} />
        Memory River — your RAM at a glance
      </div>
    </div>
  );
}
