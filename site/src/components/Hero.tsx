import MemoryRiver from './MemoryRiver';
import styles from './Hero.module.css';
import mainWindow from '../assets/main-window.png';

const RELEASES_URL = 'https://github.com/alecf/totalrecall/releases';

export default function Hero() {
  return (
    <section className={styles.hero}>
      <div className={styles.glow} aria-hidden="true" />

      <div className={styles.content}>
        <div className={styles.badge}>Open Source &middot; macOS &middot; Swift</div>

        <h1 className={styles.title}>Total Recall</h1>

        <p className={styles.tagline}>
          Finally understand where your RAM is going.{' '}
          {/* The break is placed for a desktop measure and is hidden on phones;
              the explicit space is what the line falls back to there. */}
          <br />
          Not just processes — <em>applications</em>. Not just totals — what is{' '}
          <em>really in RAM</em> versus what macOS has compressed or swapped away.
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
        <img
          src={mainWindow}
          width={780}
          height={560}
          className={styles.shot}
          alt="The Total Recall inspection window: a Memory River bar across the top with a blue
               &lsquo;In RAM&rsquo; and amber &lsquo;Compressed&rsquo; label down its left edge and a
               written key beneath it, then total/used/free readouts, then a list of process groups
               with sparklines and memory totals."
        />
      </div>
    </section>
  );
}
