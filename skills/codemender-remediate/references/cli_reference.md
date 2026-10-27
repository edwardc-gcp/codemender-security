# CodeMender CLI Command Reference (cm 0.16.0)

Every public `cm` command, flag, environment variable, and runtime limit of **CodeMender CLI 0.16.0**. Sources: the `--help` output, the `cm init` template, the public CodeMender docs and release notes, and test runs of the public CLI (marked "observed"). Nothing here comes from internal or undocumented sources. Print the installed version with `cm --version` (there is no `cm version` subcommand).

Examples show bare `cm` for readability. In an agent session, run every stateful subcommand through `cm_exec.sh` (Section 1). For `config.yaml` keys, see `config_schema.md`.

**Contents**: 1. Stateless invocation · 2. Global flags · 3. `cm find` · 4. Diff scans · 5. `cm verify` · 6. `cm fix`, `cm build`, `cm vcs` · 7. Reporting · 8. Sessions · 9. Health, init, and maintenance · 10. Models · 11. Environment variables · 12. Files and directories · 13. Runtime limits · 14. Exit codes · 15. Messages and what to do

---

## 1. Stateless Invocation (`cm_exec.sh`)

Run the stateful subcommands (`find`, `verify`, `fix`, `init`, `report import`, `vcs`, `build`) only through the bundled wrapper:

```bash
bash "<skill-dir>/scripts/cm_exec.sh" <subcommand> [args...]
```

On every call, the wrapper:
* Sets `HOME` and `CM_HOME` to the repository (`${PROJECT_ROOT}/.codemender`), so each repository keeps its own config, `state.db`, and logs, and concurrent projects never share `~/.codemender`.
* Forwards the real `~/.gitconfig`, the gcloud config, `GOOGLE_APPLICATION_CREDENTIALS` (the variable when set, else the ADC file), and `GOOGLE_CLOUD_PROJECT` (else the gcloud default project).
* Adds `.codemender/`, `.cm_project`, `.exploit/`, toolchain caches, and the plugin's SARIF files to `.git/info/exclude`, so the `git clean -fd` inside `cm fix` and a later `git add -A` never touch them.
* Refuses `-y`/`--yes` on `cm init`, and skips `cm init` when `.codemender/config.yaml` already exists (`cm init --verify` always runs, because it only reads).
* Adds `--compact` to `find`, `verify`, and `fix` (unless `--compact` or `-v` is passed), and `--bypass-warning` to `verify` and `fix`.

The other bundled scripts accept extra `cm` flags after `--`: `cm_diff_scan.sh ... -- <cm find flags>` and `cm_remediate_loop.sh ... -- <cm fix flags>`.

---

## 2. Global Flags (every command)

Subcommand `--help` output doesn't list these, but every command accepts them.

| Flag | Effect |
| :--- | :--- |
| `-y, --yes` | Auto-approves prompts (commands and file writes) and skips the automatic update check. Required for non-interactive runs. |
| `--bypass-warning` | Skips the warning prompt. |
| `--compact` | Rolling status line (`Tokens: 40k in / 12k out / 60k total`) that updates in place, for `find`, `fix`, `verify`, and `session resume`. |
| `-v, --verbose` | Verbose debug output (session logs always include debug lines). |
| `--sandbox` | OS-level sandbox, on by default. `--sandbox=false` turns it off: **explicit per-invocation user consent required**. |
| `--no-model-fallback` | Uses only the selected model instead of retrying `gemini-4-argon` safety blocks on fallback models (or `CM_DISABLE_MODEL_FALLBACK=true`). |
| `--team-id <id>` | Telemetry team identifier sent as the `X-CodeMender-Team-Id` header (or `$CM_TEAM_ID`, or `team_id` in `config.yaml`); at most 63 characters from `[A-Za-z0-9._-]`. |
| `--version` | Prints the CLI version. |
| `--notices` | Prints the third-party license notices. |
| `-h, --help` | Help for any command. |

---

## 3. Scans (`cm find <path>`)

`<path>` is a directory or a single file. Since 0.16.0, `cm find` without a mode flag runs a **deep scan**; `--deep`, `--quick`, and `--diff` are mutually exclusive.

| Mode | Command | Scope | Use for |
| :--- | :--- | :--- | :--- |
| Deep (default) | `cm find . -y` | Every discovered source file, audited concurrently and corroborated before reporting | Baselines, scheduled and pre-release audits, compliance evidence. Slowest and most token-heavy mode: never use it as a blocking pull request check. |
| Quick | `cm find ./src --quick -y` | One single-session scan of the target | Fast local triage of a module. Lower recall on large repositories, and may report false positives (triage them with `cm verify`). |
| Diff | `cm find . --diff -y` | Changed hunks plus the files that call or depend on them | The inner loop, pre-commit and pre-push hooks, and pull request gates (Section 4). |

### All `cm find` flags

| Flag | Default | Modes | Use it when |
| :--- | :--- | :--- | :--- |
| `-c, --context <text>` | none | all | You can name the threat model, trust boundaries, or focus areas ("Focus on auth bypass in the admin API"). |
| `--model <name>` | `gemini-3.8-flash` | all | You need deeper reasoning (`gemini-4-argon`) or a cyber model you have access to (Section 10). |
| `--include-hidden` | off | all | Dot-prefixed directories and files matter, such as `.github/workflows` (or `scan.include_hidden: true`). Add the file extensions too. |
| `--enable-bash` | off | all | The scan agent needs shell commands (sandboxed) to understand the code, for example generated sources. Uses more turns (or `CMOC_FIND_ENABLE_BASH=true`). |
| `--format <fmt>` | `table` | all | `json` for scripts, `sarif` (SARIF v2.1.0) for code scanning. |
| `--output <file>` | stdout | all | The report should go to a file (written for every mode since 0.12.0). |
| `--unrestricted` | off | all | Never by default: turns off the filesystem sandbox. **Explicit per-invocation user consent required.** |
| `-y, --yes` | off | all | Always in agent and CI runs. |
| `--deep` | (default mode) | deep | Only for backward compatibility. |
| `--deep-workers <n>` | `8` | deep | Lower it (1 to 16) on small machines or quota limits; raise it for large repositories. |
| `--deep-max-turns <n>` | `5` | deep | Lower it to cut cost; raise it for complex files (or `CMOC_DEEP_MAX_TURNS`; `0` means unlimited). |
| `--quick` | off | quick | You want a fast single-session look. |
| `--diff[=<ref>]` | `HEAD` | diff | Scanning changes against `<ref>` (Section 4). |
| `--staged` | off | diff | Only the staged changes should be scanned (pre-commit). |
| `--diff-depth <n>` | `1` | diff | A change alters a contract or signature used farther away (1 to 3 hops). |
| `--diff-workers <n>` | `4` | diff | Many files changed (1 to 16 concurrent file jobs). |
| `--diff-max-neighbors <n>` | `10` | diff | A widely used function changed and more callers should be inspected. |
| `--diff-job-timeout <duration>` | `10m` | diff | Large files time out (the scan becomes INCOMPLETE); the timeout already scales for large files. |
| `--fail-on <severities>` | `CRITICAL,HIGH` | diff | Setting the gate policy; `--fail-on ""` reports without failing. |
| `--fail-on-truncation` | off | diff | A CI gate must fail when dependent-file discovery hits `--diff-max-neighbors`, instead of passing with partial coverage. |

### File discovery (0.16.0)
* Scans files whose extensions are in `scan.extensions.include` (28 by default), plus extensionless scripts with a `python`, `node`, `ruby`, or `php` shebang.
* Skips `scan.extensions.exclude` suffixes, `scan.exclude_dirs` (a leading `/` matches only at the scan root, so nested `build/`, `target/`, `obj/`, and `bin/` source directories are scanned), dot-prefixed paths unless `--include-hidden`, and files larger than `scan.max_file_size_kb`.
* Also scans production code under `spec/`, `locale/`, and `i18n/`.
* Diff mode picks changed tracked files even when their extension isn't listed (observed: a `.gitignore` edited by `cm verify` was scanned).

```bash
# Quick triage of one module, with threat-model context
cm find ./src/auth/ --quick -y -c "Focus on SQL injection and auth bypass"

# Deep scan of the whole repository (confirm the cost with the user first)
cm find . -y --deep-workers=8 --format sarif --output deep-scan.sarif
```

---

## 4. Diff Scans (`cm find --diff`)

| Command | Scans |
| :--- | :--- |
| `cm find . --diff -y` | Uncommitted changes to **tracked** files, compared with `HEAD`. |
| `cm find . --diff --staged -y` | Staged content only (`git diff --cached`): exactly what will be committed. |
| `cm find . --diff=origin/main -y` | The branch compared with a base ref (pull request gate). The ref must exist locally; in CI, check out with `fetch-depth: 0`. |
| `cm find . --diff=HEAD~1 -y` | The last commit. |

How to read the results (observed with cm 0.16.0):
* **Untracked files are not scan targets.** A brand-new file is seen only indirectly, if at all, through a changed file that uses it. Register new files with `git add -N <file>` (intent-to-add) before scanning. `cm_diff_scan.sh` does this automatically and undoes it afterwards.
* **Legacy isolation**: pre-existing issues in untouched code get a `[LEGACY / UNTOUCHED]` title prefix and never trigger `--fail-on`.
* **Exit codes**: `0` means no blocking findings, including when nothing changed (it returns in about a second, without model calls). `1` means blocking findings **or** an error, such as an unknown ref or failed authentication. Tell them apart by whether the `--output` file was written.
* **INCOMPLETE scans**: a file job that fails (`[1/2] ❌ app.py: start session failed`) leaves the summary at `N succeeded, M failed` and the session INCOMPLETE, yet the exit code can still be `0`. Treat that as unscanned code and re-run; `cm_diff_scan.sh` exits `2` in this case.
* **Report**: `--format json` writes a top-level JSON array of findings (`[]` when clean) with absolute `file_path` values. See `finding_format.md` in the `codemender-audit` skill.
* **State**: diff scans don't change the statuses in `state.db`. After the code is fixed and a re-scan is clean, `cm report` still lists the old findings (for example as `OPEN` or `VERIFIED`). Treat the latest diff report as the source of truth, and use its `--format sarif --output` file for a current-state SARIF.
* **Cost**: in a small test repository, each diff scan took about 1.5 to 9 minutes (files are scanned in parallel, so the slowest file sets the pace) and 70k to 180k tokens, compared with about 1.4M tokens for one `cm verify` and 3.2M for one `cm fix`.

The bundled wrapper returns `0` (clean), `1` (blocking findings), or `2` (tool or environment error, or an INCOMPLETE scan) and writes `.codemender/last-diff-scan.json`:

```bash
bash "<skill-dir>/scripts/cm_diff_scan.sh"                  # auto: the working tree with untracked files, or only the staged changes
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope staged   # pre-commit
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope branch   # against the upstream, or --base origin/main
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope last-commit
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope branch -- --diff-max-neighbors 20 --diff-job-timeout 20m --model gemini-4-argon
```

CI/CD pull request gate:

```bash
cm find . --diff=origin/main --fail-on=CRITICAL,HIGH --fail-on-truncation --format=sarif --output=results.sarif -y --bypass-warning
```

---

## 5. Verification (`cm verify <finding-id>`)

`<finding-id>` is a full finding UUID or an unambiguous prefix, taken from `cm report` or a scan report.

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `-c, --context <text>` | none | Steers the agent, for example toward one request path or a multi-tenant boundary. |
| `--model <name>` | `gemini-3.8-flash` | Model for the verification agent (Section 10). |
| `--no-reset` | off | Suppresses all workspace resets. **Always pass it**: with it, cm 0.16.0 leaves uncommitted and untracked code untouched. |
| `--skip-exploit-verification` | off | Marks high-confidence findings VERIFIED without re-running the exploit after the agent finishes (the agent still writes and runs one). |
| `--unrestricted` | off | Turns off the filesystem sandbox **and** the command policy denylist (full system access). **Explicit per-invocation user consent required**; use only in isolated VMs or containers. |
| `-y, --yes` | off | Skips the prompts for tool actions and PoC execution (which stay sandboxed). |

| Command | Purpose |
| :--- | :--- |
| `cm verify <id> --skip-exploit-verification --no-reset -y` | **Tier 1**: the agent still writes and runs a proof-of-concept (PoC) exploit; only the final re-run is skipped for high-confidence findings. |
| `cm verify <id> --no-reset -y` | **Tier 2**: also re-runs the exploit script after verification. |

* Verification sets the status to `VERIFIED` or `DISMISSED`. Running `cm verify` again on a `DISMISSED` finding re-examines it and can restore it.
* The `--architecture=3-1` example in `cm verify --help` is stale: cm 0.16.0 rejects it as an unknown flag (observed).
* It finds code that moved since `cm find` and updates the finding's location.
* Since 0.16.0 the agent writes its files only to `.exploit/` inside the project root; cm itself also appends `.exploit/` to the tracked `.gitignore`.
* Cost: in a small test repository, one Tier 1 run took about 9 minutes and 1.4M tokens. Skip it in the inner loop, where a clean diff re-scan confirms a fix.

> [!IMPORTANT]
> **Exploit Verification Triage**: If an exploit script fails or times out (`EXPLOIT_FAILED`), do NOT classify the finding as a "False Positive". Dynamic exploits frequently fail due to `exebox` blocking local TCP sockets or non-system binary paths. Findings must remain classified as `UNCONFIRMED / OPEN` unless explicitly marked `DISMISSED` with concrete sanitizer/unreachability proof.

### Verification artifacts (`${PROJECT_ROOT}/.exploit/`, overwritten by the next run)
* `PLAN.md`: investigation and validation checklist.
* `LOG.md`: investigation log (commands, requests, and observations).
* `REPORT.md`: executive summary, root cause analysis, fix recommendation, and reproduction steps.
* `exploit.sh`: standalone, executable PoC.
* `info.yaml`: machine-readable verdict (`vulnerability_id`, `severity`, `confidence`, `status` such as `valid`, `chained_vulnerabilities`).
* Runtime logs from the PoC, such as `server.log`. `cm report --artifacts` lists the captured files per finding.

---

## 6. Remediation (`cm fix`, `cm build`, `cm vcs`)

### `cm fix <finding-id>`

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `-c, --context <text>` | none | Constraints or coding guidelines ("Use the parameterized helper in db/query.py"). |
| `--model <name>` | `gemini-3.8-flash` | A stronger model (`gemini-4-argon`) for complex patches. |
| `--no-cache` | off | Ignores cached patches and runs a fresh session, for example after a failed or unwanted patch. |
| `--export <session-id>` | none | **Not implemented in 0.16.0** (observed): it only prints `Exporting patch from session ... (not yet implemented)` and exits `0`. See generated patches with `cm report --patches` instead. |
| `--unrestricted` | off | Turns off the filesystem sandbox. **Explicit per-invocation user consent required.** |
| `-y, --yes` | off | Auto-approves file writes (otherwise each write prompts, unless `tools.confirm_writes: false`). |

How it validates a patch: it generates a candidate, applies it to a sandboxed copy, runs `build.command`, re-runs the verified PoC, and then applies the patch to your workspace. Since 0.12.0 it won't modify CI/CD pipelines, static analysis configs, build definitions, or repository configuration files outside the finding's scope. Through `cm_remediate_loop.sh`, pass these flags after `--` (for example `-- --model gemini-4-argon --no-cache`).

> [!CAUTION]
> `cm fix` has no `--no-reset`. Observed with cm 0.16.0:
> * It runs `git checkout HEAD -- . && git clean -fd` in its workspace before patching. **Commit uncommitted work first**: `cm_remediate_loop.sh` creates a `wip(cm)` checkpoint commit and restores the working tree afterwards. Don't use `git stash` for this.
> * Its workspace is the finding's directory (for example `app/`), not necessarily the repository root, and `build.command` runs from there. Anchor the command to the root: `cd "$(git rev-parse --show-toplevel)" && make test`.
> * When validation fails, the unvalidated patch stays in the working tree. Revert it.
> * It may create `<dir>/.gitignore` (headed `# CodeMender enforced ignores`) and copy `.exploit/` into its workspace. Don't commit them.
> * It exits `0` when it makes no edits, so check `git status` for changes.

### `cm build [path] --force`
Runs `build.command` in `[path]` (default: the current directory); `--force` skips the confirmation. It runs **outside** the sandbox (observed: on Linux it could write outside the repository), so a passing `cm build` doesn't prove that the sandboxed validation inside `cm fix` passes.

### `cm vcs <subcommand>`
| Subcommand | Effect |
| :--- | :--- |
| `cm vcs status` | Lists the files the agent modified or created. |
| `cm vcs diff` | Shows the changes since the last clean state. |
| `cm vcs stage` | Stages all modified files for commit. |
| `cm vcs reset` | **Destructive**: discards all uncommitted changes (`git checkout HEAD -- . && git clean -fd` for git). |
| `cm vcs init` | Ensures a clean Git repository exists at the path, for the agent's structured-thinking workspace. |

The commands come from `vcs.type` (git and mercurial auto-populate them) or `vcs.commands` for a custom VCS.

---

## 7. Reporting (`cm report`, `cm report import`, `cm stats`)

`cm report` reads `.codemender/state.db`. It doesn't reflect fixes confirmed only by a diff re-scan (Section 4).

### `cm report [finding-id]`

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `[finding-id]` | all | A finding ID or prefix shows just that finding. |
| `-f, --format <fmt>` | `table` | `table`, `json` (bare array, see `finding_format.md`), `sarif` (v2.1.0 with rule descriptors and repository-relative paths, for GitHub code scanning or Security Command Center), `html`, or `md` (GitHub-flavored Markdown). |
| `-o, --open` | off | Opens the HTML report in the default browser. |
| `--status <state>` | all | `OPEN`, `FIXED`, `DISMISSED`, or `REOPENED`. `VERIFIED` (set by `cm verify`) is rejected as a filter value (observed), so find verified findings in `cm report -f json` by their `status`. |
| `--severity <level>` | all | `CRITICAL`, `HIGH`, `MEDIUM`, or `LOW`. |
| `--session <id-prefix>` | all | Findings from one session. |
| `--sort <order>` | `severity` | `severity` or `time`. |
| `--patches` | off | Includes the full unified diffs of generated fixes. |
| `--artifacts` | off | Lists captured agent-generated files (logs, exploit scripts). |

### `cm report import`

| Flag | Effect |
| :--- | :--- |
| `-f, --file <path>` | Simple JSON or basic SARIF from other scanners (Semgrep, CodeQL, Snyk). See `finding_format.md` for the JSON schema. |
| `-p, --project-dir <dir>` | Resolves relative file paths against `<dir>`. |
| (no `--file`) | Interactive wizard: enter path, line, severity, and description per finding; `q` finishes. |

Imported findings start as `OPEN` and can go straight to `cm verify` or `cm fix`.

### `cm stats`

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `--since <duration>` | `168h` (7 days) | Time window, for example `24h`. |
| `--session <id>` | all | Drills into one session. |
| `--json` | off | JSON output, including model invocation counts (total, per session, and per turn). |

Reads only local session logs (no server calls). The table has one row per command type, broken down by scan mode (`cm find --diff`, `cm find --deep`, `cm find --quick`, `cm verify`, `cm fix`), with requests, polls, input, output, cached, and thought tokens, tool calls, total, cache hit rate, thinking ratio, and duration.

---

## 8. Sessions (`cm session`)

Every scan, verification, and fix is a session in `state.db`. Statuses: `RUNNING`, `WAITING_FOR_TOOL`, `COMPLETED`, `FAILED`, `CANCELLED`, and `INCOMPLETE` (a multi-file scan where a file job failed). The server keeps session data for up to 7 days.

| Command | Effect |
| :--- | :--- |
| `cm session list` | Lists sessions with type, status, target, creation time, and whether they can be resumed. |
| `cm session resume <id>` | Reconnects to a running or waiting session (for example after `Ctrl+C` or a network drop) and continues from the latest checkpoint. `-y` also accepts resuming with a backend or location that differs from the current settings. |
| `cm session cancel <id>` | Stops a running session and its server-side compute (ID prefixes are accepted). |

---

## 9. Health, Init, and Maintenance

### `cm health`
Side-effect-free preflight check: no repository access, no disk writes, no model quota or billing, and no `cm init` needed. It runs four layers in order and stops at the first failure.

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `--json` | off | One JSON object: `status`, `exit_code`, `backend`, `endpoint`, `location`, `project_id`, `agent_id`, `duration_ms`, `layers` (each with `layer`, `status`, `detail` or `error`), plus `warnings` and `error` when present. |
| `--strict` | off | Treats warnings, such as skipped project-level IAM checks, as exit code `40`. |
| `--timeout <duration>` | `30s` | Overall timeout for the probe. |

Exit codes: `0` healthy, `10` credentials (no valid token, or `401`), `20` config (`config.yaml`, `--team-id`, `CM_TEAM_ID`, backend, or KMS key), `30` reachability (DNS, TLS, proxy, VPC Service Controls), `40` authorization (for example missing `roles/aiplatform.user`), `50` timeout. For service accounts on the Task API, set `CM_TASK_AGENT_ID`.

### `cm init` and `cm init --verify`
* `cm init` creates the CodeMender home (`$CM_HOME`, else `~/.codemender`) with `config.yaml`, `logs/`, `backups/`, and `patches/`; `state.db` appears on first use. Through `cm_exec.sh`, never with `-y`.
* `cm init --verify` changes nothing and checks the workspace directory, config file, config parsing, server, server connectivity (skipped on the default transport), build command, VCS type, and state database (observed). It reports a failure when no config exists yet, and it doesn't flag unknown config keys: use `cm_config_check.sh` for that.

### `cm clean`
Purges `state.db`, the HTML reports under `reports/`, and the `.bak` patch backups. Local only, and it erases the findings history.

### `cm update`
Downloads and installs the latest release **immediately, without prompting**, after checking the binary's SHA-256 against the release manifest (the version string isn't compared). **Explicit user consent required** before running it. Separately, interactive runs check for updates at most once every 24 hours and ask first; `-y` and non-interactive runs skip that check. Use `sudo cm update` when the binary lives in a root-owned directory.

### `cm completion <shell>`
Prints a shell completion script.

---

## 10. Models

| Model | `--model` value | Notes |
| :--- | :--- | :--- |
| Gemini 3.8 Flash | `gemini-3.8-flash` | Default. |
| Gemini 4 Argon | `gemini-4-argon` | Deeper reasoning. Built-in cyber safety may block exploit generation or verification: a safety block retries on `gemini-3.8-flash-cyber`, then falls back to `gemini-3.8-flash` without cyber access. `--no-model-fallback` turns the retries off. |
| Gemini 3.8 Flash Cyber | `gemini-3.8-flash-cyber` | Allowlisted customers only (Fairwind Program). |
| Gemini 4 Argon Cyber Permissive | `gemini-4-argon-cyber-permissive` | Allowlisted customers only (Fairwind Program). |
| Gemini 3.7 / 3.6 / 3.5 Flash | `gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash` | Older models. |
| Gemini 3.1 Pro Preview | `gemini-3.1-pro-preview` | Preview. |

`cm find`, `cm verify`, and `cm fix` accept `--model`. The config docs also list a `model:` key; the plugin passes `--model` on the command line instead, so the model choice is explicit in every run.

---

## 11. Environment Variables

| Variable | Effect |
| :--- | :--- |
| `GOOGLE_CLOUD_PROJECT` | Project for CodeMender calls. Without it, cm uses the ADC project, then the gcloud default project. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Credentials file (else the ADC file from `gcloud auth application-default login`). |
| `CM_HOME` | CodeMender home directory (config, state, logs); `cm_exec.sh` sets it to `.codemender/` in the repository. |
| `CM_TEAM_ID` | Same as `--team-id`. |
| `CM_TELEMETRY_OPT_OUT` | `1` or `true` turns off the anonymous CLI telemetry. |
| `CM_DISABLE_MODEL_FALLBACK` | `true` is the same as `--no-model-fallback`. |
| `CMOC_FIND_ENABLE_BASH` | `true` is the same as `cm find --enable-bash`. |
| `CMOC_DEEP_MAX_TURNS` | Default for `--deep-max-turns` (`0` means unlimited). |
| `CM_TASK_AGENT_ID` | Agent ID for service accounts on the Task API, so `cm health` checks access with `TaskService.ListTasks`. |

Don't set other `CM_*` variables: only the ones above are documented.

Inside the sandbox, `TMPDIR` points to a temporary directory under the session's artifacts directory.

---

## 12. Files and Directories

In the CodeMender home (`$CM_HOME`; `.codemender/` in the repository with `cm_exec.sh`):

| Path | Contents |
| :--- | :--- |
| `config.yaml` | Configuration (`config_schema.md`). |
| `state.db` | Local SQLite database of sessions and findings, read by `cm report` and `cm session list`. |
| `logs/` | One debug log per session (`<timestamp>_<session-id>.log`, or `_pending.log` before a session exists). |
| `artifacts/<session-id>/` | Files the agent writes during a session; always writable for the agent, even with the sandbox on. |
| `patches/`, `backups/` | Generated patches and pre-patch backups. |
| `reports/` | HTML reports (removed by `cm clean`). |
| `audit.log` | Log of tool calls. |

In the repository: `.cm_project` (project marker; keep it out of commits), `.exploit/` (verification artifacts), and the plugin's `.codemender/last-diff-scan.json`, `.meta`, `.log`, and `remediate-scan.json`.

---

## 13. Runtime Limits (0.16.0)

* **Agent shell commands** (`run_command`, used by `verify`, `fix`, and `find --enable-bash`): 120 seconds by default, 300 seconds at most.
* **File reads**: at most 256 KiB per turn, with pagination for larger files.
* **Diff scans**: each file job times out after `--diff-job-timeout` (10 minutes, scaled up for large files).
* **Sandbox**: writes outside the allowed directories go to a temporary in-memory filesystem; the host `/tmp` is always blocked (even if listed in `project_paths`); outbound network is blocked unless `sandbox.network.profile: permissive-open`. Linux uses namespaces and seccomp, macOS uses `sandbox-exec` (Seatbelt), and Windows uses AppContainer (experimental).
* **Session retention**: up to 7 days on the server, so `cm session resume` works within that window.

---

## 14. Exit Codes

| Command | Codes |
| :--- | :--- |
| `cm find` | `0` no blocking findings; `1` blocking findings (per `--fail-on`) **or** an error. Check whether `--output` was written. |
| `cm health` | `0`, `10`, `20`, `30`, `40`, `50` (Section 9). |
| `cm fix` | `0` also when it made no edits. |
| `cm_diff_scan.sh` | `0` clean, `1` blocking findings, `2` error or INCOMPLETE scan. |
| `cm_git_hook.sh run` | `1` blocks the commit or push; scan errors don't block unless `CM_HOOK_STRICT=1`. |

---

## 15. Messages and What To Do

| Message | Meaning and action |
| :--- | :--- |
| `Resource setup has just started. Please try again shortly.` | First use of the project: wait a few minutes and retry. |
| The CLI opens an activation page and waits | The project isn't activated for CodeMender: ask the user to finish activation (never wait in a loop). |
| `StartSession failed with HTTP 403 Forbidden` or `Permission 'aiplatform.interactions.create' denied` | Missing access: check the project, the Agent Platform API, and `roles/aiplatform.user`; run `cm health --strict`. |
| `Error: unknown flag: --diff` | The CLI predates diff mode: update it (with consent). |
| `git diff failed: exit status 128: fatal: ambiguous argument 'origin/main'` | The base ref isn't fetched: `git fetch origin` (in CI, `fetch-depth: 0`). |
| `[1/1] ❌ src/app.py: start session failed` | That file wasn't scanned (the scan is INCOMPLETE): re-run. |
| `🚨 CI Gate Failure: N blocking finding(s) match --fail-on=...` | A result, not a crash: fix the findings. |
| `Skipping the automatic update check: not an interactive terminal` | Informational in agent and CI runs. |
| `We've updated your default model to gemini-3.8-flash` | Informational; pass `--model` to choose another model. |
