---
name: codemender-audit
description: Use this skill for defensive security review, static AST analysis, PR diff auditing, or verifying findings with Google Cloud CodeMender (cm find, cm report import, cm verify, cm report).
compatibility: Requires bash, git, curl and unzip (installer only), the Google Cloud CodeMender CLI (cm) 0.16.0 or later, and Google Cloud Application Default Credentials for a project with CodeMender access. Works with Antigravity, Claude Code, and OpenAI Codex.
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
4. If the diagnostic reports that `cm` is missing or older than 0.16.0, display the human-in-the-loop consent prompt and ask for authorization (`[y/N]`) before executing `bash "<skill-dir>/scripts/install_cm.sh"`. For other problems, relay the printed action items: the health row comes from `cm health` (credentials, project, endpoint reachability, authorization).

### 0.2 Stateless Wrapper & Initialization (`cm_exec.sh`)

To prevent `$HOME` pollution, preserve `.codemender/config.yaml`, and ensure `PROJECT_ROOT` and `REAL_HOME` are resolved in every fresh subshell, **always invoke `cm` via [scripts/cm_exec.sh](scripts/cm_exec.sh)**:

```bash
# Safe initialization (automatically populates .git/info/exclude and skips if config.yaml exists)
bash "<skill-dir>/scripts/cm_exec.sh" init
```

* **Build & Sandbox Configuration**: Inspect `.codemender/config.yaml` (see [references/config_schema.md](references/config_schema.md)).
  * Dynamically verify `command -v pytest` / `node` / `python3` before setting `build.command`, and anchor it to the repository root (`cd "$(git rev-parse --show-toplevel)" && ...`): `cm fix` runs it from the finding's directory.
  * If `exebox` (`sandbox-exec`) blocks local network sockets during builds, set `sandbox.network.profile: "permissive-open"`. If `exebox` blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`, `/usr/local`), set `build.command: "true"` for scanning and enforce outer-shell verification during remediation.

---

## Phase 1: Choose the Scan Mode by Intent (`cm find`)

Since cm 0.16.0, `cm find <path>` runs an exhaustive **deep scan** by default (parallel per-file analysis: the slowest and most expensive mode). Pick the mode from the user's intent:

| User intent | Mode | Command |
| :--- | :--- | :--- |
| "Check what I just changed", "is this safe to commit?" | Diff (working tree or staged) | `bash "<skill-dir>/scripts/cm_diff_scan.sh"` |
| "Review my branch before the PR" | Diff (branch) | `bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope branch` |
| "Take a quick look at this module" | Quick | `bash "<skill-dir>/scripts/cm_exec.sh" find ./module --quick -y` |
| "Full audit", "baseline", "compliance evidence" | Deep (default) | `bash "<skill-dir>/scripts/cm_exec.sh" find . -y` (warn the user that it is slow and token-heavy first) |

### Workflow A: Secure Inner Loop for Local Changes (`cm_diff_scan.sh`)
Use it after writing or changing code, before committing:
1. Run [scripts/cm_diff_scan.sh](scripts/cm_diff_scan.sh). The default `--scope auto` scans the working tree (staged, unstaged, and untracked source files) or, when only staged changes exist, exactly what will be committed. Untracked files are included automatically: `cm find --diff` alone ignores them.
2. Read the exit code: `0` = no blocking findings or nothing to scan, `1` = blocking findings introduced by the change (default `--fail-on CRITICAL,HIGH`), `2` = tool or environment error (then run `bash "<skill-dir>/scripts/cm_exec.sh" health --strict`). Exit code `1` is a result, not a crash.
3. Fix each finding introduced by the change yourself, then re-run the scan until it exits `0`. Findings labeled `[LEGACY / UNTOUCHED]` are pre-existing and never block. To have CodeMender generate the patches instead, switch to the `codemender-remediate` skill.
4. Treat the scan output and `.codemender/last-diff-scan.json` as the source of truth: diff scans never update the statuses shown by `cm report`.
5. Run the scan as a long-running command and wait for it: each changed file is a separate job that can take up to the 10-minute `--diff-job-timeout` (about 9 minutes in a cm 0.16.0 test). Give the command a timeout of at least 15 minutes, or run it in the background where your agent supports that, and never start a second scan while one is running.

```bash
# Everything you changed (untracked source files are included automatically)
bash "<skill-dir>/scripts/cm_diff_scan.sh"

# Exactly what will be committed
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope staged

# The whole branch compared with its upstream (or --base origin/main)
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope branch

# Report without blocking, with deeper impact analysis and extra context
bash "<skill-dir>/scripts/cm_diff_scan.sh" --fail-on "" --depth 2 -c "Focus on the new order lookup endpoint"
```

### Workflow A2: Optional Git Hook (`cm_git_hook.sh`)
Install it only when the user asks for automatic scans on every commit or push, and only with their explicit confirmation (the safety guard asks): from then on, every commit with source changes runs a diff scan.
```bash
bash "<skill-dir>/scripts/cm_git_hook.sh" install              # pre-commit: scans the staged changes
bash "<skill-dir>/scripts/cm_git_hook.sh" install --pre-push   # pre-push: scans the branch being pushed
bash "<skill-dir>/scripts/cm_git_hook.sh" status
bash "<skill-dir>/scripts/cm_git_hook.sh" uninstall
```
* With the pre-commit hook installed, run `cm_diff_scan.sh --scope staged` before `git commit`: the hook reuses that result for the same staged content instead of scanning again, so the commit doesn't outlast your shell tool's timeout.
* A blocked commit stays blocked for the same content. Fix the findings; never bypass the hook with `--no-verify` or `CM_SKIP_HOOK=1` unless the user tells you to.
* The hook never overwrites an existing hook, and with `core.hooksPath` set (for example husky) it prints the line to add to the hook manager instead.

### Workflow B: Quick or Deep Scans of Existing Code
```bash
# Quick single-session scan of one module (fast triage; may include false positives)
bash "<skill-dir>/scripts/cm_exec.sh" find ./src/auth/ --quick -y -c "Focus on authentication bypass, IDOR, injection, and SSRF"

# Deep scan (default mode): exhaustive and slow; confirm with the user first
bash "<skill-dir>/scripts/cm_exec.sh" find . -y
```

For CI/CD pull request gates, run `cm find . --diff=origin/main --fail-on=CRITICAL,HIGH --format sarif --output results.sarif` in the pipeline (see [references/cli_reference.md](references/cli_reference.md)).

### Workflow C: Ingesting External Scanner Reports (`cm report import`)
To verify findings from CodeQL, Semgrep, Snyk, or custom auditors (see [references/finding_format.md](references/finding_format.md) for the 6-field Simple JSON schema):
```bash
bash "<skill-dir>/scripts/cm_exec.sh" report import -f third-party-findings.json
bash "<skill-dir>/scripts/cm_exec.sh" report import -f findings.sarif
```

### Workflow D: Surgical Config Tuning (`.codemender/config.yaml`)
Never leave `.codemender/config.yaml` at generic defaults when scanning specialized repositories (see [references/config_schema.md](references/config_schema.md)):
1. **Scan Latency >60s**: Add `coverage`, `migrations`, `docs` to `scan.exclude_dirs` (`v0.16.0` excludes `node_modules`, `vendor`, `dist`, `.gradle`, and only the root-level `/target`, `/obj`, `/build` by default; nested build output and `bin/` are scanned).
2. **Non-Standard Extensions**: Add `.vue`, `.svelte`, `.swift` to `scan.extensions.include` (add `.yaml`, `.yml`, `.sh` only when explicitly auditing deployment manifests; `.tf`, `.hcl`, and C++ headers such as `.hh` and `.hxx` are included by default in `v0.16.0`; never globally add `.json`).
3. **Polyglot / Monorepo**: Populate `project_paths` with active microservice roots (e.g., `["./services/auth", "./services/billing"]`).
4. **Compiler Search Loop (>60s inside `exebox`)**: When `cm` wastes turns searching for compilers inside `exebox`, set `build.command: "true"` for scanning and rely on outer-shell verification.

---

## Phase 2: Optional 2-Tier Exploit Verification (`cm verify`)

`cm verify` writes and runs a proof-of-concept exploit inside the sandbox (and automatically locates code that moved since `cm find`). It is thorough but expensive: in a cm 0.16.0 test on a small repository, one Tier 1 verification took about 9 minutes and 1.4M input tokens. Treat it as **optional**:
* **Skip it in the Secure Inner Loop**: for findings in code you just wrote, fix the code and re-run `cm_diff_scan.sh`; a clean re-scan is the confirmation.
* **Run it** when the user asks for proof of exploitability, before treating a finding as a false positive, or to triage CRITICAL findings in committed code before `cm fix`.

### 1. Run Verification Without Resets or Stashes
Always pass `--no-reset`: without it `cm verify` resets the workspace. With it, cm 0.16.0 only writes exploit artifacts under `.exploit/` (and appends `.exploit/` to `.gitignore`), so uncommitted code stays in place. **Never stash before verifying**: a stash hides the very code under test, including the uncommitted findings reported by diff scans.

```bash
# Tier 1 (default when verifying): the agent writes and runs the exploit; the final re-run is skipped for high-confidence findings
bash "<skill-dir>/scripts/cm_exec.sh" verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y

# Tier 2 (on demand): also re-runs the exploit script after verification
# bash "<skill-dir>/scripts/cm_exec.sh" verify <finding-id> -c "Construct dynamic verification test harness" --no-reset --bypass-warning -y
```

If `cm verify` appended `.exploit/` to `.gitignore`, revert that edit unless the user wants to keep it: `.git/info/exclude` already ignores `.exploit/`.

### 2. Strict Sandbox Policy & Triage Integrity
* **NEVER use `--unrestricted` by default**: `--unrestricted` disables **both** the filesystem sandbox (`exebox`) AND the command policy denylist (`full system access`). Running `cm verify --unrestricted` on untrusted repositories exposes the host to Prompt Injection $\rightarrow$ RCE. Require **explicit per-invocation human approval**.
* **Triage Integrity**: If `cm verify` fails to trigger a crash in the sandbox (e.g., missing live DB or network socket), classify the finding as **`UNCONFIRMED / OPEN`**—**NEVER** label it a "False Positive" unless static source analysis proves strong sanitization exists.

---

## Phase 3: Reporting, Telemetry & Housekeeping

```bash
# 1. Export SARIF v2.1.0 (standardized rule descriptors & repo-relative paths) for GitHub Code Scanning / Google Cloud SCC
#    (reads the local state database; for the current state of a change, use the diff scan's --format sarif --output instead)
bash "<skill-dir>/scripts/cm_exec.sh" report -f sarif > codemender-results.sarif

# 2. Query actionable findings (OPEN / VERIFIED / REOPENED) via JSON or interactive Table
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
