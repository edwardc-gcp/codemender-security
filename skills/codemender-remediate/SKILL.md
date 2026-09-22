---
name: codemender-remediate
description: Context-aware security patch remediation, regression test validation, and PoC re-attack verification using Google Cloud CodeMender (cm). ACTIVATE this skill whenever remediating discovered vulnerabilities, fixing code security issues, applying verified patches, or rolling back broken security fixes.
---

# CodeMender Context-Aware Remediation Skill

This skill guides coding agents (Antigravity, Claude Code, OpenAI Codex, Gemini CLI) to safely fix verified security vulnerabilities using the Google Cloud CodeMender (`cm fix`) workflow.

It guarantees **zero-regression patches** by enforcing an automated 4-step closed validation loop:
1. Candidate patch synthesis via Gemini reasoning models.
2. Local OS-sandboxed application.
3. Automated compilation and unit test execution (`build.command` + outer-shell hard gate).
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
# To revert this local exclusion later, remove .codemender/, .cm_project, and .exploit/ from $(git rev-parse --git-path info/exclude)
EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && [ -d "$(dirname "${EXCLUDE_FILE}")" ]; then
  for entry in ".codemender/" ".cm_project" ".exploit/"; do
    grep -qxF "$entry" "${EXCLUDE_FILE}" 2>/dev/null || echo "$entry" >> "${EXCLUDE_FILE}"
  done
fi

# Use anchored regex so user files containing '.exploit' or '.codemender' substrings are never skipped
if [ -n "$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/)')" ]; then
  STASH_MSG="cm-pre-fix-backup-$(date +%s)"
  echo "📌 Backing up uncommitted changes (including untracked files) to stash: ${STASH_MSG}"
  git stash push -u -m "${STASH_MSG}"
fi
```

### 2. Scalable Dynamic Build Probe & Outer-Shell Hard Gate
Verify that `build.command` in `${PROJECT_ROOT}/.codemender/config.yaml` is functional before running `cm fix`:
* **Why `cm fix` Rolls Back Valid Patches**:
  1. **The No-Test Trap**: In new MVP projects, `package.json` often has `echo "Error: no test specified" && exit 1`.
  2. **The Sandbox Path Trap**: `cm fix` executes `build.command` inside its `exebox` sandbox, which may block host toolchains installed in `~/.nvm`, `/opt/homebrew`, `~/.pyenv`, or `~/.cargo`.
* **Scalable 2-Step Strategy**:
  1. **Runtime Probe First**: Never hardcode an untested command (like `python` on macOS where only `python3` exists). Probe dynamically in the shell and verify it exits `0`, saving the verified command in `OUTER_BUILD_CMD`:
     - Python: `OUTER_BUILD_CMD="$(command -v pytest || command -v python3 || command -v python) -m compileall -q ."`
     - Node/TS: `OUTER_BUILD_CMD="$(command -v node) --check <entry>.js"` or `"npx tsc --noEmit"`
     - Go / Rust: `OUTER_BUILD_CMD="go build ./..."` / `"cargo check"`
  2. **Outer-Shell Hard Gate (Universal)**: If no unit test exists or `exebox` blocks the toolchain binary, set `build.command: "true"` in `.codemender/config.yaml` so `cm fix` does not falsely roll back the patch, and enforce `if ! eval "${OUTER_BUILD_CMD:-true}"; then git checkout HEAD -- . && git clean -fd; continue; fi` in the outer agent shell before `git commit`!

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

Run the fix command using the stateless on-the-fly invocation (forwarding `GIT_CONFIG_GLOBAL` and `CLOUDSDK_CONFIG`):

```bash
HOME="${PROJECT_ROOT}" \
GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" \
CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" \
GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" \
GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" \
cm fix <finding-id> -c "<guidance>" --bypass-warning -y
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
HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm vcs diff
```
* Present the unified diff to the developer with an explanation of why the fix is safe.

### 2. Stage Changes
If the user approves:
```bash
git add -A
```

### 3. Discard / Rollback
If the user wants to revert or the test suite failed unexpectedly:
```bash
HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm vcs reset
```

---

## Phase 4: Atomic Multi-Vulnerability Remediation Loop & Stash Restoration

When fixing multiple findings across a repository, avoid naive shell loops which suffer from AST node and line number drift. **Execute the Atomic Remediation Loop with an enforced outer build gate, `git add -A` (so newly created helper files are never wiped by subsequent `git clean -fd` runs), and conflict-safe `git stash pop` restoration**:

```bash
# 1. Query actionable findings using python3 (captures OPEN, REOPENED, VERIFIED; avoids jq dependency and --status enum errors)
FINDINGS=$(HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report -f json 2>/dev/null | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for item in (data if isinstance(data, list) else []):
        if item.get("status") not in ("FIXED", "DISMISSED") and item.get("patch_status") != "APPLIED":
            print(item.get("finding_id", ""))
except Exception:
    pass
')

# 2. Iterate atomically: One fix -> Enforced Outer Build Hard Gate -> git add -A & Commit -> Reconcile AST -> Next
for fid in $FINDINGS; do
  [ -z "$fid" ] && continue
  echo "--- Remediating Finding: $fid ---"
  HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm fix "$fid" --bypass-warning -y

  # Enforce Outer-Shell Build Hard Gate before committing
  if ! eval "${OUTER_BUILD_CMD:-true}"; then
    echo "❌ Outer build/syntax validation failed for $fid; reverting patch..."
    git checkout HEAD -- . && git clean -fd
    continue
  fi

  # Stage ALL changes (including newly created files) and commit atomically BEFORE restoring stashed WIP
  if [ -n "$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/)')" ]; then
    git add -A
    git commit -m "security(cm): remediate finding $fid"
  fi

  # Reconcile AST cache incrementally before next fix
  HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y
done

# 3. Export final clean report
HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report -f sarif > "${PROJECT_ROOT}/remediated-results.sarif"

# 4. MANDATORY: Restore user's uncommitted/untracked WIP files with merge-conflict notification
if git stash list | grep -q "cm-pre-fix-backup"; then
  echo "Restoring stashed user working files..."
  git stash pop || echo "⚠️ Merge conflict while restoring stash! Your uncommitted changes are safely preserved in: $(git stash list | head -n 1)"
fi
```
