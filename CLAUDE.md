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

# Scan workspace
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y --compact

# Fast incremental diff scan
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y --diff-only --compact

# Sandboxed dynamic PoC exploit verification
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm verify <finding-id> -y --compact

# Context-aware patch remediation
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm fix <finding-id> -c "<guidance>" -y

# VCS diff & rollback
HOME="${PROJECT_ROOT}" cm vcs diff
HOME="${PROJECT_ROOT}" cm vcs reset
```

---

## Operational Guardrails

1. **Non-Destructive VCS**: Before running `cm fix` or `cm vcs reset`, check `git status --porcelain`. If dirty, run `git stash push -m "cm-pre-fix-backup"` to protect uncommitted manual work.
2. **Vibe Coding Test Adaptive Check**: If `build.command` (e.g. `npm test`) fails due to no tests in a new project, adapt `build.command` in `.codemender/config.yaml` to typecheck (`npx tsc --noEmit`) or compilation (`go build ./...`) to prevent `cm fix` from deadlock rollback.
3. **Atomic Remediation**: When fixing multiple findings, fix 1 finding at a time, commit the clean patch, and run `cm find --diff-only` before moving to the next finding.
4. **Sandboxing**: Never disable the sandbox (`--sandbox=false`) without explicit operator approval.
