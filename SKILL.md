---
name: codemender-security
description: Use this skill when orchestrating end-to-end security code review, AST vulnerability analysis, and context-aware remediation using Google Cloud CodeMender (cm).
---

# Google Cloud CodeMender (`cm`) Security Orchestrator

You are an Autonomous AppSec Engineer orchestrating the **Google Cloud CodeMender (`cm`)** CLI (`v0.16.0+`).

## 1. Modular Sub-Skills & Executable Helpers

To conserve context tokens and prevent stateless subshell bugs, delegate to the specialized sub-skills and executable wrapper scripts:

* **Sub-Skills**:
  * **Auditing & PoC Verification**: Read [skills/codemender-audit/SKILL.md](skills/codemender-audit/SKILL.md) for AST scanning (`cm find`), third-party SARIF/JSON ingestion (`cm report import`), and 2-Tier verification (`cm verify`).
  * **Context-Aware Remediation**: Read [skills/codemender-remediate/SKILL.md](skills/codemender-remediate/SKILL.md) for patch generation (`cm fix`), tiered build hard gates, and rollback (`cm vcs`).
* **Executable Helpers** (Always use these instead of raw `cm` calls):
  * **[scripts/cm_exec.sh](scripts/cm_exec.sh)**: Stateless workspace wrapper that dynamically computes `PROJECT_ROOT` and `REAL_HOME`, forwards `GIT_CONFIG_GLOBAL` and `CLOUDSDK_CONFIG`, blocks `cm init -y`, and populates `.git/info/exclude` (`.codemender/`, `.cm_project`, `.exploit/`, `.cache/`, `.npm/`, `.cargo/`, `.local/`, `.config/`, `*.sarif`).
  * **[scripts/cm_diff_scan.sh](scripts/cm_diff_scan.sh)**: Local change scanner for `cm find --diff` (working tree, staged, branch, or last-commit scope) that includes untracked source files via a temporary `git add -N`, skips scans when no source file changed, and returns `0` clean / `1` blocking findings / `2` error.
  * **[scripts/cm_git_hook.sh](scripts/cm_git_hook.sh)**: Opt-in pre-commit (or pre-push) hook installer that runs `cm_diff_scan.sh` on every commit; install it only when the user asks, with their confirmation.
  * **[scripts/cm_remediate_loop.sh](scripts/cm_remediate_loop.sh)**: Atomic multi-vulnerability remediation runner with a checkpoint commit for uncommitted work, dynamic `OUTER_BUILD_CMD` hard gate, autofix-style fix commits (tracked changes plus new source files), and a re-scan of the change after every fix (`cm_diff_scan.sh`).

---

## 2. Quick-Start Command Reference (Stateless Subshell Safe)

Each shell tool call (`run_command` in Antigravity, `Bash` in Claude Code and Codex) runs in a fresh subshell. Replace `<plugin-root>` with the absolute path of this plugin's install directory (the directory containing this file) and invoke `cm_exec.sh`, `cm_diff_scan.sh`, or `cm_remediate_loop.sh`; each skill also bundles the same helpers under its own `scripts/` directory:

```bash
# 1. Safe Initialization (Never passes -y; skips if .codemender/config.yaml exists)
bash "<plugin-root>/scripts/cm_exec.sh" init

# 2a. Secure Inner Loop: scan local changes (untracked source files included); exit 0 clean, 1 findings, 2 error
bash "<plugin-root>/scripts/cm_diff_scan.sh"

# 2b. Quick single-session scan of a module, or the deep scan (default mode, slow and token-heavy) for full audits
bash "<plugin-root>/scripts/cm_exec.sh" find ./src --quick -y -c "Focus on auth bypass, injection, and SSRF"
bash "<plugin-root>/scripts/cm_exec.sh" find . -y

# 3a. Optional Tier 1 exploit verification (minutes and many tokens per finding; skip it in the inner loop)
bash "<plugin-root>/scripts/cm_exec.sh" verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y

# 3b. Optional Tier 2 verification (also re-runs the exploit after verification)
bash "<plugin-root>/scripts/cm_exec.sh" verify <finding-id> -c "Verify exploitability" --no-reset --bypass-warning -y

# 4. Ingest Third-Party SARIF or Simple JSON Findings
bash "<plugin-root>/scripts/cm_exec.sh" report import -f third-party-findings.json

# 5. Atomic Multi-Vulnerability Remediation Loop (Checkpoint + Outer Build Gate + Safe Commit + Re-Scan)
bash "<plugin-root>/scripts/cm_remediate_loop.sh" -c "Apply minimal security fix preserving API contracts"

# 6. Export GitHub / SCC SARIF v2.1.0 Report
bash "<plugin-root>/scripts/cm_exec.sh" report -f sarif > codemender-results.sarif
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
