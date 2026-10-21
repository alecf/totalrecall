# Agent Notes

## Architecture Boundaries

- Keep parent orchestration layers generic. `AppState` may merge, sort, trend, and format generic `ProcessGroup` metadata, but it must not branch on specific child classifiers such as Claude Code, Chrome, Electron, or System.
- Put app-specific process knowledge in the owning classifier. A classifier should expose any context the parent needs through generic model fields such as `ProcessGroup.name`, `stableIdentifier`, `explanation`, `subGroups`, and process membership.
- If a parent needs new behavior that only one classifier can currently use, add a generic model concept first. Do not special-case a classifier name in the parent.

## Pull Requests

- Run `/code-review` on the branch every time you open a PR, and again after pushing substantive changes to one. A reviewer subagent is not a substitute.
- Fix obvious issues the review finds and push the fixes to the same PR.
- When a finding is ambiguous — a judgment call on design, scope, or behavior rather than a clear bug — ask the operator before acting on it instead of guessing. Say which findings you fixed, which you skipped and why, and which are waiting on their answer.
