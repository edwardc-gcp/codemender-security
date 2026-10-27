---
trigger: always_on
description: Mandatory execution wrapper and safety guardrails for Google Cloud CodeMender (cm) CLI.
---

# CodeMender (`cm`) Execution Guardrails

1. **Mandatory Wrapper**: NEVER invoke stateful `cm` subcommands (`find`, `verify`, `fix`, `init`, `report import`, `vcs`, `build`) directly. Always execute via [cm_exec.sh](../scripts/cm_exec.sh), [cm_diff_scan.sh](../scripts/cm_diff_scan.sh) for local change scans, or [cm_remediate_loop.sh](../scripts/cm_remediate_loop.sh) for atomic patching, and read `codemender-audit` or `codemender-remediate` first.
2. **Hard Prohibitions**: NEVER pass `-y` to `cm init`. NEVER run `install_cm.sh`, `cm update`, `cm_git_hook.sh install`, or any `cm` command with the sandbox disabled (`--unrestricted`, `--sandbox=false`) without explicit per-invocation user confirmation.
