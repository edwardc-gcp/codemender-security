# CodeMender Configuration Schema (.codemender/config.yaml)

CodeMender relies on a workspace configuration file located at `.codemender/config.yaml` (or global `~/.config/codemender/config.yaml`).

## Complete Production Schema

```yaml
version: 1

# Enterprise telemetry and audit tracking header
team_id: "secops-team"

# Default Model: "gemini-3.7-flash" (Default, fast & accurate) or "gemini-3.1-pro-preview" (Deep reasoning)
model: "gemini-3.7-flash"

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
      - "vendor"
      - ".git"
      - "dist"
      - "build"
      - "bin"
  max_file_size_kb: 500
  incremental: true

# Verification test command (cm fix executes this to verify zero regressions)
build:
  command: "npm test"  # Alternatives: "pytest", "go test ./...", "cargo test", "make build && make test"

# Sandboxing & Tool Safety
sandbox:
  enabled: true       # Runs local tool execution inside process-level sandbox
  mounts:
    target_dir: "."   # Active workspace directory mounted inside sandbox
  network:
    profile: "permissive-closed"  # Options: "permissive-closed" (isolated) | "permissive-open" (outbound allowed)

# Security and Read-Only Host Protections
security:
  protected_files:
    - "~/.ssh/*"
    - "~/.gnupg/*"

# Additional project paths accessible to the agent during compilation/tests
project_paths: []

# Safety Confirmation Flags
tools:
  human_confirmation: true   # Set to false in headless CI/CD
  confirm_commands: false
  confirm_writes: false

vcs:
  type: "git"
```

## Key Configuration Fields

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `model` | string | `gemini-3.7-flash` | The backend reasoning model. Supported: `gemini-3.7-flash` (default), `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.1-pro-preview`. |
| `scan.incremental` | boolean | `true` | When `true`, caches scan state in `~/.codemender/state.db` to only analyze modified AST subtrees on subsequent runs. |
| `scan.extensions.include` | list | `[...]` | Whitelisted file extensions ingested during scanning. |
| `scan.extensions.exclude` | list | `[...]` | Blacklisted dependency and build directories to skip. |
| `build.command` | string | `""` | Command executed by `cm fix` to validate that synthesized patches compile and pass existing test suites. |
| `sandbox.enabled` | boolean | `true` | Runs commands inside OS-level sandbox (Linux namespaces/seccomp, macOS `sandbox-exec`, Windows `AppContainer`). |
| `sandbox.network.profile` | string | `permissive-closed` | Network isolation policy. `permissive-closed` blocks all outbound traffic; `permissive-open` allows outbound connections. |
| `security.protected_files`| list | `[]` | Host files/directories mounted read-only inside the sandbox. Supports wildcard expansion (`~`, `*`). |
| `project_paths` | list | `[]` | Additional directories granted read/write access during compilation and testing. |
| `team_id` | string | `""` | Attached to Cloud Logging / GCP telemetry headers (`X-CodeMender-Team-Id`) for compliance tracking. |

