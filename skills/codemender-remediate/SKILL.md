---
name: codemender-remediate
description: Use this skill when remediating vulnerabilities, generating security patches, running outer-shell regression hard gates, or executing atomic multi-vulnerability fix loops with Google Cloud CodeMender (cm fix, cm vcs).
compatibility: Requires bash, git, curl and unzip (installer only), the Google Cloud CodeMender CLI (cm) 0.16.0 or later, and Google Cloud Application Default Credentials for a project with CodeMender access. Works with Antigravity, Claude Code, and OpenAI Codex.
---

# CodeMender Context-Aware Patch Remediation (`codemender-remediate`)

You are an Autonomous Security Remediation Engineer powered by **Google Cloud CodeMender (`cm`)**. Your objective is to patch discovered vulnerabilities (`cm fix`), enforce zero-regression build hard gates, and preserve git working tree integrity.

## Script Location

Every helper script used below ships inside this skill's own [`scripts/`](scripts/) directory. In each command, replace `<skill-dir>` with the absolute path of the directory that contains this `SKILL.md`. Each shell tool call runs in a fresh subshell, so always use the full path.

---

## Phase 0: Non-Destructive VCS & Build Gate Architecture

> **CRITICAL VCS WARNING**: `cm fix` runs `git checkout HEAD -- . && git clean -fd` on its workspace at startup (still true in cm 0.16.0, where only the sandbox stopped it). Untracked or uncommitted files that are neither committed beforehand nor ignored via `.git/info/exclude` can be **permanently deleted**, and stashing them would hide the very code that needs fixing.

To eliminate cross-subshell variable loss (`PROJECT_ROOT=""`), `.cache`/`.npm` commit leakage, and accidental `git clean -fd` data loss, **always execute remediation via [scripts/cm_remediate_loop.sh](scripts/cm_remediate_loop.sh) or [scripts/cm_exec.sh](scripts/cm_exec.sh)**.

### What `scripts/cm_remediate_loop.sh` Automatically Guarantees:
1. **Stateless Workspace & `.git/info/exclude` Shield**: Scopes `HOME="${PROJECT_ROOT}"`, forwards `GIT_CONFIG_GLOBAL` and `CLOUDSDK_CONFIG`, and excludes `.codemender/`, `.cm_project`, `.exploit/`, `.cache/`, `.npm/`, `.cargo/`, `.local/`, `.config/`, and `*.sarif`.
2. **Checkpoint Commit for Uncommitted Work**: If the working tree has uncommitted changes, the loop commits them as `wip(cm): checkpoint before security remediation` before the first `cm fix`, so the fix can see the code and the workspace reset cannot delete it. On exit (including failures and interrupts) it drops leftover patches and resets back to the original base: your changes come back uncommitted, now including the applied fixes (previously staged changes come back unstaged). Pass `--keep-commits` to keep the checkpoint and fix commits for review instead.
3. **Outer-Shell Build Hard Gate (`OUTER_BUILD_CMD`)**: Dynamically probes `pytest`, `python3 -m py_compile`, `node --check`, `go test`, or `cargo check`. If `cm fix` produces a patch that fails the outer build gate, it immediately reverts (`git checkout HEAD -- . && git clean -fd`).
4. **Autofix-Style Commits & Differential AST Reconciliation**: Like the official CodeMender autofix job, each fix commit contains changes to files already in the repository plus new source files the fix adds (for example a sanitizer helper); other new files such as test output stay out. CodeMender's own ignore-file edits (`.exploit/` appended to `.gitignore`, generated `# CodeMender enforced ignores` files) are dropped because `.git/info/exclude` already covers those paths. Commits use `--no-verify` because the loop runs its own gates, and the loop runs `cm find . --diff=HEAD~1 -y` after every commit so subsequent patches reconcile modified files and 1-hop callers without rescanning the entire repository.

---

## Phase 1: Atomic Multi-Vulnerability Remediation (`cm_remediate_loop.sh`)

### Option A: Remediate All Actionable (`OPEN` / `REOPENED`) Findings
```bash
bash "<skill-dir>/scripts/cm_remediate_loop.sh" \
  -c "Apply idiomatic security patch preserving public function signatures and HTTP status codes"
```

### Option B: Remediate Specific Finding ID(s) with Custom Build Gate
```bash
bash "<skill-dir>/scripts/cm_remediate_loop.sh" \
  -c "Replace string interpolation with parameterized SQL queries" \
  -b "pytest tests/security/" \
  <finding-id-1> <finding-id-2>
```

### Option C: Keep the Checkpoint and Fix Commits
Use this when the user wants reviewable commits (for example, to open a pull request) instead of getting their work back as uncommitted changes:
```bash
bash "<skill-dir>/scripts/cm_remediate_loop.sh" --keep-commits \
  -c "Apply idiomatic security patch preserving public function signatures and HTTP status codes"
```

---

## Phase 2: Post-Fix Re-Verification & Rollback (`cm vcs`)

### 1. Confirm Remediation Status (`FIXED` vs. `REOPENED`)
After `cm_remediate_loop.sh` completes its `cm find . --diff=HEAD~1 -y` AST reconciliation, inspect the report:
```bash
bash "<skill-dir>/scripts/cm_exec.sh" report
bash "<skill-dir>/scripts/cm_exec.sh" report -f sarif > remediated-results.sarif
```
* **`FIXED`**: Vulnerability is resolved and verified.
* **`REOPENED`**: Indicates a patch regression or incomplete fix across a secondary dataflow path; re-run `cm_remediate_loop.sh` with more specific `-c "<guidance>"`.

### 2. Emergency VCS Rollback (`cm vcs`)
If you need to inspect or revert CodeMender's internal VCS snapshot state:
```bash
bash "<skill-dir>/scripts/cm_exec.sh" vcs status
bash "<skill-dir>/scripts/cm_exec.sh" vcs diff
```

---

## Reference Documentation
* [Configuration & Sandbox Schema](references/config_schema.md)
* [Vibe Coding Security Pitfalls](references/vibe_coding_pitfalls.md)
* [CLI Command Reference](references/cli_reference.md)
