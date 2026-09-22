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

### 2. Vibe-Coding Test Adaptive Check
Verify that `build.command` in `${PROJECT_ROOT}/.codemender/config.yaml` is functional:
* **The No-Test Trap**: In new MVP projects, `package.json` often has `echo "Error: no test specified" && exit 1`. If left as `npm test`, `cm fix` will treat exit code 1 as a regression and **roll back the fix automatically**.
* **Adaptive Fallback**:
  - Node.js / TypeScript: If `npm test` errors, set `build.command: "npx tsc --noEmit"`, `"node --check <entry>.js"`, or `"npm run build"`
  - Python: If no test runner, set `build.command: "python -m compileall -q ."`
  - Go: Set `build.command: "go build ./..."`
  - Rust: Set `build.command: "cargo check"`

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
HOME="${PROJECT_ROOT}" cm vcs diff
```
* Present the unified diff to the developer with an explanation of why the fix is safe.

### 2. Stage Changes
If the user approves:
```bash
HOME="${PROJECT_ROOT}" cm vcs stage
```

### 3. Discard / Rollback
If the user wants to revert or the test suite failed unexpectedly:
```bash
HOME="${PROJECT_ROOT}" cm vcs reset
```

---

## Phase 4: Atomic Multi-Vulnerability Remediation Loop

When fixing multiple findings across a repository, avoid naive shell loops which suffer from AST node and line number drift. **Execute the Atomic Remediation Loop**:

```bash
# 1. Query verified open findings (cm report returns bare array; status is OPEN, not VERIFIED)
FINDINGS=$(HOME="${PROJECT_ROOT}" cm report --status OPEN -f json 2>/dev/null | jq -r '.[]? | .finding_id')

# 2. Iterate atomically: One fix -> Verify -> Commit -> Next
for fid in $FINDINGS; do
  echo "--- Remediating Finding: $fid ---"
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm fix "$fid" -y
  
  # Verify diff was applied to working directory
  git diff --stat
  
  # Commit atomically to preserve patch
  git commit -am "security(cm): remediate finding $fid" || true
  
  # Reconcile AST cache incrementally before next fix
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y
done

# 3. Export final clean report
HOME="${PROJECT_ROOT}" cm report -f sarif > "${PROJECT_ROOT}/remediated-results.sarif"
```
