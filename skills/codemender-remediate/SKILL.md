---
name: codemender-remediate
description: Context-aware security patch remediation, regression test validation, and PoC re-attack verification using Google Cloud CodeMender (cm). ACTIVATE this skill whenever remediating discovered vulnerabilities, fixing code security issues, applying verified patches, or rolling back broken security fixes.
---

# CodeMender Context-Aware Remediation Skill

This skill guides coding agents (Antigravity, Claude Code, OpenAI Codex, Gemini CLI) to safely fix verified security vulnerabilities using the Google Cloud CodeMender (`cm fix`) workflow.

It guarantees **zero-regression patches** by enforcing an automated 4-step closed validation loop:
1. Candidate patch synthesis via Gemini reasoning models.
2. Local OS-sandboxed application.
3. Automated compilation and unit test execution (`build.command`).
4. **Re-Attack Verification**: Autonomous re-execution of the verified PoC exploit to prove the attack is completely neutralized.

---

## Phase 0: Non-Destructive VCS Safety & Test Adaptive Check

### 1. Mandatory Non-Destructive VCS Guardrail
Before touching any code or running `cm fix`, protect the developer's uncommitted manual work:

```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

# Protect localized .codemender state from 'cm fix' internal 'git clean -fd' (supports worktrees & submodules)
EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && [ -d "$(dirname "${EXCLUDE_FILE}")" ]; then
  for entry in ".codemender/" ".cm_project" ".exploit/"; do
    grep -qxF "$entry" "${EXCLUDE_FILE}" 2>/dev/null || echo "$entry" >> "${EXCLUDE_FILE}"
  done
fi

DIRTY=$(git status --porcelain 2>/dev/null | grep -vE '\.codemender|\.cm_project|\.exploit' | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ]; then
  echo "Backing up uncommitted changes (including untracked files) before remediation..."
  git stash push -u -m "cm-pre-fix-backup-$(date +%s)"
fi
```

### 2. Scalable Dynamic Build Probe & Outer-Shell Fallback
Verify that `build.command` in `${PROJECT_ROOT}/.codemender/config.yaml` is functional before running `cm fix`:
* **Why `cm fix` Rolls Back Valid Patches**:
  1. **The No-Test Trap**: In new MVP projects, `package.json` often has `echo "Error: no test specified" && exit 1`.
  2. **The Sandbox Path Trap**: `cm fix` executes `build.command` inside its `exebox` sandbox, which may block host toolchains installed in `~/.nvm`, `/opt/homebrew`, `~/.pyenv`, or `~/.cargo`.
* **Scalable 2-Step Strategy**:
  1. **Runtime Probe First**: Never hardcode an untested command (like `python` on macOS where only `python3` exists). Probe dynamically in the shell and verify it exits `0`:
     - Python: `"$(command -v pytest || command -v python3 || command -v python) -m compileall -q ."`
     - Node/TS: `"$(command -v node) --check <entry>.js"` or `"npx tsc --noEmit"`
     - Go / Rust: `"go build ./..."` / `"cargo check"`
  2. **Outer-Shell Validation Fallback (Universal)**: If no unit test exists or `exebox` blocks the toolchain binary, set `build.command: "true"` in `.codemender/config.yaml` so `cm fix` does not falsely roll back the patch, and run the real build/test command in the outer agent shell right after `cm fix` (before `git commit`)!

---

## Phase 1: Context Synthesis (Domain Guidance)

**CRITICAL**: Never execute blind fixes with an empty context. CodeMender accepts a `-c / --context` flag that dramatically improves patch accuracy by steering the reasoning engine toward project-specific conventions.

### Guidance Formulation Rules:
1. **Identify the Architecture**: Check what libraries the project already uses (e.g. Prisma, Mongoose, SQLx, standard library).
2. **Consult Vibe Coding Patterns**: If fixing common LLM pitfalls (hardcoded secrets, raw string SQL, open CORS), consult `references/vibe_coding_pitfalls.md`.
3. **Formulate the Context Flag**:
   - *Example for SQL Injection*: `-c "Use the internal db.SafeQuery helper in src/db/helper.go without adding third-party dependencies"`
   - *Example for Secret Leak*: `-c "Read API key from process.env.GEMINI_API_KEY; do not expose key to client bundle"`
   - *Example for Complex Refactor*: Add `--model gemini-3.1-pro-preview` for multi-file architectural changes.

---

## Phase 2: Closed-Loop Remediation Execution

Run the fix command using the stateless on-the-fly invocation:

```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm fix <finding-id> -c "<guidance>" --bypass-warning -y
```

### The 4-Step Validation Loop Performed by `cm`:
```
   [1. Generate Patch] ──► [2. Apply in Sandbox] ──► [3. Run build.command] ──► [4. Re-Attack via PoC]
                                                                                      │
                                   ┌──────────────────────────────────────────────────┴─────────────┐
                                   ▼                                                                ▼
                         [PoC Attack Fails]                                               [PoC Still Exploitable]
                         Patch is VALIDATED                                               Patch is REJECTED
```

* If `build.command` fails (tests break) or the re-attack succeeds (vulnerability persists), CodeMender automatically rejects the patch candidate.

---

## Phase 3: VCS Diff Review & Change Management

Once CodeMender successfully applies a validated patch, inspect and stage the changes:

### 1. Review Diff on Disk
Verify real file changes with `git diff`:
```bash
# Verify modified working files directly
git diff

# Or using cm vcs wrapper
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm vcs diff
```
* Present the unified diff to the developer with an explanation of why the fix is safe.

### 2. Stage Changes
If the user approves:
```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm vcs stage
```

### 3. Discard / Rollback
If the user wants to revert or the test suite failed unexpectedly:
```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm vcs reset
```

---

## Phase 4: Atomic Multi-Vulnerability Remediation Loop & Stash Restoration

When fixing multiple findings across a repository, avoid naive shell loops which suffer from AST node and line number drift. **Execute the Atomic Remediation Loop, and ALWAYS restore stashed user files (`git stash pop`) after all commits are finished**:

```bash
# 1. Query verified open findings (cm report returns bare array; status is OPEN)
FINDINGS=$(HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report --status OPEN -f json 2>/dev/null | jq -r '.[]? | .finding_id')

# 2. Iterate atomically: One fix -> Outer Build Check -> Commit -> Reconcile AST -> Next
for fid in $FINDINGS; do
  echo "--- Remediating Finding: $fid ---"
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm fix "$fid" --bypass-warning -y

  # Verify diff was applied to working directory and validate build/syntax in outer shell
  git diff --stat

  # Commit atomically to preserve patch BEFORE restoring any stashed WIP files
  git commit -am "security(cm): remediate finding $fid" || true

  # Reconcile AST cache incrementally before next fix
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y
done

# 3. Export final clean report
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report -f sarif > "${PROJECT_ROOT}/remediated-results.sarif"

# 4. MANDATORY: Restore user's uncommitted/untracked WIP files stashed before remediation
if git stash list | grep -q "cm-pre-fix-backup"; then
  echo "Restoring stashed user working files..."
  git stash pop
fi
```
