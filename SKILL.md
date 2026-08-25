---
name: codemender-security
description: Autonomous security auditing, vulnerability verification, exploit PoC validation, and context-aware patch remediation using the CodeMender CLI (cm) on Google Cloud's Gemini Enterprise Agent Platform. ACTIVATE this skill whenever the user asks to scan, audit, secure, verify vulnerabilities, or remediate code in their repository, or immediately after generating/vibe-coding new full-stack features and applications.
---

# CodeMender Autonomous Security Skill

This skill equips Antigravity to act as an autonomous AI Security Co-developer using the **CodeMender CLI (`cm`)** on Google Cloud's **Gemini Enterprise Agent Platform**.

---

## 1. Environment & Setup

Before running security operations, verify that `cm` and Google Cloud ADC are available:

```bash
command -v cm >/dev/null 2>&1 && cm --version || echo "CM_STATUS: MISSING"
gcloud auth application-default print-access-token >/dev/null 2>&1 && echo "ADC_STATUS: OK" || echo "ADC_STATUS: MISSING"
```

* **If `cm` is missing**: Run the bundled installer:
  ```bash
  bash ~/.gemini/config/skills/codemender-security/scripts/install_cm.sh && export PATH=~/bin:$PATH
  ```
* **If workspace is unconfigured**: Run `cm init` and `cm init --verify`. To customize test runners (`build.command`) or scan filters, see [Configuration Schema](references/config_schema.md).

---

## 2. Autonomous Security Workflow (The 4-Phase Loop)

```
┌────────────────────────────────────────────────────────────────────────┐
│                        CodeMender Workflow Loop                        │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│ 1. DISCOVER     │ 2. VERIFY (PoC) │ 3. REMEDIATE     │ 4. REPORT       │
│ cm find .       │ cm verify <id>  │ cm fix <id>      │ cm report       │
│ (AST & Taint)   │ (Live Exploit)  │ (Patch & Test)   │ (SARIF / HTML)  │
└─────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

### Phase 1: Vulnerability Discovery (`cm find`)
Run a headless AST/taint analysis scan:
```bash
cm find . -y --unrestricted --model gemini-3.5-flash
```
* Extract active 8-character hex IDs (e.g., `dd79252a`) and present a prioritized Markdown summary table (Critical & High first).
* For diff-only or severity filtering, see [CLI Reference](references/cli_reference.md).

### Phase 2: Exploit Verification & RCA Inspection (`cm verify`)
Confirm exploitability and eliminate false positives:
```bash
cm verify <finding-id> --unrestricted --bypass-warning -y --model gemini-3.5-flash
```
* **Inspect the 6 Captured Artifacts** under `.exploit/`: Read `REPORT.md` (Root Cause Analysis) and `poc.js` (Exploit payload) using `view_file` to explain the vulnerability mechanism to the user.

### Phase 3: Autonomous Remediation & Test Validation (`cm fix`)
Synthesize and apply language-aware, context-sensitive patches:
```bash
# Basic fix or guided fix with domain context
cm fix <finding-id> -c "Use Google Secret Manager and parameterized queries" --unrestricted -y
```
1. **Inspect Diff**: Run `cm vcs diff` and review changes.
2. **Execute Tests**: Run `npm test` (or `pytest`/`cargo test`) to guarantee zero regression. If tests fail, provide feedback via `cm fix <id> -c "Fix error"` or revert with `cm vcs revert`.

### Phase 4: Compliance Reporting & Export (`cm report`)
```bash
cm report -f table                    # Terminal summary table
cm report -f sarif > results.sarif    # OASIS SARIF v2.1.0 for CI/CD
cm report -f html                     # Interactive HTML audit dashboard
```

---

## 3. Special Scenarios & Deep Reference Pointers

* **Vibe Coding & GenAI Pitfalls**: When reviewing LLM-generated code (API key leaks, prompt injection, raw SQL), refer to [Vibe Coding Pitfalls](references/vibe_coding_pitfalls.md).
* **Advanced Commands & Third-Party SARIF**: For importing Semgrep/Snyk findings (`cm report import`), session recovery (`cm session resume`), and token tracking (`cm stats`), see [CLI Reference](references/cli_reference.md).

---

## 4. Agent Rules of Engagement

1. **Non-blocking Execution**: Always use `-y` and `--unrestricted` for non-interactive execution.
2. **Never Guess Finding IDs**: Always obtain valid hex IDs via `cm find .` or `cm report -f table`.
3. **Always Verify & Run Tests**: Inspect diffs with `cm vcs diff` and run project test suites after every fix.
4. **Model Selection**: Use `gemini-3.5-flash` for fast scans/fixes; use `gemini-3.1-pro-preview` for complex cross-file refactoring.
