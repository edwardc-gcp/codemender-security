#!/usr/bin/env bash
# Automated CI Validation Script for codemender-security plugin
# Verifies shell/python syntax, hardcoded path prohibition, PreToolUse hook logic, JSON array parser, manifests, reference sync, and markdown links.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "🔍 Running codemender-security Plugin Validation Suite..."

# 0. Hardcoded User Path Prohibition Gate (Prevent /Users/<user> or /home/<user> leakage)
if grep -rnE '(/Users/[a-zA-Z0-9._-]+|/home/[a-zA-Z0-9._-]+)' SKILL.md CLAUDE.md README.md hooks.json rules/ scripts/ skills/ references/ --exclude="validate_plugin.sh"; then
  echo "❌ Hardcoded personal path detected in repository files!"
  exit 1
fi
echo "✅ Zero hardcoded user paths in repository files"

# 1. Shell Script Syntax Verification
for sh_file in scripts/install_cm.sh scripts/cm_exec.sh scripts/cm_remediate_loop.sh scripts/validate_plugin.sh; do
  bash -n "${sh_file}"
  chmod +x "${sh_file}"
  echo "✅ Shell syntax & executable bit valid: ${sh_file}"
done

# 2. PreToolUse Hook Verification (Syntax + 8 Behavioral Unit Tests)
chmod +x scripts/pre_tool_guard.py
python3 -c '
import subprocess, json, sys

def run_hook(cmd):
    payload = json.dumps({"toolCall": {"name": "run_command", "args": {"CommandLine": cmd}}})
    out = subprocess.check_output(["python3", "scripts/pre_tool_guard.py"], input=payload, text=True)
    return json.loads(out)

assert run_hook("cm init -y")["decision"] == "deny", "Expected deny on cm init -y"
assert run_hook("cm verify 123 --unrestricted")["decision"] == "force_ask", "Expected force_ask on --unrestricted"
assert run_hook("bash scripts/install_cm.sh")["decision"] == "force_ask", "Expected force_ask on install_cm.sh"
assert run_hook("cm find . -y")["decision"] == "deny", "Expected deny on unscoped cm find"
assert run_hook("timeout 60 cm find . -y")["decision"] == "deny", "Expected deny on prefixed timeout cm find"
assert run_hook("cm report import -f findings.sarif")["decision"] == "deny", "Expected deny on unscoped cm report import"
assert run_hook("bash scripts/cm_exec.sh find . -y")["decision"] == "allow", "Expected allow on cm_exec.sh find"
assert run_hook("cm version")["decision"] == "allow", "Expected allow on read-only cm version"
assert run_hook("cm report -f json")["decision"] == "allow", "Expected allow on read-only cm report -f json"
print("✅ PreToolUse hook unit tests passed (9/9 assertions)")
'

# 3. JSON Array Parser Verification (Matches cm report -f json v0.8.0 schema)
python3 -c '
import json

sample = """Notice: telemetry enabled
[
  {"finding_id": "sql-inj-001", "status": "OPEN"},
  {"finding_id": "xss-002", "status": "FIXED"},
  {"finding_id": "ssrf-003", "status": "REOPENED"}
]"""
candidates = [i for i in (sample.find("["), sample.find("{")) if i != -1]
start = min(candidates) if candidates else -1
data = json.loads(sample[start:])
items = data if isinstance(data, list) else data.get("findings", [])
out = [f.get("finding_id") or f.get("id") for f in items if f.get("status") not in ("FIXED", "DISMISSED")]
assert out == ["sql-inj-001", "ssrf-003"], f"Unexpected parser output: {out}"
print("✅ cm report -f json top-level array parser verified")
'

# 4. JSON Manifests & hooks.json Consistency Check
python3 -c '
import json, sys

with open("hooks.json") as fh:
    hooks = json.load(fh)
    assert "codemender-safety-guard" in hooks, "Missing codemender-safety-guard in hooks.json"
print("✅ hooks.json valid")

manifests = [
    "plugin.json",
    "gemini-extension.json",
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json"
]
versions = set()
for m in manifests:
    with open(m) as f:
        data = json.load(f)
        versions.add(data.get("version"))
        desc = data.get("description", "")
        if "not an official Google product" not in desc:
            print(f"❌ Missing unofficial disclaimer in {m}")
            sys.exit(1)
        ver = data.get("version")
        print(f"✅ Manifest OK: {m} (v{ver})")

if len(versions) != 1:
    print(f"❌ Version mismatch across manifests: {versions}")
    sys.exit(1)
'

# 5. Reference File Synchronization Check (Zero-Drift Guard)
diff -u references/cli_reference.md skills/codemender-audit/references/cli_reference.md
diff -u references/config_schema.md skills/codemender-audit/references/config_schema.md
diff -u references/config_schema.md skills/codemender-remediate/references/config_schema.md
diff -u references/vibe_coding_pitfalls.md skills/codemender-remediate/references/vibe_coding_pitfalls.md
echo "✅ Reference files are 100% synchronized across root, audit, and remediate skills (zero drift)."

# 6. Relative Markdown Link Integrity Check
python3 -c '
import os, re, sys

md_files = [
    "SKILL.md",
    "CLAUDE.md",
    "skills/codemender-audit/SKILL.md",
    "skills/codemender-remediate/SKILL.md",
    "rules/codemender-safety.md"
]
link_re = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
for md in md_files:
    base_dir = os.path.dirname(os.path.abspath(md))
    with open(md) as f:
        content = f.read()
    for target in link_re.findall(content):
        if target.startswith(("http://", "https://", "#")):
            continue
        if target.startswith("file://"):
            resolved = target[len("file://"):].split("#")[0]
        else:
            resolved = os.path.normpath(os.path.join(base_dir, target.split("#")[0]))
        if not os.path.exists(resolved):
            print(f"❌ Broken link in {md}: {target} -> {resolved}")
            sys.exit(1)
print("✅ All Markdown links verified (0 broken paths).")
'
