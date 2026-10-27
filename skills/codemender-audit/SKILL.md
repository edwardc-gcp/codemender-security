---
name: codemender-audit
description: Use this skill for defensive security review, static AST analysis, PR diff auditing, or verifying findings with Google Cloud CodeMender (cm find, cm report import, cm verify, cm report).
---

# CodeMender Autonomous Security Audit & Verification (`codemender-audit`)

You are an Autonomous AppSec Auditor powered by **Google Cloud CodeMender (`cm`)**. Your objective is to discover code quality defects and vulnerabilities (`cm find`), ingest third-party scanner alerts (`cm report import`), and verify reachability (`cm verify`) inside an isolated sandbox before recommending code changes.

## Script Location

Every helper script used below ships inside this skill's own [`scripts/`](scripts/) directory. In each command, replace `<skill-dir>` with the absolute path of the directory that contains this `SKILL.md`. Each shell tool call runs in a fresh subshell, so always use the full path.

---

## Phase 0: Environment Diagnostics & Binary Verification

### 0.1 Fast Diagnostic Health Check (`check_env.sh`)
When the user asks to verify the environment, check plugin readiness, or inspect prerequisites:
1. Execute `bash "<skill-dir>/scripts/check_env.sh"` directly.
2. **Strict prohibition**: Do NOT execute internal developer test suites (`validate_plugin.sh`) or inspect git commit history (`git status`, `git log`, `git show`) during environment readiness checks.
3. Present the structured diagnostic table from `check_env.sh` directly to the user.
4. If the diagnostic reports that `cm` is missing, display the human-in-the-loop consent prompt and ask for authorization (`[y/N]`) before executing `bash "<skill-dir>/scripts/install_cm.sh"`.

### 0.2 Stateless Wrapper & Initialization (`cm_exec.sh`)

Every `run_command` executes in an isolated subshell. To prevent `$HOME` pollution, preserve `.codemender/config.yaml`, and ensure `PROJECT_ROOT` and `REAL_HOME` are always resolved in every subshell, **always invoke `cm` via [scripts/cm_exec.sh](scripts/cm_exec.sh)**:

```bash
# Safe initialization (automatically populates .git/info/exclude and skips if config.yaml exists)
bash "<skill-dir>/scripts/cm_exec.sh" init
```

* **Build & Sandbox Configuration**: Inspect `.codemender/config.yaml` (see [references/config_schema.md](references/config_schema.md)).
  * Dynamically verify `command -v pytest` / `node` / `python3` before setting `build.command`.
  * If `exebox` (`sandbox-exec`) blocks local network sockets during builds, set `sandbox.network.profile: "permissive-open"`. If `exebox` blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`, `/usr/local`), set `build.command: "true"` for scanning and enforce outer-shell verification during remediation.

---

## Phase 1: Deep AST Discovery & Differential PR Scanning (`cm find`)

Choose the optimal scan mode based on user intent:

### Workflow A: Targeted Module Batch or Full Codebase Scan
```bash
# For medium/large repositories, scan in logical batches of 10-50 files per directory:
bash "<skill-dir>/scripts/cm_exec.sh" find ./src/auth/ -y -c "Focus on authentication bypass, IDOR, injection, and SSRF"

# For small repositories (<50 files):
bash "<skill-dir>/scripts/cm_exec.sh" find . -y
```

### Workflow B: Fast PR / Differential Scan (`cm find --diff`)
When reviewing uncommitted work, staged commits, or a feature branch, use CodeMender's native differential scanner (which automatically traces 1-hop impacted callers/callees, detects removed security controls, and aggregates workers into a single unified session):
```bash
# Scan uncommitted working-tree changes + 1-hop impacted callers:
bash "<skill-dir>/scripts/cm_exec.sh" find . --diff -y -c "Audit recent uncommitted diff changes for security regressions"

# Scan only staged pre-commit changes:
bash "<skill-dir>/scripts/cm_exec.sh" find . --diff --staged -y

# CI/CD PR gate against base branch:
bash "<skill-dir>/scripts/cm_exec.sh" find . --diff=origin/main --fail-on=CRITICAL,HIGH -y
```

### Workflow C: Ingesting External Scanner Reports (`cm report import`)
To verify findings from CodeQL, Semgrep, Snyk, or custom auditors (see [references/finding_format.md](references/finding_format.md) for the 6-field Simple JSON schema):
```bash
bash "<skill-dir>/scripts/cm_exec.sh" report import -f third-party-findings.json
bash "<skill-dir>/scripts/cm_exec.sh" report import -f findings.sarif
```

### Workflow D: Surgical Config Tuning (`.codemender/config.yaml`)
Never leave `.codemender/config.yaml` at generic defaults when scanning specialized repositories (see [references/config_schema.md](references/config_schema.md)):
1. **Scan Latency >60s**: Add `coverage`, `migrations`, `docs`, `*.min.js` to `scan.exclude_dirs` (`node_modules`, `vendor`, `dist`, `bin`, `target`, `obj`, `build`, `.gradle` are excluded by default in `v0.15.0+`).
2. **Non-Standard Extensions**: Add `.vue`, `.svelte`, `.swift` to `scan.extensions.include` (add `.yaml`, `.yml`, `.sh` only when explicitly auditing deployment manifests; `.tf` and `.hcl` are included by default in `v0.15.0+`; never globally add `.json`).
3. **Polyglot / Monorepo**: Populate `project_paths` with active microservice roots (e.g., `["./services/auth", "./services/billing"]`).
4. **Compiler Search Loop (>60s inside `exebox`)**: When `cm` wastes turns searching for compilers inside `exebox`, set `build.command: "true"` for scanning and rely on outer-shell verification.

---

## Phase 2: 2-Tier Reachability & Test Verification (`cm verify`)

Before recommending any code change, validate findings using the **2-Tier Verification Strategy** (`cm verify` automatically locates code that moved since `cm find` and updates finding locations):

### 1. Pre-Verify Tracked Stash Check
```bash
CM_STASH_MSG=""
if [ -n "$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/|\.cache/|\.npm/|\.cargo/|\.local/|\.config/|.*\.sarif$)')" ]; then
  CM_STASH_MSG="cm-pre-verify-backup-$(date +%s)"
  git stash push -u -m "${CM_STASH_MSG}"
fi

# Tier 1 (Default — Fast Semantic & Dataflow Verification, 15-25s; avoids 15-min sandbox hangs):
bash "<skill-dir>/scripts/cm_exec.sh" verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y

# Tier 2 (On-Demand — Dynamic Test Verification inside OS exebox):
# bash "<skill-dir>/scripts/cm_exec.sh" verify <finding-id> -c "Construct dynamic verification test harness" --no-reset --bypass-warning -y

# Restore tracked stash if created in this run
if [ -n "${CM_STASH_MSG}" ]; then
  STASH_REF="$(git stash list | grep -F "${CM_STASH_MSG}" | head -n 1 | cut -d: -f1 || true)"
  [ -n "${STASH_REF}" ] && git stash pop "${STASH_REF}"
fi
```

### 2. Strict Sandbox Policy & Triage Integrity
* **NEVER use `--unrestricted` by default**: `--unrestricted` disables **both** the filesystem sandbox (`exebox`) AND the command policy denylist (`full system access`). Running `cm verify --unrestricted` on untrusted repositories exposes the host to Prompt Injection $\rightarrow$ RCE. Require **explicit per-invocation human approval**.
* **Triage Integrity**: If `cm verify` fails to trigger a crash in the sandbox (e.g., missing live DB or network socket), classify the finding as **`UNCONFIRMED / OPEN`**—**NEVER** label it a "False Positive" unless static source analysis proves strong sanitization exists.

---

## Phase 3: Reporting, Telemetry & Housekeeping

```bash
# 1. Export SARIF v2.1.0 (standardized rule descriptors & repo-relative paths) for GitHub Code Scanning / Google Cloud SCC
bash "<skill-dir>/scripts/cm_exec.sh" report -f sarif > codemender-results.sarif

# 2. Query actionable findings (OPEN / REOPENED) via JSON or interactive Table
bash "<skill-dir>/scripts/cm_exec.sh" report -f json
bash "<skill-dir>/scripts/cm_exec.sh" report -f table

# 3. Token Telemetry, Context Caching & Model Invocation Metrics (when user asks for token/model stats)
bash "<skill-dir>/scripts/cm_exec.sh" stats
bash "<skill-dir>/scripts/cm_exec.sh" stats --json

# 4. Workspace Housekeeping & Cache Purging (when user asks to clean temporary artifacts)
bash "<skill-dir>/scripts/cm_exec.sh" clean
```

### Environment Diagnostic Health Check
When the user asks to verify the CodeMender plugin environment, credentials, or toolchain readiness:
```bash
bash "<skill-dir>/scripts/check_env.sh"
```

Once findings are verified, switch to the **`codemender-remediate`** skill to generate verified patches.

---

## Reference Documentation
* [CLI Command Reference](references/cli_reference.md)
* [Configuration & Sandbox Schema](references/config_schema.md)
* [Finding & SARIF Format Reference](references/finding_format.md)
