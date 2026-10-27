#!/usr/bin/env bash
# Copies the canonical helpers in scripts/ into each skill's own scripts/ directory, so every
# skill is self-contained (Agent Skills spec: reference bundled files relative to the skill root).
#
# Usage:
#   bash scripts/sync_skill_scripts.sh          # refresh the skill-bundled copies after editing scripts/
#   bash scripts/sync_skill_scripts.sh --check  # verify the copies are identical and executable (CI)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Single source of truth: <skill>:<space-separated scripts bundled with that skill>
SKILL_SCRIPTS=(
  "codemender-audit:cm_exec.sh cm_diff_scan.sh cm_git_hook.sh check_env.sh install_cm.sh"
  "codemender-remediate:cm_exec.sh cm_diff_scan.sh cm_remediate_loop.sh"
)

MODE="${1:-sync}"
status=0
for entry in "${SKILL_SCRIPTS[@]}"; do
  skill="${entry%%:*}"
  for script in ${entry#*:}; do
    src="scripts/${script}"
    dst="skills/${skill}/scripts/${script}"
    if [ "${MODE}" = "--check" ]; then
      if ! cmp -s "${src}" "${dst}"; then
        echo "❌ Drift: ${dst} differs from ${src} (run: bash scripts/sync_skill_scripts.sh)"
        status=1
      elif [ ! -x "${dst}" ]; then
        echo "❌ Not executable: ${dst}"
        status=1
      fi
    else
      mkdir -p "skills/${skill}/scripts"
      cp "${src}" "${dst}"
      chmod +x "${dst}"
    fi
  done
done

if [ "${MODE}" = "--check" ]; then
  if [ "${status}" -eq 0 ]; then
    echo "✅ Skill-bundled scripts are identical to scripts/ (zero drift)."
  fi
  exit "${status}"
fi
echo "✅ Synced bundled scripts into skills/*/scripts/."
