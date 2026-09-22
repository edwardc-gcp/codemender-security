---
name: codemender-audit
description: Autonomous security auditing, fast differential AST scanning, third-party report ingestion (Semgrep/Snyk), and sandboxed PoC exploit verification using Google Cloud CodeMender (cm). ACTIVATE this skill whenever scanning codebases, reviewing PR diffs, verifying vulnerabilities without false positives, or preparing SARIF security reports.
---

# CodeMender Autonomous Security Audit Skill

This skill guides coding agents (Antigravity, Claude Code, OpenAI Codex, Gemini CLI) to discover, triage, and verify security vulnerabilities using the Google Cloud CodeMender (`cm`) CLI.

It delivers **grounded, empirical security audits** by executing dynamic proof-of-concept (PoC) exploits inside an isolated local OS-level sandbox before presenting findings to developers.

---

## Quick Reference & Decision Tree

* **Scanning a freshly generated / vibe-coded application**: ➔ Run **Workflow A (Full Scan)**.
* **Scanning uncommitted Git changes or PR diff**: ➔ Run **Workflow B (Incremental Scan)**.
* **Verifying external SAST findings (Semgrep / Snyk / SonarQube)**: ➔ Run **Workflow C (Report Ingestion)**.
* **Confirming exploitability on candidate findings**: ➔ Run **Workflow D (PoC Verification)**.

---

## Phase 0: Stateless On-the-Fly Scoping Handshake

Before executing scans, ensure environment readiness and project isolation:

```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

# 1. Verify cm binary
PLUGIN_ROOT="${REAL_HOME}/.gemini/config/plugins/codemender-security"
if ! command -v cm >/dev/null 2>&1; then
  echo "CodeMender CLI not found. Running installer..."
  bash "${PLUGIN_ROOT}/scripts/install_cm.sh"
fi

# 2. Verify Google Cloud Application Default Credentials (ADC)
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "ADC credentials missing. Please run: gcloud auth application-default login"
fi

# 3. Protect localized .codemender state from internal 'git clean -fd' (supports worktrees & submodules)
EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && [ -d "$(dirname "${EXCLUDE_FILE}")" ]; then
  for entry in ".codemender/" ".cm_project" ".exploit/"; do
    grep -qxF "$entry" "${EXCLUDE_FILE}" 2>/dev/null || echo "$entry" >> "${EXCLUDE_FILE}"
  done
fi

# 4. Initialize workspace if not already initialized
if [ ! -f "${PROJECT_ROOT}/.codemender/config.yaml" ]; then
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm init
fi
```

---

## Phase 1: Vulnerability Discovery Workflows

### Workflow A: Vibe-Coding Full Scan (New Project Hardening)
When a user asks to audit a newly created project or perform a comprehensive security pass:

```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y
```
* CodeMender performs deep AST and taint analysis across all supported source files.
* Identifies unauthenticated endpoints, hardcoded credentials, open CORS policies, and injection sinks.

### Workflow B: Incremental Diff Scan (Fast PR / Pre-commit Check)
When the user has modified files and wants a fast safety check:

```bash
# Leverages .codemender/state.db when scan.incremental is true (default in config.yaml)
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y

# Or target specifically modified paths:
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find ./src/auth/ -y
```
* Leverages local AST caching to scan **only modified code slices**.
* Completes in 5–15 seconds with minimal token consumption.

### Workflow C: Third-Party Report Ingestion
When the user supplies a SAST report from existing CI/CD tools:

```bash
# For Semgrep
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report import -f semgrep.sarif

# For Snyk
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report import -f snyk.json
```

### Workflow D: Surgical `.codemender/config.yaml` Tuning (Troubleshooting Coverage & Performance)
CodeMender intentionally ships with a conservative default `config.yaml` to minimize scan latency and token usage. **Do NOT proactively dump all possible extensions into `config.yaml` upfront.** Instead, inspect and surgically tune `${PROJECT_ROOT}/.codemender/config.yaml` (see `references/config_schema.md`) when encountering specific symptoms:

1. **Missed Vulnerabilities or `0 files scanned` (Coverage Gap)**:
   * **Root Cause**: `scan.extensions.include` defaults strictly to `[".py", ".java", ".go", ".js", ".ts", ".c", ".cc", ".cpp", ".h", ".rb", ".php"]`. Files with other suffixes or files exceeding `scan.max_file_size_kb: 500` are silently skipped.
   * **Surgical Fix**: Check the target repository's primary source files (`git ls-files`) and append **only the specific suffixes needed for that project** (e.g., add `".tsx", ".jsx"` for Next.js/React, `".mjs"` for ES modules, `".rs"` for Rust, `".kt"` for Kotlin, `".swift"` for Swift, or `".cs"` for C#), then re-run `cm find`.
2. **Slow Scan Performance or High Token Usage (Scope Bloat)**:
   * **Root Cause**: `scan.exclude_dirs` defaults only to `["node_modules"]`. If the repo contains local virtual environments or build outputs, `cm find` will scan thousands of third-party `site-packages` or compiled bundles.
   * **Surgical Fix**: Add present artifact/dependency directories (e.g., `".venv"`, `"venv"`, `".next"`, `"dist"`, `"build"`, `"vendor"`, `"target"`) to `scan.exclude_dirs`.
3. **Traceability Principle for `tools.confirm_*`**:
   * Leave `tools.confirm_commands: true` and `tools.confirm_writes: true` untouched in `.codemender/config.yaml`. Always pass `-y` / `--bypass-warning` explicitly on the CLI so automated actions remain visible and traceable in command logs.

---

## Phase 2: Scalable 2-Tier Verification (Eliminating False Positives Without Sandbox Deadlocks)

Raw static analysis findings can contain false positives. However, on macOS/Linux developer machines, `cm`'s internal `exebox` (`sandbox-exec`) blocks local TCP port binding (`localhost:<port>`) and blocks `process-exec*` on toolchains installed outside `/usr/bin` (such as `~/.nvm`, `/opt/homebrew`, `~/.pyenv`), causing dynamic verification loops to hang for 15–20 minutes.

Use the **Scalable 2-Tier Verification Architecture**:

### Tier 1 (Default — Fast Semantic & Taint Verification, 15–25s):
Run `cm verify` with the native `--skip-exploit-verification` flag to execute deep cloud taint-flow, reachability, and sanitizer verification **without** spawning blocked sandbox sockets:
```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y
```

### Tier 2 (Dynamic Exploit Execution — When Live PoC Execution is Required):
* **System-Binary CLI / Library Targets**: Run in the default sandbox (`exebox`):
  ```bash
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm verify <finding-id> --no-reset --bypass-warning -y
  ```
* **Web Servers (`localhost` TCP ports) or Homebrew/NVM/pyenv Toolchains**: Because `exebox` blocks TCP sockets and non-`/usr/bin` binaries at the OS kernel level (and `-c` prompts cannot bypass kernel sandbox rules), first stash uncommitted files (`git stash push -u`) and run with `--unrestricted` (when approved/safe):
  ```bash
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm verify <finding-id> --unrestricted --no-reset --bypass-warning -y
  ```

### Triage Integrity Rules:
1. Check `cm report -f json` and `${PROJECT_ROOT}/.exploit/` (`PLAN.md`, `LOG.md`, `REPORT.md`).
2. If dynamic exploit execution fails or times out, retain the finding as **`OPEN / UNCONFIRMED`** for manual security inspection.
   > [!WARNING]
   > Do **NOT** classify failed dynamic PoC executions as false positives. Only treat a finding as a False Positive when `cm verify` explicitly marks the status `DISMISSED` with concrete code-level proof.

---

## Phase 3: Reporting & Presentation

Display the triage summary to the user:

```bash
HOME="${PROJECT_ROOT}" cm report -f md
```

### Presentation Format:
Present findings in a structured Markdown table:

| Finding ID | Severity | Status | CWE | Vulnerable Location | Verified PoC |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `f-1a2b3c` | CRITICAL | OPEN (Verified) | CWE-89 (SQL Injection) | `src/auth/login.go:45` | `.exploit/f-1a2b3c/poc.js` |
| `f-4d5e6f` | HIGH | OPEN (Verified) | CWE-22 (Path Traversal) | `src/api/files.ts:88` | `.exploit/f-4d5e6f/exploit.py` |
| `f-7g8h9i` | MEDIUM | OPEN (Unverified) | CWE-798 (Hardcoded Key) | `config/default.json:12` | — |

### SARIF Export for CI/CD:
If requested, generate standard SARIF 2.1.0 output:
```bash
HOME="${PROJECT_ROOT}" cm report -f sarif > "${PROJECT_ROOT}/codemender-results.sarif"
```

Next Step: If confirmed vulnerabilities exist, proceed to **`codemender-remediate`** for context-aware patch generation with automated regression checks and re-attack validation.
