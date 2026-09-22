---
trigger: always_on
---

# CodeMender (`cm`) Security & Workspace Guardrails

Mandatory safety rules when orchestrating the Google Cloud CodeMender (`cm`) CLI.

## 1. Stateless On-the-Fly Workspace Scoping
Never mutate parent shell `$HOME`. Always scope state to `${PROJECT_ROOT}` and protect `.codemender/` via `.git/info/exclude` from `cm fix`'s internal `git clean -fd`:
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

HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm <command> [args...]
```

## 2. Non-Destructive VCS Lifecycle (Pre-Stash & Post-Restore Mandate)
`cm fix` runs `git checkout HEAD -- . && git clean -fd` on startup. Before ANY `cm fix`, `cm verify`, or `cm vcs reset`:
1. **Pre-Fix Stash**: If `git status --porcelain | grep -vE '\.codemender|\.cm_project|\.exploit'` is non-empty, stash tracked & untracked (`-u`) files:
   `git stash push -u -m "cm-pre-fix-backup-$(date +%s)"`
2. **Non-Interactive Flags**: Always pass `--bypass-warning -y` to `cm fix` / `cm verify`, and `--no-reset` to `cm verify`.
3. **Post-Fix Restoration (Mandatory)**: After all `cm fix` patches are committed to Git, **always restore the user's stashed work**:
   `if git stash list | grep -q "cm-pre-fix-backup"; then git stash pop; fi`

## 3. Scalable Build Validation (Avoiding Rollback Deadlock)
`cm fix` runs `build.command` inside its `exebox` sandbox and rolls back patches if it exits non-zero (e.g., placeholder `npm test` exiting 1, or sandbox blocking NVM/Homebrew/pyenv paths).
* **Probe First**: Before setting `build.command` in `.codemender/config.yaml`, dynamically probe the binary in shell (`command -v pytest`, `command -v python3`, `command -v tsc`) and confirm the command exits `0`.
* **Outer-Shell Fallback**: If no unit test exists or `exebox` blocks host toolchain paths, set `build.command: "true"` in `.codemender/config.yaml` to prevent false rollbacks, and execute the real build/syntax check in the outer agent shell before `git commit`.

## 4. Atomic Remediation Loop
Never batch-fix in a blind loop (`for id in ...`). Fix one finding at a time:
1. `cm fix <id> -c "<guidance>" --bypass-warning -y`
2. Verify build/syntax in outer shell and inspect `git diff`.
3. Commit atomically: `git commit -am "security(cm): fix <cwe> in <file>"`
4. Reconcile AST line numbers: `cm find . -y`
5. After the loop completes, restore stashed user files (`git stash pop`).

## 5. Sandbox & Triage Integrity
* Keep `--sandbox=true` default unless `--unrestricted` is explicitly approved. For fast verification without `exebox` socket hangs, use `cm verify <id> --skip-exploit-verification --no-reset --bypass-warning -y`.
* **Triage Integrity**: NEVER classify a failed dynamic PoC as a "False Positive" (exploits often fail due to sandbox socket/exec policies). Mark as `UNCONFIRMED / OPEN`.

## 6. Zero Data-Loss `cm init`
NEVER pass `-y` to `cm init` (it silently wipes `.codemender/config.yaml`). Always guard:
`[ -f "${PROJECT_ROOT}/.codemender/config.yaml" ] || HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" cm init`
