# CLAUDE.md - CodeMender Security Plugin Guidelines

This document provides operational instructions for Anthropic Claude Code when executing security audits and patch remediations using the CodeMender CLI (`cm`).

## Overview
`codemender-security` provides autonomous AST scanning, dynamic sandbox PoC exploit verification, and context-aware patch remediation powered by Google Cloud CodeMender (`cm`).

---

## Command Patterns (Stateless On-the-Fly)

Always invoke `cm` on-the-fly with project-scoped environment variables to avoid mutating the global environment:

```bash
# Resolve roots
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${HOME}/.config/gcloud/application_default_credentials.json"

# Full scan
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y

# Incremental scan (automatically diffs AST cache in .codemender/state.db when scan.incremental: true)
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y
# Or target modified path:
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find ./src/services/ -y

# Sandboxed dynamic PoC exploit verification with reset suppression
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm verify <finding-id> --no-reset -y

# Context-aware patch remediation
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm fix <finding-id> -c "<guidance>" -y

# Verify changes directly on disk
git diff

# VCS diff & rollback
HOME="${PROJECT_ROOT}" cm vcs diff
HOME="${PROJECT_ROOT}" cm vcs reset
```

---

## Operational Guardrails

1. **Non-Destructive VCS**: Before running `cm fix`, `cm verify`, or `cm vcs reset`, check `git status --porcelain`. If dirty, run `git stash push -m "cm-pre-fix-backup"` to protect uncommitted manual work.
2. **Vibe Coding Test Adaptive Check**: If `build.command` (e.g. `npm test`) fails due to no tests in a new project, adapt `build.command` in `.codemender/config.yaml` to typecheck (`npx tsc --noEmit`) or compilation (`go build ./...`) to prevent `cm fix` from deadlock rollback.
3. **Atomic Remediation**: When fixing multiple findings, fix 1 finding at a time, verify diff with `git diff`, commit the clean patch, and run `cm find . -y` before moving to the next finding.
4. **Sandboxing**: Never disable the sandbox (`--sandbox=false` or `--unrestricted`) without explicit operator approval.
5. **Triage Integrity**: When a PoC exploit fails during `cm verify`, retain the finding as `OPEN / UNCONFIRMED` for manual review. Never prematurely dismiss unverified exploits as false positives.
