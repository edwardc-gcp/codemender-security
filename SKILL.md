---
name: codemender-security
description: Autonomous security auditing, vulnerability verification, exploit PoC validation, and context-aware patch remediation using Google Cloud CodeMender (cm) on Gemini Enterprise Agent Platform. ACTIVATE this skill whenever scanning codebases, reviewing PR diffs, verifying vulnerabilities without false positives, or safely remediating security flaws with zero regressions.
---

# CodeMender Autonomous Security Master Skill

This skill equips AI Coding Agents (Antigravity, Gemini CLI, Claude Code, OpenAI Codex) to act as an autonomous enterprise security co-developer powered by **Google Cloud CodeMender (`cm` 0.8.0+)** on the **Gemini Enterprise Agent Platform**.

---

## ⚡ Decision Tree & Workflow Router

```
                                  [User Request]
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼                                               ▼
   [Audit / Scan / Ingest SAST]                    [Fix / Patch / Remediate]
                 │                                               │
     ┌───────────┴───────────┐                       ┌───────────┴───────────┐
     ▼                       ▼                       ▼                       ▼
[New / Vibe Project]    [Git Diff / PR]        [Single Finding]        [Batch Remediation]
Run Full AST Scan       Incremental Scan       Context-Aware Fix       Atomic Loop
cm find . -y            cm find . -y           cm fix <id> -c "..."    Fix ➔ Test ➔ Commit
     │                  (incremental: true)          │                       │
     └───────────┬───────────┘                       └───────────┬───────────┘
                 ▼                                               ▼
       [PoC Triage (cm verify)]                        [Re-Attack Validation]
      Execute Dynamic Exploit in                      Automated build.command
      exebox with --no-reset                         and PoC Re-Attack in sandbox
```

---

## Phase 0: Stateless On-the-Fly Scoping & Pre-flight Handshake

Before running commands, identify project paths and execute via the **Stateless On-the-Fly Pattern**:

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

# Helper invocation: always pass on-the-fly to isolate .codemender/
run_cm() {
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm "$@"
}
```

### Pre-flight Checks:
1. **Binary Check**: `command -v cm >/dev/null 2>&1 || bash "${REAL_HOME}/.gemini/config/plugins/codemender-security/scripts/install_cm.sh"`
2. **ADC Check**: `gcloud auth application-default print-access-token >/dev/null 2>&1 || echo "ADC_MISSING: Run gcloud auth application-default login"`
3. **Workspace Init**:
   ```bash
   if [ ! -f "${PROJECT_ROOT}/.codemender/config.yaml" ]; then
     HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm init
   fi
   ```

---

## Phase 1: Vulnerability Discovery Workflows

### Workflow A: Vibe-Coding Full Scan (New Project Hardening)
When auditing a freshly generated MVP or full codebase:
```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y
```
* Analyzes AST and taint data flows using default `gemini-3.8-flash`. Identifies leaked API keys, open CORS, dynamic SQL queries, and permissive cloud rules.

### Workflow B: Fast Differential Scan (PR / Pre-commit Check)
When the user has modified files and wants a rapid safety check (5–15 seconds):
```bash
# CodeMender automatically diffs against .codemender/state.db when scan.incremental is true (default)
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y

# Or target specifically modified paths:
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find ./src/services/ -y
```
* Uses local AST caching to inspect only modified code slices.

### Workflow C: Third-Party SAST Report Ingestion
When ingesting findings from CI/CD tools:
```bash
# Ingest Semgrep SARIF report
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report import -f semgrep.sarif

# Ingest Snyk JSON report
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report import -f snyk.json
```

---

## Phase 2: Scalable 2-Tier Verification (Eliminating False Positives Without Sandbox Deadlocks)

Raw static analysis findings can contain false positives. However, `cm`'s internal `exebox` (`sandbox-exec`) blocks local TCP socket binding (`localhost:<port>`) and blocks `process-exec*` on toolchains installed outside `/usr/bin` (`~/.nvm`, `/opt/homebrew`, `~/.pyenv`). Use the **Scalable 2-Tier Verification Architecture**:

1. **Tier 1 (Default — Fast Semantic & Taint Verification, 15–25s)**:
   ```bash
   HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y
   ```
   Runs deep cloud taint-flow, reachability, and sanitizer verification without spawning blocked sandbox sockets.
2. **Tier 2 (Dynamic Exploit Execution — When Live PoC Execution is Required)**:
   * **System-Binary CLI / Library Targets**: `cm verify <finding-id> --no-reset --bypass-warning -y`
   * **Web Servers (`localhost` TCP ports) or Homebrew/NVM Toolchains**: Stash uncommitted files first (`git stash push -u`) and run with `--unrestricted` (when approved/safe):
     ```bash
     HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm verify <finding-id> --unrestricted --no-reset --bypass-warning -y
     ```
3. **Triage Integrity**: If dynamic exploit execution fails or times out, retain the finding as `OPEN / UNCONFIRMED` for manual inspection. **Never dismiss an unverified exploit as a "False Positive"** unless `cm verify` explicitly marks it `DISMISSED` with concrete code-level proof.

---

## Phase 3: Closed-Loop Context-Aware Remediation

### 1. Mandatory Non-Destructive VCS Safety Check
Before generating fixes, protect the developer's uncommitted manual work:
```bash
DIRTY=$(git status --porcelain 2>/dev/null | grep -vE '\.codemender|\.cm_project|\.exploit' | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ]; then
  echo "Backing up uncommitted changes (including untracked files)..."
  git stash push -u -m "cm-pre-fix-backup-$(date +%s)"
fi
```

### 2. Scalable Dynamic Build Probe & Outer-Shell Fallback
Verify that `build.command` in `.codemender/config.yaml` is functional before running `cm fix`:
* **Runtime Probe First**: Never hardcode an untested command (e.g., `python` on macOS where only `python3` exists). Probe the binary in shell (`command -v pytest`, `command -v python3`, `command -v node`, `command -v go`) and verify the command exits `0`:
  - Python: `"$(command -v pytest || command -v python3 || command -v python) -m compileall -q ."`
  - Node/TS: `"$(command -v node) --check <entry>.js"` or `"npx tsc --noEmit"`
  - Go / Rust: `"go build ./..."` / `"cargo check"`
* **Outer-Shell Validation Fallback (Universal)**: If no unit test exists or `cm fix`'s `exebox` sandbox blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`, `~/.pyenv`), set `build.command: "true"` in `.codemender/config.yaml` to prevent false rollbacks, and execute the real build/test verification in the outer agent shell before `git commit`!

### 3. Context Formulation (`-c "<guidance>"`)
Never execute blind fixes. Inspect project architecture and supply explicit domain guidance:
* *SQL Injection*: `-c "Use parameterized query placeholders with internal db helper in src/db.ts"`
* *Hardcoded Key*: `-c "Read secret from process.env.GEMINI_API_KEY; never bundle secret in frontend code"`
* *Prompt Injection*: `-c "Separate system instructions using systemInstruction parameter; enforce JSON schema"`

### 4. Execute Fix with Closed-Loop Validation
```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm fix <finding-id> -c "<guidance>" --bypass-warning -y
```

**The 4-Step Validation Loop Performed by `cm`:**
1. Generates patch candidate via Gemini reasoning model.
2. Applies patch in isolated sandbox.
3. Compiles and runs `build.command`.
4. **Re-Attack Grounding**: Re-runs the verified PoC exploit against the patched code. If the exploit still succeeds or tests fail, the patch is automatically rejected!

---

## Phase 4: VCS Review, Atomic Batch Remediation & Stash Restoration

### Reviewing and Staging Diff:
```bash
# View unified diff on disk
git diff

# Or using cm vcs wrapper
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm vcs diff

# If user approves, stage changes:
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm vcs stage

# If rollback is needed:
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm vcs reset
```

### Atomic Multi-Vulnerability Remediation Loop:
To fix multiple findings without AST drift or patch collisions, and **always restore stashed user work (`git stash pop`) at the end**:
```bash
# 1. Fetch confirmed open findings (cm report returns bare JSON array of finding objects)
FINDINGS=$(HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report --status OPEN -f json 2>/dev/null | jq -r '.[]? | .finding_id')

# 2. Iterate atomically: One fix -> Outer Build Check -> Commit -> Reconcile AST -> Next
for fid in $FINDINGS; do
  echo "--- Remediating Finding: $fid ---"
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm fix "$fid" --bypass-warning -y
  
  # Validate diff on disk and verify build/syntax in outer shell
  git diff --stat
  
  # Commit atomically BEFORE restoring stashed WIP files
  git commit -am "security(cm): remediate finding $fid" || true
  
  # Reconcile AST cache incrementally
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y
done

# 3. Export compliance SARIF report
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report -f sarif > "${PROJECT_ROOT}/codemender-remediated.sarif"

# 4. MANDATORY: Restore user's uncommitted/untracked WIP files stashed before remediation
if git stash list | grep -q "cm-pre-fix-backup"; then
  echo "Restoring stashed user working files..."
  git stash pop
fi
```

---

## 5. Reference Documentation

For deep technical details, refer to:
* [CLI Reference](references/cli_reference.md): Complete command catalog and sandbox architecture.
* [Configuration Schema](references/config_schema.md): Complete `.codemender/config.yaml` schema.
* [Vibe Coding Pitfalls](references/vibe_coding_pitfalls.md): Top GenAI & LLM security patterns.
* [Finding Format](skills/codemender-audit/references/finding_format.md): Exploit artifact breakdown (`.exploit/`).
