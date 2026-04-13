import styles from './Footer.module.css';

const GITHUB_URL = 'https://github.com/alecf/totalrecall';

export default function Footer() {
  return (
    <footer className={styles.footer}>
      <div className="section-inner">
        <div className={styles.inner}>
          <div className={styles.brand}>
            <span className={styles.dot} />
            <span>Total Recall</span>
          </div>
          <div className={styles.links}>
            <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
              GitHub
            </a>
            <a href={`${GITHUB_URL}/releases`} target="_blank" rel="noopener noreferrer">
              Releases
            </a>
            <a href={`${GITHUB_URL}/issues`} target="_blank" rel="noopener noreferrer">
              Issues
            </a>
          </div>
          <div className={styles.license}>MIT License &middot; Alec Flett</div>
        </div>
      </div>
    </footer>
  );
}
