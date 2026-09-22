# CodeMender CLI Advanced Command & Architecture Reference

## 1. Stateless On-the-Fly Invocation Pattern

To ensure clean isolation when running across multiple concurrent projects or agent workspaces on the same machine without losing host `git` or `gcloud` configurations, all commands should be executed statelessly per invocation:

```bash
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

HOME="${PROJECT_ROOT}" \
GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" \
CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" \
GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" \
GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" \
cm "$@"
```

---

## 2. Discovery & Scanning Commands (`cm find`)

| Command | Purpose |
| :--- | :--- |
| `cm find . -y` | Full codebase AST scan using default `gemini-3.8-flash` reasoning engine inside OS sandbox (`exebox`). |
| `cm find . -y` *(Incremental)* | When `scan.incremental: true` in `.codemender/config.yaml`, CodeMender automatically diffs AST against `.codemender/state.db` and only scans modified files (5-15s). |
| `cm find ./src/auth/ -y` | Target a specific subdirectory or modified service module. |
| `cm find . -y -c "Focus on SQL injection and auth bypass"` | Scan with explicit contextual guidance. |
| `cm find . --model gemini-3.1-pro-preview -y` | Use deep reasoning model for intricate inter-procedural flows. |

> [!NOTE]
> `cm find` does not take a `--diff-only` CLI flag. Incremental differential analysis is managed automatically via `scan.incremental: true` in `.codemender/config.yaml` using the SQLite AST database (`.codemender/state.db`).

---

## 3. Verification Modes (`cm verify`)

| Command | Purpose |
| :--- | :--- |
| `cm verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y` | **(Tier 1 Default — Fast & Safe)** Deep LLM taint & reachability verification without running active exploit scripts or hitting `exebox` socket blocks. |
| `cm verify <finding-id> --no-reset --bypass-warning -y` | Synthesize and run an autonomous PoC exploit script inside the local OS-level sandbox (`exebox`) while suppressing workspace resets. |
| `cm verify <finding-id> --unrestricted --no-reset --bypass-warning -y` | **(CRITICAL RCE HAZARD — Explicit Per-Invocation Human Consent Required)** Disables BOTH `exebox` filesystem sandboxing AND the command policy denylist (`full system access`). Only run in isolated VMs/containers on trusted code. |

> [!IMPORTANT]
> **Exploit Verification Triage**: If an exploit script fails or times out (`EXPLOIT_FAILED`), do NOT classify the finding as a "False Positive". Dynamic exploits frequently fail due to `exebox` blocking local TCP sockets or non-system binary paths. Findings must remain classified as `UNCONFIRMED / OPEN` unless explicitly marked `DISMISSED` with concrete sanitizer/unreachability proof.

### Generated Verification Artifacts (in `${PROJECT_ROOT}/.exploit/`):
* `PLAN.md`: Reasoning steps and attack strategy formulated by the verification agent.
* `LOG.md`: Execution trace, network calls, and sandbox telemetry.
* `poc.js` / `exploit.py`: Executable proof-of-concept exploit script.
* `exploit.sh`: Standalone bash test harness executing the exploit.
* `REPORT.md`: Root Cause Analysis (RCA), vulnerable call stack, and remediation guidance.

---

## 4. Third-Party SAST Import & Reporting (`cm report`)

| Command | Purpose |
| :--- | :--- |
| `cm report import -f findings.sarif` | Ingest external findings from basic SARIF v2.1.0 files (e.g., Semgrep). |
| `cm report import -f findings.json` | Ingest external findings from Simple JSON format (`cm report import` supports Simple JSON and basic SARIF). |
| `cm report -f table` | Print interactive terminal summary table from SQLite state database. |
| `cm report -f json` | Output bare JSON array of findings (`finding_id`, `severity`, `status`, `patch_status`). |
| `cm report -f sarif > results.sarif` | Export OASIS SARIF v2.1.0 report for GitHub Code Scanning / SCC. |
| `cm report -f html > report.html` | Export self-contained HTML audit dashboard. |

---

## 5. Remediation & Patching (`cm fix`)

| Command | Purpose |
| :--- | :--- |
| `cm fix <finding-id> --bypass-warning -y` | Synthesize targeted patch, apply in isolated candidate branch, verify with `build.command`, and apply to working tree. |
| `cm fix <finding-id> -c "Preserve existing auth middleware" --bypass-warning -y` | Provide constraint context to the remediation agent. |
| `cm fix <finding-id> --no-cache --bypass-warning -y` | Bypass cached patch candidates and generate a fresh fix session. |

> [!CAUTION]
> Always stash uncommitted and untracked work (`git stash push -u -m "cm-pre-fix-backup-$(date +%s)"`) before `cm fix`, stage ALL modified and newly created files (`git add -A && git commit -m ...`), and restore stashed work (`git stash pop`) with conflict checking after committing all patches!

---

## 6. Session Lifecycle & Token Diagnostics

| Command | Purpose |
| :--- | :--- |
| `cm session list` | View active and historical sessions from `${PROJECT_ROOT}/.codemender/state.db`. |
| `cm session resume <session-id>` | Resume an interrupted audit session after a network glitch or timeout. |
| `cm session cancel <session-id>` | Cancel an active background session. |
| `cm stats` | Inspect token usage diagnostics (input, output, cached, reasoning). |
| `cm clean` | Purge local findings cache and temporary exploit outputs. |
