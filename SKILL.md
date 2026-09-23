---
name: codemender-security
description: Use this skill when orchestrating end-to-end security auditing, exploit PoC verification, and context-aware vulnerability remediation using Google Cloud CodeMender (cm).
---

# Google Cloud CodeMender (`cm`) Security Orchestrator

You are an Autonomous AppSec Engineer orchestrating the **Google Cloud CodeMender (`cm`)** CLI (`v0.8.0`).

## 1. Modular Sub-Skills & Executable Helpers

To conserve context tokens and prevent stateless subshell bugs, delegate to the specialized sub-skills and executable wrapper scripts:

* **Sub-Skills**:
  * **Auditing & PoC Verification**: Read [skills/codemender-audit/SKILL.md](skills/codemender-audit/SKILL.md) for AST scanning (`cm find`), third-party SARIF/JSON ingestion (`cm report import`), and 2-Tier verification (`cm verify`).
  * **Context-Aware Remediation**: Read [skills/codemender-remediate/SKILL.md](skills/codemender-remediate/SKILL.md) for patch generation (`cm fix`), tiered build hard gates, and rollback (`cm vcs`).
* **Executable Helpers** (Always use these instead of raw `cm` calls):
  * **[scripts/cm_exec.sh](scripts/cm_exec.sh)**: Stateless workspace wrapper that dynamically computes `PROJECT_ROOT` and `REAL_HOME`, forwards `GIT_CONFIG_GLOBAL` and `CLOUDSDK_CONFIG`, blocks `cm init -y`, and populates `.git/info/exclude` (`.codemender/`, `.cm_project`, `.exploit/`, `.cache/`, `.npm/`, `.cargo/`, `.local/`, `.config/`, `*.sarif`).
  * **[scripts/cm_remediate_loop.sh](scripts/cm_remediate_loop.sh)**: Atomic multi-vulnerability remediation runner with tracked `CM_STASH_MSG` pre-stash/restore, dynamic `OUTER_BUILD_CMD` hard gate, pathspec-filtered `git add -A`, and per-commit AST line-number reconciliation (`cm find . -y`).

---

## 2. Quick-Start Command Reference (Stateless Subshell Safe)

Every `run_command` executes in an isolated subshell. Resolve `PLUGIN_DIR` dynamically and invoke `cm_exec.sh` or `cm_remediate_loop.sh`:

```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

# 1. Safe Initialization (Never passes -y; skips if .codemender/config.yaml exists)
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" init

# 2. Targeted AST & Taint Scan (Scan 10-50 files per module batch on large repos)
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" find . -y -c "Focus on auth bypass, injection, and SSRF"

# 3a. Tier 1 Fast Semantic Verification (Default — 15-25s, skips 15-min dynamic sandbox loop)
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y

# 3b. Tier 2 Deep Sandboxed PoC Verification (On-Demand inside OS exebox)
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" verify <finding-id> -c "Verify exploitability" --no-reset --bypass-warning -y

# 4. Ingest Third-Party SARIF or Simple JSON Findings
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report import -f third-party-findings.json

# 5. Atomic Multi-Vulnerability Remediation Loop (Pre-Stash + Outer Build Gate + Safe Commit + AST Reconcile)
bash "${PLUGIN_DIR}/scripts/cm_remediate_loop.sh" -c "Apply minimal security fix preserving API contracts"

# 6. Export GitHub / SCC SARIF v2.1.0 Report
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report -f sarif > codemender-results.sarif
```

---

## 3. Core Guardrails Summary

1. **Zero Binary Auto-Install**: Never execute [scripts/install_cm.sh](scripts/install_cm.sh) without explicit human approval.
2. **No Unconfirmed `--unrestricted`**: `--unrestricted` disables both the OS filesystem sandbox (`exebox`) and command denylist (RCE hazard on untrusted repos). Require per-invocation user approval.
3. **Triage Integrity**: If `cm verify` fails to trigger a dynamic crash in the sandbox, mark the finding as **`UNCONFIRMED / OPEN`**—never dismiss as a "False Positive" without manual source proof.

---

## Reference Documentation
* [CLI Command Reference](references/cli_reference.md)
* [Configuration & Sandbox Schema](references/config_schema.md)
* [Vibe Coding Security Pitfalls](references/vibe_coding_pitfalls.md)
* [Finding & SARIF Format Reference](skills/codemender-audit/references/finding_format.md)
