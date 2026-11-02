#!/usr/bin/env bash
# Regression tests for cm_config_check.sh (no cm needed).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="${REPO_ROOT}/scripts/cm_config_check.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail() { echo "❌ test_config_check: $*" >&2; exit 1; }

# Runs the checker on stdin and stores its exit code in RC and its output in OUT.
check() {
  cat > "${WORK}/config.yaml"
  set +e
  OUT="$(bash "${CHECK}" "${WORK}/config.yaml" 2>&1)"
  RC=$?
  set -e
}
expect_out() { printf '%s\n' "${OUT}" | grep -qF -- "$1" || fail "$2: expected '$1' in: ${OUT}"; }

# 1. The cm 0.17.0 `cm init` template (with a root-anchored build command) has no problems.
check <<'EOF'
server: {}
# team_id: "acme-security"
scan:
  extensions:
    include: [".py", ".java", ".go", ".js", ".ts", ".tsx", ".hh", ".hxx", ".tf", ".hcl"]
    exclude: [".min.js", ".generated.go", ".pb.go"]
  # A leading "/" matches only that directory at the scan root.
  exclude_dirs: ["node_modules", "vendor", "dist", "/target", "/obj", "/build", ".gradle"]
  max_file_size_kb: 2048
  incremental: true
output:
  format: table   # "table", "json", "sarif"
  # plain: false  # Disable emojis, Unicode glyphs, and terminal colors (or set CM_PLAIN=true)
tools:
  confirm_commands: true
  confirm_writes: true
vcs:
  type: ""
  commands:
    reset: ""
    diff: ""
    status: ""
    stage: ""
build:
  command: "cd \"$(git rev-parse --show-toplevel)\" && python3 -m pytest -q"
EOF
[ "${RC}" -eq 0 ] || fail "template: expected exit 0, got ${RC}: ${OUT}"

# 2. Undocumented keys, doc names, misplaced keys, and invalid values are reported, with the key to use instead.
check <<'EOF'
model: gemini-4-argon
human_confirmation: false
team_id: "bad team!"
scan:
  exclude_dir: ["docs"]
  extensions:
    include: ["py", ".go"]
  max_file_size_kb: big
exclude_paths: [coverage]
output:
  format: html
vcs:
  type: svn
sandbox:
  network:
    profile: open
confirm_writes: false
EOF
[ "${RC}" -eq 1 ] || fail "typos: expected exit 1, got ${RC}"
expect_out "model (line 1): documented in the config docs; the plugin still passes --model" "typos"
expect_out "human_confirmation (line 2): older CodeMender docs used this name; the current docs and the cm init template use tools.confirm_commands" "typos"
expect_out "team_id (line 3)" "typos"
expect_out "scan.exclude_dir (line 5): not a documented key, and cm doesn't warn about unknown or misspelled keys; did you mean scan.exclude_dirs?" "typos"
expect_out "entries should start with a dot: py" "typos"
expect_out "scan.max_file_size_kb (line 8): expected a whole number" "typos"
expect_out "exclude_paths (line 9): not a documented key, and cm doesn't warn about unknown or misspelled keys; did you mean scan.exclude_dirs?" "typos"
expect_out "output.format (line 11)" "typos"
expect_out "vcs.type (line 13)" "typos"
expect_out "sandbox.network.profile (line 16)" "typos"
expect_out "confirm_writes (line 17): the cm init template puts confirm_writes under tools.confirm_writes" "typos"

# 3. Docs-style inline maps are understood; risky settings are warned about without failing.
check <<'EOF'
vcs: { type: "git" }
build: { command: "make build && make test" }
sandbox:
  enabled: false
  network:
    profile: "permissive-open"
tools:
  confirm_writes: false
EOF
[ "${RC}" -eq 0 ] || fail "inline: expected exit 0, got ${RC}: ${OUT}"
expect_out "sandbox.enabled: the sandbox is disabled" "inline"
expect_out "permissive-open gives sandboxed tools full outbound network access" "inline"
expect_out "build.command: cm fix runs it from the finding's directory" "inline"
expect_out "tools.confirm_writes: confirmations are off" "inline"

# 4. A custom VCS needs its commands; execution documents only interactive_mode, so other keys there are undocumented.
check <<'EOF'
execution:
  anything: true
vcs:
  type: custom
  commands:
    reset: "./reset.sh"
EOF
[ "${RC}" -eq 1 ] || fail "custom vcs: expected exit 1, got ${RC}"
expect_out "a custom VCS needs these commands: diff, status, stage" "custom vcs"
expect_out "execution.anything (line 2): not a documented key" "custom vcs"

# 5. A missing file is an error.
set +e
bash "${CHECK}" "${WORK}/missing.yaml" > /dev/null 2>&1
RC=$?
set -e
[ "${RC}" -eq 2 ] || fail "missing: expected exit 2, got ${RC}"

# 6. cm 0.17.0 keys: output.plain is documented, and turning off interactive mode gets a note.
check <<'EOF'
output:
  plain: true
execution:
  interactive_mode: false
EOF
[ "${RC}" -eq 0 ] || fail "0.17 keys: expected exit 0, got ${RC}: ${OUT}"
expect_out "execution.interactive_mode: turns off both command and file-write prompts" "0.17 keys"
! printf '%s\n' "${OUT}" | grep -q "output.plain" || fail "0.17 keys: output.plain should be accepted silently: ${OUT}"

echo "✅ cm_config_check.sh tests passed (6 scenarios: template, undocumented keys, inline maps, custom VCS, missing file, 0.17 keys)"
