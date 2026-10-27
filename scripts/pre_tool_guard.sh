#!/usr/bin/env bash
# Deterministic PreToolUse security guard for Google Cloud CodeMender (cm) CLI.
# Zero hard dependencies (pure bash + POSIX sed/grep with optional jq/python3 acceleration).
# Compatible with Antigravity/Jetski (toolCall.args.CommandLine) and with Claude Code and Codex (tool_input.command).

set -euo pipefail

RAW_INPUT="$(cat || true)"

# Detect the payload format without forking, so the fast path stays under 2ms.
# Claude Code and Codex send {"tool_name": ..., "tool_input": {...}}; Antigravity sends {"toolCall": {...}}.
# Codex adds a "turn_id" field and exports PLUGIN_ROOT to plugin hooks.
RE_TOOL_INPUT='"tool_input"[[:space:]]*:'
RE_TURN_ID='"turn_id"[[:space:]]*:'
PAYLOAD_FORMAT="antigravity"
if [[ "${RAW_INPUT}" =~ ${RE_TOOL_INPUT} ]]; then
  PAYLOAD_FORMAT="claude"
  if [[ -n "${PLUGIN_ROOT:-}" || "${RAW_INPUT}" =~ ${RE_TURN_ID} ]]; then
    PAYLOAD_FORMAT="codex"
  fi
fi

emit_allow() {
  # Antigravity expects an explicit decision; Claude Code and Codex treat empty output as "no objection".
  if [ "${PAYLOAD_FORMAT}" = "antigravity" ]; then
    printf '{"decision": "allow"}\n'
  fi
}

# Fast-path (<2ms): if stdin doesn't mention `cm` or `install_cm.sh`, allow immediately
if [[ "${RAW_INPUT}" != *"cm"* && "${RAW_INPUT}" != *"install_cm.sh"* ]]; then
  emit_allow
  exit 0
fi

# Extract CommandLine (Antigravity) or command (Claude Code / Codex) with zero-dependency fallback
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
  emit_allow
  exit 0
fi

emit_response() {
  local decision="$1"
  local reason="$2"
  if [ "${PAYLOAD_FORMAT}" = "antigravity" ]; then
    printf '{"decision": "%s", "reason": "%s"}\n' "${decision}" "${reason}"
    return 0
  fi
  local permission="deny"
  if [[ "${decision}" == "force_ask" || "${decision}" == "ask" ]]; then
    if [ "${PAYLOAD_FORMAT}" = "codex" ]; then
      # Codex does not support "ask" yet: it would mark the hook as failed and still run the command.
      reason="${reason} Codex hooks cannot prompt for approval, so the command is blocked: show it to the user and let them run it themselves if they approve."
    else
      permission="ask"
    fi
  fi
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "%s", "permissionDecisionReason": "%s"}}\n' \
    "${permission}" "${reason}"
}

# Rule 1: Hard block `cm init -y` / `cm init --yes` (Zero Data-Loss Guard)
# Matching stays within one command segment ([^;&|]*), so `cm init` and the `-y` of another chained command never combine.
if printf '%s\n' "${CMD}" | grep -qE '(^|[^a-zA-Z0-9_-])cm[[:space:]]+init([[:space:]][^;&|]*)?[[:space:]](-y|--yes)([[:space:]]|[;&|]|$)'; then
  REASON="Blocked by codemender-security guardrail: Never pass -y or --yes to 'cm init' as it overwrites custom .codemender/config.yaml. Use scripts/cm_exec.sh init instead."
  emit_response "deny" "${REASON}"
  exit 0
fi

# Rule 2a: Force interactive user confirmation when the sandbox is disabled (`--unrestricted` or `--sandbox=false`),
# whether cm is called directly or through the plugin wrappers (RCE hazard)
if printf '%s\n' "${CMD}" | grep -qE '(^|[^a-zA-Z0-9_-])(cm|cm_exec\.sh|cm_remediate_loop\.sh)([[:space:]][^;&|]*)?[[:space:]](--unrestricted|--sandbox(=|[[:space:]]+)(false|0))([[:space:]]|[;&|]|$)'; then
  REASON="CRITICAL SECURITY WARNING: '--unrestricted' / '--sandbox=false' disables the CodeMender sandbox (Prompt Injection -> RCE risk; cm fix workspace resets can also delete uncommitted work). Explicit human confirmation is required."
  emit_response "force_ask" "${REASON}"
  exit 0
fi

# Rule 2b: Force interactive user confirmation for `install_cm.sh` or `cm update` (except `--help` / `-h`)
if [[ "${CMD}" == *"install_cm.sh"* ]] || (printf '%s\n' "${CMD}" | grep -qE '(^|[^a-zA-Z0-9_/-])cm[[:space:]]+update([[:space:]]|$)' && ! printf '%s\n' "${CMD}" | grep -qE '[[:space:]](-h|--help)([[:space:]]|$)'); then
  REASON="Binary installation or update detected (install_cm.sh / cm update). Explicit user permission is required before downloading or updating the CodeMender binary."
  emit_response "force_ask" "${REASON}"
  exit 0
fi

# Rule 2c: Force interactive user confirmation before installing the opt-in git hook (it changes every future commit or push)
if printf '%s\n' "${CMD}" | grep -qE 'cm_git_hook\.sh[^[:space:];&|]*[[:space:]]+install([[:space:]]|[;&|]|$)'; then
  REASON="Installing the CodeMender git hook changes every future commit (or push) in this repository: each one with source changes runs a diff scan that takes minutes and uses tokens. Explicit user permission is required."
  emit_response "force_ask" "${REASON}"
  exit 0
fi

# Rule 3: Block unscoped stateful `cm` invocations (`find`, `verify`, `fix`, `init`, `vcs`, `build`, `report import`)
# Catches prefixes like `env cm find`, `timeout 60 cm find`, etc., while allowing `cm version`, `cm --help`, `cm <subcmd> --help`, `cm report -f json`.
if printf '%s\n' "${CMD}" | grep -qE '(^|[^a-zA-Z0-9_/-])cm[[:space:]]+(find|verify|fix|init|vcs|build|report[[:space:]]+import)([[:space:]]|$)' && ! printf '%s\n' "${CMD}" | grep -qE '[[:space:]](-h|--help)([[:space:]]|$)'; then
  if [[ "${CMD}" != *"cm_exec.sh"* && "${CMD}" != *"cm_remediate_loop.sh"* ]] && ! printf '%s\n' "${CMD}" | grep -qE '(^|[[:space:]])(HOME|CM_HOME)='; then
    SUB="$(printf '%s\n' "${CMD}" | sed -nE 's/.*(^|[^a-zA-Z0-9_/-])cm[[:space:]]+(find|verify|fix|init|vcs|build|report[[:space:]]+import).*/\2/p' | head -n 1)"
    REASON="Blocked unscoped 'cm ${SUB}' invocation (would pollute ~/.codemender or risk git clean -fd). Always invoke via scripts/cm_exec.sh ${SUB} [args...] or scripts/cm_remediate_loop.sh."
    emit_response "deny" "${REASON}"
    exit 0
  fi
fi

emit_allow
