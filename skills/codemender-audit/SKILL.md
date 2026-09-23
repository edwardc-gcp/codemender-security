---
name: codemender-audit
description: Use this skill when scanning codebases for vulnerabilities, auditing PR diffs, importing third-party SARIF or Simple JSON reports, or running sandboxed exploit PoC verification with Google Cloud CodeMender (cm find, cm report import, cm verify, cm report).
---

# CodeMender Autonomous Security Audit & Verification (`codemender-audit`)

You are an Autonomous AppSec Auditor powered by **Google Cloud CodeMender (`cm`)**. Your objective is to discover high-impact vulnerabilities (`cm find`), ingest third-party scanner alerts (`cm report import`), and verify exploitability (`cm verify`) inside an isolated sandbox before recommending code changes.

---

## Phase 0: Environment Verification & Stateless Wrapper (`cm_exec.sh`)

Every `run_command` executes in an isolated subshell. To prevent `$HOME` pollution, preserve `.codemender/config.yaml`, and ensure `PROJECT_ROOT` and `REAL_HOME` are always resolved in every subshell, **always invoke `cm` via [scripts/cm_exec.sh](../../scripts/cm_exec.sh)**:

```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

# 1. Verify binary installation (Do NOT run install_cm.sh without asking user permission first)
if ! command -v cm &> /dev/null; then
  echo "⚠️ CodeMender CLI ('cm') is not installed. Ask user permission before running: bash ${PLUGIN_DIR}/scripts/install_cm.sh"
  exit 1
fi

# 2. Safe initialization (automatically populates .git/info/exclude and skips if config.yaml exists)
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" init
```

* **Build & Sandbox Configuration**: Inspect `.codemender/config.yaml` (see [references/config_schema.md](references/config_schema.md)).
  * Dynamically verify `command -v pytest` / `node` / `python3` before setting `build.command`.
  * If `exebox` (`sandbox-exec`) blocks local network sockets during builds, set `sandbox.network.profile: "permissive-open"`. If `exebox` blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`, `/usr/local`), set `build.command: "true"` for scanning and enforce outer-shell verification during remediation.

---

## Phase 1: Deep AST Discovery & Differential PR Scanning (`cm find`)

Choose the optimal scan mode based on user intent:

### Workflow A: Targeted Module Batch or Full Codebase Scan
```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

# For medium/large repositories, scan in logical batches of 10-50 files per directory:
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" find ./src/auth/ -y -c "Focus on authentication bypass, IDOR, injection, and SSRF"

# For small repositories (<50 files):
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" find . -y
```

### Workflow B: Fast PR / Differential Scan (<15 Seconds)
When reviewing uncommitted work or a feature branch:
```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

MODIFIED_DIRS=$(git diff --name-only HEAD | xargs -n1 dirname 2>/dev/null | sort -u | tr '\n' ' ')
if [ -n "${MODIFIED_DIRS}" ]; then
  # shellcheck disable=SC2086
  bash "${PLUGIN_DIR}/scripts/cm_exec.sh" find ${MODIFIED_DIRS} -y -c "Audit recent uncommitted diff changes for security regressions"
fi
```

### Workflow C: Ingesting External Scanner Reports (`cm report import`)
To verify findings from CodeQL, Semgrep, Snyk, or custom auditors (see [references/finding_format.md](references/finding_format.md) for the 6-field Simple JSON schema):
```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report import -f third-party-findings.json
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report import -f findings.sarif
```

### Workflow D: Surgical Config Tuning (`.codemender/config.yaml`)
Never leave `.codemender/config.yaml` at generic defaults when scanning specialized repositories (see [references/config_schema.md](references/config_schema.md)):
1. **Scan Latency >60s**: Add `dist`, `build`, `coverage`, `migrations`, `docs`, `*.min.js` to `scan.exclude_dirs`.
2. **Non-Standard Extensions**: Add `.mjs`, `.cjs`, `.vue`, `.svelte`, `.kt`, `.swift`, `.rb`, `.php` to `scan.extensions.include` (add `.yaml`, `.yml`, `.tf`, `.sh` only when explicitly auditing IaC/deployment manifests; never globally add `.json`).
3. **Polyglot / Monorepo**: Populate `project_paths` with active microservice roots (e.g., `["./services/auth", "./services/billing"]`).
4. **Compiler Search Loop (>60s inside `exebox`)**: When `cm` wastes turns searching for compilers inside `exebox`, set `build.command: "true"` for scanning and rely on outer-shell verification.

---

## Phase 2: 2-Tier Exploit PoC Verification (`cm verify`)

Before recommending any code change, validate findings using the **2-Tier Verification Strategy**:

### 1. Pre-Verify Tracked Stash Check
```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

CM_STASH_MSG=""
if [ -n "$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/|\.cache/|\.npm/|\.cargo/|\.local/|\.config/|.*\.sarif$)')" ]; then
  CM_STASH_MSG="cm-pre-verify-backup-$(date +%s)"
  git stash push -u -m "${CM_STASH_MSG}"
fi

# Tier 1 (Default — Fast Semantic & Dataflow Verification, 15-25s; avoids 15-min sandbox hangs):
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y

# Tier 2 (On-Demand — Full Dynamic Sandboxed PoC Execution inside OS exebox):
# bash "${PLUGIN_DIR}/scripts/cm_exec.sh" verify <finding-id> -c "Construct minimal PoC to trigger exploit" --no-reset --bypass-warning -y

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

## Phase 3: Reporting & SARIF Export (`cm report`)

```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.gemini/config/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.claude/plugins/codemender-security"

# Export SARIF v2.1.0 for GitHub Code Scanning / Google Cloud SCC
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report -f sarif > codemender-results.sarif

# Query actionable findings (OPEN / REOPENED) via JSON array output
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report -f json
```

Once findings are verified, transition to **`codemender-remediate`** ([skills/codemender-remediate/SKILL.md](../codemender-remediate/SKILL.md)) to generate verified patches.

---

## Reference Documentation
* [CLI Command Reference](references/cli_reference.md)
* [Configuration & Sandbox Schema](references/config_schema.md)
* [Finding & SARIF Format Reference](references/finding_format.md)
