import styles from './ScreenshotPlaceholder.module.css';

interface ScreenshotPlaceholderProps {
  width: number;
  height: number;
  label: string;
  filename: string;
  children?: React.ReactNode;
}

/**
 * A styled placeholder for app screenshots.
 * Shows a mock window chrome + inner content + replacement instructions.
 * Replace the entire component with an <img> once you have the real screenshot.
 */
export default function ScreenshotPlaceholder({
  width,
  height,
  label,
  filename,
  children,
}: ScreenshotPlaceholderProps) {
  return (
    <div
      className={styles.placeholder}
      style={{ aspectRatio: `${width} / ${height}` }}
    >
      <div className={styles.chrome}>
        <span className={`${styles.dot} ${styles.red}`} />
        <span className={`${styles.dot} ${styles.yellow}`} />
        <span className={`${styles.dot} ${styles.green}`} />
        <span className={styles.title}>{label}</span>
      </div>
      <div className={styles.body}>
        {children}
        <div className={styles.note}>
          Replace with: <code>{filename}</code>
          <br />
          {width} &times; {height}px @2x
        </div>
      </div>
    </div>
  );
}
