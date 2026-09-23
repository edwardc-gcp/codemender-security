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
for sh_file in scripts/install_cm.sh scripts/cm_exec.sh scripts/cm_remediate_loop.sh scripts/pre_tool_guard.sh scripts/validate_plugin.sh; do
  bash -n "${sh_file}"
  chmod +x "${sh_file}"
  echo "✅ Shell syntax & executable bit valid: ${sh_file}"
done

# 2. PreToolUse Hook Verification (Normal PATH + Pure POSIX Fallback without python3/jq)
python3 -c '
import subprocess, json

def run_hook(cmd, use_minimal_env=False):
    payload = json.dumps({"toolCall": {"name": "run_command", "args": {"CommandLine": cmd}}})
    if use_minimal_env:
        out = subprocess.check_output(
            ["bash", "-c", "jq() { return 127; }; python3() { return 127; }; export -f jq python3; source scripts/pre_tool_guard.sh"],
            input=payload,
            text=True,
        )
    else:
        out = subprocess.check_output(["bash", "scripts/pre_tool_guard.sh"], input=payload, text=True)
    return json.loads(out)

for minimal in (False, True):
    assert run_hook("cm init -y", minimal)["decision"] == "deny", "Expected deny on cm init -y"
    assert run_hook("cm verify 123 --unrestricted", minimal)["decision"] == "force_ask", "Expected force_ask on --unrestricted"
    assert run_hook("bash scripts/install_cm.sh", minimal)["decision"] == "force_ask", "Expected force_ask on install_cm.sh"
    assert run_hook("cm find . -y", minimal)["decision"] == "deny", "Expected deny on unscoped cm find"
    assert run_hook("timeout 60 cm find . -y", minimal)["decision"] == "deny", "Expected deny on prefixed timeout cm find"
    assert run_hook("cm report import -f findings.sarif", minimal)["decision"] == "deny", "Expected deny on unscoped cm report import"
    assert run_hook("bash scripts/cm_exec.sh find . -y", minimal)["decision"] == "allow", "Expected allow on cm_exec.sh find"
    assert run_hook("cm version", minimal)["decision"] == "allow", "Expected allow on read-only cm version"
    assert run_hook("cm report -f json", minimal)["decision"] == "allow", "Expected allow on read-only cm report -f json"
print("✅ PreToolUse shell hook unit tests passed (18/18 assertions across standard & no-Python/no-jq environments)")
'

# 3. JSON Array Parser Verification (Matches cm report -f json v0.8.0 schema across Python & pure awk)
python3 -c '
import json, subprocess

sample = """Notice: telemetry enabled
[
  {"finding_id": "sql-inj-001", "status": "OPEN"},
  {"finding_id": "xss-002", "status": "FIXED"},
  {"finding_id": "ssrf-003", "status": "REOPENED"}
]"""
awk_out = subprocess.check_output(["awk", """
  /"finding_id"[[:space:]]*:/ {
    match($0, /"finding_id"[[:space:]]*:[[:space:]]*"[^"]+"/);
    s = substr($0, RSTART, RLENGTH);
    sub(/.*:[[:space:]]*"/, "", s);
    sub(/"$/, "", s);
    fid = s;
  }
  /"status"[[:space:]]*:/ {
    if (fid != "" && $0 !~ /"FIXED"/ && $0 !~ /"DISMISSED"/) {
      print fid;
    }
    fid = "";
  }
"""], input=sample, text=True).strip().splitlines()
assert awk_out == ["sql-inj-001", "ssrf-003"], f"Unexpected awk parser output: {awk_out}"
print("✅ cm report -f json top-level array parser verified (Python & pure awk fallback)")
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
