import styles from './Install.module.css';

const RELEASES_URL = 'https://github.com/alecf/totalrecall/releases';

const buildSteps = [
  'git clone https://github.com/alecf/totalrecall.git',
  'cd totalrecall',
  'swift build',
  'swift run TotalRecall',
];

export default function Install() {
  return (
    <section className={styles.section} id="install">
      <div className="section-inner">
        <h2 className="section-heading">Get started</h2>

        <div className={styles.grid}>
          <div className={styles.card}>
            <h3>Download</h3>
            <p>
              Grab the latest <code>.dmg</code> from GitHub Releases. Since the app isn't
              code-signed, right-click &rarr; Open to bypass Gatekeeper on first launch.
            </p>
            <a
              href={RELEASES_URL}
              className="btn btn-secondary"
              target="_blank"
              rel="noopener noreferrer"
            >
              Latest Release
            </a>
          </div>

          <div className={styles.card}>
            <h3>Build from source</h3>
            <div className={styles.codeLines}>
              {buildSteps.map((line) => (
                <code key={line}>{line}</code>
              ))}
            </div>
            <p className={styles.note}>Requires Xcode 17+ with the macOS 26 SDK.</p>
          </div>
        </div>
      </div>
    </section>
  );
}
