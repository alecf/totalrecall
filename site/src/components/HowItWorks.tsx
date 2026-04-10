import styles from './HowItWorks.module.css';

const steps = [
  {
    num: '1',
    title: 'Collect',
    text: 'Every 5 seconds, Total Recall reads the full process table via libproc and sysctl. PID, memory footprint, command-line args, parent PID, executable path — all captured in ~15ms.',
  },
  {
    num: '2',
    title: 'Classify',
    text: 'Processes pass through a chain of classifiers in priority order. Each one claims the processes it recognizes — Chrome tabs, Electron renderers, system daemons — and groups them into logical applications.',
  },
  {
    num: '3',
    title: 'Deduplicate',
    text: 'Shared memory between processes in a group is counted once, not per-process. The result: accurate group totals that match what macOS is actually using.',
  },
  {
    num: '4',
    title: 'Display',
    text: 'Groups are ranked by footprint, trends are computed from a rolling window, and everything flows into a SwiftUI interface designed around the Memory River visualization.',
  },
];

const classifiers = [
  {
    name: 'Chrome',
    color: 'rgb(86, 126, 211)',
    description:
      'Groups browser, renderer, GPU, and utility processes. Identifies profiles by --user-data-dir. Works for Chromium, Brave, Edge, Arc.',
  },
  {
    name: 'Electron',
    color: 'rgb(129, 102, 208)',
    description:
      'Detects Electron apps by framework path and bundle structure. Groups VS Code, Slack, Discord, Figma, and dozens more by their .app bundle.',
  },
  {
    name: 'Claude Code',
    color: 'rgb(75, 160, 130)',
    description:
      'Recognizes Claude Code CLI sessions and their child processes. Resolves volta shims, groups by workspace directory.',
  },
  {
    name: 'System',
    color: 'rgb(209, 107, 56)',
    description:
      'Maps opaque daemon names to human-readable descriptions. bird becomes "iCloud Sync", mds_stores becomes "Spotlight Indexing".',
  },
  {
    name: 'Generic',
    color: 'rgb(115, 117, 128)',
    description:
      'The catch-all. Groups remaining processes by app bundle or executable name. Resolves runtime tools — node running webpack, python3 running pytest.',
  },
];

export default function HowItWorks() {
  return (
    <section className={styles.section} id="how-it-works">
      <div className="section-inner">
        <h2 className="section-heading">How it works</h2>
        <p className="section-subheading">
          A pipeline of specialized classifiers examines every running process and groups them by
          application.
        </p>

        <div className={styles.pipeline}>
          {steps.map((step, i) => (
            <div key={step.num}>
              <div className={styles.step}>
                <div className={styles.number}>{step.num}</div>
                <div className={styles.stepContent}>
                  <h3>{step.title}</h3>
                  <p>{step.text}</p>
                </div>
              </div>
              {i < steps.length - 1 && <div className={styles.connector} />}
            </div>
          ))}
        </div>

        <div className={styles.classifiersSection}>
          <h3 className={styles.classifiersTitle}>Built-in classifiers</h3>
          <div className={styles.classifiersGrid}>
            {classifiers.map((c) => (
              <div
                key={c.name}
                className={styles.classifierCard}
                style={{ '--accent': c.color } as React.CSSProperties}
              >
                <div className={styles.classifierDot} />
                <h4>{c.name}</h4>
                <p>{c.description}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
