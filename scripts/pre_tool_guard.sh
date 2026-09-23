#!/usr/bin/env bash
# Deterministic PreToolUse security guard for Google Cloud CodeMender (cm) CLI.
# Zero hard dependencies (pure bash + POSIX sed/grep with optional jq/python3 acceleration).
# Compatible with both Antigravity/Jetski (toolCall.args.CommandLine) and Claude Code (tool_input.command).

set -euo pipefail

RAW_INPUT="$(cat || true)"

# Fast-path (<2ms): if stdin doesn't mention `cm` or `install_cm.sh`, allow immediately
if [[ "${RAW_INPUT}" != *"cm"* && "${RAW_INPUT}" != *"install_cm.sh"* ]]; then
  printf '{"decision": "allow"}\n'
  exit 0
fi

# Extract CommandLine (Antigravity) or command (Claude Code) with zero-dependency fallback
extract_cmd() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "${RAW_INPUT}" | jq -r '.toolCall.args.CommandLine // .tool_input.command // empty' 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "${RAW_INPUT}" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    c = (d.get("toolCall") or {}).get("args", {}).get("CommandLine") or (d.get("tool_input") or {}).get("command") or ""
    print(c, end="")
except Exception:
    pass
' 2>/dev/null && return 0
  fi
  # Pure POSIX sed fallback if neither jq nor python3 is installed
  printf '%s' "${RAW_INPUT}" | sed -nE 's/.*"CommandLine"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p; s/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1 | sed 's/\\"/"/g; s/\\\\/\\/g'
}

CMD="$(extract_cmd || true)"

if [ -z "${CMD}" ]; then
  printf '{"decision": "allow"}\n'
  exit 0
fi

# Rule 1: Hard block `cm init -y` / `cm init --yes` (Zero Data-Loss Guard)
if printf '%s\n' "${CMD}" | grep -qE '(^|[^a-zA-Z0-9_-])cm[[:space:]]+init([[:space:]].*)?[[:space:]](-y|--yes)([[:space:]]|$)'; then
  printf '{"decision": "deny", "reason": "Blocked by codemender-security guardrail: Never pass -y or --yes to '\''cm init'\'' as it overwrites custom .codemender/config.yaml. Use scripts/cm_exec.sh init instead."}\n'
  exit 0
fi

# Rule 2a: Force interactive user confirmation for `--unrestricted` (RCE hazard)
if printf '%s\n' "${CMD}" | grep -qE '(^|[^a-zA-Z0-9_-])cm([[:space:]].*)?[[:space:]]--unrestricted([[:space:]]|$)'; then
  printf '{"decision": "force_ask", "reason": "CRITICAL SECURITY WARNING: '\''cm --unrestricted'\'' disables both the filesystem sandbox and command denylist (Prompt Injection -> RCE risk). Explicit human confirmation is required."}\n'
  exit 0
fi

# Rule 2b: Force interactive user confirmation for `install_cm.sh`
if [[ "${CMD}" == *"install_cm.sh"* ]]; then
  printf '{"decision": "force_ask", "reason": "Binary installation detected (install_cm.sh). Explicit user permission is required before downloading or installing the CodeMender binary."}\n'
  exit 0
fi

# Rule 3: Block unscoped stateful `cm` invocations (`find`, `verify`, `fix`, `init`, `vcs`, `report import`)
# Catches prefixes like `env cm find`, `timeout 60 cm find`, etc., while allowing `cm version`, `cm --help`, `cm report -f json`.
if printf '%s\n' "${CMD}" | grep -qE '(^|[^a-zA-Z0-9_/-])cm[[:space:]]+(find|verify|fix|init|vcs|report[[:space:]]+import)([[:space:]]|$)'; then
  if [[ "${CMD}" != *"cm_exec.sh"* && "${CMD}" != *"cm_remediate_loop.sh"* ]] && ! printf '%s\n' "${CMD}" | grep -qE '(^|[[:space:]])HOME='; then
    SUB="$(printf '%s\n' "${CMD}" | sed -nE 's/.*(^|[^a-zA-Z0-9_/-])cm[[:space:]]+(find|verify|fix|init|vcs|report[[:space:]]+import).*/\2/p' | head -n 1)"
    printf '{"decision": "deny", "reason": "Blocked unscoped '\''cm %s'\'' invocation (would pollute ~/.codemender or risk git clean -fd). Always invoke via scripts/cm_exec.sh %s [args...] or scripts/cm_remediate_loop.sh."}\n' "${SUB}" "${SUB}"
    exit 0
  fi
fi

printf '{"decision": "allow"}\n'
