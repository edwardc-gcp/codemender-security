# CodeMender CLI Advanced Command & Architecture Reference

## 1. Stateless On-the-Fly Invocation Pattern

To ensure clean isolation when running across multiple concurrent projects or agent workspaces on the same machine, all commands should be executed statelessly per invocation, avoiding wrapper scripts:

```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

HOME="${PROJECT_ROOT}" \
GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-${REAL_HOME}/.config/gcloud/application_default_credentials.json}" \
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

## 3. Sandboxed Exploit Verification (`cm verify`)

| Command | Purpose |
| :--- | :--- |
| `cm verify <finding-id> -y` | Synthesize and run an autonomous PoC exploit script inside the local OS-level sandbox (`exebox`). |
| `cm verify <finding-id> --no-reset -y` | Run verification while suppressing workspace resets (`git checkout HEAD -- . && git clean -fd`). |
| `cm verify <finding-id> --skip-exploit-verification` | Perform static verification only without running active exploit scripts. |
| `cm verify <finding-id> -c "Server listens on port 8080" -y` | Provide runtime port or service context to the verification agent. |

> [!IMPORTANT]
> **Exploit Verification Triage**: If an exploit script fails (`EXPLOIT_FAILED`), do NOT classify the finding as a "False Positive". Dynamic exploits frequently fail due to offline local servers or environment dependencies. Findings should remain classified as `UNCONFIRMED / OPEN` until verified or intentionally dismissed by a security engineer (`DISMISSED`).

### Generated Verification Artifacts (in `${PROJECT_ROOT}/.exploit/<id>/`):
* `info.yaml`: Finding metadata, severity, confidence score, CWE identifiers.
* `PLAN.md`: Reasoning steps and attack strategy formulated by the verification agent.
* `LOG.md`: Execution trace, network calls, and sandbox telemetry.
* `poc.js` / `exploit.py`: Executable proof-of-concept exploit script.
* `exploit.sh`: Standalone bash test harness executing the exploit.
* `REPORT.md`: Root Cause Analysis (RCA), vulnerable call stack, and remediation guidance.

---

## 4. Third-Party SAST Import & Reporting (`cm report`)

| Command | Purpose |
| :--- | :--- |
| `cm report import -f semgrep.sarif` | Ingest findings from Semgrep for PoC verification and patch synthesis. |
| `cm report import -f snyk.json` | Ingest findings from Snyk CLI export. |
| `cm report import -f sonar.sarif` | Ingest findings from SonarQube / SonarCloud. |
| `cm report -f table` | Print interactive terminal summary table from SQLite state database. |
| `cm report -f md` | Export native Markdown vulnerability summary. |
| `cm report -f sarif > results.sarif` | Export OASIS SARIF v2.1.0 report for GitHub Code Scanning / SCC. |
| `cm report -f html > report.html` | Export self-contained HTML audit dashboard. |

---

## 5. Remediation & Patching (`cm fix`)

| Command | Purpose |
| :--- | :--- |
| `cm fix <finding-id> -y` | Synthesize targeted patch, apply in isolated candidate branch, verify with `build.command`, and present diff. |
| `cm fix <finding-id> -c "Preserve existing auth middleware" -y` | Provide constraint context to the remediation agent. |
| `cm fix <finding-id> --no-cache -y` | Bypass cached patch candidates and generate a fresh fix session. |

---

## 6. Session Lifecycle & Token Diagnostics

| Command | Purpose |
| :--- | :--- |
| `cm session list` | View active and historical sessions from `${PROJECT_ROOT}/.codemender/state.db`. |
| `cm session resume <session-id>` | Resume an interrupted audit session after a network glitch or timeout. |
| `cm session cancel <session-id>` | Cancel an active background session. |
| `cm stats` | Inspect token usage diagnostics (input, output, cached, reasoning). |
| `cm clean` | Purge local findings cache and temporary exploit outputs. |
