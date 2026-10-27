#!/usr/bin/env bash
# Checks .codemender/config.yaml against the documented keys, and for invalid or risky values.
#
# cm 0.16.0 doesn't warn about unknown or misspelled keys (`cm init --verify` still reports "Config loaded successfully"),
# and the web docs use a few names that differ from the `cm init` template. Run this script after editing the config,
# together with `cm_exec.sh init --verify` (which catches YAML syntax errors and an invalid team_id). The schema comes
# only from the `cm init` 0.16.0 template, the public CodeMender docs, and the release notes.
#
# Usage: cm_config_check.sh [CONFIG_PATH]   (default: <repository root>/.codemender/config.yaml)
# Exit codes: 0 = no problems (warnings and notes may be printed), 1 = problems found, 2 = file missing or unreadable.

set -uo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,10p' "$0" | sed -E 's/^# ?//'
  exit 0
fi

CONFIG="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.codemender/config.yaml}"
if [ ! -r "${CONFIG}" ]; then
  echo "❌ Config not found: ${CONFIG} (create it with: cm_exec.sh init)" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ cm_config_check.sh needs python3." >&2
  exit 2
fi

python3 - "${CONFIG}" <<'PY'
import difflib, re, sys

path = sys.argv[1]

# Documented keys: the `cm init` 0.16.0 template, the public config docs, and the release notes (scan.include_hidden).
KNOWN = {
    "server": "any",  # template: `server: {}`; its comment says the built-in endpoint can be overridden here
    "team_id": "str",
    "scan": "map", "scan.extensions": "map", "scan.extensions.include": "list", "scan.extensions.exclude": "list",
    "scan.exclude_dirs": "list", "scan.include_hidden": "bool", "scan.max_file_size_kb": "int", "scan.incremental": "bool",
    "project_paths": "list",
    "output": "map", "output.format": "str",
    "tools": "map", "tools.confirm_commands": "bool", "tools.confirm_writes": "bool",
    "tools.cleanup_candidate_branches": "bool",
    "vcs": "map", "vcs.type": "str", "vcs.commands": "map", "vcs.commands.reset": "str", "vcs.commands.diff": "str",
    "vcs.commands.status": "str", "vcs.commands.stage": "str",
    "build": "map", "build.command": "str",
    "sandbox": "map", "sandbox.enabled": "bool", "sandbox.mounts": "map", "sandbox.mounts.target_dir": "str",
    "sandbox.network": "map", "sandbox.network.profile": "str",
    "security": "map", "security.protected_files": "list",
    "model": "str",  # listed in the public config docs
    "execution": "any",  # named in the public sandbox docs, without documented keys
}
# Names the web docs use instead of the `cm init` template's keys.
DOC_NAMES = {
    "human_confirmation": "tools.confirm_commands and tools.confirm_writes",
    "require_confirmation": "tools.confirm_commands and tools.confirm_writes",
}
# Common slips that difflib alone wouldn't catch.
SUGGEST = {"exclude_paths": "scan.exclude_dirs", "project_path": "project_paths", "build_command": "build.command"}
LEAVES = {}
for known_key in KNOWN:
    LEAVES.setdefault(known_key.split(".")[-1], []).append(known_key)

problems, warnings, notes = [], [], []

def strip_comment(line):
    out, quote = [], None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out).rstrip()

def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v

def split_top(s):
    parts, depth, cur, quote = [], 0, [], None
    for ch in s:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
        elif ch == "," and depth == 0:
            parts.append("".join(cur)); cur = []
            continue
        cur.append(ch)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return parts

values = {}   # key path -> scalar string, list of strings, or "{map}"
lines_of = {} # key path -> line number

def record(key, value, lineno):
    values[key] = value
    lines_of[key] = lineno

def parse_inline_map(prefix, text, lineno):
    for part in split_top(text.strip()[1:-1]):
        if ":" not in part:
            continue
        k, v = part.split(":", 1)
        k = unquote(k)
        full = f"{prefix}.{k}" if prefix else k
        v = v.strip()
        if v.startswith("{") and v.endswith("}"):
            record(full, "{map}", lineno)
            parse_inline_map(full, v, lineno)
        elif v.startswith("[") and v.endswith("]"):
            record(full, [unquote(x) for x in split_top(v[1:-1])], lineno)
        else:
            record(full, unquote(v), lineno)

try:
    raw_lines = open(path, encoding="utf-8").read().splitlines()
except OSError as exc:
    print(f"❌ Cannot read {path}: {exc}")
    sys.exit(2)

stack = []  # (indent, key)
list_owner = None
for lineno, raw in enumerate(raw_lines, 1):
    if "\t" in raw[: len(raw) - len(raw.lstrip())]:
        problems.append((f"line {lineno}", "tab indentation; YAML needs spaces"))
    line = strip_comment(raw)
    if not line.strip():
        continue
    indent = len(line) - len(line.lstrip(" "))
    text = line.strip()
    if text.startswith("- "):
        if list_owner and isinstance(values.get(list_owner), list):
            values[list_owner].append(unquote(text[2:]))
        continue
    m = re.match(r'^("[^"]+"|\'[^\']+\'|[^:\s][^:]*?)\s*:(?:\s+(.*))?$', text)
    if not m:
        continue
    key, value = unquote(m.group(1)), (m.group(2) or "").strip()
    while stack and stack[-1][0] >= indent:
        stack.pop()
    full = ".".join([k for _, k in stack] + [key])
    stack.append((indent, key))
    list_owner = None
    if value == "":
        record(full, [], lineno)
        list_owner = full
    elif value.startswith("{") and value.endswith("}"):
        record(full, "{map}", lineno)
        parse_inline_map(full, value, lineno)
    elif value.startswith("[") and value.endswith("]"):
        record(full, [unquote(x) for x in split_top(value[1:-1])], lineno)
    else:
        record(full, unquote(value), lineno)

def covered_by_any(key):
    parts = key.split(".")
    return any(KNOWN.get(".".join(parts[:i])) == "any" for i in range(1, len(parts)))

for key in sorted(values, key=lambda k: lines_of[k]):
    where = f"{key} (line {lines_of[key]})"
    if key in KNOWN or covered_by_any(key):
        continue
    leaf = key.split(".")[-1]
    if key in DOC_NAMES:
        warnings.append((where, f"the web docs mention this name, but the cm init template uses {DOC_NAMES[key]}; prefer those"))
        continue
    homes = [k for k in LEAVES.get(leaf, []) if k != key]
    if len(homes) == 1 and "." in homes[0]:
        warnings.append((where, f"the cm init template puts {leaf} under {homes[0]}; move it there"))
        continue
    suggestion = SUGGEST.get(leaf) or next(iter(difflib.get_close_matches(key, list(KNOWN), n=1, cutoff=0.75)), None)
    hint = f"; did you mean {suggestion}?" if suggestion else ""
    problems.append((where, f"not a documented key, and cm doesn't warn about unknown or misspelled keys{hint}"))

if "model" in values:
    notes.append((f"model (line {lines_of['model']})", "documented in the config docs; the plugin still passes --model on the "
                  "command line, which cm find, cm verify, and cm fix document"))
if "execution" in values:
    notes.append((f"execution (line {lines_of['execution']})", "the docs name this block but don't document its keys"))

BOOL = {"true", "false", "yes", "no", "on", "off"}

def val(key):
    v = values.get(key)
    return v if isinstance(v, str) else None

for key, kind in KNOWN.items():
    v = values.get(key)
    if v is None or v == "{map}":
        continue
    where = f"{key} (line {lines_of[key]})"
    if kind == "bool" and isinstance(v, str) and v.lower() not in BOOL:
        problems.append((where, f"expected true or false, got {v!r}"))
    if kind == "int" and isinstance(v, str) and not re.fullmatch(r"\d+", v):
        problems.append((where, f"expected a whole number, got {v!r}"))

team = val("team_id")
if team is not None and team != "" and not re.fullmatch(r"[A-Za-z0-9._-]{1,63}", team):
    problems.append((f"team_id (line {lines_of['team_id']})", "must be at most 63 characters from [A-Za-z0-9._-]"))

for key in ("scan.extensions.include", "scan.extensions.exclude"):
    v = values.get(key)
    if isinstance(v, list):
        bad = [e for e in v if e and not e.startswith(".")]
        if bad:
            problems.append((f"{key} (line {lines_of[key]})", f"entries should start with a dot: {', '.join(bad)}"))

fmt = val("output.format")
if fmt is not None and fmt not in ("table", "json", "sarif"):
    problems.append((f"output.format (line {lines_of['output.format']})", "expected table, json, or sarif"))

vcs_type = val("vcs.type")
if vcs_type is not None and vcs_type not in ("", "git", "mercurial", "custom", "none"):
    problems.append((f"vcs.type (line {lines_of['vcs.type']})", "expected git, mercurial, custom, none, or \"\" (auto-detect)"))
if vcs_type == "custom":
    missing = [c for c in ("reset", "diff", "status", "stage") if not val("vcs.commands." + c)]
    if missing:
        problems.append(("vcs.commands", "a custom VCS needs these commands: " + ", ".join(missing)))
if vcs_type == "none":
    warnings.append(("vcs.type", "none: cm runs without VCS support, so it can't track or reset its changes"))

profile = val("sandbox.network.profile")
if profile is not None and profile not in ("permissive-closed", "permissive-open"):
    problems.append((f"sandbox.network.profile (line {lines_of['sandbox.network.profile']})",
                     "documented profiles are permissive-closed (default) and permissive-open"))
elif profile == "permissive-open":
    notes.append(("sandbox.network.profile", "permissive-open gives sandboxed tools full outbound network access"))

if (val("sandbox.enabled") or "").lower() in ("false", "no", "off"):
    warnings.append(("sandbox.enabled", "the sandbox is disabled, so agent tools run unisolated on the host; this needs explicit user consent"))
for key in ("tools.confirm_commands", "tools.confirm_writes"):
    if (val(key) or "").lower() in ("false", "no", "off"):
        notes.append((key, "confirmations are off for every run; the plugin prefers keeping them on and passing -y per command"))

build = val("build.command")
if build is not None:
    if build == "":
        notes.append(("build.command", "empty: cm fix can't build-check its patches (cm_remediate_loop.sh still runs OUTER_BUILD_CMD)"))
    elif build not in ("true", ":") and "rev-parse --show-toplevel" not in build:
        notes.append(("build.command", "cm fix runs it from the finding's directory; anchor it to the root: "
                      "cd \"$(git rev-parse --show-toplevel)\" && ..."))

for title, items, icon in (("Problems", problems, "❌"), ("Warnings", warnings, "⚠️ "), ("Notes", notes, "ℹ️ ")):
    for where, msg in items:
        print(f"{icon} {where}: {msg}")
if not problems:
    print(f"✅ {path}: no problems found ({len(warnings)} warning(s), {len(notes)} note(s)).")
    sys.exit(0)
print(f"❌ {path}: {len(problems)} problem(s). cm ignores unknown keys silently, so fix them before relying on the config.")
sys.exit(1)
PY
