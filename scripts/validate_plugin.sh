#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running codemender-security Plugin Validation Suite..."

# 1. Validate shell scripts
bash -n scripts/install_cm.sh
echo "✅ Shell syntax valid: scripts/install_cm.sh"

# 2. Validate JSON manifests & version/disclaimer parity
python3 - << 'EOF'
import json

manifests = [
    "plugin.json",
    "gemini-extension.json",
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
]
versions = set()
for path in manifests:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    versions.add(data.get("version"))
    assert "This is not an official Google product." in data.get("description", ""), f"Missing disclaimer in {path}"
    print(f"✅ Manifest OK: {path} (v{data.get('version')})")

assert len(versions) == 1, f"Version mismatch across manifests: {versions}"
EOF

# 3. Check reference file parity (zero drift)
diff -u references/cli_reference.md skills/codemender-audit/references/cli_reference.md
diff -u references/config_schema.md skills/codemender-remediate/references/config_schema.md
echo "✅ Reference files are 100% synchronized (zero drift)."
