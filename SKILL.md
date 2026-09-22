---
name: codemender-security
description: Autonomous security auditing, vulnerability verification, exploit PoC validation, and context-aware patch remediation using Google Cloud CodeMender (cm) on Gemini Enterprise Agent Platform. ACTIVATE this skill whenever scanning codebases, reviewing PR diffs, verifying vulnerabilities without false positives, or safely remediating security flaws with zero regressions.
---

# Google Cloud CodeMender (`cm`) Security Skill

This skill orchestrates the **Google Cloud CodeMender (`cm`) CLI** (`v0.8.0+`) across two specialized sub-workflows:
- **[`codemender-audit`](skills/codemender-audit/SKILL.md)**: AST discovery (`cm find`), surgical `config.yaml` tuning, and 2-Tier verification (`cm verify`).
- **[`codemender-remediate`](skills/codemender-remediate/SKILL.md)**: Context-aware patch synthesis (`cm fix`), enforced outer-shell build gates, atomic commits (`git add -A`), and conflict-safe `git stash` restoration.

---

## Phase 0: Stateless On-the-Fly Workspace Handshake

Always invoke `cm` statelessly with project-scoped environment variables, forwarding `GIT_CONFIG_GLOBAL` and `CLOUDSDK_CONFIG`:

```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

# 1. Verify cm binary (NEVER run install_cm.sh without explicit user permission)
if ! command -v cm >/dev/null 2>&1; then
  echo "❌ CodeMender CLI (cm) not found. Ask the user for permission before running scripts/install_cm.sh."
fi

# 2. Protect localized .codemender state from 'cm fix' internal 'git clean -fd'
# (To revert later, remove .codemender/, .cm_project, .exploit/ from $(git rev-parse --git-path info/exclude))
EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && [ -d "$(dirname "${EXCLUDE_FILE}")" ]; then
  for entry in ".codemender/" ".cm_project" ".exploit/"; do
    grep -qxF "$entry" "${EXCLUDE_FILE}" 2>/dev/null || echo "$entry" >> "${EXCLUDE_FILE}"
  done
fi

# 3. Initialize workspace if not already initialized (never pass -y to cm init)
if [ ! -f "${PROJECT_ROOT}/.codemender/config.yaml" ]; then
  HOME="${PROJECT_ROOT}" \
  GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" \
  CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" \
  GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" \
  GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" \
  cm init
fi
```

---

## Phase 1: Vulnerability Discovery & Surgical `config.yaml` Tuning

* **Full / Incremental Scan**:
  ```bash
  HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y
  ```
* **Report Ingestion (`Simple JSON` & `Basic SARIF` only)**:
  ```bash
  HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report import -f findings.sarif
  ```
* **Surgical `.codemender/config.yaml` Tuning**:
  Do NOT proactively dump all extensions into `config.yaml`. Only adjust `.codemender/config.yaml` when troubleshooting:
  - **Missed files (`0 scanned`)**: Default `scan.extensions.include` only covers `[".py", ".java", ".go", ".js", ".ts", ".c", ".cc", ".cpp", ".h", ".rb", ".php"]`. Append **only** the specific suffixes used by the target project (e.g., `".tsx", ".jsx"` for Next.js/React, `".rs"` for Rust, `".kt"` for Kotlin).
  - **Slow scans / token bloat**: Add existing build/virtualenv directories (`".venv"`, `".next"`, `"dist"`, `"vendor"`, `"target"`) to `scan.exclude_dirs`.
  - **CLI Traceability**: Keep `tools.confirm_commands: true` and `confirm_writes: true` in `config.yaml`; pass `--bypass-warning -y` on the CLI.

---

## Phase 2: Scalable 2-Tier Verification

1. **Tier 1 (Default — Fast Semantic & Taint Verification, 15–25s)**:
   ```bash
   HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm verify <finding-id> --skip-exploit-verification --no-reset --bypass-warning -y
   ```
2. **Tier 2 (Dynamic PoC Execution)**:
   * **Sandboxed CLI/Library**: `cm verify <finding-id> --no-reset --bypass-warning -y`
   * **`--unrestricted` Hazard Warning**: `--unrestricted` disables **both** the filesystem sandbox AND the command policy denylist (`full system access`) while running LLM-generated exploit scripts (Prompt Injection $\rightarrow$ RCE risk on untrusted code). **Require explicit per-invocation human confirmation** and only use in isolated VMs/containers.
3. **Triage Integrity**: Never classify failed dynamic PoCs as "False Positives"; keep as `OPEN / UNCONFIRMED` unless marked `DISMISSED` with concrete code proof.

---

## Phase 3: Atomic Remediation Loop (`git add -A`, Hard Gate & Stash Restore)

```bash
# 1. Pre-Fix Anchored Stash
if [ -n "$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/)')" ]; then
  STASH_MSG="cm-pre-fix-backup-$(date +%s)"
  echo "📌 Saving uncommitted work to git stash: ${STASH_MSG}"
  git stash push -u -m "${STASH_MSG}"
fi

# 2. Query actionable findings via python3 (captures any status other than FIXED/DISMISSED, including verified OPEN and REOPENED items)
command -v python3 >/dev/null 2>&1 || { echo "❌ Error: python3 is required to parse cm report JSON." >&2; exit 1; }
FINDINGS=$(HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm report -f json 2>/dev/null | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for item in (data if isinstance(data, list) else []):
        if item.get("status") not in ("FIXED", "DISMISSED"):
            print(item.get("finding_id", ""))
except Exception as e:
    print(f"⚠️ Warning: failed to parse cm report JSON: {e}", file=sys.stderr)
')

# 3. Iterate atomically (using while read <<< for full bash & zsh compatibility):
while IFS= read -r fid; do
  [ -z "$fid" ] && continue
  HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm fix "$fid" --bypass-warning -y

  # Enforced Outer-Shell Build Hard Gate
  if [ -z "${OUTER_BUILD_CMD:-}" ]; then
    echo "⚠️ Warning: OUTER_BUILD_CMD is unset — no outer build/syntax check ran for $fid."
  elif ! eval "${OUTER_BUILD_CMD}"; then
    echo "❌ Outer build validation failed for $fid; reverting patch..."
    git checkout HEAD -- . && git clean -fd
    continue
  fi

  # Stage ALL changes (including newly created helper files) so next cm fix's git clean -fd doesn't delete them
  if [ -n "$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/)')" ]; then
    git add -A
    git commit -m "security(cm): remediate finding $fid"
  fi

  HOME="${PROJECT_ROOT}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm find . -y
done <<< "${FINDINGS}"

# 4. MANDATORY: Conflict-safe Stash Restoration
if git stash list | grep -q "cm-pre-fix-backup"; then
  git stash pop || echo "⚠️ Merge conflict restoring stash! Your work is safely preserved in: $(git stash list | head -n 1)"
fi
```

---

## Reference Documentation
* [CLI Reference](references/cli_reference.md)
* [Configuration Schema & Surgical Tuning Playbook](references/config_schema.md)
* [Vibe Coding Pitfalls](references/vibe_coding_pitfalls.md)
* [Finding Format](skills/codemender-audit/references/finding_format.md)
