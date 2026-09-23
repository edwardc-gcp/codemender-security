---
name: codemender-remediate
description: Use this skill when remediating vulnerabilities, generating security patches, running outer-shell regression hard gates, or executing atomic multi-vulnerability fix loops with Google Cloud CodeMender (cm fix, cm vcs).
---

# CodeMender Context-Aware Patch Remediation (`codemender-remediate`)

You are an Autonomous Security Remediation Engineer powered by **Google Cloud CodeMender (`cm`)**. Your objective is to patch discovered vulnerabilities (`cm fix`), enforce zero-regression build hard gates, and preserve git working tree integrity.

---

## Phase 0: Non-Destructive VCS & Build Gate Architecture

> **CRITICAL VCS WARNING**: `cm fix` executes `git checkout HEAD -- . && git clean -fd` on startup. Any untracked or uncommitted user files not protected by `.git/info/exclude` or stashed beforehand will be **permanently deleted**.

To eliminate cross-subshell variable loss (`PROJECT_ROOT=""`), `.cache`/`.npm` commit leakage, and accidental `git clean -fd` data loss, **always execute remediation via [scripts/cm_remediate_loop.sh](../../scripts/cm_remediate_loop.sh) or [scripts/cm_exec.sh](../../scripts/cm_exec.sh)**.

### What `scripts/cm_remediate_loop.sh` Automatically Guarantees:
1. **Stateless Workspace & `.git/info/exclude` Shield**: Scopes `HOME="${PROJECT_ROOT}"`, forwards `GIT_CONFIG_GLOBAL` and `CLOUDSDK_CONFIG`, and excludes `.codemender/`, `.cm_project`, `.exploit/`, `.cache/`, `.npm/`, `.cargo/`, `.local/`, `.config/`, and `*.sarif`.
2. **Tracked Pre-Fix Stash (`CM_STASH_MSG`)**: Only stashes if dirty user files exist, records the exact `CM_STASH_MSG` timestamp, and uses an `EXIT` trap to `git stash pop "${STASH_REF}"` for that specific stash entry—never popping unrelated user stashes (`stash@{0}`).
3. **Outer-Shell Build Hard Gate (`OUTER_BUILD_CMD`)**: Dynamically probes `pytest`, `python3 -m py_compile`, `node --check`, `go test`, or `cargo check`. If `cm fix` produces a patch that fails the outer build gate, it immediately reverts (`git checkout HEAD -- . && git clean -fd`).
4. **Pathspec-Filtered `git add -A` & Per-Commit AST Reconciliation**: Stages newly created security helper files while excluding `:!.codemender`, `:!.cache`, `:!.npm`, `:!.config`, and `:!*.sarif`, and runs `cm find . -y` inside the loop after every commit so subsequent patches use updated line numbers.

---

## Phase 1: Atomic Multi-Vulnerability Remediation (`cm_remediate_loop.sh`)

### Option A: Remediate All Actionable (`OPEN` / `REOPENED`) Findings
```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

bash "${PLUGIN_DIR}/scripts/cm_remediate_loop.sh" \
  -c "Apply idiomatic security patch preserving public function signatures and HTTP status codes"
```

### Option B: Remediate Specific Finding ID(s) with Custom Build Gate
```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

bash "${PLUGIN_DIR}/scripts/cm_remediate_loop.sh" \
  -c "Replace string interpolation with parameterized SQL queries" \
  -b "pytest tests/security/" \
  <finding-id-1> <finding-id-2>
```

---

## Phase 2: Post-Fix Re-Verification & Rollback (`cm vcs`)

### 1. Confirm Remediation Status (`FIXED` vs. `REOPENED`)
After `cm_remediate_loop.sh` completes its `cm find . -y` AST reconciliation, inspect the report:
```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report -f sarif > remediated-results.sarif
```
* **`FIXED`**: Vulnerability is resolved and verified.
* **`REOPENED`**: Indicates a patch regression or incomplete fix across a secondary dataflow path; re-run `cm_remediate_loop.sh` with more specific `-c "<guidance>"`.

### 2. Emergency VCS Rollback (`cm vcs`)
If you need to inspect or revert CodeMender's internal VCS snapshot state:
```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

bash "${PLUGIN_DIR}/scripts/cm_exec.sh" vcs status
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" vcs diff
```

---

## Reference Documentation
* [Configuration & Sandbox Schema](references/config_schema.md)
* [Vibe Coding Security Pitfalls](references/vibe_coding_pitfalls.md)
* [CLI Command Reference](../codemender-audit/references/cli_reference.md)
