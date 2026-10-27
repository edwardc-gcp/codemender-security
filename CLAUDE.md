# CLAUDE.md - CodeMender Security Plugin Guidelines

Operational instructions for Anthropic Claude Code when executing security audits and patch remediations using Google Cloud CodeMender (`cm`).

---

## Command Patterns (Stateless Executable Wrappers)

Each command invocation runs in an isolated subshell. Always invoke `cm` via [scripts/cm_exec.sh](scripts/cm_exec.sh) or [scripts/cm_remediate_loop.sh](scripts/cm_remediate_loop.sh) so `PROJECT_ROOT`, `REAL_HOME`, `GIT_CONFIG_GLOBAL`, `CLOUDSDK_CONFIG`, and `.git/info/exclude` are resolved automatically in every subshell. Replace `<plugin-root>` with the absolute path of the plugin's install directory (Claude Code and Codex expose it to hooks as `${CLAUDE_PLUGIN_ROOT}`):

```bash
# 1. Safe initialization (skips if .codemender/config.yaml exists; blocks -y)
bash "<plugin-root>/scripts/cm_exec.sh" init

# 2a. Secure Inner Loop: scan local changes (untracked source files included); exit 0 clean, 1 findings, 2 error
bash "<plugin-root>/scripts/cm_diff_scan.sh"

# 2b. Quick scan of a module, or the deep scan (default mode, slow and token-heavy) for full audits
bash "<plugin-root>/scripts/cm_exec.sh" find ./src --quick -y
bash "<plugin-root>/scripts/cm_exec.sh" find . -y

# 3. Optional Tier 1 exploit verification (minutes and many tokens per finding; never stash first, always --no-reset)
bash "<plugin-root>/scripts/cm_exec.sh" verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y

# 4. Ingest Third-Party SARIF / Simple JSON
bash "<plugin-root>/scripts/cm_exec.sh" report import -f third-party-findings.json

# 5. Atomic multi-vulnerability remediation loop (Checkpoint + Outer Build Gate + Safe Commit + Re-Scan)
bash "<plugin-root>/scripts/cm_remediate_loop.sh" -c "Apply minimal security fix preserving API behavior"

# 6. Export SARIF report
bash "<plugin-root>/scripts/cm_exec.sh" report -f sarif > codemender-results.sarif
```

---

## Operational Guardrails

1. **Checkpoint Commit Lifecycle**: `cm_remediate_loop.sh` checks `git status --porcelain` (excluding `.codemender/`, `.cm_project`, `.exploit/`, `.cache/`, `.npm/`, `.cargo/`, `.local/`, `.config/`, `*.sarif`), commits uncommitted work as a `wip(cm)` checkpoint before `cm fix` (whose workspace reset would otherwise delete or hide it), and on exit resets back to the original base so the work returns uncommitted with the fixes applied (`--keep-commits` keeps the commits instead).
2. **Tiered Build Validation & Outer Hard Gate**: Dynamically probes `pytest`, `python3 -m py_compile`, `node --check`, `go test`, or `cargo check`. If `exebox` blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`, `/usr/local`), set `build.command: "true"` in `config.yaml` and enforce `OUTER_BUILD_CMD` in the outer shell before committing.
3. **Autofix-Style Atomic Commit**: Each fix commit contains changes to files already in the repository plus new source files the fix adds; other new files (test output, logs) and CodeMender's own ignore-file edits stay out, and runtime/cache paths are ignored via `.git/info/exclude` (registered by `cm_exec.sh`). Commits use `--no-verify`, and the loop re-scans the change with `cm_diff_scan.sh` after every fix (`--strict` reverts fixes the re-scan does not confirm).
4. **Sandboxing & `--unrestricted` Warning**: `--unrestricted` disables both the filesystem sandbox AND command policy denylist (`full system access`). Require explicit per-invocation human confirmation. Never run `install_cm.sh` without explicit user permission.
5. **Triage Integrity**: When a dynamic PoC exploit fails during `cm verify`, retain the finding as `OPEN / UNCONFIRMED`. Never classify a failed PoC as a false positive without manual source verification.
6. **Zero Data-Loss Init**: Never pass `-y` to `cm init`.
