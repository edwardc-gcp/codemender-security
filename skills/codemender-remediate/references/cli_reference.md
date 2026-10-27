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
CM_HOME="${PROJECT_ROOT}/.codemender" \
CM_LOCATION="${CM_LOCATION:-global}" \
GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" \
CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" \
GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" \
GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" \
cm "$@"
```

---

## 2. Discovery & Scanning Commands (`cm find`)

CodeMender provides three distinct scanning modes (`Standard`, `Diff`, and `Deep`) plus flexible model and scope flags:

| Command | Purpose |
| :--- | :--- |
| `cm find . -y` | **Standard Scan**: Fast AST & taint scan of the target directory using the default `gemini-3.8-flash` model inside OS sandbox (`exebox`). When `scan.incremental: true` in `.codemender/config.yaml`, caches and diffs against `.codemender/state.db`. |
| `cm find ./src/auth/ -y` | Target a specific subdirectory or service module. |
| `cm find . --diff -y` | **Diff Scan (Uncommitted / PR)**: Native differential scan of modified files plus **1-hop impacted callers/callees** (`--diff-depth=1`), automatically detecting removed security controls and aggregating workers into a single unified session. |
| `cm find . --diff --staged -y` | **Pre-Commit Staged Diff Scan**: Scope differential impact analysis strictly to staged changes (`git diff --cached`). |
| `cm find . --diff=origin/main --fail-on=CRITICAL,HIGH -y` | **CI/CD PR Gate**: Scan branch delta against `origin/main` and exit with code `1` if `CRITICAL` or `HIGH` findings are detected. Use `--diff-job-timeout=15m` for large monolithic files. |
| `cm find . --deep --deep-workers=8 --deep-max-turns=5 -y` | **Deep Scan**: Exhaustive repository-wide parallel audit across all source files, merged into a single unified session, with exploratory turns per file capped by `--deep-max-turns` (default `5`). |
| `cm find . --include-hidden --enable-bash -y` | Include hidden directories/files (such as `.github/` and `.config/`) and allow shell command execution (`run_command`) during discovery. |
| `cm find . -y -c "Focus on SQL injection and auth bypass"` | Scan with explicit architectural or threat-modeling context. |
| `cm find . --model gemini-4-argon -y` | Use **Gemini 4 Argon** (`1M` unified token context) for complex cross-file reasoning. Automatically falls back to `gemini-3.8-flash-cyber` / `gemini-3.8-flash` on cyber safety blocks unless `--no-model-fallback` is set. |

---

## 3. Verification Modes (`cm verify`)

| Command | Purpose |
| :--- | :--- |
| `cm verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y` | **(Tier 1 Default — Fast & Safe)** Deep LLM taint & reachability verification without re-running active exploit scripts after verification. Automatically tracks code that moved since `cm find` and updates finding line numbers. |
| `cm verify <finding-id> --no-reset --bypass-warning -y` | **(Tier 2 Dynamic Sandbox PoC)** Synthesize and execute an autonomous PoC exploit script (`.exploit/exploit.sh`, automatically `chmod +x`) inside the local OS-level sandbox (`exebox`) while suppressing workspace resets. |
| `cm verify <finding-id> --model gemini-4-argon --no-reset --bypass-warning -y` | Run verification using Gemini 4 Argon (with automatic safety-block fallback to `gemini-3.8-flash-cyber` / `gemini-3.8-flash`). |
| `cm verify <finding-id> --unrestricted --no-reset --bypass-warning -y` | **(CRITICAL RCE HAZARD — Explicit Per-Invocation Human Consent Required)** Disables BOTH `exebox` filesystem sandboxing AND the command policy denylist (`full system access`). Only run in isolated VMs/containers on trusted code. |

> [!IMPORTANT]
> **Exploit Verification Triage**: If an exploit script fails or times out (`EXPLOIT_FAILED`), do NOT classify the finding as a "False Positive". Dynamic exploits frequently fail due to `exebox` blocking local TCP sockets or non-system binary paths. Findings must remain classified as `UNCONFIRMED / OPEN` unless explicitly marked `DISMISSED` with concrete sanitizer/unreachability proof.

### Generated Verification Artifacts (in `${PROJECT_ROOT}/.exploit/`):
* `PLAN.md`: Reasoning steps and attack strategy formulated by the verification agent.
* `LOG.md`: Execution trace, network calls, and sandbox telemetry.
* `poc.js` / `exploit.py`: Executable proof-of-concept exploit script.
* `exploit.sh`: Standalone executable (`chmod +x`) bash test harness running the exploit.
* `REPORT.md`: Root Cause Analysis (RCA), vulnerable call stack, and remediation guidance.

---

## 4. Third-Party SAST Import & Reporting (`cm report`)

| Command | Purpose |
| :--- | :--- |
| `cm report import -f findings.sarif` | Ingest external findings from basic SARIF v2.1.0 files (e.g., Semgrep, CodeQL). |
| `cm report import -f findings.json` | Ingest external findings from Simple JSON format (`cm report import` supports Simple JSON and basic SARIF). |
| `cm report -f table` | Print interactive terminal summary table from local SQLite state database (`.codemender/state.db`). |
| `cm report -f json` | Output bare JSON array of findings (`finding_id`, `severity`, `status`, `vuln_id`, `start_line`, `end_line`). |
| `cm report -f sarif > results.sarif` | Export enhanced OASIS SARIF v2.1.0 report with standardized rule descriptors, severity properties, and repository-relative artifact paths for GitHub Code Scanning / Google Cloud SCC. |
| `cm report -f html > report.html` | Export self-contained HTML audit dashboard. |

---

## 5. Remediation & Patching (`cm fix` & `cm build`)

| Command | Purpose |
| :--- | :--- |
| `cm fix <finding-id> --bypass-warning -y` | Synthesize targeted scoped patch (preventing out-of-scope edits to CI/CD or build configs), validate with `build.command`, and apply to working tree. |
| `cm fix <finding-id> -c "Preserve existing auth middleware" --bypass-warning -y` | Provide constraint context to the remediation agent. |
| `cm fix <finding-id> --model gemini-4-argon --bypass-warning -y` | Synthesize complex architectural patches using Gemini 4 Argon. |
| `cm fix <finding-id> --no-cache --bypass-warning -y` | Bypass cached patch candidates and generate a fresh fix session. |
| `cm build --force` | Execute the project `build.command` configured in `.codemender/config.yaml` to verify compilation and tests. |

> [!CAUTION]
> Always stash uncommitted and untracked work (`git stash push -u -m "cm-pre-fix-backup-$(date +%s)"`) before `cm fix`, stage ALL modified and newly created files (`git add -A && git commit -m ...`), and restore stashed work (`git stash pop`) with conflict checking after committing all patches!

---

## 6. Session Lifecycle, Token Telemetry & CLI Maintenance

| Command | Purpose |
| :--- | :--- |
| `cm session list` | View active and historical unified sessions from `${PROJECT_ROOT}/.codemender/state.db`. |
| `cm session resume <session-id>` | Resume an interrupted audit session after a network glitch or `Ctrl+C` interrupt. |
| `cm session cancel <session-id>` | Cancel an active background session. |
| `cm stats` | Inspect cumulative all-turn token usage diagnostics (input, output, cached, reasoning) across local session logs. |
| `cm stats --json` | Output structured JSON telemetry including **model invocation metrics** (total, per-session, and per-turn invocation counts) and token usage. |
| `cm clean` | Purge local findings cache (`state.db`), HTML dashboards, and `.bak` patch backup files. |
| `cm update` | Verify local binary SHA-256 against the official release manifest and atomically update `cm` to the latest release (requires user confirmation). |
