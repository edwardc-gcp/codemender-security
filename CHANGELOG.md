# Changelog

All notable changes to the `codemender-security` community plugin are documented in this file.

## [1.7.0] - 2026-11-12

Works with CodeMender CLI 0.16.0 through 0.21.0 (0.21.0 recommended).

### Features
- `cm_remediate_loop.sh` checks `build.command` in CodeMender's sandbox before the first fix. CodeMender 0.21.0 runs `build.command` inside the sandbox both for `cm build` and for the build validation in `cm fix`, so one `cm build` (no model tokens) shows whether `cm fix` can validate a patch at all. When the build fails there, for example because it needs the network or Go modules that aren't vendored, the loop stops with exit `2` and shows the build's last lines before any fix session spends tokens. The full output goes to `.codemender/build-preflight.log`, and `--no-build-preflight` skips the check. Older CLIs and empty or no-op build commands aren't affected.
- The audit skill checks a new or changed `build.command` in the sandbox with `cm_exec.sh build --force` on CodeMender 0.21.0 and later.

### CodeMender 0.20.0 and 0.21.0 Support
- `cm report --status` (0.20.0) accepts `VERIFIED` and `EXPLOIT_FAILED`, and `OPEN` now matches every finding that isn't `FIXED` or `DISMISSED` (observed). The skills and references no longer say that `VERIFIED` is rejected, and `cm_remediate_loop.sh --all-open` documents that it picks the same set (its behavior doesn't change).
- The CLI and config references cover 0.21.0: builds inside the sandbox (no network, writes only inside the repository, `.npmrc` unreadable, caches that start empty, `GOPROXY=off` for Go), `cm vcs diff` without diff drivers, repository Git hooks that still run in a build command's own git commands (observed, although the release notes say hooks are disabled), Gemini 4 Carbon (Preview) and Gemini 4 Carbon for cyber, the `cm verify` advice to use a cyber model, the 30-minute timeout for silent turns, and the 0.20.0 fix for scans that reported zero findings for unreadable directories.
- Observed behaviors re-checked on 0.21.0: the `cm init` template and command policy are unchanged since 0.17.0, unknown config keys still aren't flagged, `cm fix --export` still isn't implemented, and the `--architecture` example in `cm verify --help` is still an unknown flag.

### Fixes
- On CodeMender 0.18.0 and later, `cm_diff_scan.sh --depth 2` said that the installed release (for example 0.21.0) removed `--diff-depth`; it now names 0.18.0, the release that removed it.
- The audit skill's diff-scan example used `--depth 2`, which CodeMender 0.18.0 and later refuse; it now passes `--diff-max-neighbors 20` instead.

## [1.6.0] - 2026-11-06

Works with CodeMender CLI 0.16.0 through 0.18.0 (0.18.0 recommended).

### Safety
- With CodeMender 0.18.0 and plugin 1.5.0, a diff scan with `--dry-run` after `--` printed "No blocking findings" for a scope preview and recorded it as a clean staged scan, so the pre-commit hook skipped the real scan of those changes (observed). `cm_diff_scan.sh` now refuses `--dry-run` and the interactive `--validate` after `--`, and only a findings array counts as a result: any other report exits `2` without a `.meta` file, and a run without a report isn't recorded for reuse.
- The pre-commit hook reuses a staged scan only when its report holds findings, so a preview that 1.5.0 recorded can't let a commit through unscanned. Run `cm_git_hook.sh install` again to update an installed hook runner.

### CodeMender 0.18.0 Support
- `cm_diff_scan.sh --depth` follows the installed CLI. 0.18.0 removed `--diff-depth` (diff scans always resolve 1 hop), so `--depth 1` is dropped and a larger depth is refused before cm runs, instead of failing with a credentials hint. Releases up to 0.17.0 still get `--diff-depth`.
- New `cm_diff_scan.sh --dry-run` (0.18.0 or later) previews the changed files, the 1-hop neighbors, and an architecture summary at no cost, with the same scope logic as a scan (untracked files included). The preview goes to `.codemender/last-diff-scan.dry-run.json` and never replaces the findings report or its `.meta`.
- When cm fails without a report, `cm_diff_scan.sh` shows cm's own error line (for example an unknown flag) and points at `cm find --help`.
- The audit playbook raises `--diff-max-neighbors` (with `--fail-on-truncation`) for a widely used function that changed, instead of `--depth 2`.
- The CLI and config references cover 0.18.0: no `--diff-depth`, `--dry-run`, `--validate`, `cm models`, new messages, no `model` key in `config.yaml`, and the current telemetry description. The import schema follows the current docs (`start_line`, `end_line`, `snippet`).
- Observed behaviors re-checked on 0.18.0: the `cm init` template and command policy are unchanged, unknown config keys still aren't flagged, `cm fix --export` still isn't implemented, and the `--architecture` example in `cm verify --help` is still an unknown flag.

### Fixes
- `cm_diff_scan.sh` stops with a usage error when an option is missing its value (a bare `--depth` looped forever), and its help shows the whole header.
- The README no longer says that CLI telemetry excludes identity: per the CodeMender docs, it can identify the account and project.

## [1.5.0] - 2026-11-02

Works with CodeMender CLI 0.16.0 and 0.17.0 (0.17.0 recommended).

### Safety
- The guard asks before CodeMender 0.17.0's `--allow-all-paths` and `--allow-all-commands`, which turn off the path boundary and the command policy, and before every spelling of `--sandbox=false` that cm accepts (`=False`, `=FALSE`, `=f`). The safety rule and docs describe these flags instead of `--unrestricted`, which 0.17.0 removed.
- `cm_diff_scan.sh` refuses `--allow-all-paths` and `--allow-all-commands` after `--`.

### CodeMender 0.17.0 Support
- `cm_remediate_loop.sh` passes `--no-reset` to `cm fix` on 0.17.0 and later (the checkpoint commit stays), and keeps untracked `*.sarif` reports when it cleans up.
- `cm_diff_scan.sh` explains setup failures by their new exit codes (`10` credentials, `20` config, `30` reachability, `40` authorization, `50` timeout) instead of always pointing at credentials.
- `cm_config_check.sh` knows `output.plain` and `execution.interactive_mode`, and notes when interactive mode is off.
- The CLI and config references cover 0.17.0: `--plain`, `--no-reset`, `cm stats --jsonl`, `cm support-bundle`, confirmation precedence, `command_policy.yaml`, the new sandbox protections, setup exit codes, model retirements, and new messages. The skills use them.
- Observed behaviors re-checked on 0.17.0: unknown config keys still aren't flagged, `cm fix --export` still isn't implemented, `cm report --status VERIFIED` is still rejected, and the `--architecture` example in `cm verify --help` is still an unknown flag.

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
