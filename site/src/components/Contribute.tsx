import styles from './Contribute.module.css';

const GITHUB_URL = 'https://github.com/alecf/totalrecall';

const steps = [
  {
    title: (
      <>
        Implement <code>ProcessClassifier</code>
      </>
    ),
    text: 'A single Swift protocol with one method: classify([ProcessSnapshot]) \u2192 ClassificationResult. You get the full process list and return groups.',
  },
  {
    title: 'Register it in the chain',
    text: 'Add your classifier to ClassifierRegistry.default. Order matters — earlier classifiers get first pick of processes.',
  },
  {
    title: 'Add fixtures and tests',
    text: 'Use the FixtureBuilder to create synthetic test data. No real process captures needed — tests run on any machine.',
  },
  {
    title: 'Iterate with the CLI',
    text: "Run swift run TotalRecallDiag to see your classifier's output against live processes. Check for duplicates, missing icons, opaque names.",
  },
];

export default function Contribute() {
  return (
    <section className={styles.section} id="contribute">
      <div className="section-inner">
        <div className={styles.layout}>
          <div className={styles.text}>
            <h2 className="section-heading">Your app deserves a classifier</h2>
            <p className={styles.lead}>
              Total Recall ships with 5 classifiers, but macOS runs hundreds of different
              applications. Docker, Xcode, Firefox, JetBrains IDEs, Steam — each has its own process
              hierarchy that could be grouped intelligently.
            </p>
            <p className={styles.lead}>
              Contributing a classifier is one of the highest-impact ways to improve Total Recall.
              Each one you write makes the app smarter for everyone who uses that software.
            </p>

            <div className={styles.steps}>
              {steps.map((step, i) => (
                <div key={i} className={styles.step}>
                  <span className={styles.stepNum}>{i + 1}</span>
                  <div>
                    <strong>{step.title}</strong>
                    <p>{step.text}</p>
                  </div>
                </div>
              ))}
            </div>

            <a
              href={GITHUB_URL}
              className="btn btn-primary"
              target="_blank"
              rel="noopener noreferrer"
            >
              View on GitHub
            </a>
          </div>

          <div className={styles.codeBlock}>
            <div className={styles.codeWindow}>
              <div className={styles.codeChrome}>
                <span className={styles.dot} data-color="red" />
                <span className={styles.dot} data-color="yellow" />
                <span className={styles.dot} data-color="green" />
                <span className={styles.codeFilename}>DockerClassifier.swift</span>
              </div>
              <pre className={styles.codeBody}>
                <code>
                  <Line kw>public struct</Line>{' '}
                  <Line type>DockerClassifier</Line>
                  {': '}
                  <Line type>ProcessClassifier</Line>
                  {' {\n'}
                  {'    '}
                  <Line kw>public let</Line>
                  {' name = '}
                  <Line str>"Docker"</Line>
                  {'\n\n'}
                  {'    '}
                  <Line kw>public func</Line>{' '}
                  <Line fn>classify</Line>
                  {'(\n'}
                  {'        '}
                  <Line kw>_</Line>
                  {' processes: ['}
                  <Line type>ProcessSnapshot</Line>
                  {']\n'}
                  {'    ) -> '}
                  <Line type>ClassificationResult</Line>
                  {' {\n'}
                  {'        '}
                  <Line kw>let</Line>
                  {' dockerProcs = processes.'}
                  <Line fn>filter</Line>
                  {' {\n'}
                  {'            $0.path.'}
                  <Line fn>contains</Line>
                  {'('}
                  <Line str>"Docker.app"</Line>
                  {') ||\n'}
                  {'            $0.name.'}
                  <Line fn>hasPrefix</Line>
                  {'('}
                  <Line str>"com.docker"</Line>
                  {')\n'}
                  {'        }\n'}
                  {'        '}
                  <Line kw>guard</Line>
                  {' !dockerProcs.isEmpty '}
                  <Line kw>else</Line>
                  {' {\n'}
                  {'            '}
                  <Line kw>return</Line>
                  {' .empty\n'}
                  {'        }\n'}
                  {'        '}
                  <Line kw>let</Line>
                  {' group = '}
                  <Line type>ProcessGroup</Line>
                  {'(\n'}
                  {'            name: '}
                  <Line str>"Docker"</Line>
                  {',\n'}
                  {'            classifierName: name,\n'}
                  {'            processes: dockerProcs\n'}
                  {'        )\n'}
                  {'        '}
                  <Line kw>return</Line>{' '}
                  <Line type>ClassificationResult</Line>
                  {'(\n'}
                  {'            groups: [group],\n'}
                  {'            claimedPIDs: '}
                  <Line type>Set</Line>
                  {'(dockerProcs.'}
                  <Line fn>map</Line>
                  {'(\\.pid))\n'}
                  {'        )\n'}
                  {'    }\n'}
                  {'}'}
                </code>
              </pre>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function Line({ children, kw, type, str, fn }: {
  children: React.ReactNode;
  kw?: boolean;
  type?: boolean;
  str?: boolean;
  fn?: boolean;
}) {
  const className = kw
    ? styles.syntaxKw
    : type
      ? styles.syntaxType
      : str
        ? styles.syntaxStr
        : fn
          ? styles.syntaxFn
          : undefined;
  return <span className={className}>{children}</span>;
}
