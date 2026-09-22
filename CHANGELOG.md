# Changelog

All notable changes to the `codemender-security` community plugin are documented in this file.

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
