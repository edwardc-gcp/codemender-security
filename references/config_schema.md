# CodeMender Configuration Schema (.codemender/config.yaml)

CodeMender relies on a workspace configuration file located at `.codemender/config.yaml` (or `~/.codemender/config.yaml`).

## Complete Production Schema

```yaml
version: 1

# Enterprise telemetry and audit tracking header
team_id: "secops-team"

# Default Model: "gemini-3.5-flash" (fast scanning) or "gemini-3.1-pro-preview" (deep reasoning)
model: gemini-3.5-flash

# Target scanning scope and file filters
scan:
  extensions:
    include:
      - ".py"
      - ".java"
      - ".go"
      - ".js"
      - ".ts"
      - ".c"
      - ".cc"
      - ".cpp"
      - ".h"
      - ".rb"
      - ".php"
      - ".rs"
    exclude:
      - ".min.js"
      - ".generated.go"
      - ".pb.go"
      - "node_modules"
      - ".git"
      - "dist"
      - "build"
  max_file_size_kb: 500
  incremental: true

# Verification test command (Crucial: cm fix executes this to verify zero regressions)
build:
  command: "npm test"  # Alternatives: "pytest", "go test ./...", "cargo test"

# Sandboxing & Tool Safety
tools:
  confirm_commands: false
  confirm_writes: false

vcs:
  type: "git"
```

## Key Configuration Fields

| Field | Type | Description |
| :--- | :--- | :--- |
| `build.command` | string | Command executed by `cm fix` to validate that synthesized patches compile and pass existing test suites. |
| `scan.incremental` | boolean | When `true`, caches scan state to only analyze modified AST subtrees on subsequent runs. |
| `scan.extensions` | object | Whitelist (`include`) and blacklist (`exclude`) glob extensions for SAST parsing. |
| `team_id` | string | Attached to Cloud Logging / GCP telemetry headers (`X-CodeMender-Team-Id`) for compliance tracking. |
