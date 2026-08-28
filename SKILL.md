---
name: codemender-security
description: Autonomous security auditing, vulnerability verification, exploit PoC validation, and context-aware patch remediation using the CodeMender CLI (cm) on Google Cloud's Gemini Enterprise Agent Platform. ACTIVATE this skill whenever the user asks to scan, audit, secure, verify vulnerabilities, or remediate code in their repository, or immediately after generating/vibe-coding new full-stack features and applications.
---

# CodeMender Autonomous Security Skill

This skill equips Antigravity to act as an autonomous AI Security Co-developer using the **CodeMender CLI (`cm`)** on Google Cloud's **Gemini Enterprise Agent Platform**.

---

## 1. Environment & Setup

Before initiating security operations, verify that `cm` and Google Cloud ADC are available:

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

## 2. State-Aware Agent Workflow (The Dynamic State Machine)

To preserve AST caches, avoid redundant full scans, and support multi-turn development, the agent follows a **State-Aware State Machine**:

```
                     ┌──────────────────────────────┐
                     │ Phase 0: Rapid State Probing │
                     │   (Zero-Token CWD Probe)     │
                     └──────────────┬───────────────┘
                                    │
       ┌────────────────────────────┼────────────────────────────┐
       ▼                            ▼                            ▼
[Condition A: Clean Workspace] [Condition B: Dirty Working Tree] [Condition C: Interrupted Task]
Run Initial Full Scan         Run Incremental Reconcile     Resume Active Session
(cm find . -y)                (cm find --diff-only -y)      (cm session resume <id>)
       │                            │                            │
       └────────────────────────────┼────────────────────────────┘
                                    ▼
                     ┌──────────────────────────────┐
                     │ Phase 1: Contextual Triage   │
                     │  (Read .exploit/ or Verify)  │
                     └──────────────┬───────────────┘
                                    ▼
                     ┌──────────────────────────────┐
                     │ Phase 2: Patch & Test Loop   │
                     │  cm fix ➔ npm test ➔ Status  │
                     └──────────────┬───────────────┘
                                    ▼
                     ┌──────────────────────────────┐
                     │ Phase 3: Session Retention   │
                     │ (Preserve state / Clean only │
                     │   when explicitly asked)     │
                     └──────────────────────────────┘
```

### Phase 0: Rapid State Probing (Entry Evaluation)
When the user requests security tasks, execute a single non-intrusive probe:
```bash
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
GIT_DIRTY=$(git -C "$GIT_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
SESSION_FINDINGS=$(cm report -f table 2>/dev/null | grep -E "CRITICAL|HIGH|MEDIUM|LOW" | wc -l | tr -d ' ')
INTERRUPTED=$(cm session list 2>/dev/null | grep -i "interrupted" | wc -l | tr -d ' ')
echo "PROBE: ROOT=${GIT_ROOT} DIRTY=${GIT_DIRTY} FINDINGS=${SESSION_FINDINGS} INTERRUPTED=${INTERRUPTED}"
```

* **Condition A (No active session / `FINDINGS == 0`)**: Execute initial full scan:
  ```bash
  cm find . -y --unrestricted --model gemini-3.7-flash
  ```
* **Condition B (Existing session + Uncommitted changes / `DIRTY > 0`)**: Reconcile incrementally:
  ```bash
  cm find . -y --diff-only --unrestricted --model gemini-3.7-flash
  ```
* **Condition C (Existing session + Clean working tree / `DIRTY == 0`)**: Zero-wait triage. Directly read and present `cm report -f table`.
* **Condition D (Interrupted session detected / `INTERRUPTED > 0`)**: Seamlessly resume:
  ```bash
  cm session resume <interrupted-session-id>
  ```

### Phase 1: Contextual Triage & PoC Inspection
* **Inspect Existing PoCs**: If `.exploit/<finding-id>/REPORT.md` exists, read it using `view_file` to explain Root Cause Analysis (RCA) and attack vectors without re-executing verification.
* **Verify Unconfirmed Findings**:
  ```bash
  cm verify <finding-id> --unrestricted --bypass-warning -y --model gemini-3.7-flash
  ```
* Present findings in a prioritized Markdown table sorted by Severity (Critical ➔ High ➔ Medium ➔ Low).

### Phase 2: Guided Patch Synthesis & Regression Closed-Loop
Synthesize language-aware, context-sensitive patches and ensure zero behavioral regressions:
```bash
# 1. Synthesize patch with domain context
cm fix <finding-id> -c "Use Google Secret Manager and parameterized queries" --unrestricted -y

# 2. Inspect synthesized diff
cm vcs diff

# 3. Execute project regression test suite
npm test # (or pytest, go test ./..., cargo test)
```
* **If tests PASS**: Confirm fix and refresh report (`cm report -f table`).
* **If tests FAIL**: Pass compiler/test failure output back to the agent:
  ```bash
  cm fix <finding-id> -c "Fix test regression: <error_message>" --unrestricted -y
  # Or rollback cleanly if needed: cm vcs reset
  ```

### Phase 3: Session Retention & Controlled Purge
* **Continuous Multi-Turn Development**: Maintain `~/.codemender/state.db` and AST cache across turns to allow step-by-step remediation of findings throughout the day.
* **Controlled Purge**: Execute `cm clean` **ONLY** when the user explicitly requests a complete workspace reset or cache purge.

---

## 3. Special Scenarios & Deep Reference Pointers

* **Vibe Coding & GenAI Pitfalls**: When reviewing LLM-generated code (hardcoded API keys, prompt injections, raw SQL), see [Vibe Coding Pitfalls](references/vibe_coding_pitfalls.md).
* **Advanced Commands & Third-Party SARIF**: For importing Semgrep/Snyk findings (`cm report import`), OS sandboxing flags (`--sandbox=false`), and token stats (`cm stats`), see [CLI Reference](references/cli_reference.md).
* **Workspace Configuration**: For customizing network profiles, mount paths, and test commands, see [Configuration Schema](references/config_schema.md).

---

## 4. Agent Rules of Engagement

1. **State-Aware Discovery**: Probe workspace state first; never perform unnecessary full scans when incremental diffs or cached findings are available.
2. **Git-Root Anchoring**: Always anchor operations to the repository root (`git rev-parse --show-toplevel`) to prevent cross-directory state pollution.
3. **Never Guess Finding IDs**: Always dynamically query active 8-character hex IDs via `cm find .` or `cm report -f table`.
4. **Always Verify & Run Tests**: Inspect diffs with `cm vcs diff` and run project test suites after every fix.
5. **Model Selection**: Use `gemini-3.7-flash` (default) for fast scanning, PoC verification, and patch synthesis; use `gemini-3.1-pro-preview` for complex cross-file architectural refactors.
6. **Explicit Reset Only**: Never automatically purge session data (`cm clean`) unless explicitly commanded by the user.
