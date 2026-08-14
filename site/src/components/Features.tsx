import styles from './Features.module.css';
import memoryRiverShot from '../assets/memory-river.png';
import groupRowsShot from '../assets/group-rows.png';

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
      'A proportional stacked bar shows your entire RAM allocation at a glance, with an "Other" segment for memory no app claims and a trailing segment for free memory. The bar splits at a midline: width above it is what an app holds in RAM right now, and below it each app hangs an amber stub for what has been compressed or swapped out. Since width is already resident memory, stub depth makes every rectangle\'s area the memory it holds — a deep stub is an app far bigger than it looks, and two stubs of equal area hold equal memory wherever they sit. Hover any segment to read its name and share of total RAM; click to drill in.',
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
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M4 5h5" />
        <path d="M4 12h5" />
        <path d="M4 19h5" />
        <path d="M13 5h7" />
        <path d="M13 12h7" />
        <path d="M13 19h7" />
        <circle cx="10.5" cy="5" r="1.4" />
        <circle cx="10.5" cy="12" r="1.4" />
        <circle cx="10.5" cy="19" r="1.4" />
      </svg>
    ),
    title: 'Read It Your Way',
    description:
      "Three toggles in the status bar reshape the list: merge every window of an app into one group or split them apart, expand a group as a parent-child process tree or a flat list sorted by size, and rank by total footprint or by what's resident right now.",
  },
];

const shots = [
  {
    src: memoryRiverShot,
    width: 780,
    height: 150,
    alt: 'The Memory River bar with a wide System Services segment followed by dozens of narrow app segments, above readouts for total, used, compressed and free memory and a green Normal pressure indicator.',
    caption:
      'The river spans every byte of RAM. Beneath it: total, used (with what’s compressed), free, and current memory pressure.',
  },
  {
    src: groupRowsShot,
    width: 780,
    height: 230,
    alt: 'A list of process groups — System Services, Safari, TotalRecall, Weather — each with an app icon, process count, sparkline, memory total and trend arrow.',
    caption:
      'Each group row carries its own ~2-minute sparkline and a trend arrow. Expand a group to see the processes inside it.',
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
          {shots.map((shot) => (
            <figure key={shot.src} className={styles.shotFigure}>
              <img
                src={shot.src}
                width={shot.width}
                height={shot.height}
                className={styles.shot}
                alt={shot.alt}
              />
              <figcaption>{shot.caption}</figcaption>
            </figure>
          ))}
        </div>
      </div>
    </section>
  );
}
