import MemoryRiver from './MemoryRiver';
import ScreenshotPlaceholder from './ScreenshotPlaceholder';
import styles from './Hero.module.css';

const RELEASES_URL = 'https://github.com/alecf/totalrecall/releases';

export default function Hero() {
  return (
    <section className={styles.hero}>
      <div className={styles.glow} aria-hidden="true" />

      <div className={styles.content}>
        <div className={styles.badge}>Open Source &middot; macOS &middot; Swift</div>

        <h1 className={styles.title}>Total Recall</h1>

        <p className={styles.tagline}>
          Finally understand where your RAM is going.
          <br />
          Not just processes — <em>applications</em>.
        </p>

        <MemoryRiver />

        <div className={styles.actions}>
          <a href={RELEASES_URL} className="btn btn-primary" target="_blank" rel="noopener noreferrer">
            Download Latest Release
          </a>
          <a href="#install" className="btn btn-secondary">
            Build from Source
          </a>
        </div>
      </div>

      <div className={styles.screenshot}>
        <ScreenshotPlaceholder
          width={780}
          height={560}
          label="Total Recall"
          filename="hero-screenshot.png"
        >
          {/* Mock of the full app window */}
          <div className={styles.mockRiver}>
            <div style={{ flex: 3.2, background: 'rgb(86, 126, 211)', borderRadius: 3 }} />
            <div style={{ flex: 2.4, background: 'rgb(129, 102, 208)', borderRadius: 3 }} />
            <div style={{ flex: 1.0, background: 'rgb(75, 160, 130)', borderRadius: 3 }} />
            <div style={{ flex: 2.0, background: 'rgb(209, 107, 56)', borderRadius: 3 }} />
            <div style={{ flex: 1.4, background: 'rgb(115, 117, 128)', borderRadius: 3 }} />
          </div>
          <div className={styles.mockStats}>
            14.2 GB used &middot; Pressure: Normal &middot; 247 processes in 18 groups
          </div>
          <div className={styles.mockRows}>
            {[
              { icon: '\u{1F310}', name: 'Chrome', mem: '4.2 GB' },
              { icon: '\u270E', name: 'VS Code', mem: '2.8 GB' },
              { icon: '\u25B6', name: 'Claude Code', mem: '1.1 GB' },
              { icon: '\u2699', name: 'System Services', mem: '2.4 GB' },
              { icon: '\u{1F433}', name: 'Docker', mem: '1.8 GB' },
            ].map((row) => (
              <div key={row.name} className={styles.mockRow}>
                <span className={styles.mockIcon}>{row.icon}</span>
                <span>{row.name}</span>
                <span className={styles.mockMem}>{row.mem}</span>
              </div>
            ))}
          </div>
        </ScreenshotPlaceholder>
      </div>
    </section>
  );
}
