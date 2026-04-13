import ScreenshotPlaceholder from './ScreenshotPlaceholder';
import styles from './Features.module.css';

const features = [
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="3" y="3" width="7" height="7" rx="1.5" />
        <rect x="14" y="3" width="7" height="7" rx="1.5" />
        <rect x="3" y="14" width="7" height="7" rx="1.5" />
        <rect x="14" y="14" width="7" height="7" rx="1.5" />
      </svg>
    ),
    title: 'Smart Process Grouping',
    description:
      "Chrome's 47 helper processes become one entry. Electron apps, Docker containers, Claude Code sessions — all grouped by the application they belong to, not scattered across a flat list.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M2 12h4l3-9 4 18 3-9h6" />
      </svg>
    ),
    title: 'Memory River',
    description:
      'A proportional stacked bar shows your entire RAM allocation at a glance. Click any segment to drill in. Hover for details. Watch it shift as apps grow and shrink.',
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <circle cx="12" cy="12" r="10" />
        <path d="M12 6v6l4 2" />
      </svg>
    ),
    title: 'Trend Tracking',
    description:
      'Rolling 30-second trends show which apps are growing or shrinking. Catch a memory leak before it becomes a problem. See the direction, not just the snapshot.',
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M12 2L2 7l10 5 10-5-10-5z" />
        <path d="M2 17l10 5 10-5" />
        <path d="M2 12l10 5 10-5" />
      </svg>
    ),
    title: 'Memory Composition',
    description:
      "See how much of each app is actually in RAM vs compressed or swapped to disk. Understand not just total footprint, but what's actively consuming physical memory.",
  },
];

export default function Features() {
  return (
    <section className={styles.features} id="features">
      <div className="section-inner">
        <h2 className="section-heading">Not another Activity Monitor</h2>
        <p className="section-subheading">
          Total Recall uses built-in knowledge of application architectures to show you what's{' '}
          <em>really</em> consuming your memory.
        </p>

        <div className={styles.grid}>
          {features.map((f) => (
            <div key={f.title} className={styles.card}>
              <div className={styles.icon}>{f.icon}</div>
              <h3>{f.title}</h3>
              <p>{f.description}</p>
            </div>
          ))}
        </div>

        <div className={styles.screenshots}>
          <ScreenshotPlaceholder
            width={320}
            height={200}
            label="Menu Bar"
            filename="menubar-screenshot.png"
          >
            <div className={styles.mockMenubar}>
              <div className={styles.mockMenubarIcon}>
                <span className={styles.greenDot} />
                <span className={styles.mono}>14.2 / 36 GB</span>
              </div>
              <div className={styles.mockMenuItems}>
                <div>Memory: 14.2 / 36.0 GB</div>
                <div>Pressure: Normal</div>
                <hr className={styles.menuDivider} />
                <div>Top: Chrome — 4.2 GB</div>
                <hr className={styles.menuDivider} />
                <div className={styles.menuAction}>Open Total Recall &ensp; &#8984;&#8679;M</div>
              </div>
            </div>
          </ScreenshotPlaceholder>

          <ScreenshotPlaceholder
            width={280}
            height={400}
            label="Detail Panel"
            filename="detail-screenshot.png"
          >
            <div className={styles.mockDetail}>
              <div className={styles.detailHeader}>
                <span className={styles.appIcon}>{'\u{1F310}'}</span>
                <div>
                  <strong>Chrome</strong>
                  <small>Browser (Chrome-based)</small>
                </div>
              </div>
              <div className={styles.detailRows}>
                <div className={styles.detailRow}>
                  <span>Processes</span>
                  <span className={styles.mono}>47</span>
                </div>
                <div className={styles.detailBar}>
                  <div style={{ width: '72%', background: 'rgb(86, 126, 185)', borderRadius: 2, height: '100%' }} />
                  <div style={{ width: '28%', background: 'rgb(209, 133, 56)', borderRadius: 2, height: '100%' }} />
                </div>
                <div className={styles.detailRow}>
                  <span>In RAM</span>
                  <span className={styles.mono}>3.0 GB (72%)</span>
                </div>
                <div className={styles.detailRow}>
                  <span>Compressed</span>
                  <span className={styles.mono}>~1.2 GB (28%)</span>
                </div>
                <div className={styles.detailRow}>
                  <span>Shared</span>
                  <span className={styles.mono}>~680 MB</span>
                </div>
              </div>
            </div>
          </ScreenshotPlaceholder>
        </div>
      </div>
    </section>
  );
}
