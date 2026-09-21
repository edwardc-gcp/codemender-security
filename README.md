# CodeMender Security Plugin (`codemender-security`)

The `codemender-security` plugin equips AI coding agents with autonomous security auditing, zero-false-positive exploit verification, and context-aware patch remediation powered by **Google Cloud CodeMender (`cm`)** on the Gemini Enterprise Agent Platform.

Built on the open [Agent Plugins specification](https://agent-plugins.org/), this plugin bundles curated Agent Skills, safety guardrails, and operational runbooks for **Google Antigravity**, **Anthropic Claude Code**, **OpenAI Codex**, and **Gemini CLI**.

---

## 🚀 Installation

### Antigravity
Install the plugin directly via the Antigravity CLI or clone into your configuration:

```bash
# Via Antigravity CLI
agy plugin install https://github.com/edwardc-gcp/codemender-security.git

# Or install manually to global plugins
git clone https://github.com/edwardc-gcp/codemender-security.git ~/.gemini/config/plugins/codemender-security
```

> [!TIP]
> You can also install via the Antigravity IDE UI under **Settings** (`Cmd+,` / `Ctrl+,`) → **Plugins** → **Install from URL**.

### Claude Code
Install with a single command via the Claude Code plugin manager:

```bash
claude plugin add https://github.com/edwardc-gcp/codemender-security.git
```

### Codex CLI
Install to your Codex environment or project:

```bash
codex plugin add https://github.com/edwardc-gcp/codemender-security.git
```

### Gemini CLI
Install as an official extension:

```bash
gemini extensions install https://github.com/edwardc-gcp/codemender-security.git
```

---

## 🔑 Prerequisites

Before using the plugin, ensure your environment meets the following requirements:

1. **Google Cloud Application Default Credentials (ADC)**:
   Authenticate your local development machine with Google Cloud:
   ```bash
   gcloud auth application-default login
   ```
   *Ensure your active Google Cloud project has access to CodeMender on Gemini Enterprise Agent Platform.*

2. **CodeMender CLI (`cm`)**:
   Install the official `cm` binary (version 0.8.0+) via the bundled script:
   ```bash
   bash scripts/install_cm.sh
   ```
   *Verify installation with `cm --version`.*

---

## 📦 What's Included

### Bundled Skills
- **[`codemender-audit`](./skills/codemender-audit)**:
  Full-codebase AST and taint scanning, differential git scanning, external SAST report ingestion (`cm report import -f semgrep.sarif`), and autonomous dynamic PoC exploit verification inside local process sandboxes (`cm verify`).
- **[`codemender-remediate`](./skills/codemender-remediate)**:
  Domain-guided patch synthesis (`cm fix`), automated regression testing, exploit re-attack validation, and an atomic multi-vulnerability remediation loop that prevents AST drift.

### Safety Rules & Guardrails
- **[`codemender-safety.md`](./rules/codemender-safety.md)**:
  Always-active safety guardrails that protect developer workspaces:
  - **Zero Data-Loss VCS Guardrail**: Automatically stashes uncommitted code before running fixes or tests.
  - **Vibe-Coding Adaptive Degradation**: Intelligently falls back from missing unit tests to syntax/type compilation checks (`tsc --noEmit`, `go build`), preventing rollback deadlocks on new AI-generated projects.
  - **Zero Data-Loss Config Initialization**: Guarantees existing `.codemender/config.yaml` files are never overwritten.
  - **Stateless Workspace Scoping**: Isolates local database and configuration per project under `${PROJECT_ROOT}/.codemender/` without mutating parent shell environments.

---

## 💡 How It Works

Once installed, simply prompt your coding agent using natural language. The agent autonomously determines the best workflow and executes it safely under CodeMender guardrails.

### Scenario 1: Post-Vibe-Coding Hardening Pass
*You just generated a new MVP or feature with AI (Cursor, Bolt, Antigravity, Claude Code) and want to secure it before deployment:*

> *"I just finished building this full-stack project with AI. Do a comprehensive security audit and hardening pass, verify real vulnerabilities in the sandbox, and remediate them before I deploy."*

1. **Discovery & Scoping**: The agent initializes `.codemender/` and scans the codebase for high-risk vulnerabilities (hardcoded credentials, open CORS, SQL injection, unsanitized inputs).
2. **Sandbox PoC Verification**: For each candidate finding, CodeMender synthesizes and executes a dynamic exploit inside an isolated sandbox to eliminate false positives.
3. **Adaptive Remediation**: The agent synthesizes context-aware patches. If unit tests don't exist yet, it automatically configures typecheck/build validation to prevent patch rollback.
4. **Closed-Loop Verification**: Re-runs the PoC exploit to prove the vulnerability is completely resolved.

### Scenario 2: SAST Triage & Zero-Regression Fixes
*You have an existing production codebase with existing test suites or an external SAST report:*

> *"Triage this `semgrep.sarif` report with CodeMender, verify which candidates are true positives, and fix them without breaking our existing test suite."*

1. **Pre-flight Safety**: The agent checks `git status` and creates an automatic stash to ensure in-progress work is never lost.
2. **SAST Ingestion & PoC Validation**: Ingests external findings and runs sandboxed exploit tests. Candidate alerts that fail to reproduce are retained for manual review rather than blindly trusted or ignored.
3. **Atomic Remediation**: Fixes confirmed vulnerabilities one by one, verifying diffs against local unit tests (`npm test` / `pytest`) and committing atomically to prevent AST drift.
4. **Compliance Report**: Exports an OASIS SARIF 2.1.0 report ready for CI/CD integration.

---

## 📄 License

Licensed under the [Apache License, Version 2.0](LICENSE).
