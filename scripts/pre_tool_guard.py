#!/usr/bin/env python3
"""Deterministic PreToolUse security guard for Google Cloud CodeMender (cm) CLI.
Compatible with both Antigravity/Jetski (toolCall.args.CommandLine) and Claude Code (tool_input.command).
"""
import json
import re
import sys


def extract_command(payload: dict) -> str:
    # 1. Antigravity / Jetski schema
    tool_call = payload.get("toolCall") or {}
    args = tool_call.get("args") or {}
    if isinstance(args.get("CommandLine"), str):
        return args["CommandLine"]
    # 2. Claude Code schema
    tool_input = payload.get("tool_input") or {}
    if isinstance(tool_input.get("command"), str):
        return tool_input["command"]
    return ""


def evaluate_command(cmd: str) -> dict:
    if not cmd or ("cm" not in cmd and "install_cm.sh" not in cmd):
        return {"decision": "allow"}

    # Rule 1: Hard block `cm init -y` / `cm init --yes` (Zero Data-Loss Guard)
    if re.search(r"\bcm\s+init\b.*(\s-y\b|\s--yes\b)", cmd):
        return {
            "decision": "deny",
            "reason": (
                "Blocked by codemender-security guardrail: Never pass -y or --yes to 'cm init' "
                "as it overwrites custom .codemender/config.yaml. Use scripts/cm_exec.sh init instead."
            ),
        }

    # Rule 2: Force interactive user confirmation for `--unrestricted` (RCE hazard) or `install_cm.sh`
    if re.search(r"\bcm\b.*--unrestricted\b", cmd):
        return {
            "decision": "force_ask",
            "reason": (
                "CRITICAL SECURITY WARNING: 'cm --unrestricted' disables both the filesystem sandbox "
                "and command denylist (Prompt Injection -> RCE risk). Explicit human confirmation is required."
            ),
        }

    if "install_cm.sh" in cmd:
        return {
            "decision": "force_ask",
            "reason": (
                "Binary installation detected (install_cm.sh). Explicit user permission is required "
                "before downloading or installing the CodeMender binary."
            ),
        }

    # Rule 3: Block unscoped stateful `cm` invocations (`find`, `verify`, `fix`, `init`, `vcs`, `report import`)
    # Catches prefixes like `env cm find`, `timeout 60 cm find`, etc.
    # Allows read-only diagnostic invocations (`cm version`, `cm --help`, `cm help`, `cm report -f json`, `cm update`).
    stateful_match = re.search(
        r"\bcm\s+(find|verify|fix|init|vcs|report\s+import)\b", cmd
    )
    if stateful_match:
        has_wrapper = "cm_exec.sh" in cmd or "cm_remediate_loop.sh" in cmd
        has_home_scope = bool(re.search(r"\bHOME=", cmd))
        if not (has_wrapper or has_home_scope):
            sub = stateful_match.group(1)
            return {
                "decision": "deny",
                "reason": (
                    f"Blocked unscoped 'cm {sub}' invocation (would pollute ~/.codemender or risk git clean -fd). "
                    f"Always invoke via scripts/cm_exec.sh {sub} [args...] or scripts/cm_remediate_loop.sh."
                ),
            }

    return {"decision": "allow"}


def main() -> None:
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        print(json.dumps({"decision": "allow"}))
        return

    cmd = extract_command(payload)
    result = evaluate_command(cmd)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
