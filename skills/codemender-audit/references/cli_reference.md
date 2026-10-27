# CodeMender CLI Command Reference (cm 0.16.0)

Checked against the `--help` output of **CodeMender CLI 0.16.0**, the public CodeMender docs, and test runs on a small repository. Print the installed version with `cm --version` (there is no `cm version` subcommand).

Examples show bare `cm` for readability. In an agent session, run every stateful subcommand through `cm_exec.sh` (Section 1).

---

## 1. Stateless Invocation (`cm_exec.sh`)

Run the stateful subcommands (`find`, `verify`, `fix`, `init`, `report import`, `vcs`, `build`) only through the bundled wrapper:

```bash
bash "<skill-dir>/scripts/cm_exec.sh" <subcommand> [args...]
```

On every call, the wrapper:
* Sets `HOME` and `CM_HOME` to the repository (`${PROJECT_ROOT}/.codemender`), so each repository keeps its own config, `state.db`, and logs, and concurrent projects never share `~/.codemender`.
* Forwards the real `~/.gitconfig`, the gcloud config, `GOOGLE_APPLICATION_CREDENTIALS` (the variable when set, else the ADC file), and `GOOGLE_CLOUD_PROJECT` (else the gcloud default project). `CM_LOCATION` defaults to `global`.
* Adds `.codemender/`, `.cm_project`, `.exploit/`, toolchain caches, and the plugin's SARIF files to `.git/info/exclude`, so the `git clean -fd` inside `cm fix` and a later `git add -A` never touch them.
* Refuses `-y`/`--yes` on `cm init`, and skips `cm init` when `.codemender/config.yaml` already exists.
* Adds `--compact` to `find`, `verify`, and `fix` (unless `--compact` or `-v` is passed), and `--bypass-warning` to `verify` and `fix`.

---

## 2. Global Flags

| Flag | Effect |
| :--- | :--- |
| `-y, --yes` | Auto-approves prompts (commands and file writes) and skips the automatic update check. Required for non-interactive runs. |
| `--bypass-warning` | Skips the warning prompt. |
| `--compact` | Compact rolling output: tool steps update in place. |
| `-v, --verbose` | Verbose debug output. |
| `--sandbox` | OS-level sandbox, on by default. `--sandbox=false` turns it off: **explicit per-invocation user consent required**. |
| `--no-model-fallback` | Uses only the selected model instead of retrying `gemini-4-argon` safety blocks on fallback models (or `CM_DISABLE_MODEL_FALLBACK=true`). |
| `--team-id <id>` | Telemetry team identifier (or `$CM_TEAM_ID`, or `team_id` in `config.yaml`). |
| `--version`, `--notices` | Print the CLI version or the third-party license notices. |

---

## 3. Scan Modes (`cm find`)

Since 0.16.0, `cm find <path>` without a mode flag runs a **deep scan**. The three modes are mutually exclusive:

| Mode | Command | Scope | Use for |
| :--- | :--- | :--- | :--- |
| Deep (default) | `cm find . -y` | Every discovered source file, audited concurrently and corroborated before reporting | Baselines, scheduled and pre-release audits, compliance evidence. Slowest and most token-heavy mode: never use it as a blocking pull request check. |
| Quick | `cm find ./src --quick -y` | One single-session scan of the target | Fast local triage of a module. Lower recall on large repositories, and may report false positives (triage them with `cm verify`). |
| Diff | `cm find . --diff -y` | Changed hunks plus the files that call or depend on them | The inner loop, pre-commit and pre-push hooks, and pull request gates (Section 4). |

Flags for every mode:

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `-c, --context <text>` | none | Extra guidance for the agent, such as architecture notes or a threat focus. |
| `--model <name>` | `gemini-3.8-flash` | Other values: `gemini-3.1-pro-preview`, `gemini-3.5-flash`, `gemini-3.6-flash`, `gemini-3.7-flash`, `gemini-4-argon`, and the allowlist-only `gemini-3.8-flash-cyber` and `gemini-4-argon-cyber-permissive`. |
| `--include-hidden` | off | Includes dot-prefixed directories and files, such as `.github/`. |
| `--enable-bash` | off | Allows the `run_command` tool during scans (or `CMOC_FIND_ENABLE_BASH=true`). |
| `--deep-workers <n>` | `8` | Deep scan concurrency (1 to 16). |
| `--deep-max-turns <n>` | `5` | Exploratory tool turns per file in a deep scan (or `CMOC_DEEP_MAX_TURNS`; `0` means unlimited). |
| `--unrestricted` | off | Turns off the filesystem sandbox: **explicit per-invocation user consent required**. |

```bash
# Quick triage of one module, with threat-model context
cm find ./src/auth/ --quick -y -c "Focus on SQL injection and auth bypass"

# Deep scan of the whole repository (confirm the cost with the user first)
cm find . -y --deep-workers=8
```

---

## 4. Diff Scans (`cm find --diff`)

| Command | Scans |
| :--- | :--- |
| `cm find . --diff -y` | Uncommitted changes to **tracked** files, compared with `HEAD`. |
| `cm find . --diff --staged -y` | Staged content only (`git diff --cached`): exactly what will be committed. |
| `cm find . --diff=origin/main -y` | The branch compared with a base ref (pull request gate). The ref must exist locally; in CI, check out with `fetch-depth: 0`. |
| `cm find . --diff=HEAD~1 -y` | The last commit. |

| Flag | Default | Effect |
| :--- | :--- | :--- |
| `--diff[=<ref>]` | `HEAD` | Turns on diff mode against `<ref>`. |
| `--staged` | off | With `--diff`, scans staged changes only. |
| `--diff-depth <n>` | `1` | Impact analysis depth (1 to 3). |
| `--diff-workers <n>` | `4` | Files scanned concurrently (1 to 16). |
| `--diff-max-neighbors <n>` | `10` | Maximum number of dependent files to inspect. |
| `--diff-job-timeout <d>` | `10m` | Per-file session timeout (scales automatically for large files). |
| `--fail-on <severities>` | `CRITICAL,HIGH` | Severities that make `cm find` exit `1`. With an empty value (`--fail-on ""`), findings don't affect the exit code. |
| `--fail-on-truncation` | off | Exits `1` when dependent-file discovery exceeds `--diff-max-neighbors`. |
| `--format <fmt>` | `table` | `table`, `json`, or `sarif` (SARIF v2.1.0). |
| `--output <file>` | stdout | Writes the report to a file. |

How to read the results (observed with cm 0.16.0):
* **Untracked files are not scan targets.** A brand-new file is seen only indirectly, if at all, through a changed file that uses it. Register new files with `git add -N <file>` (intent-to-add) before scanning. `cm_diff_scan.sh` does this automatically and undoes it afterwards.
* **Legacy isolation**: pre-existing issues in untouched code get a `[LEGACY / UNTOUCHED]` title prefix and never trigger `--fail-on`.
* **Exit codes**: `0` means no blocking findings, including when nothing changed (it returns in about a second, without model calls). `1` means blocking findings **or** an error, such as an unknown ref or failed authentication. Tell them apart by whether the `--output` file was written.
* **Report**: `--format json` writes a top-level JSON array of findings (`[]` when clean) with absolute `file_path` values. See `finding_format.md` in the `codemender-audit` skill.
* **State**: diff scans don't change the statuses in `state.db`. After the code is fixed and a re-scan is clean, `cm report` still lists the old findings (for example as `OPEN` or `VERIFIED`). Treat the latest diff report as the source of truth, and use its `--format sarif --output` file for a current-state SARIF.
* **File selection**: diff mode scans every changed tracked file, whatever `scan.extensions.include` says (for example, a `.gitignore` edited by `cm verify`).
* **Cost**: in a small test repository, each diff scan took about 1 to 6 minutes and 70k to 180k tokens, compared with about 1.4M tokens for one `cm verify` and 3.2M for one `cm fix`.

The bundled wrapper returns `0` (clean), `1` (blocking findings), or `2` (tool or environment error) and writes `.codemender/last-diff-scan.json`:

```bash
bash "<skill-dir>/scripts/cm_diff_scan.sh"                  # auto: the working tree with untracked files, or only the staged changes
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope staged   # pre-commit
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope branch   # against the upstream, or --base origin/main
bash "<skill-dir>/scripts/cm_diff_scan.sh" --scope last-commit
```

CI/CD pull request gate:

```bash
cm find . --diff=origin/main --fail-on=CRITICAL,HIGH --format=sarif --output=results.sarif -y --bypass-warning
```

---

## 5. Verification (`cm verify`)

| Command | Purpose |
| :--- | :--- |
| `cm verify <id> --skip-exploit-verification --no-reset -y` | **Tier 1**: the agent still writes and runs a proof-of-concept (PoC) exploit; only the final re-run is skipped for high-confidence findings. |
| `cm verify <id> --no-reset -y` | **Tier 2**: also re-runs the exploit script after verification. |
| `cm verify <id> --no-reset -y -c "<focus>"` | Steers the agent, for example toward one request path. |
| `cm verify <id> --unrestricted ...` | Turns off the filesystem sandbox **and** the command policy denylist (full system access). **Explicit per-invocation user consent required**; use only in isolated VMs or containers. |

* `<id>` is a full finding UUID or an unambiguous prefix, taken from `cm report` or a scan report.
* Always pass `--no-reset`. Without it, verification may reset the workspace. With it, cm 0.16.0 leaves uncommitted and untracked code untouched: it only writes `.exploit/` and appends `.exploit/` to the tracked `.gitignore`.
* Verification sets the finding status to `VERIFIED` or `DISMISSED`.
* Cost: in a small test repository, one Tier 1 run took about 9 minutes and 1.4M tokens. Skip it in the inner loop, where a clean diff re-scan confirms a fix.

> [!IMPORTANT]
> **Exploit Verification Triage**: If an exploit script fails or times out (`EXPLOIT_FAILED`), do NOT classify the finding as a "False Positive". Dynamic exploits frequently fail due to `exebox` blocking local TCP sockets or non-system binary paths. Findings must remain classified as `UNCONFIRMED / OPEN` unless explicitly marked `DISMISSED` with concrete sanitizer/unreachability proof.

### Verification artifacts (`${PROJECT_ROOT}/.exploit/`, overwritten by the next run)
* `PLAN.md`: investigation and validation checklist.
* `LOG.md`: investigation log (commands, requests, and observations).
* `REPORT.md`: executive summary, root cause analysis, fix recommendation, and reproduction steps.
* `exploit.sh`: standalone, executable PoC.
* `info.yaml`: machine-readable verdict (`vulnerability_id`, `severity`, `confidence`, `status` such as `valid`, `chained_vulnerabilities`).
* Runtime logs from the PoC, such as `server.log`.

---

## 6. Remediation (`cm fix`, `cm build`, `cm vcs`)

| Command | Purpose |
| :--- | :--- |
| `cm fix <id> -y` | Generates a patch, validates it (`build.command` and a PoC re-run), and applies it to the working tree. |
| `cm fix <id> -y -c "Use the parameterized helper in db/query.py"` | Constrains the fix. |
| `cm fix <id> -y --no-cache` | Ignores cached patches and runs a fresh session. |
| `cm fix <id> -y --model gemini-4-argon` | Uses a stronger model for complex patches. |
| `cm fix --export <session-id>` | Exports the patch from a session. |
| `cm build [path] --force` | Runs `build.command` in the given path (default: the current directory). |
| `cm vcs status`, `cm vcs diff`, `cm vcs stage` | Inspect and stage the agent's changes. |
| `cm vcs reset` | **Destructive**: discards all uncommitted changes (`git checkout HEAD -- . && git clean -fd` for git). |

> [!CAUTION]
> `cm fix` has no `--no-reset`. Observed with cm 0.16.0:
> * It runs `git checkout HEAD -- . && git clean -fd` in its workspace before patching. **Commit uncommitted work first**: `cm_remediate_loop.sh` creates a `wip(cm)` checkpoint commit and restores the working tree afterwards. Don't use `git stash` for this.
> * Its workspace is the finding's directory (for example `app/`), not necessarily the repository root, and `build.command` runs from there. Anchor the command to the root: `cd "$(git rev-parse --show-toplevel)" && make test`.
> * When validation fails, the unvalidated patch stays in the working tree. Revert it.
> * It may create `<dir>/.gitignore` (headed `# CodeMender enforced ignores`) and copy `.exploit/` into its workspace. Don't commit them.
> * It exits `0` when it makes no edits, so check `git status` for changes.
> * `cm build --force` runs `build.command` outside the sandbox (on Linux it could write outside the repository), so a passing `cm build` doesn't prove that the sandboxed validation inside `cm fix` passes.

---

## 7. Reporting (`cm report`, `cm report import`, `cm stats`)

`cm report` reads `.codemender/state.db`. It doesn't reflect fixes confirmed only by a diff re-scan (Section 4).

| Command | Purpose |
| :--- | :--- |
| `cm report` | Findings table, sorted by severity (`--sort time` for newest first). |
| `cm report -f json` | Bare JSON array of findings (see `finding_format.md`). |
| `cm report -f sarif > results.sarif` | SARIF v2.1.0 with rule descriptors and repository-relative paths, for GitHub code scanning or Security Command Center. |
| `cm report -f html -o` / `cm report -f md` | HTML dashboard (`-o` opens it in a browser) or Markdown. |
| `cm report --status OPEN --severity HIGH` | Filters by status (`OPEN`, `FIXED`, `DISMISSED`, `REOPENED`) and severity (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`). |
| `cm report --session <id-prefix>` | Findings from one session. |
| `cm report --patches` / `cm report --artifacts` | Generated patches, or captured agent-generated files. |
| `cm report import -f findings.json` | Imports Simple JSON or basic SARIF from other scanners (Semgrep, CodeQL). `-p <dir>` resolves relative paths; without `-f`, import is interactive. |
| `cm stats` | Local token usage for the last 7 days (`--since 24h` to change), broken down by command type (for example `cm find --diff`, `cm verify`, `cm fix`): requests, input, output, cached and thought tokens, cache hit rate, and duration. Makes no server calls. |
| `cm stats --json` / `cm stats --session <id>` | JSON output, or one session in detail. |

---

## 8. Health, Sessions & Maintenance

| Command | Purpose |
| :--- | :--- |
| `cm health --strict --json` | Side-effect-free preflight check: no repository access, no disk writes, no model quota or billing, and no `cm init` needed. Exit codes: `0` healthy, `10` credentials, `20` config, `30` endpoint reachability, `40` authorization (with `--strict`, warnings such as skipped project IAM checks also return `40`), `50` timeout (`--timeout`, default `30s`). For service accounts, set `CM_TASK_AGENT_ID`. |
| `cm init` | Creates `.codemender/` (config, logs, patch storage; `state.db` is created on first use). Through `cm_exec.sh`, never with `-y`. |
| `cm init --verify` | Checks the setup without modifying anything. Reports a failure when no config exists yet: use `cm health` to check credentials. |
| `cm session list` | Lists the sessions in the local state database. |
| `cm session resume <id>` | Reconnects to a running or waiting session, for example after `Ctrl+C`. |
| `cm session cancel <id>` | Cancels a running session (ID prefixes are accepted). |
| `cm clean` | Purges `state.db`, the HTML reports, and the `.bak` patch backups. Local only, and erases the findings history. |
| `cm update` | Downloads and installs the latest release **immediately, without prompting**, verified against the SHA-256 in the release manifest. **Explicit user consent required** before running it. Interactive runs also check for updates once a day; `-y` and non-interactive runs skip that check. |
