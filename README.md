# CodeMender Security Plugin (`codemender-security`)

> [!IMPORTANT]
> **CodeMender Public Preview Access**: Access to the Google Cloud CodeMender (`cm`) API and artifacts is currently in **Public Preview** (contact your Google Cloud representative for project allowlisting). Ensure your Google Cloud account is authenticated and associated with an authorized project where the Vertex AI API is enabled before running scans.

The `codemender-security` plugin equips AI coding agents with autonomous security auditing, zero-false-positive exploit verification, and context-aware patch remediation powered by **Google Cloud CodeMender (`cm`)** on the Gemini Enterprise Agent Platform.

Built on the open [Agent Plugins specification](https://agent-plugins.org/), this plugin bundles curated Agent Skills, safety guardrails, and operational runbooks for **Google Antigravity**, **Anthropic Claude Code**, and **OpenAI Codex**.

---

## 🚀 Installation

| Agent | Skills | Safety hook (`pre_tool_guard.sh`) | Always-on rule |
| :--- | :--- | :--- | :--- |
| Google Antigravity | ✅ | ✅ via [`hooks.json`](./hooks.json) | ✅ via [`rules/`](./rules/codemender-safety.md) |
| Anthropic Claude Code | ✅ | ✅ via [`hooks/hooks.json`](./hooks/hooks.json) | — |
| OpenAI Codex | ✅ | ✅ via [`hooks/hooks.json`](./hooks/hooks.json), after you trust it in `/hooks` | — |

### Google Antigravity (`agy`)
Install directly via the Antigravity CLI:

```bash
agy plugin install https://github.com/edwardc-gcp/codemender-security.git
```

> [!TIP]
> You can also install via the Antigravity IDE UI under **Settings** (`Cmd+,` / `Ctrl+,`) → **Plugins** → **Install from URL**, or clone the repository into your Antigravity plugins directory (for example `~/.gemini/config/plugins/codemender-security`) and restart.

### Anthropic Claude Code (`claude`)
This repository is also a Claude Code plugin marketplace ([`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json)). Add it, then install the plugin:

```bash
claude plugin marketplace add edwardc-gcp/codemender-security
claude plugin install codemender-security@codemender-security
```

### OpenAI Codex (`codex`)
This repository is also a Codex repo marketplace ([`.agents/plugins/marketplace.json`](./.agents/plugins/marketplace.json)). Add it from the CLI:

```bash
codex plugin marketplace add edwardc-gcp/codemender-security
```

Then open `/plugins`, install **CodeMender Security**, and start a new session. Codex skips plugin hooks until you review and trust them, so open `/hooks` and trust the bundled safety hook.

> [!NOTE]
> Codex hooks cannot prompt for approval yet. Commands that need explicit consent (`install_cm.sh`, `cm update`, `--unrestricted`) are therefore blocked in Codex with an explanation; run them yourself after reviewing them.

---

## 🔑 Prerequisites

Before using the plugin, ensure your environment meets the following requirements:

1. **Google Cloud Project, APIs & IAM Role**:
   Enable the required Google Cloud APIs and ensure your account has the **Vertex AI User** (`roles/aiplatform.user`) IAM role on an allowlisted Public Preview project:
   ```bash
   gcloud services enable aiplatform.googleapis.com cloudresourcemanager.googleapis.com
   ```
   *(Note: On your very first run in a newly provisioned project, the backend may return `Resource setup has just started. Please try again shortly.` Wait 1–2 minutes and retry.)*

2. **Google Cloud Application Default Credentials (ADC)**:
   Authenticate your local development machine with Google Cloud:
   ```bash
   gcloud auth application-default login
   ```
   *Ensure your active Google Cloud project has access to CodeMender on Gemini Enterprise Agent Platform.*

3. **CodeMender CLI (`cm`) Installation & Updates**:
   Ask your agent to *"check my CodeMender environment"*: the `codemender-audit` skill runs `check_env.sh` and asks for your consent before running the bundled cross-platform installer. To run the installer yourself (requires `curl` and `unzip`; it checks the latest official release manifest, downloads the binary, and verifies its uncompressed SHA-256 checksum):
   ```bash
   git clone https://github.com/edwardc-gcp/codemender-security.git
   bash codemender-security/scripts/install_cm.sh
   ```
   *Re-running `install_cm.sh` automatically checks for newer remote releases and upgrades `cm` when available (or run `cm update` manually).*

4. **Privacy & Telemetry Opt-Out (Optional)**:
   CodeMender follows a local-first architecture (only targeted code snippets are transmitted via the Interactions API). CLI telemetry (which excludes source code, findings, and identity) is enabled by default; to disable it, export:
   ```bash
   export CM_TELEMETRY_OPT_OUT=1
   ```

---

## 📦 What's Included

### Bundled Skills
- **[`codemender-audit`](./skills/codemender-audit)**:
  Full-codebase AST and taint scanning, differential git scanning, external SAST report ingestion (`cm report import -f findings.sarif`), and 2-Tier verification (`cm verify --skip-exploit-verification` for fast semantic verification or sandboxed dynamic PoC execution).
- **[`codemender-remediate`](./skills/codemender-remediate)**:
  Domain-guided patch synthesis (`cm fix`), automated regression testing, exploit re-attack validation, and an atomic multi-vulnerability remediation loop with enforced outer-shell build gates and checkpoint-protected uncommitted work.

### Safety Rules, Hooks & Execution Wrappers
- **[`codemender-safety.md`](./rules/codemender-safety.md)** *(Always-On Routing Stub)*:
  Lightweight (~75-token) always-on rule that enforces wrapper execution and requires explicit operator confirmation before running `install_cm.sh` or `cm verify --unrestricted`.
- **[`hooks.json`](./hooks.json), [`hooks/hooks.json`](./hooks/hooks.json) & [`pre_tool_guard.sh`](./scripts/pre_tool_guard.sh)** *(Deterministic `PreToolUse` Interceptor)*:
  Pure-Bash runtime hook (`<2ms` fast-path) that intercepts shell commands before execution—blocking unwrapped stateful `cm` subcommands and `cm init -y` while enforcing interactive confirmation (`force_ask`) for `install_cm.sh` and `--unrestricted` verification. Antigravity loads `hooks.json`; Claude Code and Codex load `hooks/hooks.json`.
- **[`cm_exec.sh`](./scripts/cm_exec.sh)** *(Stateless Workspace Wrapper)*:
  Isolates `.codemender/` and `HOME="${PROJECT_ROOT}/.cache"` per repository, forwards `GIT_CONFIG_GLOBAL` and `CLOUDSDK_CONFIG` (ADC), prevents `.codemender/config.yaml` overwrites, and registers `.codemender/` and `.cache/` in `.git/info/exclude`.
- **[`cm_remediate_loop.sh`](./scripts/cm_remediate_loop.sh)** *(Atomic Multi-Vulnerability Remediation Loop)*:
  Protects uncommitted work with a checkpoint commit (restored as uncommitted changes afterwards), runs declarative Strategy Pipeline polyglot build gates (`OUTER_BUILD_CMD`), per-finding `cm fix` synthesis, and post-commit AST line reconciliation.
- **[`check_env.sh`](./scripts/check_env.sh)** *(Diagnostic Environment Health Checker)*:
  Instantly verifies CLI version, Google Cloud ADC authentication status, active project, and workspace data protection in a structured ASCII summary.

---

## 💡 How It Works

Once installed, simply prompt your coding agent using natural language. The agent autonomously determines the best workflow and executes it safely under CodeMender guardrails.

### Scenario 1: Post-Vibe-Coding Hardening Pass
*You just generated a new MVP or feature with AI and want to secure it before deployment:*

> *"I just finished building this full-stack project with AI. Do a comprehensive security audit and hardening pass, verify real vulnerabilities, and remediate them before I deploy."*

1. **Discovery & Scoping**: The agent initializes `.codemender/` and scans the codebase for high-risk vulnerabilities (hardcoded credentials, open CORS, SQL injection, unsanitized inputs).
2. **2-Tier Verification**: Uses `cm verify --skip-exploit-verification` for fast 15–25s semantic taint verification (or isolated sandbox PoC execution) to eliminate false positives.
3. **Adaptive Remediation & Hard Gate**: Synthesizes context-aware patches (`cm fix`), validates the build/syntax in the outer shell, and reverts any patch that breaks compilation.
4. **Checkpoint Protection**: Commits uncommitted work as a checkpoint before `cm fix` (whose workspace reset would otherwise delete it), commits each validated fix, then restores everything as uncommitted changes with the fixes applied (or keeps the commits with `--keep-commits`).

---

## 📄 License & Disclaimer

Licensed under the [Apache License, Version 2.0](LICENSE).
**Disclaimer**: This is not an official Google product.
