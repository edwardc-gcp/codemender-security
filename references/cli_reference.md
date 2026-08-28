# CodeMender CLI Advanced Command & Architecture Reference

## 1. Complete Command Catalog

### Discovery (`cm find`)
* `cm find . -y --unrestricted --model gemini-3.7-flash`: Full codebase scan (Gemini 3.7 Flash default).
* `cm find . -y --diff-only --unrestricted`: Scan only uncommitted Git changes or PR diffs (Incremental reconciliation).
* `cm find . -y --severity CRITICAL,HIGH --unrestricted`: Focus on high-impact findings.
* `cm find . -y --compact --unrestricted`: Single-line terminal summary with live rolling token counter (`Tokens: 40k in / 12k out / 60k total`).
* `cm find . --sandbox=false -y`: Disable local process sandbox (recommended only in isolated disposable VMs/containers).
* `cm find . --team-id "secops-team" -y`: Attach multi-tenant team telemetry identifier.

### Exploit Verification (`cm verify`)
* `cm verify <id> --unrestricted --bypass-warning -y --model gemini-3.7-flash`: Execute autonomous PoC exploit test in isolated sandbox.
* **Captured Artifacts** (stored under `<target-dir>/.exploit/<id>/`):
  - `info.yaml`: Severity, confidence, and CWE tags.
  - `PLAN.md`: Reasoning steps taken by the verification agent.
  - `LOG.md`: Audit trace of HTTP probes and port bindings.
  - `poc.js` / `exploit.py`: Executable exploit proof-of-concept.
  - `exploit.sh`: Standalone test wrapper.
  - `REPORT.md`: Root Cause Analysis (RCA) and remediation guidance.

### Remediation (`cm fix`)
* `cm fix <id> --unrestricted -y`: Basic patch synthesis.
* `cm fix <id> -c "<guidance>" --unrestricted -y`: Domain-guided patch (e.g. `-c "Use Google Secret Manager and parameterized queries"`).
* `cm fix <id> --model gemini-3.1-pro-preview --unrestricted -y`: Deep reasoning for complex cross-file refactors.
* `cm fix <id> --no-cache --unrestricted -y`: Force fresh patch generation bypassing cached inferences.
* Batch remediation in CI: `for id in $(cm report -f json | jq -r '.[].id'); do cm fix "$id" -y --unrestricted; done`

### VCS & Rollback (`cm vcs`)
* `cm vcs status`: View modified and staged files.
* `cm vcs diff`: Inspect synthesized unified diffs.
* `cm vcs reset`: Discard uncommitted patches and restore workspace if test suite fails.
* `cm vcs stage`: Stage synthesized patches to Git index.

### Compliance Reporting (`cm report` & `cm report import`)
* `cm report -f table`: Print interactive terminal table from local session cache.
* `cm report -f md`: Export native Markdown vulnerability summary.
* `cm report -f sarif > results.sarif`: OASIS SARIF v2.1.0 for GitHub Code Scanning / CI/CD.
* `cm report -f html > report.html`: Interactive standalone HTML audit dashboard.
* `cm report import -f semgrep.sarif`: Ingest Semgrep findings.
* `cm report import -f snyk.json`: Ingest Snyk findings.
* `cm report import -f sonar.sarif`: Ingest SonarQube findings.

### Session Lifecycle & Maintenance (`cm session` / `cm update` / `cm clean`)
* `cm session list`: View active and historical sessions in `~/.codemender/state.db`.
* `cm session resume <session-id>`: Resume an interrupted session after network disconnect.
* `cm session cancel <session-id>`: Abort a running session.
* `cm stats`: Inspect local token consumption breakdown (input, output, cached, thought, tool-use).
* `cm update`: Force immediate check and atomic binary upgrade.
* `cm clean`: Purge local SQLite cache and temporary files in the current workspace.

---

## 2. Process-Level Sandboxing Architecture

CodeMender CLI enables local process-level sandboxing by default to protect host systems from untrusted tool side-effects:

* **Linux**: Leverages Linux kernel namespaces (`CLONE_NEWNS`, `CLONE_NEWUSER`) and `seccomp` filters to restrict system calls and file visibility.
* **macOS**: Leverages Apple's built-in `sandbox-exec` (Seatbelt) engine to restrict filesystem writes and outbound network access.
* **Windows (Experimental)**: Uses `AppContainer` isolation and Access Control Lists (ACLs).

To configure network isolation profiles (`permissive-closed` vs `permissive-open`) and read-only file mounts (`protected_files`), configure `.codemender/config.yaml`.

---

## 3. State Machine & Session Hygiene in Daily Workflows

In multi-turn engineering environments, follow these rules:

1. **Git-Root Anchoring**: Always execute commands with the repository root as target (`git rev-parse --show-toplevel`). This ensures `~/.codemender/state.db` maps cleanly to the active project.
2. **Incremental Reconciliation**: When making feature changes, run `cm find . -y --diff-only` to update finding statuses without triggering full AST re-scans.
3. **PoC Reuse**: Check if `.exploit/<id>/REPORT.md` exists before re-running `cm verify <id>`.
4. **Controlled Cleanup**: Never run `cm clean` automatically during routine tasks; only run it when starting a fresh repository or when explicitly requested by the developer.

---

## 4. Model Selection Strategy

| Model | Speed / Latency | Ideal Use Case |
| :--- | :--- | :--- |
| `gemini-3.7-flash` (Default) | Ultra-fast (< 15s) | Primary engine for codebase discovery (`cm find`), exploit verification, and contextual patch synthesis. |
| `gemini-3.6-flash` | Ultra-fast (< 15s) | High-throughput AST scanning and rapid verification. |
| `gemini-3.5-flash` | Fast (< 25s) | Standard lightweight Flash backend. |
| `gemini-3.1-pro-preview` | Deep Reasoning (30-60s) | Complex inter-procedural taint analysis, multi-file architectural refactoring, framework migrations. |

---

## 5. Troubleshooting & Error Matrix

| Error Message | Cause | Resolution |
| :--- | :--- | :--- |
| `cm: command not found` | Binary missing or PATH not set | Run `bash ~/.gemini/config/skills/codemender-security/scripts/install_cm.sh` and export `PATH=~/bin:$PATH`. |
| `ADC: Could not load default credentials` | ADC missing or expired | Run `gcloud auth application-default login`. |
| `HTTP 403: Permission denied` | Missing `roles/aiplatform.user` | Run `gcloud projects add-iam-policy-binding <PROJECT> --member=user:<EMAIL> --role=roles/aiplatform.user`. |
| `Build verification failed after fix` | Patch broke tests | Run `cm fix <id> -c "Fix test error: <msg>"` or run `cm vcs reset`. |
| `Session interrupted by disconnect` | Network timeout during verify | Run `cm session resume <session-id>`. |
| `Sandbox failed to initialize (relative path)` | Outdated CLI version | Run `cm update` to update to the latest release. |
