# CLAUDE.md - CodeMender Security Plugin Guidelines

> **Disclaimer**: This is not an official Google product. It is a community-maintained skill and plugin wrapper for the Google Cloud CodeMender (`cm`) CLI.

This document provides operational instructions for Anthropic Claude Code when executing security audits and patch remediations using the CodeMender CLI (`cm`).

---

## Command Patterns (Stateless On-the-Fly)

Always invoke `cm` on-the-fly with project-scoped environment variables, forwarding `GIT_CONFIG_GLOBAL` and `CLOUDSDK_CONFIG` so `git` and `gcloud` retain host configurations:

```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

# Protect localized .codemender state from 'cm fix' internal 'git clean -fd'
EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && [ -d "$(dirname "${EXCLUDE_FILE}")" ]; then
  for entry in ".codemender/" ".cm_project" ".exploit/"; do
    grep -qxF "$entry" "${EXCLUDE_FILE}" 2>/dev/null || echo "$entry" >> "${EXCLUDE_FILE}"
  done
fi

# Full or Incremental scan
HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y

# Fast semantic verification (Tier 1 default, 15-25s)
HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y

# Context-aware patch remediation
HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm fix <finding-id> -c "<guidance>" --bypass-warning -y
```

---

## Operational Guardrails

1. **Non-Destructive VCS Lifecycle**: Before running `cm fix`, `cm verify`, or `cm vcs reset`, check `git status --porcelain | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/)'`. If non-empty, run `git stash push -u -m "cm-pre-fix-backup-$(date +%s)"` and print the stash name. **After all fixes are committed, always run `git stash pop || echo "⚠️ Merge conflict..."` to restore the user's stashed files.**
2. **Scalable Dynamic Build Probe & Enforced Outer Hard Gate**: Probe the binary in the shell (`command -v pytest`, `command -v python3`, `command -v node`) and confirm it exits `0`. If no unit test exists or `exebox` blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`), set `build.command: "true"` in `config.yaml` and enforce `if ! eval "${OUTER_BUILD_CMD}"; then git checkout HEAD -- . && git clean -fd; continue; fi` in the outer shell before committing.
3. **Atomic Remediation (`git add -A`)**: Fix 1 finding at a time, validate build in the outer shell, run `git add -A && git commit -m "security(cm): ..."` (never `git commit -am`, which misses newly created files and leaves them vulnerable to `git clean -fd`), and run `cm find . -y` before moving to the next finding.
4. **Sandboxing & `--unrestricted` Warning**: `--unrestricted` disables **both** the filesystem sandbox AND the command policy denylist (`full system access`), creating a Prompt Injection $\rightarrow$ RCE risk on untrusted code. Require explicit per-invocation human confirmation and never run on untrusted repos outside an isolated VM/container. Never run `install_cm.sh` without explicit user permission.
5. **Triage Integrity**: When a PoC exploit fails during `cm verify`, retain the finding as `OPEN / UNCONFIRMED` for manual review. Never prematurely dismiss unverified exploits as false positives.
6. **Zero Data-Loss Init**: Never pass `-y` to `cm init`. Guard with `if [ ! -f ... ]` to prevent silent overwriting of `.codemender/config.yaml`.
