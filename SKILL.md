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

# Helper invocation: always pass on-the-fly to isolate .codemender/
run_cm() {
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm "$@"
}
```

### Pre-flight Checks:
1. **Binary Check**: `command -v cm >/dev/null 2>&1 || bash scripts/install_cm.sh`
2. **ADC Check**: `gcloud auth application-default print-access-token >/dev/null 2>&1 || echo "ADC_MISSING: Run gcloud auth application-default login"`
3. **Workspace Init**:
   ```bash
   if [ ! -f "${PROJECT_ROOT}/.codemender/config.yaml" ]; then
     HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm init -y
   fi
   ```

---

## Phase 1: Vulnerability Discovery Workflows

### Workflow A: Vibe-Coding Full Scan (New Project Hardening)
When auditing a freshly generated MVP or full codebase:
```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y
```
* Analyzes AST and taint data flows using default `gemini-3.8-flash`. Identifies leaked API keys, open CORS, dynamic SQL queries, and permissive cloud rules.

### Workflow B: Fast Differential Scan (PR / Pre-commit Check)
When the user has modified files and wants a rapid safety check (5–15 seconds):
```bash
# CodeMender automatically diffs against .codemender/state.db when scan.incremental is true (default)
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y

# Or target specifically modified paths:
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find ./src/services/ -y
```
* Uses local AST caching to inspect only modified code slices.

### Workflow C: Third-Party SAST Report Ingestion
When ingesting findings from CI/CD tools:
```bash
# Ingest Semgrep SARIF report
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm report import -f semgrep.sarif

# Ingest Snyk JSON report
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm report import -f snyk.json
```

---

## Phase 2: Grounded PoC Verification (Zero False Positives)

Raw static analysis findings can contain false positives. For candidate findings, **run dynamic PoC verification**:

```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm verify <finding-id> --no-reset -y
```

### What Happens in the Sandbox:
1. Synthesizes an exploit script under `${PROJECT_ROOT}/.exploit/<finding-id>/` (`poc.js`, `exploit.py`, or `exploit.sh`).
2. Executes the payload inside the isolated process sandbox (`exebox`).
3. If the exploit triggers the bug, it updates the finding status to `VERIFIED` and produces `${PROJECT_ROOT}/.exploit/<id>/REPORT.md`.
4. If the exploit fails to reproduce, the finding status remains `OPEN / UNCONFIRMED` for manual security inspection. **Never dismiss an unverified exploit as a "False Positive" automatically**, as local environment or offline servers may prevent reproduction.

> [!NOTE]
> For Web service vulnerabilities, ensure the target dev server or mock endpoint is active if the exploit requires HTTP communication.

---

## Phase 3: Closed-Loop Context-Aware Remediation

### 1. Mandatory Non-Destructive VCS Safety Check
Before generating fixes, protect the developer's uncommitted manual work:
```bash
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ]; then
  echo "Backing up uncommitted changes..."
  git stash push -m "cm-pre-fix-backup-$(date +%s)"
fi
```

### 2. Vibe-Coding Test Adaptive Check
Verify that `build.command` in `.codemender/config.yaml` is functional:
* If `npm test` fails because no tests are written (`no test specified`), adapt `build.command`:
  - Node/TS: `"npx tsc --noEmit"` or `"npm run build"`
  - Python: `"python -m compileall -q ."`
  - Go: `"go build ./..."`
  This prevents `cm fix` from deadlocking and rolling back valid patches!

### 3. Context Formulation (`-c "<guidance>"`)
Never execute blind fixes. Inspect project architecture and supply explicit domain guidance:
* *SQL Injection*: `-c "Use parameterized query placeholders with internal db helper in src/db.ts"`
* *Hardcoded Key*: `-c "Read secret from process.env.GEMINI_API_KEY; never bundle secret in frontend code"`
* *Prompt Injection*: `-c "Separate system instructions using systemInstruction parameter; enforce JSON schema"`

### 4. Execute Fix with Closed-Loop Validation
```bash
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm fix <finding-id> -c "<guidance>" -y
```

**The 4-Step Validation Loop Performed by `cm`:**
1. Generates patch candidate via Gemini reasoning model.
2. Applies patch in isolated sandbox.
3. Compiles and runs `build.command`.
4. **Re-Attack Grounding**: Re-runs the verified PoC exploit against the patched code. If the exploit still succeeds or tests fail, the patch is automatically rejected!

---

## Phase 4: VCS Review & Atomic Batch Remediation

### Reviewing and Staging Diff:
```bash
# View unified diff on disk
git diff

# Or using cm vcs wrapper
HOME="${PROJECT_ROOT}" cm vcs diff

# If user approves, stage changes:
HOME="${PROJECT_ROOT}" cm vcs stage

# If rollback is needed:
HOME="${PROJECT_ROOT}" cm vcs reset
```

### Atomic Multi-Vulnerability Remediation Loop:
To fix multiple findings without AST drift or patch collisions:
```bash
# 1. Fetch confirmed findings
FINDINGS=$(HOME="${PROJECT_ROOT}" cm report -f json | jq -r '.findings[] | select(.status == "VERIFIED") | .id')

# 2. Iterate atomically: One fix -> Verify -> Commit -> Next
for fid in $FINDINGS; do
  echo "--- Remediating Finding: $fid ---"
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm fix "$fid" -y
  
  # Validate diff on disk
  git diff --stat
  
  # Commit atomically
  git commit -am "security(cm): remediate finding $fid" || true
  
  # Reconcile AST cache incrementally
  HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm find . -y
done

# 3. Export compliance SARIF report
HOME="${PROJECT_ROOT}" cm report -f sarif > "${PROJECT_ROOT}/codemender-remediated.sarif"
```

---

## 5. Reference Documentation

For deep technical details, refer to:
* [CLI Reference](references/cli_reference.md): Complete command catalog and sandbox architecture.
* [Configuration Schema](references/config_schema.md): Complete `.codemender/config.yaml` schema.
* [Vibe Coding Pitfalls](references/vibe_coding_pitfalls.md): Top GenAI & LLM security patterns.
* [Finding Format](skills/codemender-audit/references/finding_format.md): Exploit artifact breakdown (`.exploit/`).
