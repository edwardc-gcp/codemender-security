# CLAUDE.md - CodeMender Security Plugin Guidelines

Operational instructions for Anthropic Claude Code when executing security audits and patch remediations using Google Cloud CodeMender (`cm`).

---

## Command Patterns (Stateless Executable Wrappers)

Each command invocation runs in an isolated subshell. Always invoke `cm` via [scripts/cm_exec.sh](scripts/cm_exec.sh) or [scripts/cm_remediate_loop.sh](scripts/cm_remediate_loop.sh) so `PROJECT_ROOT`, `REAL_HOME`, `GIT_CONFIG_GLOBAL`, `CLOUDSDK_CONFIG`, and `.git/info/exclude` are resolved automatically in every subshell:

```bash
PLUGIN_DIR="${CM_PLUGIN_DIR:-${HOME}/.claude/plugins/codemender-security}"
[ -d "${PLUGIN_DIR}" ] || PLUGIN_DIR="${HOME}/.gemini/config/plugins/codemender-security"

# 1. Safe initialization (skips if .codemender/config.yaml exists; blocks -y)
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" init

# 2. Targeted module or repository AST scan
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" find . -y

# 3. Tier 1 Fast Semantic Verification (15-25s default)
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y

# 4. Ingest Third-Party SARIF / Simple JSON
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report import -f third-party-findings.json

# 5. Atomic multi-vulnerability remediation loop (Tracked Stash + Outer Build Gate + Pathspec Commit + AST Reconcile)
bash "${PLUGIN_DIR}/scripts/cm_remediate_loop.sh" -c "Apply minimal security fix preserving API behavior"

# 6. Export SARIF report
bash "${PLUGIN_DIR}/scripts/cm_exec.sh" report -f sarif > codemender-results.sarif
```

---

## Operational Guardrails

1. **Non-Destructive Tracked Stash Lifecycle**: `cm_remediate_loop.sh` checks `git status --porcelain` (excluding `.codemender/`, `.cm_project`, `.exploit/`, `.cache/`, `.npm/`, `.cargo/`, `.local/`, `.config/`, `*.sarif`), records `CM_STASH_MSG="cm-pre-fix-backup-$(date +%s)"`, and restores the exact `STASH_REF` via `git stash pop "${STASH_REF}"` on exit—never popping unrelated user stashes.
2. **Tiered Build Validation & Outer Hard Gate**: Dynamically probes `pytest`, `python3 -m py_compile`, `node --check`, `go test`, or `cargo check`. If `exebox` blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`, `/usr/local`), set `build.command: "true"` in `config.yaml` and enforce `OUTER_BUILD_CMD` in the outer shell before committing.
3. **Pathspec-Protected Atomic Commit (`git add -A`)**: Stages modified and newly created helper files while excluding `$HOME` cache artifacts (`git add -A -- ':!.codemender' ':!.cm_project' ':!.exploit' ':!.cache' ':!.npm' ':!.cargo' ':!.local' ':!.config' ':!*.sarif'`), and runs `cm find . -y` inside the loop after every commit.
4. **Sandboxing & `--unrestricted` Warning**: `--unrestricted` disables both the filesystem sandbox AND command policy denylist (`full system access`). Require explicit per-invocation human confirmation. Never run `install_cm.sh` without explicit user permission.
5. **Triage Integrity**: When a dynamic PoC exploit fails during `cm verify`, retain the finding as `OPEN / UNCONFIRMED`. Never classify a failed PoC as a false positive without manual source verification.
6. **Zero Data-Loss Init**: Never pass `-y` to `cm init`.
