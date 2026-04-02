# Total Recall

A macOS menu bar app that provides intelligent, grouped views of memory (RAM) usage. Unlike Activity Monitor, Total Recall groups processes by logical application using built-in knowledge of how apps like Chrome, VS Code, Docker, and system services manage their process hierarchies.

## Features

- **Smart process grouping**: Chrome processes grouped by profile, Electron apps by bundle, system daemons with human-readable explanations
- **Memory River**: proportional stacked bar showing where your RAM is going at a glance
- **Menu bar presence**: memory pressure indicator + used/total display
- **Trend indicators**: see which apps are growing or shrinking over time
- **Safe kill actions**: PID-verified termination with system process protection
- **Secret redaction**: command-line arguments are filtered for passwords and tokens

## Requirements

- macOS 26+
- Xcode 17+ (for building from source)

## Building

```bash
git clone <repo-url>
cd memwatch
swift build
swift run
```

## Architecture

Total Recall uses a tiered data collection strategy:

| Tier | API | Cost (886 PIDs) | Strategy |
|------|-----|-----------------|----------|
| 0 | proc_listallpids | 0.17ms | Every cycle |
| 1 | proc_pid_rusage | 2.6ms | Every cycle |
| 2 | proc_pidinfo + proc_pidpath | 2.8ms | Cached per PID |
| 3 | KERN_PROCARGS2 | 9.2ms | Cached per PID |

Full collection takes ~15ms for 886 processes (0.3% of a 5-second interval).

## License

TBD
