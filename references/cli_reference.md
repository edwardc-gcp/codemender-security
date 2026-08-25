# CodeMender CLI Advanced Command & Architecture Reference

## 1. Complete Command Catalog

### Discovery (`cm find`)
* `cm find . -y --unrestricted --model gemini-3.5-flash`: Full codebase scan.
* `cm find . -y --diff-only --unrestricted`: Scan only uncommitted Git changes or PR diffs.
* `cm find . -y --severity CRITICAL,HIGH --unrestricted`: Focus on high-risk findings.
* `cm find . -y --compact --unrestricted`: Single-line terminal summary with live token counter.

### Exploit Verification (`cm verify`)
* `cm verify <id> --unrestricted --bypass-warning -y --model gemini-3.5-flash`: Execute autonomous PoC exploit test.
* **Captured Artifacts** (stored under `<target-dir>/.exploit/`):
  - `info.yaml`: Severity, confidence, and CWE tags.
  - `PLAN.md`: Reasoning steps taken by the verification agent.
  - `LOG.md`: Audit trace of HTTP probes and port bindings.
  - `poc.js` / `exploit.py`: Executable exploit proof-of-concept.
  - `exploit.sh`: Standalone test wrapper.
  - `REPORT.md`: Root Cause Analysis (RCA) and remediation guidance.

### Remediation (`cm fix`)
* `cm fix <id> --unrestricted -y`: Basic patch synthesis.
* `cm fix <id> -c "<guidance>" --unrestricted -y`: Domain-guided patch (e.g. `-c "Use Google Secret Manager"`).
* `cm fix <id> --model gemini-3.1-pro-preview --unrestricted -y`: Deep reasoning for complex cross-file refactors.
* `cm fix <id> --no-cache --unrestricted -y`: Force fresh patch generation.
* `cm fix --all --unrestricted -y`: Batch remediate all open findings.

### VCS & Rollback (`cm vcs`)
* `cm vcs status`: View changed files.
* `cm vcs diff`: Inspect synthesized unified diffs.
* `cm vcs revert`: Roll back patches if test suite fails.

### Third-Party SARIF Ingestion (`cm report import`)
* `cm report import -f semgrep.sarif`: Ingest Semgrep findings.
* `cm report import -f snyk.json`: Ingest Snyk findings.
* `cm report import -f sonar.sarif`: Ingest SonarQube findings.
* *Follow-up*: Run `cm verify <imported-id>` or `cm fix <imported-id>` to remediate third-party findings.

### Session Lifecycle (`cm session`)
* `cm session list`: View active and historical sessions in `~/.codemender/state.db`.
* `cm session resume <session-id>`: Resume an interrupted session.
* `cm session cancel <session-id>`: Abort a running session.
* `cm stats`: Inspect token consumption and API request metrics.
* `cm clean`: Purge local SQLite cache and temporary files.

---

## 2. Model Selection Strategy

| Model | Speed / Latency | Ideal Use Case |
| :--- | :--- | :--- |
| `gemini-3.5-flash` (Default) | Ultra-fast (< 15s) | Codebase discovery (`cm find`), simple single-file fixes, CI/CD pipelines. |
| `gemini-3.1-pro-preview` | Deep Reasoning (30-60s) | Complex taint analysis, multi-file architectural refactoring, framework migrations. |

---

## 3. Troubleshooting & Error Matrix

| Error Message | Cause | Resolution |
| :--- | :--- | :--- |
| `cm: command not found` | Binary missing or PATH not set | Run `bash ~/.gemini/config/skills/codemender-security/scripts/install_cm.sh` and export `PATH=~/bin:$PATH`. |
| `ADC: Could not load default credentials` | ADC missing or expired | Run `gcloud auth application-default login`. |
| `HTTP 403: Permission denied` | Missing `roles/aiplatform.user` | Run `gcloud projects add-iam-policy-binding <PROJECT> --member=user:<EMAIL> --role=roles/aiplatform.user`. |
| `Build verification failed after fix` | Patch broke tests | Run `cm fix <id> -c "Fix test error: <msg>"` or run `cm vcs revert`. |
| `Session interrupted by disconnect` | Network timeout during verify | Run `cm session resume <session-id>`. |
