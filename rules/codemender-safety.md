---
trigger: always_on
---

# CodeMender (`cm`) Security & Workspace Guardrails

Mandatory safety rules when orchestrating the Google Cloud CodeMender (`cm`) CLI.

## 1. Stateless On-the-Fly Workspace Scoping
Never mutate parent shell `$HOME`. Scope `.codemender/` to `${PROJECT_ROOT}`, forward `GIT_CONFIG_GLOBAL` & `CLOUDSDK_CONFIG`, and protect `.codemender/` via `.git/info/exclude` from `cm fix`'s internal `git clean -fd`:
```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && [ -d "$(dirname "${EXCLUDE_FILE}")" ]; then
  for entry in ".codemender/" ".cm_project" ".exploit/"; do
    grep -qxF "$entry" "${EXCLUDE_FILE}" 2>/dev/null || echo "$entry" >> "${EXCLUDE_FILE}"
  done
fi

HOME="${PROJECT_ROOT}" \
GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" \
CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" \
GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" \
GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" \
cm <command> [args...]
```

## 2. Non-Destructive VCS Lifecycle (Pre-Stash & Conflict-Safe Restore)
`cm fix` runs `git checkout HEAD -- . && git clean -fd` on startup. Before ANY `cm fix`, `cm verify`, or `cm vcs reset`:
1. **Anchored Pre-Fix Stash**: Check dirty files using an anchored regex so user files containing `.exploit` or `.codemender` substrings are never skipped:
   ```bash
   if [ -n "$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/)')" ]; then
     STASH_MSG="cm-pre-fix-backup-$(date +%s)"
     echo "📌 Saving uncommitted work to git stash: ${STASH_MSG}"
     git stash push -u -m "${STASH_MSG}"
   fi
   ```
2. **Non-Interactive Flags**: Pass `--bypass-warning -y` on the CLI (keep `confirm_commands: true` in `config.yaml` for audit traceability).
3. **Conflict-Safe Restoration**: After all fixes are committed, always restore the stash and notify on merge conflicts:
   ```bash
   if git stash list | grep -q "cm-pre-fix-backup"; then
     git stash pop || echo "⚠️ Merge conflict restoring stash! Your work is safely preserved in: $(git stash list | head -n 1)"
   fi
   ```

## 3. Scalable Build Validation & Hard Gate
* **Probe First**: Dynamically probe (`command -v pytest`, `command -v python3`, `command -v node`) and confirm exit code `0` before setting `build.command`.
* **Outer-Shell Hard Gate**: If no unit test exists or `exebox` blocks host toolchain paths (`~/.nvm`, `/opt/homebrew`), set `build.command: "true"` in `.codemender/config.yaml` and enforce a **mandatory outer-shell build hard gate** (`if ! eval "${OUTER_BUILD_CMD}"; then git checkout HEAD -- . && git clean -fd; continue; fi`) before committing!

## 4. Atomic Remediation Loop (`git add -A` Mandate)
Query actionable findings via `cm report -f json` (`status not in ("FIXED", "DISMISSED")` using `python3 -c`, avoiding `--status` enum mismatches and `jq` dependencies). Fix one finding at a time:
1. `cm fix "$fid" -c "<guidance>" --bypass-warning -y`
2. Run outer-shell build hard gate (`OUTER_BUILD_CMD`); revert immediately if build fails.
3. Stage ALL changes including newly created files (`git add -A && git commit -m "security(cm): fix $fid"`) so `cm fix` helper files are not wiped by the next iteration's `git clean -fd`!
4. Reconcile AST line numbers (`cm find . -y`), and run `git stash pop` after the loop ends.

## 5. Sandbox, `--unrestricted` & Installer Consent
* **No Silent Binary Install**: Never run `install_cm.sh` without explicit user permission.
* **`--unrestricted` Hazard**: `--unrestricted` disables **both** the filesystem sandbox AND the command policy denylist (`full system access`). Because `cm verify` executes LLM-generated exploit scripts, running `--unrestricted` on untrusted repos creates a Prompt Injection $\rightarrow$ RCE risk. **Require explicit per-invocation human confirmation** and only use in isolated VMs/containers.
* **Triage Integrity**: NEVER classify a failed dynamic PoC as a "False Positive". Mark as `UNCONFIRMED / OPEN`.

## 6. Zero Data-Loss `cm init`
NEVER pass `-y` to `cm init`. Always guard with `[ -f "${PROJECT_ROOT}/.codemender/config.yaml" ] || ... cm init`.
