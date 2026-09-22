# CLAUDE.md - CodeMender Security Plugin Guidelines

This document provides operational instructions for Anthropic Claude Code when executing security audits and patch remediations using the CodeMender CLI (`cm`).

## Overview
`codemender-security` provides autonomous AST scanning, dynamic sandbox PoC exploit verification, and context-aware patch remediation powered by Google Cloud CodeMender (`cm`).

---

## Command Patterns (Stateless On-the-Fly)

Always invoke `cm` on-the-fly with project-scoped environment variables to avoid mutating the global environment:

```bash
# Resolve roots & active GCP project
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

# Protect localized .codemender state from 'cm fix' internal 'git clean -fd' (supports worktrees & submodules)
EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && [ -d "$(dirname "${EXCLUDE_FILE}")" ]; then
  for entry in ".codemender/" ".cm_project" ".exploit/"; do
    grep -qxF "$entry" "${EXCLUDE_FILE}" 2>/dev/null || echo "$entry" >> "${EXCLUDE_FILE}"
  done
fi

# Full scan
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y

# Incremental scan (automatically diffs AST cache in .codemender/state.db when scan.incremental: true)
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y
# Or target modified path:
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find ./src/services/ -y

# Sandboxed dynamic PoC exploit verification with reset suppression
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm verify <finding-id> --no-reset --bypass-warning -y

# Context-aware patch remediation
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm fix <finding-id> -c "<guidance>" --bypass-warning -y

# Verify changes directly on disk
git diff

# VCS diff & rollback
HOME="${PROJECT_ROOT}" cm vcs diff
HOME="${PROJECT_ROOT}" cm vcs reset
```

---

## Operational Guardrails

1. **Non-Destructive VCS Lifecycle**: Before running `cm fix`, `cm verify`, or `cm vcs reset`, check `git status --porcelain`. If dirty, run `git stash push -u -m "cm-pre-fix-backup-$(date +%s)"` to protect uncommitted & untracked files, and ensure `.codemender/` is in `.git/info/exclude`. **After all fixes are committed, always run `git stash pop` to restore the user's stashed files.**
2. **Scalable Dynamic Build Probe & Outer-Shell Fallback**: Before setting `build.command` in `.codemender/config.yaml`, probe the binary in the shell (`command -v pytest`, `command -v python3`, `command -v node`) and confirm it exits `0`. If no unit test exists or `exebox` blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`), set `build.command: "true"` in `config.yaml` to prevent false rollbacks and run the real build/syntax check in the outer shell before `git commit`.
3. **Atomic Remediation**: When fixing multiple findings, fix 1 finding at a time, verify diff (`git diff`) and build in outer shell, commit the clean patch, and run `cm find . -y` before moving to the next finding. Restore stashed WIP (`git stash pop`) only after the entire loop completes.
4. **Sandboxing**: Never disable the sandbox (`--sandbox=false` or `--unrestricted`) without explicit operator approval. Use `cm verify <id> --skip-exploit-verification --no-reset --bypass-warning -y` for fast verification without sandbox socket hangs.
5. **Triage Integrity**: When a PoC exploit fails during `cm verify`, retain the finding as `OPEN / UNCONFIRMED` for manual review. Never prematurely dismiss unverified exploits as false positives.
6. **Zero Data-Loss Init**: Never pass `-y` to `cm init`. Guard with `if [ ! -f ... ]` to prevent silent overwriting of `.codemender/config.yaml`.
