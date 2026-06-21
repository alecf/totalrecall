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
      'A proportional stacked bar shows your entire RAM allocation at a glance, with a trailing segment for free memory. Hover any segment to read its name and share of total RAM in the line beneath the bar; click to drill in. Watch it shift as apps grow and shrink.',
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
      'Every group row charts its memory footprint over the last ~2 minutes. Read the shape: a slow ramp is a likely leak, a sawtooth is GC churn, a step is a one-off event. Direction and magnitude, not just the snapshot.',
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
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="3" y="3" width="18" height="4" rx="1" />
        <rect x="3" y="10" width="11" height="4" rx="1" />
        <rect x="3" y="17" width="7" height="4" rx="1" />
      </svg>
    ),
    title: 'VM Region Map',
    description:
      'Select any single-process app to see a vmmap-style breakdown of its virtual address space: __TEXT (code), Heap, Stack, Anonymous, and File-backed regions with virtual size and resident pages side by side.',
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
            label="Detail Panel — Regions Tab"
            filename="detail-regions-screenshot.png"
          >
            <div className={styles.mockDetail}>
              <div className={styles.detailHeader}>
                <span className={styles.appIcon}>{'🧮'}</span>
                <div>
                  <strong>Calculator</strong>
                  <small>PID 1234</small>
                </div>
              </div>
              <div className={styles.mockTabs}>
                <span className={styles.mockTab}>Overview</span>
                <span className={`${styles.mockTab} ${styles.mockTabActive}`}>Regions</span>
              </div>
              <div className={styles.regionTable}>
                <div className={styles.regionHeader}>
                  <span>Region</span>
                  <span>Size</span>
                  <span>Resident</span>
                </div>
                {[
                  { name: 'Heap',        size: '220 MB', res: '180 MB' },
                  { name: '__TEXT',      size: '140 MB', res: '85 MB'  },
                  { name: 'File-backed', size: '62 MB',  res: '40 MB'  },
                  { name: 'Anonymous',   size: '45 MB',  res: '30 MB'  },
                  { name: 'Stack',       size: '8 MB',   res: '4 MB'   },
                ].map((r) => (
                  <div key={r.name} className={styles.regionRow}>
                    <span>{r.name}</span>
                    <span className={styles.mono}>{r.size}</span>
                    <span className={`${styles.mono} ${styles.regionResident}`}>{r.res}</span>
                  </div>
                ))}
                <div className={styles.regionNote}>
                  Sizes are virtual; Resident is pages in RAM × page size.
                </div>
              </div>
            </div>
          </ScreenshotPlaceholder>
        </div>
      </div>
    </section>
  );
}
