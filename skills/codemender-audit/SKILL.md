---
name: codemender-audit
description: Autonomous security auditing, fast differential AST scanning, third-party report ingestion (Semgrep/Snyk), and sandboxed PoC exploit verification using Google Cloud CodeMender (cm). ACTIVATE this skill whenever scanning codebases, reviewing PR diffs, verifying vulnerabilities without false positives, or preparing SARIF security reports.
---

# CodeMender Autonomous Security Audit Skill

This skill guides coding agents (Antigravity, Claude Code, OpenAI Codex, Gemini CLI) to discover, triage, and verify security vulnerabilities using the Google Cloud CodeMender (`cm`) CLI.

It delivers **grounded, zero-false-positive security audits** by executing dynamic proof-of-concept (PoC) exploits inside an isolated local OS-level sandbox before presenting findings to developers.

---

## Quick Reference & Decision Tree

* **Scanning a freshly generated / vibe-coded application**: ➔ Run **Workflow A (Full Scan)**.
* **Scanning uncommitted Git changes or PR diff**: ➔ Run **Workflow B (Incremental Scan)**.
* **Verifying external SAST findings (Semgrep / Snyk / SonarQube)**: ➔ Run **Workflow C (Report Ingestion)**.
* **Eliminating false positives on candidate findings**: ➔ Run **Workflow D (PoC Verification)**.

---

## Phase 0: Stateless On-the-Fly Scoping Handshake

Before executing scans, ensure environment readiness and project isolation:

```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"

# 1. Verify cm binary
if ! command -v cm >/dev/null 2>&1; then
  echo "CodeMender CLI not found. Running installer..."
  bash "${PROJECT_ROOT}/scripts/install_cm.sh"
fi

# 2. Verify Google Cloud Application Default Credentials (ADC)
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "ADC credentials missing. Please run: gcloud auth application-default login"
fi

# 3. Initialize workspace if not already initialized
if [ ! -f "${PROJECT_ROOT}/.codemender/config.yaml" ]; then
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm init -y
fi
```

---

## Phase 1: Vulnerability Discovery Workflows

### Workflow A: Vibe-Coding Full Scan (New Project Hardening)
When a user asks to audit a newly created project or perform a comprehensive security pass:

```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y --compact
```
* CodeMender performs deep AST and taint analysis across all supported source files.
* Identifies unauthenticated endpoints, hardcoded credentials, open CORS policies, and injection sinks.

### Workflow B: Incremental Diff Scan (Fast PR / Pre-commit Check)
When the user has modified files and wants a fast safety check:

```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y --diff-only --compact
```
* Leverages local AST caching to scan **only modified code slices**.
* Completes in 5–15 seconds with minimal token consumption.

### Workflow C: Third-Party Report Ingestion
When the user supplies a SAST report from existing CI/CD tools:

```bash
# For Semgrep
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm report import -f semgrep.sarif

# For Snyk
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm report import -f snyk.json
```

---

## Phase 2: Grounded PoC Verification (Eliminating False Positives)

Raw static analysis findings can contain false positives. For every Critical or High candidate finding, **execute an autonomous exploit verification test**:

```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm verify <finding-id> -y --compact
```

### What happens under the hood:
1. The cloud reasoning engine synthesizes a customized exploit script (`poc.js`, `exploit.py`, or `exploit.sh`).
2. The local daemon executes the exploit inside an isolated OS-level process sandbox (`exebox`).
3. If the exploit triggers unexpected behavior (e.g., unauthorized data leak, SQL error, path traversal):
   - Status is marked as **Confirmed**.
   - Root Cause Analysis and reproduction artifacts are saved in `${PROJECT_ROOT}/.exploit/<finding-id>/REPORT.md`.
4. If the exploit fails, the finding is marked as **Unconfirmed / False Positive**, sparing developer fatigue.

> [!NOTE]
> For Web vulnerabilities (e.g. CORS, SQLi on HTTP endpoints), ensure the local application server or mock service is listening if the exploit makes HTTP network probes.

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
| `f-1a2b3c` | CRITICAL | Confirmed | CWE-89 (SQL Injection) | `src/auth/login.go:45` | `.exploit/f-1a2b3c/poc.js` |
| `f-4d5e6f` | HIGH | Confirmed | CWE-22 (Path Traversal) | `src/api/files.ts:88` | `.exploit/f-4d5e6f/exploit.py` |
| `f-7g8h9i` | MEDIUM | Unconfirmed | CWE-798 (Hardcoded Key) | `config/default.json:12` | Unverified |

### SARIF Export for CI/CD:
If requested, generate standard SARIF 2.1.0 output:
```bash
HOME="${PROJECT_ROOT}" cm report -f sarif > "${PROJECT_ROOT}/codemender-results.sarif"
```

Next Step: If confirmed vulnerabilities exist, proceed to **`codemender-remediate`** for context-aware patch generation with automated regression checks and re-attack validation.
