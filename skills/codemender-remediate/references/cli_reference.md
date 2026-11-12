# CodeMender CLI Command Reference (cm 0.21.0)

Every public `cm` command, flag, environment variable, and runtime limit of **CodeMender CLI 0.21.0**, with notes where earlier releases (0.16.0 through 0.20.0) differ. Sources: the `--help` output, the `cm init` template, the public CodeMender docs and release notes, and test runs of the public CLI (marked "observed"). Nothing here comes from internal or undocumented sources. Print the installed version with `cm --version` (there is no `cm version` subcommand).

Examples show bare `cm` for readability. In an agent session, run every stateful subcommand through `cm_exec.sh` (Section 1). For `config.yaml` keys, see `config_schema.md`.

**Contents**: 1. Stateless invocation · 2. Global flags and safety boundaries · 3. `cm find` · 4. Diff scans · 5. `cm verify` · 6. `cm fix`, `cm build`, `cm vcs` · 7. Reporting · 8. Sessions · 9. Health, init, support, and maintenance · 10. Models · 11. Environment variables · 12. Files and directories · 13. Runtime limits and sandbox · 14. Exit codes · 15. Messages and what to do

---

## 1. Stateless Invocation (`cm_exec.sh`)

Run the stateful subcommands (`find`, `verify`, `fix`, `init`, `report import`, `vcs`, `build`) only through the bundled wrapper:

```bash
bash "<skill-dir>/scripts/cm_exec.sh" <subcommand> [args...]
```

On every call, the wrapper:
* Sets `HOME` and `CM_HOME` to the repository (`${PROJECT_ROOT}/.codemender`), so each repository keeps its own config, command policy, `state.db`, and logs, and concurrent projects never share `~/.codemender`.
* Forwards the real `~/.gitconfig`, the gcloud config, `GOOGLE_APPLICATION_CREDENTIALS` (the variable when set, else the ADC file), and `GOOGLE_CLOUD_PROJECT` (else the gcloud default project).
* Adds `.codemender/`, `.cm_project`, `.exploit/`, toolchain caches, and the plugin's SARIF files to `.git/info/exclude`, so a `git clean -fd` inside `cm fix` and a later `git add -A` never touch them.
* Refuses `-y`/`--yes` on `cm init`, and skips `cm init` when `.codemender/config.yaml` already exists (`cm init --verify` always runs, because it only reads).
* Adds `--compact` to `find`, `verify`, and `fix` (unless `--compact` or `-v` is passed), and `--bypass-warning` to `verify` and `fix`.

The other bundled scripts accept extra `cm` flags after `--`: `cm_diff_scan.sh ... -- <cm find flags>` and `cm_remediate_loop.sh ... -- <cm fix flags>`. On cm 0.17.0 and later, `cm_remediate_loop.sh` also passes `--no-reset` to every `cm fix` call. `cm_diff_scan.sh` has its own `--dry-run` (0.18.0) and refuses `--dry-run` and `--validate` after `--`; its `--depth` becomes `--diff-depth` only up to cm 0.17.0. On cm 0.21.0 and later, `cm_remediate_loop.sh` runs `build.command` once through `cm build` before the first fix (no model tokens) and stops with exit `2` when the build fails in the sandbox, because `cm fix` couldn't validate a patch there (`--no-build-preflight` skips the check).

---

## 2. Global Flags and Safety Boundaries

Subcommand `--help` output doesn't list these, but every command accepts them, including `cm session resume`.

| Flag | Effect |
| :--- | :--- |
| `-y, --yes` | Approves all command and file-write prompts for one run, whatever `config.yaml` says, and skips the automatic update check. Required for non-interactive runs. |
| `--bypass-warning` | Skips the warning that the agent can modify files and run commands on your system; `-y` doesn't skip it. A non-interactive run that shows the warning without this flag fails with `warning not acknowledged`. `cm find` skips the warning when the sandbox is on with the default `permissive-closed` network profile. |
| `--sandbox` | Runs agent shell commands inside the OS-level sandbox (`exebox`), on by default; since 0.21.0 it also covers `build.command` in `cm build` and `cm fix`. `--sandbox=false` turns it off, including network isolation; since 0.17.0 the path boundary and the command policy still apply. **Explicit per-invocation user consent required.** |
| `--allow-all-paths` | 0.17.0: turns off the workspace path boundary (`allowedRoots`), so agent tools can reach paths outside the project root and `project_paths` (with `--sandbox=false`, also host paths that the sandbox doesn't mount). **Explicit per-invocation user consent required.** |
| `--allow-all-commands` | 0.17.0: turns off the `command_policy.yaml` blocklist for one run. **Explicit per-invocation user consent required.** |
| `--plain` | 0.17.0: ASCII-only output without emoji, Unicode glyphs, or terminal colors (or `CM_PLAIN=true`, or `output.plain: true`; `TERM=dumb` also turns it on). `json` and `sarif` reports and code diffs don't change. `--plain=false` overrides the variable and the config. |
| `--compact` | Rolling status line (`Tokens: 40k in / 12k out / 60k total`) that updates in place, for `find`, `fix`, `verify`, and `session resume`. |
| `-v, --verbose` | Verbose debug output (session logs always include debug lines). |
| `--no-model-fallback` | Uses only the selected model instead of retrying `gemini-4-argon` or `gemini-4-carbon` safety blocks on fallback models (or `CM_DISABLE_MODEL_FALLBACK=true`). |
| `--team-id <id>` | Telemetry team identifier sent as the `X-CodeMender-Team-Id` header (or `$CM_TEAM_ID`, or `team_id` in `config.yaml`); at most 63 characters from `[A-Za-z0-9._-]`. `cm stats` JSON output attributes usage to it. |
| `--version` | Prints the CLI version. |
| `--notices` | Prints the third-party license notices. |
| `-h, --help` | Help for any command. |

**`--unrestricted` is gone**: cm 0.17.0 removed it (`Error: unknown flag: --unrestricted`, observed). In 0.16.0 it turned off the sandbox, the path boundary, and the command policy at once; in 0.17.0 each boundary has its own flag above. The plugin's guard asks the user before any of them, including `--unrestricted` for older CLIs.

### Confirmation prompts (0.17.0 docs)
CodeMender asks before it runs a shell command (`tools.confirm_commands`) and before it writes a file (`tools.confirm_writes`); both default to `true`. In order of precedence, these turn the prompts off:
1. `-y` / `--yes` for one run.
2. `execution.interactive_mode: false` in `config.yaml`, for every run.
3. `tools.confirm_commands: false` or `tools.confirm_writes: false`, independently.

When none applies and no one can answer (for example in CI without a terminal), CodeMender doesn't run the command or write the file. With the sandbox on and the default `permissive-closed` network profile, `cm find` mounts the workspace read-only and skips command prompts automatically.

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
| `--model <name>` | `gemini-3.8-flash` | all | You need deeper reasoning (`gemini-4-argon`, or `gemini-4-carbon` in Preview) or a cyber model you have access to (Section 10). |
| `--include-hidden` | off | all | Dot-prefixed directories and files matter, such as `.github/workflows` (or `scan.include_hidden: true`). Add the file extensions too. |
| `--format <fmt>` | `table` | all | `json` for scripts, `sarif` (SARIF v2.1.0) for code scanning. |
| `--output <file>` | stdout | all | The report should go to a file (written for every mode since 0.12.0). |
| `--dry-run` | off | all | 0.18.0: you want to see the detected architecture and the candidate scan scope first, at no cost: no scan session, 0 tokens, exit `0` (observed). `--output` then gets a JSON preview object, not findings. For a diff scope, use `cm_diff_scan.sh --dry-run`. Can't be combined with `--validate`. |
| `--validate` | off | all | 0.18.0: a person at a terminal wants to confirm or refine the detected architecture and security context before the scan. Interactive, so not for agent runs (`cm_diff_scan.sh` refuses it). Can't be combined with `--dry-run`. |
| `-y, --yes` | off | all | Always in agent and CI runs. |
| `--deep` | (default mode) | deep | Only for backward compatibility. |
| `--deep-workers <n>` | `8` | deep | Lower it (1 to 16) on small machines or quota limits; raise it for large repositories. |
| `--deep-max-turns <n>` | `5` | deep | Lower it to cut cost; raise it for complex files (or `CMOC_DEEP_MAX_TURNS`; `0` means unlimited). Since 0.20.0 the default is higher when only one file is scanned. |
| `--enable-bash` | off | deep | A deep-scan worker needs shell commands (sandboxed) to understand the code, for example generated sources; uses more turns (or `CMOC_FIND_ENABLE_BASH=true`). Quick and diff scans always have shell commands. |
| `--quick` | off | quick | You want a fast single-session look. |
| `--diff[=<ref>]` | `HEAD` | diff | Scanning changes against `<ref>` (Section 4). |
| `--staged` | off | diff | Only the staged changes should be scanned (pre-commit). |
| `--diff-depth <n>` | `1` | diff | **Removed in 0.18.0** (`Error: unknown flag: --diff-depth`, observed), where diff scans always resolve 1 hop. Up to 0.17.0: a change alters a contract or signature used farther away (impact depth in hops). |
| `--diff-workers <n>` | `4` | diff | Many files changed (1 to 16 concurrent file jobs). |
| `--diff-max-neighbors <n>` | `10` | diff | A widely used function changed and more callers should be inspected. |
| `--diff-job-timeout <duration>` | `10m` | diff | Large files time out (the scan becomes INCOMPLETE); the timeout already scales for large files. |
| `--fail-on <severities>` | `CRITICAL,HIGH` | diff | Setting the gate policy; `--fail-on ""` reports without failing. |
| `--fail-on-truncation` | off | diff | A CI gate must fail when dependent-file discovery hits `--diff-max-neighbors`, instead of passing with partial coverage. |

### File discovery (0.16.0 and later)
* Scans files whose extensions are in `scan.extensions.include` (28 by default), plus extensionless scripts with a `python`, `node`, `ruby`, or `php` shebang.
* Skips `scan.extensions.exclude` suffixes, `scan.exclude_dirs` (a leading `/` matches only at the scan root, so nested `build/`, `target/`, `obj/`, and `bin/` source directories are scanned), dot-prefixed paths unless `--include-hidden`, and files larger than `scan.max_file_size_kb`.
* Also scans production code under `spec/`, `locale/`, and `i18n/`.
* Diff mode picks changed tracked files even when their extension isn't listed (observed: a `.gitignore` edited by `cm verify`, and a changed `package.json`, were scanned).

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

How to read the results (observed with cm 0.16.0 and 0.17.0):
* **Untracked files are not scan targets.** A brand-new file is seen only indirectly, if at all, through a changed file that uses it. Register new files with `git add -N <file>` (intent-to-add) before scanning. `cm_diff_scan.sh` does this automatically and undoes it afterwards.
* **Legacy isolation**: pre-existing issues in untouched code get a `[LEGACY / UNTOUCHED]` title prefix and never trigger `--fail-on`.
* **Exit codes**: `0` means no blocking findings, including when nothing changed (it returns in about a second, without model calls). `1` means blocking findings **or** another error, such as an unknown flag (for example `--diff-depth` since 0.18.0) or ref. Since 0.17.0, setup failures exit with the `cm health` codes instead: `10` credentials, `20` config (observed for an invalid `config.yaml`), `30` reachability, `40` authorization, `50` timeout. Tell findings from errors by whether the `--output` file was written.
* **INCOMPLETE scans**: a file job that fails (`[1/2] ❌ app.py: start session failed`) leaves the summary at `N succeeded, M failed` and the session INCOMPLETE, yet the exit code can still be `0`. Treat that as unscanned code and re-run; `cm_diff_scan.sh` exits `2` in this case.
* **Unreadable directories** (0.20.0, release notes): a scan now fails with a permission error when it can't read a directory. Earlier releases could report zero findings instead, which looked like a clean result, so gate with 0.20.0 or later.
* **Sandbox violations** (0.17.0): the output can include `🔒 Sandbox violations detected during session:` followed by `sandbox: denied read ...` lines. They list reads that the sandbox blocked outside the allowed directories; the scan result is still valid.
* **Impact depth** (0.18.0): diff scans resolve 1-hop impact (callers, importers, and callees of the changed symbols); `--diff-depth`, which went deeper up to 0.17.0, is gone. For more 1-hop neighbors, raise `--diff-max-neighbors`; when partial coverage must fail, add `--fail-on-truncation`; for callers farther away, deep-scan their directories.
* **Dry run** (0.18.0, observed): `--dry-run` prints the same scope header (modified files, modified symbols, and 1-hop neighbors) plus a codebase architecture and scope summary, uses no tokens, and exits `0`. Its `--output` file is a JSON object (`project_root`, `languages`, `frameworks`, `auth_containers`, `entrypoints`, `route_files`, `total_files`, `candidate_files`, `pruned_files`, `prune_reasons`), not findings, so never read it as a scan result.
* **Report**: `--format json` writes a top-level JSON array of findings (`[]` when clean) with absolute `file_path` values. See `finding_format.md` in the `codemender-audit` skill.
* **State**: diff scans don't change the statuses in `state.db`. After the code is fixed and a re-scan is clean, `cm report` still lists the old findings (for example as `OPEN` or `VERIFIED`). Treat the latest diff report as the source of truth, and use its `--format sarif --output` file for a current-state SARIF.
* **Cost**: in a small test repository, each diff scan took about 1.5 to 9 minutes (files are scanned in parallel, so the slowest file sets the pace) and 70k to 180k tokens; for a 3-file change in OWASP Juice Shop (plus 3 affected neighbors), about 5 to 6 minutes and 460k to 525k tokens. One `cm verify` took about 1.4M tokens and one `cm fix` 1.9M to 3.2M, mostly cached (cm 0.16.0).

The bundled wrapper returns `0` (clean, or a completed `--dry-run`), `1` (blocking findings), or `2` (tool, usage, or environment error, or an INCOMPLETE scan, with a hint per setup exit code) and writes `.codemender/last-diff-scan.json`:

```bash
bash "<skill-dir>/scripts/cm_diff_scan.sh"                  # auto: the working tree with untracked files, or only the staged changes
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope staged   # pre-commit
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope branch   # against the upstream, or --base origin/main
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope last-commit
bash "<skill-dir>/scripts/cm_diff_scan.sh" --dry-run        # cm 0.18.0+: preview the scope, 0 tokens, never a result
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
| `--model <name>` | `gemini-3.8-flash` | Model for the verification agent. The docs say `cm verify` works best with a cyber model, if the project has one through the Fairwind Program (Section 10). |
| `--no-reset` | off | Suppresses all workspace resets. **Always pass it**: with it, cm leaves uncommitted and untracked code untouched (observed with 0.16.0). |
| `--skip-exploit-verification` | off | Marks high-confidence findings VERIFIED without re-running the exploit after the agent finishes (the agent still writes and runs one). |
| `-y, --yes` | off | Skips the prompts for tool actions and PoC execution (which stay sandboxed unless you also pass `--sandbox=false`). |

| Command | Purpose |
| :--- | :--- |
| `cm verify <id> --skip-exploit-verification --no-reset -y` | **Tier 1**: the agent still writes and runs a proof-of-concept (PoC) exploit; only the final re-run is skipped for high-confidence findings. |
| `cm verify <id> --no-reset -y` | **Tier 2**: also re-runs the exploit script after verification. |

* Verification sets the status, for example to `VERIFIED` or `DISMISSED`. Since 0.17.0, an unexploitable verdict also updates the status instead of leaving the finding `OPEN` (release notes). Running `cm verify` again on a `DISMISSED` finding re-examines it and can restore it.
* The `--architecture=3-1` example in `cm verify --help` is stale: cm 0.16.0 through 0.21.0 reject it as an unknown flag (observed).
* It finds code that moved since `cm find` and updates the finding's location.
* Since 0.16.0 the agent writes its files only to `.exploit/` inside the project root; cm itself also appends `.exploit/` to the tracked `.gitignore`.
* Since 0.21.0, the output of a proof of concept that fails to run (stdout and stderr) is kept, to help diagnose build failures, timeouts, and setup problems (release notes).
* Cost: in a small test repository, one Tier 1 run took about 9 minutes and 1.4M tokens. Skip it in the inner loop, where a clean diff re-scan confirms a fix.

> [!IMPORTANT]
> **Exploit Verification Triage**: If an exploit script fails or times out (`EXPLOIT_FAILED`), do NOT classify the finding as a "False Positive". Dynamic exploits frequently fail because the sandbox blocks local TCP sockets, non-system binary paths, credential directories, or secret-like environment variables. Treat such findings as `UNCONFIRMED` unless there is concrete sanitizer or unreachability proof, even when cm records the verdict as `DISMISSED`.

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
| `--model <name>` | `gemini-3.8-flash` | A stronger model (`gemini-4-argon`, or `gemini-4-carbon` in Preview) for complex patches. |
| `--no-cache` | off | Ignores cached patches and runs a fresh session, for example after a failed or unwanted patch. |
| `--no-reset` | off | 0.17.0: skips the workspace reset before fixing. On git, model-fallback retries undo only the failed attempt's edits and keep pre-existing uncommitted and untracked files. `cm_remediate_loop.sh` passes it on 0.17.0 and later. |
| `--export <session-id>` | none | **Not implemented in 0.16.0 through 0.21.0** (observed): it only prints `Exporting patch from session ... (not yet implemented)` and exits `0`. See generated patches with `cm report --patches` instead. |
| `-y, --yes` | off | Auto-approves file writes and command prompts (otherwise each one prompts, unless turned off in `config.yaml`). |

How it validates a patch: it generates a candidate, applies it to a sandboxed copy, runs `build.command`, re-runs the verified PoC, and then applies the patch to your workspace. Since 0.21.0, with the sandbox on (the default), `build.command` runs inside the sandbox (release notes), with the limits in Section 13; `cm fix` then refreshes the stored patch diff, and when the sandbox fails mid-run it retries the patch generation in a fresh one. 0.20.0 fixed patch application on large repositories and with mixed LF and CRLF line endings. Since 0.12.0 it won't modify CI/CD pipelines, static analysis configs, build definitions, or repository configuration files outside the finding's scope; since 0.17.0 the agent gets the finding's exact line range. Through `cm_remediate_loop.sh`, pass these flags after `--` (for example `-- --model gemini-4-argon --no-cache`).

> [!CAUTION]
> Without `--no-reset` (always in 0.16.0), `cm fix` runs `git checkout HEAD -- . && git clean -fd` in its workspace before patching (observed with 0.16.0). On 0.17.0, pass `--no-reset`; on 0.16.0, **commit uncommitted work first**. `cm_remediate_loop.sh` does both: it creates a `wip(cm)` checkpoint commit and restores the working tree afterwards. Don't use `git stash` for this. Also observed with 0.16.0:
> * Its workspace is the finding's directory (for example `app/`), not necessarily the repository root, and `build.command` runs from there. Anchor the command to the root: `cd "$(git rev-parse --show-toplevel)" && make test`.
> * When validation fails, the unvalidated patch stays in the working tree. Revert it.
> * It may create `<dir>/.gitignore` (headed `# CodeMender enforced ignores`) and copy `.exploit/` into its workspace. Don't commit them.
> * It exits `0` when it makes no edits, so check `git status` for changes.

### `cm build [path] --force`
Runs `build.command` with `[path]` (default: the current directory) as its working directory; `--force` skips the confirmation. Since 0.21.0 it runs **inside the sandbox** when the sandbox is on, like the build validation in `cm fix` (release notes; observed: writes outside the repository fail with `Read-only file system`, the network is unreachable, and blocked operations are listed after `🔒 Sandbox violations detected during command:`). A passing `cm build` is therefore a check without model tokens that `cm fix` can validate its patches, and `cm_remediate_loop.sh` runs it before the first fix. It exits `1` with `❌ Build failed.` and `Error: build command failed: exit status N`, exits `0` with `⚠️ No build command configured.` when `build.command` is empty, and exits `1` before `cm init` (observed). Up to 0.20.0 it ran **outside** the sandbox (observed with 0.16.0: on Linux it could write outside the repository), so a pass didn't prove that the validation inside `cm fix` would pass.

### `cm vcs <subcommand>`
| Subcommand | Effect |
| :--- | :--- |
| `cm vcs status` | Lists the files the agent modified or created. |
| `cm vcs diff` | Shows the changes since the last clean state. Since 0.21.0 the git command is `git diff --no-ext-diff --no-textconv`, so diff drivers configured in the repository don't run (observed). |
| `cm vcs stage` | Stages all modified files for commit. |
| `cm vcs reset` | **Destructive**: discards all uncommitted changes (`git checkout HEAD -- . && git clean -fd` for git). It asks `Continue? [y/N]`; without a terminal it fails with `failed to read confirmation: EOF` (observed). Never answer that prompt for the user. |
| `cm vcs init` | Ensures a clean Git repository exists at the path, for the agent's structured-thinking workspace. |

The commands come from `vcs.type` (git and mercurial auto-populate them) or `vcs.commands` for a custom VCS.

---

## 7. Reporting (`cm report`, `cm report import`, `cm stats`)

`cm report` reads `.codemender/state.db`. It doesn't reflect fixes confirmed only by a diff re-scan (Section 4).

### `cm report [finding-id]`

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `[finding-id]` | all | A finding ID or prefix shows just that finding. |
| `-f, --format <fmt>` | `table` | `table`, `json` (bare array, see `finding_format.md`), `sarif` (v2.1.0 with rule descriptors and repository-relative paths, for GitHub code scanning or Security Command Center), `html`, or `md` (GitHub-flavored Markdown). `--plain` removes UI emoji from `table`, `md`, and `html`. |
| `-o, --open` | off | Opens the HTML report in the default browser. |
| `--status <state>` | all | 0.20.0: `OPEN`, `VERIFIED`, `EXPLOIT_FAILED`, `FIXED`, `DISMISSED`, or `REOPENED`, in any letter case. `OPEN` matches every finding that isn't `FIXED` or `DISMISSED`, so it includes verified ones (observed). Up to 0.18.0 the help lists only `OPEN`, `FIXED`, `DISMISSED`, and `REOPENED`, and `VERIFIED` is rejected (observed with 0.16.0 and 0.17.0): find verified findings in `cm report -f json` by their `status` there. |
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

Imported findings start as `OPEN` and can go straight to `cm verify` or `cm fix`. Since 0.17.0, findings without location data are imported as file-level findings instead of pointing at the first line.

### `cm stats`

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `--since <duration>` | `168h` (7 days) | Time window, for example `24h`. |
| `--session <id>` | all | Drills into one session (an ID prefix works, including multi-worker deep and diff scans). |
| `--json` | off | Indented JSON, including model invocation counts (total, per session, and per turn). |
| `--jsonl` | off | 0.17.0: one single-line JSON summary for log pipelines such as Cloud Logging. |

Reads only local session logs (no server calls). The table has one row per command type, broken down by scan mode (`cm find --diff`, `cm find --deep`, `cm find --quick`, `cm verify`, `cm fix`), with requests, polls, input, output, cached, and thought tokens, tool calls, total, cache hit rate, thinking ratio, and duration (format unchanged in 0.17.0, observed). Cached tokens are part of the input count. JSON output includes `model` (or `models`) and `team_id` (or `team_ids`) when sessions recorded them.

---

## 8. Sessions (`cm session`)

Every scan, verification, and fix is a session in `state.db`. Statuses: `RUNNING`, `WAITING_FOR_TOOL`, `COMPLETED`, `FAILED`, `CANCELLED`, and `INCOMPLETE` (a multi-file scan where a file job failed). The server keeps session data for up to 7 days.

| Command | Effect |
| :--- | :--- |
| `cm session list` | Lists sessions with type, status, target, creation time, and whether they can be resumed. |
| `cm session resume <id>` | Reconnects to a running or waiting session (for example after `Ctrl+C` or a network drop) and continues from the latest checkpoint. `-y` also accepts resuming with a backend or location that differs from the current settings. The safety-boundary flags (Section 2) apply here too. |
| `cm session cancel <id>` | Stops a running session and its server-side compute (ID prefixes are accepted); since 0.17.0 it goes to the session's original region. |

---

## 9. Health, Init, Support, and Maintenance

### `cm health`
Preflight check: it doesn't read the repository, write to disk, run a model, or use model quota, and it works without `cm init`. It runs four layers in order and stops at the first failure. With `CM_TASK_AGENT_ID` set (service accounts on the Task API), it creates one idle task on the agent (labeled `cm-health-probe=true`, with no input, so no model runs) and deletes it again; a missing agent, or one the caller may not use, fails with `40`.

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `--json` | off | One JSON object: `status`, `exit_code`, `backend`, `endpoint`, `location`, `project_id`, `agent_id`, `duration_ms`, `layers` (each with `layer`, `status`, `detail` or `error`), plus `warnings` and `error` when present. |
| `--strict` | off | Treats warnings, such as skipped project-level IAM checks, as exit code `40`. |
| `--timeout <duration>` | `30s` | Overall timeout for the probe. |

Exit codes: `0` healthy, `10` credentials (no valid token, or `401`), `20` config (`config.yaml`, `--team-id`, `CM_TEAM_ID`, backend, or KMS key), `30` reachability (DNS, TLS, proxy, VPC Service Controls), `40` authorization (for example missing `roles/aiplatform.user`), `50` timeout.

### `cm init` and `cm init --verify`
* `cm init` creates the CodeMender home (`$CM_HOME`, else `~/.codemender`) with `config.yaml`, `logs/`, `backups/`, `patches/`, and, since 0.17.0, a commented-out `command_policy.yaml` template; `state.db` appears on first use. Through `cm_exec.sh`, never with `-y`.
* `cm init --verify` changes nothing and checks the workspace directory, config file, config parsing, server, server connectivity (skipped on the default transport), build command, VCS type, and state database (observed). It reports a failure when no config exists yet or the YAML doesn't parse (for example a duplicated key), and it doesn't flag unknown config keys (observed with 0.16.0 through 0.21.0): use `cm_config_check.sh` for that.

### `cm support-bundle` (0.17.0)
Collects diagnostic data for a support case into a `.tar.gz` archive (default `./cm-support-bundle-<timestamp>.tar.gz`). Nothing is uploaded: you review the archive and attach it yourself.
* By default it leaves out source code, diffs, and tool inputs and outputs: it contains `manifest.json` (CLI version, OS, what was collected), `environment.json` (`CM_*` variables, project and proxy settings), `health.json` (the `cm health` results), `config.yaml` and the command policy, `sessions.json` (status, model, and target of the selected sessions), and `logs/sessions/` (per-turn timing, token usage, and tool call names and durations). Session data can still contain paths, `cm` command arguments, finding titles, and tool error messages.
* `--include-content` also adds findings, patches, and the CLI debug logs, which can contain source code: **ask the user first**, and have them review the archive before sharing it.
* `--session <id>` (repeatable, prefix match, includes the child sessions of deep and diff scans), `--since <duration>` (default `72h`, without `--session`), `-o, --output <path>`, `--skip-health` (no endpoint contact).
* Access tokens, API keys, private keys, authorization headers, and password fields are redacted. The archive keeps the `~/.codemender` layout, so `CM_HOME=<extracted dir> cm stats --session <id>` works on it.

### `cm clean`
Purges `state.db`, the session logs, the project marker (`.cm_project`), the HTML reports under `reports/`, and the `.bak` patch backups. Local only, and it erases the findings history. It asks for confirmation (`[y/N]`); in a non-interactive shell it fails with `failed to read confirmation: EOF` (observed). Never answer that prompt for the user.

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
| Gemini 4 Carbon | `gemini-4-carbon` | Preview in CodeMender since 0.21.0 (release notes). Built-in cyber safety like Gemini 4 Argon, with the same retries on `gemini-3.8-flash-cyber` and then `gemini-3.8-flash` (docs). |
| Gemini 3.8 Flash Cyber | `gemini-3.8-flash-cyber` | Allowlisted customers only (Fairwind Program). |
| Gemini 4 Argon Cyber Permissive | `gemini-4-argon-cyber-permissive` | Allowlisted customers only (Fairwind Program). |
| Gemini 4 Carbon for cyber | `gemini-4-carbon-cyber-permissive` | Allowlisted customers only (Fairwind Program). |
| Gemini 3.7 Flash | `gemini-3.7-flash` | Retires on January 28, 2027. |
| Gemini 3.6 Flash | `gemini-3.6-flash` | Deprecated; retires on November 19, 2026. The CLI warns when you use it, and `cm models` (0.18.0 and later) doesn't list it (observed). |
| Gemini 3.5 Flash | `gemini-3.5-flash` | Older model. |
| Gemini 3.1 Pro Preview | `gemini-3.1-pro-preview` | Preview. |

Deprecated models work until their retirement date; after that, requests that use them fail. `cm find`, `cm verify`, and `cm fix` accept `--model`. Since the 0.18.0 docs, `config.yaml` doesn't set the model: pass `--model` on the command line (the plugin always does, so the model choice is explicit in every run). `cm verify` works best with a cyber model: with access through the Fairwind Program, pass one with `--model`, for example `--model gemini-3.8-flash-cyber` (docs).

`cm models` lists the models that the CLI offers, marking the default and the allowlist-only ones (observed with 0.21.0: `gemini-3.1-pro-preview`, `gemini-3.5-flash`, `gemini-3.7-flash`, `gemini-3.8-flash (default)`, `gemini-4-argon`, `gemini-4-carbon`, `gemini-3.8-flash-cyber (allowlist only)`, `gemini-4-argon-cyber-permissive (allowlist only)`, and `gemini-4-carbon-cyber-permissive (allowlist only)`; 0.20.0 didn't list the Carbon models yet). The name given to `--model` isn't checked before a session starts (observed: `cm find --dry-run` accepts any name).

---

## 11. Environment Variables

| Variable | Effect |
| :--- | :--- |
| `GOOGLE_CLOUD_PROJECT` | Project for CodeMender calls. Without it, cm uses the ADC project, then the gcloud default project. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Credentials file (else the ADC file from `gcloud auth application-default login`). |
| `CM_HOME` | CodeMender home directory (config, command policy, state, logs); `cm_exec.sh` sets it to `.codemender/` in the repository. |
| `CM_TEAM_ID` | Same as `--team-id`. |
| `CM_PLAIN` | 0.17.0: `true` or `1` turns on plain text output, `false` or `0` turns it off (same as `--plain`). |
| `CM_TELEMETRY_OPT_OUT` | `1` or `true` turns off the CLI telemetry. Per the current setup docs, telemetry events can identify the Google Account or service account and the project, but never contain source code, file contents, file paths, prompts, findings, or patches. |
| `CM_DISABLE_MODEL_FALLBACK` | `true` is the same as `--no-model-fallback`. |
| `CMOC_FIND_ENABLE_BASH` | `true` is the same as `cm find --enable-bash`. |
| `CMOC_DEEP_MAX_TURNS` | Default for `--deep-max-turns` (`0` means unlimited). |
| `CM_TASK_AGENT_ID` | Agent ID for service accounts on the Task API; `cm health` then checks access with an idle task (Section 9). |
| `NO_COLOR` | Omits terminal color escapes. |

Don't set other `CM_*` variables: only the ones above are documented.

Inside the sandbox, `TMPDIR` points to a temporary directory under the session's artifacts directory, and environment variables that look like secrets are removed (Section 13). Since 0.21.0, sandboxed builds also get session-scoped caches that start empty (observed: `NPM_CONFIG_CACHE`, `PIP_CACHE_DIR`, `GOCACHE`, `GOMODCACHE`, `CARGO_HOME`, `GRADLE_USER_HOME`, and `PYTHONPYCACHEPREFIX` under `.codemender/tmp/cmd-<id>/`, plus `GOPROXY=off`, `GIT_EDITOR=false`, and `GIT_PAGER=cat`).

---

## 12. Files and Directories

In the CodeMender home (`$CM_HOME`; `.codemender/` in the repository with `cm_exec.sh`):

| Path | Contents |
| :--- | :--- |
| `config.yaml` | Configuration (`config_schema.md`). |
| `command_policy.yaml` | 0.17.0: command denylist for agent shell commands, with `block` (binary names, matched across pipelines, subshells, and command substitutions) and `block_patterns` (regular expressions per command segment). cm creates a commented-out template on first run. A project's `.codemender/command_policy.yaml` adds rules to the global one; with `cm_exec.sh` both are the repository's `.codemender/`. `--allow-all-commands` skips it for one run. |
| `state.db` | Local SQLite database of sessions and findings, read by `cm report` and `cm session list`. |
| `logs/` | One debug log per session (`<timestamp>_<session-id>.log`, or `_pending.log` before a session exists), plus per-session JSONL telemetry under `logs/sessions/`. |
| `artifacts/<session-id>/` | Files the agent writes during a session; always writable for the agent, even with the sandbox on. |
| `tmp/` | 0.21.0: temporary directories and caches of sandboxed builds (`tmp/cmd-<id>/`, observed). |
| `patches/`, `backups/` | Generated patches and pre-patch backups. |
| `reports/` | HTML reports (removed by `cm clean`). |
| `audit.log` | Log of tool calls. |

In the repository: `.cm_project` (project marker; keep it out of commits), `.exploit/` (verification artifacts), and the plugin's `.codemender/last-diff-scan.json`, `.meta`, `.log`, `last-diff-scan.dry-run.json` (a `--dry-run` preview, never a result), `remediate-scan.json`, and `build-preflight.log` (the output of the loop's sandbox build check).

---

## 13. Runtime Limits and Sandbox

* **Agent shell commands** (`run_command`, used by `verify`, `fix`, quick and diff scans, and `find --enable-bash` deep scans): 120 seconds by default, 300 seconds at most (release notes 0.16.0).
* **File reads**: at most 256 KiB per turn, with pagination for larger files.
* **Diff scans**: each file job times out after `--diff-job-timeout` (10 minutes, scaled up for large files).
* **Sandbox filesystem**: agent tools stay inside the allowed directories (the project root and `project_paths`); writes outside them go to a temporary in-memory filesystem, and the host `/tmp` is always blocked (even if listed in `project_paths`). During `cm find`, the workspace and allowed roots are mounted read-only, so commands can write only to the session's artifacts directory. Since 0.17.0, `.git/hooks`, `.git/config`, `.hg/hgrc`, and `.codemender` are always read-only, and agent file tools can't write to `.git`, `.hg`, or `.codemender`.
* **Sandbox credentials** (0.17.0 docs): common credential directories (`~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config/gcloud`, `~/.config/gh`, `~/.kube`, `~/.docker`, and others) are excluded, and environment variables that match secret patterns (`*_TOKEN`, `*_SECRET`, `*_KEY`, `*_PASSWORD`, `*_CREDENTIALS`, and similar) are removed before commands run. A build or exploit that needs them fails inside the sandbox.
* **Sandbox network**: outbound network is blocked unless `sandbox.network.profile: permissive-open`. Linux uses namespaces and seccomp (`exebox`), macOS uses `sandbox-exec` (Seatbelt), and Windows uses AppContainer (experimental).
* **Sandboxed builds** (0.21.0): `cm build` and the build validation in `cm fix` run `build.command` inside the sandbox (release notes). Observed with `cm build`: the repository is writable (build output such as `build/` is written), writes elsewhere fail with `Read-only file system`, the host `/tmp` isn't written, there's no network, a Node.js installed under the home directory still ran (host toolchains are mounted read-only, release notes), and reading `.npmrc` is denied (`sandbox: denied read <repo>/.npmrc`, harmless when the build needs no registry credentials). Caches start empty (Section 11), so the build must find its dependencies in the project: `node_modules/` works (observed with OWASP Juice Shop), but Go modules outside the project fail with `module lookup disabled by GOPROXY=off` even when they're in the host's module cache (observed), so vendor them (`go mod vendor`).
* **Git inside sandboxed commands** (0.21.0): the release notes say repository Git hooks are disabled and the host Git configuration is isolated during command and build runs, and `cm vcs diff` no longer runs diff drivers (observed). In `cm build`, though, the build command's own `git commit` and `git checkout` still ran the repository's `pre-commit` and `post-checkout` hooks, and the `~/.gitconfig` that `cm_exec.sh` forwards through `GIT_CONFIG_GLOBAL` (Section 1) was still read (observed). Don't rely on hooks being off inside a build.
* **Silent turns** (0.21.0, release notes): a turn that stays silent for 30 minutes is canceled, so a stalled session ends and can recover instead of hanging.
* **Session retention**: up to 7 days on the server, so `cm session resume` works within that window.

---

## 14. Exit Codes

| Command | Codes |
| :--- | :--- |
| `cm find` | `0` no blocking findings (or a completed `--dry-run`); `1` blocking findings (per `--fail-on`) **or** another error, such as an unknown flag (for example `--diff-depth` since 0.18.0). Check whether `--output` was written. Since 0.17.0, setup failures exit `10`, `20`, `30`, `40`, or `50` like `cm health` (observed: `20` for an invalid `config.yaml`). |
| `cm verify`, `cm fix` | Since 0.17.0, setup failures also have their own codes (release notes). `cm fix` exits `0` also when it made no edits. |
| `cm build` | `0` build passed, or no `build.command` configured; `1` build failed, or no CodeMender workspace yet (observed). |
| `cm health` | `0`, `10`, `20`, `30`, `40`, `50` (Section 9). |
| `cm_diff_scan.sh` | `0` clean or a completed `--dry-run`, `1` blocking findings, `2` error (including a usage error, cm's own error line for a failed run, or a report that isn't findings) or INCOMPLETE scan (with a hint for exit codes `10` to `50`). |
| `cm_remediate_loop.sh` | `0` finished (the summary lists findings that weren't fixed); `1` setup error (no commit, checkpoint, or scan); `2` `build.command` failed the sandbox preflight (cm 0.21.0 and later), before any `cm fix`. |
| `cm_git_hook.sh run` | `1` blocks the commit or push; scan errors don't block unless `CM_HOOK_STRICT=1`. |

---

## 15. Messages and What To Do

| Message | Meaning and action |
| :--- | :--- |
| `Resource setup has just started. Please try again shortly.` | First use of the project: wait a few minutes and retry. |
| The CLI opens an activation page and waits | The project isn't activated for CodeMender: ask the user to finish activation (never wait in a loop). |
| `StartSession failed with HTTP 403 Forbidden` or `Permission 'aiplatform.interactions.create' denied` | Missing access: check the project, the Agent Platform API, and `roles/aiplatform.user`; run `cm health --strict`. |
| `Error: unknown flag: --diff` | The CLI predates diff mode: update it (with consent). |
| `Error: unknown flag: --diff-depth` | cm 0.18.0 removed it: diff scans always resolve 1 hop. Drop it; raise `--diff-max-neighbors` for more callers, and deep-scan the directories of callers farther away. |
| `Error: if any flags in the group [dry-run validate] are set none of the others can be` | `--dry-run` and `--validate` (0.18.0) can't be combined: pick one. |
| `✅ Dry-run complete. No files were uploaded and 0 tokens were consumed.` | A `--dry-run` preview (0.18.0), not a scan: nothing was checked. |
| `Error: unknown flag: --unrestricted` | cm 0.17.0 removed it. Use `--sandbox=false`, `--allow-all-paths`, or `--allow-all-commands`, and only with the user's consent. |
| `Error: loading config: parsing config: yaml: ...` (exit `20`) | `config.yaml` doesn't parse (for example a duplicated key): fix it, then run `cm_config_check.sh` and `cm_exec.sh init --verify`. |
| `warning not acknowledged` | A non-interactive run without `--bypass-warning` (`cm_exec.sh` adds it for `verify` and `fix`). |
| `git diff failed: exit status 128: fatal: ambiguous argument 'origin/main'` | The base ref isn't fetched: `git fetch origin` (in CI, `fetch-depth: 0`). |
| `[1/1] ❌ src/app.py: start session failed` | That file wasn't scanned (the scan is INCOMPLETE): re-run. |
| `🚨 CI Gate Failure: N blocking finding(s) match --fail-on=...` | A result, not a crash: fix the findings. |
| `🔒 Sandbox violations detected during session:` | Informational (0.17.0): reads that the sandbox blocked outside the allowed directories. |
| `🔒 Sandbox violations detected during command:` | 0.21.0, from `cm build` and build validation: operations the sandbox blocked during the build (for example `sandbox: denied read <repo>/.npmrc`). The result line that follows decides: `✅ Build succeeded.` or `❌ Build failed.` |
| `❌ Build failed.` and `Error: build command failed: exit status N` | `build.command` failed. On 0.21.0 it ran in the sandbox: look for missing network, hidden credentials, dependencies outside the project, or writes outside it. `cm_remediate_loop.sh` stops before `cm fix` in this case. |
| `⚠️ No build command configured.` | `cm build` with an empty `build.command` (exit `0`): set one, or `"true"` to skip the build validation on purpose. |
| `module lookup disabled by GOPROXY=off` | A Go build in the 0.21.0 sandbox needs modules that aren't vendored: run `go mod vendor` (observed). |
| `⚠️ Model gemini-3.6-flash is deprecated and will be retired on 2026-11-19` | Switch to `--model gemini-3.8-flash` before the retirement date. |
| `Skipping the automatic update check: not an interactive terminal` | Informational in agent and CI runs. |
| `We've updated your default model to gemini-3.8-flash` | Informational; pass `--model` to choose another model. |
