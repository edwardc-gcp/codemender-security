# Changelog

All notable changes to the `codemender-security` community plugin are documented in this file.

## [1.4.2] - 2026-10-28

- `cm_remediate_loop.sh` reads `build.command` the way YAML does. A double-quoted command with escaped quotes, such as `"cd \"$(git rev-parse --show-toplevel)\" && npm run build"`, no longer fails the outer build gate and reverts every fix. A no-op `build.command` (`"true"`) now makes the gate probe the project instead of turning it off.
- The audit skill no longer asks for another staged scan before a commit when the same staged changes already passed one.

## [1.4.1] - 2026-10-27

- `cm_exec.sh` no longer exports a location variable that the public CodeMender docs don't mention; `cm` uses the global location by default.

## [1.4.0] - 2026-10-27

Requires CodeMender CLI 0.16.0 or later.

### Full CodeMender 0.16.0 Coverage
- **Complete references**: `cli_reference.md` now covers every public `cm` command and flag (with defaults and when to use each), global flags, environment variables, models and their fallback, files under `CM_HOME`, runtime limits, exit codes, and common messages. `config_schema.md` lists every documented config key with its type, default, and effect.
- **Observed behavior**:
  - `cm` doesn't warn about unknown config keys.
  - `cm fix --export` isn't implemented.
  - `cm report --status` rejects `VERIFIED`.
  - The `--architecture` example in `cm verify --help` is an unknown flag.
- **Flag playbooks**: The audit and remediate skills map common situations to the right flags and commands.

### Using Flags and Config
- `cm_diff_scan.sh` and `cm_remediate_loop.sh` pass extra flags after `--` to `cm find` and `cm fix`. The scanner refuses the flags it sets itself and the sandbox flags.
- New `cm_config_check.sh` reports undocumented keys (with the right name), invalid values, and risky settings such as a disabled sandbox.
- `cm_exec.sh init --verify` now runs even when the config exists.
- `cm_diff_scan.sh` treats scans with failed file jobs (INCOMPLETE) as errors instead of clean results.

### Safety Guard
- Bare `cm` matches only in command position. Commit messages and `echo` text that mention a `cm` subcommand no longer trigger the guard, while `/usr/local/bin/cm`, `cd app && cm ...`, and `$(cm ...)` are still caught.
- Sandbox flags passed through `cm_diff_scan.sh` require consent, and the safety rule now also covers `sandbox.enabled: false`.

## [1.3.0] - 2026-10-27

Requires CodeMender CLI 0.16.0 or later.

### CodeMender 0.16.0 Diff Mode (Secure Inner Loop)
- **Local change scanner (`scripts/cm_diff_scan.sh`)**: Runs `cm find --diff` on the working tree, the staged changes, the branch (merge base with `--base` or the upstream), or the last commit, with an `auto` scope that picks the right one.
  - Includes untracked source files, which `cm find --diff` alone ignores, through a temporary `git add -N` that is always undone (also after a crash).
  - Skips the scan when no source file changed, and separates findings introduced by the change from `[LEGACY / UNTOUCHED]` ones.
  - Exits `0` clean, `1` blocking findings, or `2` tool error (cm returns `1` for both findings and errors), and writes `.codemender/last-diff-scan.json` plus a `.meta` file with the scanned path, staged tree, and exit code.
- **Opt-in git hook (`scripts/cm_git_hook.sh`)**: Installs a pre-commit hook (staged changes) or a pre-push hook (pushed branch). It reuses an earlier staged scan of the same content, never overwrites existing hooks or writes into `core.hooksPath`, and doesn't block when the scan can't run unless `CM_HOOK_STRICT=1`.
- **Intent-based scan routing**: The audit skill picks diff scans for local changes, quick scans for module triage, and deep scans (the slow 0.16.0 default) only for full audits.
- **Long-running scans**: The audit skill tells agents to run diff scans as long-running commands (one took about 9 minutes in testing) instead of retrying them.

### Remediation & Verification
- **Checkpoint commit instead of `git stash`**: `cm fix` still resets its workspace in 0.16.0, so `cm_remediate_loop.sh` commits uncommitted work as a `wip(cm)` checkpoint first and restores it as uncommitted changes on exit (`--keep-commits` keeps the commits).
- **Autofix-style fix commits**: Commits tracked changes and new source files only, and drops CodeMender's own `.gitignore` edits.
- **Diff-driven targeting**: By default the loop fixes the findings introduced by the current change and re-scans after every fix (`--max-fixes`, `--strict`); explicit IDs and `--all-open` get a regression scan of each fix commit. `VERIFIED` findings count as actionable.
- **Optional verification**: Removed the pre-verify stash (`--no-reset` keeps uncommitted code in place) and made `cm verify` optional, since one run took about 9 minutes and 1.4M tokens in testing.

### Cross-Agent Support (Antigravity, Claude Code, OpenAI Codex)
- Each skill bundles its helper scripts (`skills/*/scripts/`, kept in sync by `scripts/sync_skill_scripts.sh`) and uses skill-relative paths, agent-neutral wording, and `compatibility` metadata.
- Added `hooks/hooks.json` for Claude Code and Codex, plus `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`. Codex can't prompt, so consent rules deny there with an explanation.
- Removed the Gemini CLI extension manifest (`gemini-extension.json`).

### Safety Guard & Environment
- Consent rules stay within one shell command and also cover `--sandbox=false`, wrapper calls, `cm build`, `cm update`, and `cm_git_hook.sh install`.
- `check_env.sh` checks access with the side-effect-free `cm health` (credentials, config, reachability, authorization), detects `cm` installed off `PATH`, and requires 0.16.0 or later. `install_cm.sh` verifies the install with `cm health` instead of `cm init --verify`.
- `cm_exec.sh` sets `CM_HOME`, forwards credentials more robustly, and adds `--compact` and `--bypass-warning` automatically.

### Documentation & Tests
- Aligned the CLI reference, config schema, and finding format with CodeMender 0.16.0: deep scan default, `--quick`, diff flags and exit codes, global flags, `cm health` exit codes, `cm report` filters, the `VERIFIED` status, finding fingerprints, `info.yaml`, the `cm fix` workspace reset and root-anchored `build.command`, and new `cm init` defaults.
- Added stub-`cm` regression suites for the diff scanner, the remediation loop, and the git hook, plus Claude Code and Codex guard contract tests, all run by `scripts/validate_plugin.sh`.

## [1.2.0] - 2026-09-28

### Architecture & Agent Experience Enhancements
- **Declarative Strategy Pipeline for Polyglot Build Gates (`cm_remediate_loop.sh`)**:
  - Replaced imperative `if/elif` chain with an extensible Strategy Pipeline (`probe_config_file`, `probe_node`, `probe_python`, `probe_golang`, `probe_rust`, `probe_jvm`).
  - Added priority auto-detection of `build.command` from `.codemender/config.yaml`.
  - Added full TypeScript (`tsconfig.json` $\rightarrow$ `npx tsc --noEmit`) and JVM/Gradle/Maven support.
- **Diagnostic Environment Health Checker (`scripts/check_env.sh`)**:
  - Added standalone diagnostic tool checking `cm` version, Google Cloud ADC auth status, active project, and workspace data protection in a structured ASCII summary.
- **Natural Language Telemetry & Housekeeping**:
  - Expanded `codemender-audit` with explicit conversational mapping for token diagnostics (`cm stats`), workspace cleanup (`cm clean`), and interactive status tables (`cm report -f table`).
- **GenAI Vibe Coding Pitfalls Enhancement**:
  - Added Sequelize named parameterization/replacement binding patterns (`replacements: { ... }`) to `references/vibe_coding_pitfalls.md`.

## [1.1.0] - 2026-09-22

### Security & Data-Safety Guardrails
- **Bash & Zsh Portable Remediation Loop**: Replaced `for fid in $FINDINGS` with `while IFS= read -r fid; do ... done <<< "${FINDINGS}"` so multi-finding loops execute properly in both `zsh` (macOS default) and `bash`.
- **Non-Destructive VCS Lifecycle (`git add -A` & `git stash pop`)**:
  - Added `.codemender/`, `.cm_project`, and `.exploit/` protection via `$(git rev-parse --git-path info/exclude)` so `cm fix`'s internal `git clean -fd` never wipes `.codemender/state.db`.
  - Replaced `git commit -am` with `git add -A && git commit -m` so newly created helper files from `cm fix` are staged and never deleted by subsequent `cm fix` runs.
  - Added anchored dirty-state detection (`^.. (\.codemender/|\.cm_project$|\.exploit/)`), `git stash push -u` backup naming, and conflict-safe `git stash pop` restoration.
- **Stateless Environment Forwarding**: Added `GIT_CONFIG_GLOBAL`, `CLOUDSDK_CONFIG`, and `GOOGLE_CLOUD_PROJECT` alongside `HOME="${PROJECT_ROOT}"` so child `git` and `gcloud` processes retain host configurations.
- **Enforced Outer-Shell Build Hard Gate**: Added runtime binary probing (`command -v`) and an explicit outer-shell validation gate (`OUTER_BUILD_CMD`) when `build.command: "true"` is used in `.codemender/config.yaml`.
- **2-Tier Verification & `--unrestricted` Consent**:
  - Added Tier 1 fast semantic verification (`cm verify --skip-exploit-verification --no-reset --bypass-warning -y`) to avoid macOS `exebox` (`sandbox-exec`) TCP socket and external toolchain (`~/.nvm`, `/opt/homebrew`) deadlocks.
  - Added explicit RCE hazard warning and per-invocation human confirmation requirement for `--unrestricted`.
- **Installer Hardening (`scripts/install_cm.sh`)**: Added `curl`/`unzip` dependency checks, strict OS/Arch validation (`exit 1` on unsupported platforms), SHA-256 checksum printing and `CM_SHA256` verification, and disabled silent auto-installation without user consent.

### Documentation & Governance
- Added prominent `"DISCLAIMER: This is not an official Google product."` across `README.md`, `LICENSE`, and all plugin manifests (`plugin.json`, `gemini-extension.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`).
- Added `"contextFileName": "SKILL.md"` to `gemini-extension.json`.
- Added Section 3 **Surgical `.codemender/config.yaml` Tuning Playbook** in `references/config_schema.md` and real `cm 0.8.0` JSON output schema in `finding_format.md`.
