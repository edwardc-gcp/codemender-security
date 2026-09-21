# CodeMender Security Guardrails & Workspace Safety Rules

This rule defines safety-critical guardrails for AI Coding Agents (Antigravity, Claude Code, OpenAI Codex, Gemini CLI) when orchestrating the Google Cloud CodeMender (`cm`) CLI.

---

## 1. Stateless On-the-Fly Workspace Scoping (Mandatory)

To prevent cross-project state collisions and eliminate interactive prompt blocking (`Overwrite? [y/N]`), always invoke `cm` on-the-fly with project-scoped environment variables.

### The Stateless On-the-Fly Pattern
```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"

# Stateless on-the-fly execution (never mutate the agent's long-lived parent shell)
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm <command> [args...]
```

**Key Benefits:**
1. Completely stateless: leaves the parent shell's `$HOME` untouched.
2. Localizes `.codemender/config.yaml`, `.codemender/state.db`, and patch artifacts in `${PROJECT_ROOT}/.codemender/`.
3. Seamlessly shares user-authenticated Google Cloud Application Default Credentials (ADC).

---

## 2. Non-Destructive VCS Guardrail (Zero Data Loss Mandate)

**CRITICAL**: Developers frequently run security audits on repositories containing uncommitted, in-progress code.
A blind `cm vcs reset` (which runs `git checkout HEAD -- . && git clean -fd`) or unhandled exploit reset could destroy hours of manual developer work.

### Mandatory Pre-Fix Safety Check:
Before executing ANY `cm fix`, `cm verify`, or `cm vcs reset`:
1. Check working tree cleanliness:
   ```bash
   DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
   ```
2. If `DIRTY > 0`:
   - **Automatically stash changes**:
     ```bash
     git stash push -m "cm-pre-fix-backup-$(date +%s)"
     ```
   - **Or create an isolated fix branch**:
     ```bash
     git checkout -b "cm-fix-$(date +%s)"
     ```
3. **Double Guardrail**: When running `cm verify`, pass `--no-reset` to suppress internal CLI resets while keeping `git stash` as the primary defense.
4. **NEVER** run `cm vcs reset` when unstashed manual changes exist!

---

## 3. Vibe-Coding Test Adaptive Degradation (Avoiding Rollback Deadlock)

In newly generated or vibe-coded projects, `package.json` often contains a placeholder test command: `echo "Error: no test specified" && exit 1`.
If `build.command` executes and returns exit code 1, `cm fix` will assume the patch broke the project and **automatically roll back the patch**, deadlocking the remediation.

### Adaptive Fallback Strategy:
Before running `cm fix`, verify that `build.command` is functional:
* **Node.js / TypeScript**: If `npm test` fails with no test, set `build.command: "npx tsc --noEmit"` or `"npm run build"`.
* **Python**: If no pytest exists, set `build.command: "python -m compileall -q ."`
* **Go**: Set `build.command: "go build ./..."`
* **Rust**: Set `build.command: "cargo check"`
* This guarantees syntax and type regression protection without crashing on missing unit tests.

---

## 4. Atomic Remediation Loop (Preventing AST Drift)

When multiple vulnerabilities are identified across a codebase:
* **DO NOT** execute a naive shell loop (`for fid in ...; do cm fix; done`). Multiple fixes to the same file will cause AST node and line number drift, resulting in patch collision or corrupt code.
* **Enforce the Atomic Loop**:
  1. Pick the highest priority verified finding.
  2. Run `HOME="${PROJECT_ROOT}" cm fix <id> -c "<guidance>" -y`.
  3. Validate `build.command` and verify diff on disk (`git diff`).
  4. Create an atomic Git commit: `git commit -am "security(cm): fix <cwe> in <file>"`.
  5. Run an incremental reconciliation scan (`HOME="${PROJECT_ROOT}" cm find . -y`) to update `.codemender/state.db` before fixing the next finding.

---

## 5. Process-Level Sandboxing & Triage Integrity

1. Always keep `--sandbox=true` enabled (the default).
2. Do **NOT** pass `--unrestricted` or `--sandbox=false` unless explicitly approved by the human operator.
3. For Web service vulnerabilities, ensure the local service is running or mock endpoints are responsive before executing `cm verify`.
4. **Triage Integrity**: Never classify a failed PoC execution as a "False Positive". Dynamic exploits frequently fail due to offline servers or environment mismatch. Mark as `UNCONFIRMED / OPEN` for manual inspection.

---

## 6. Zero Data-Loss Config Initialization Rule (Never Pass `-y` to `cm init`)

Passing `-y` to `cm init` unconditionally answers "Yes" to `Overwrite? [y/N]` when an existing `.codemender/config.yaml` is present, silently wiping customized settings (e.g., custom `build.command`, `team_id`, or `scan.exclude_dirs`) without backup.
* **Rule**: NEVER pass `-y` to `cm init`.
* **Guard Pattern**: Always check file existence before initializing:
  ```bash
  if [ ! -f "${PROJECT_ROOT}/.codemender/config.yaml" ]; then
    HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm init
  fi
  ```
* When `.codemender/config.yaml` does not exist, `cm init` runs without interactive prompts, making `-y` completely redundant while eliminating a dangerous copy-paste hazard.
