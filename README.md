# CodeMender Universal Security Plugin (`codemender-security`)

[![Plugin Standard: agent-plugins.org](https://img.shields.io/badge/Plugin_Standard-agent--plugins.org_v1.0-blue)](https://agent-plugins.org)
[![Supported Agents: Antigravity | Claude Code | Codex | Gemini CLI](https://img.shields.io/badge/Agents-Antigravity_%7C_Claude_Code_%7C_Codex_%7C_Gemini_CLI-4285F4)](https://cloud.google.com)
[![Platform: Google Cloud](https://img.shields.io/badge/Platform-Gemini_Enterprise_Agent_Platform-EA4335?logo=googlecloud)](https://cloud.google.com)
[![Engine: CodeMender CLI (cm)](https://img.shields.io/badge/Engine-CodeMender_cm_0.8.0+-34A853)](https://docs.cloud.google.com/gemini-enterprise-agent-platform/codemender)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

An enterprise autonomous AI Security Co-developer plugin for **Google Antigravity**, **Anthropic Claude Code**, **OpenAI Codex**, and **Gemini CLI**, powered natively by the **Google Cloud CodeMender (`cm`)** CLI on the Gemini Enterprise Agent Platform.

This plugin equips AI coding assistants to autonomously discover AST and taint vulnerabilities, synthesize and execute live exploit Proof-of-Concepts (PoCs) in local OS-level process sandboxes, perform Root Cause Analysis (RCA), synthesize context-aware remediation patches validated against local unit tests with automated PoC re-attacks, and generate compliance reports in SARIF and HTML formats.

---

## ⚡ Two Archetypal Developer Scenarios

This plugin is engineered around the two most critical real-world development workflows:

### 1. Scenario A: Post-Vibe-Coding Hardening Pass (全新 Vibe Coding 專案資安收斂)
* **When**: Right after building an MVP in an afternoon using AI tools (Cursor, Bolt, Lovable, Antigravity, Claude Code).
* **The Problem**: The app works, but contains typical GenAI pitfalls (hardcoded API keys, permissive `allow read, write: if true;`, open CORS, unsanitized SQL/prompt concatenation) and **lacks unit tests**.
* **User Prompt**: *"剛剛用 AI 寫完這個全端專案，幫我做一次全面的安全盤點與加固，把所有低級資安漏洞修掉，我要準備上線了。"*
* **Adaptive Defense**:
  1. Automated project scoping & initialization (`cm init -y`).
  2. Full AST and taint discovery (`cm find . -y --compact`).
  3. Grounded PoC exploit generation in sandbox (`cm verify <id>`).
  4. **Test-Adaptive Degradation**: Automatically sets `build.command` to typecheck (`npx tsc --noEmit`) or compilation (`go build`) if tests are missing, preventing `cm fix` from deadlocking and rolling back.
  5. Context-aware patch synthesis with secure defaults (`cm fix <id> -c "..."`).
  6. Stage clean code (`cm vcs stage`) and export summary.

### 2. Scenario B: Legacy Enterprise Repo Audit & Zero-Regression Fix (既有系統深度審計與零回歸修復)
* **When**: Auditing established enterprise repositories with extensive test suites, or ingesting external SAST reports.
* **The Problem**: Traditional SAST tools (Semgrep, Snyk, SonarQube) generate 80% false positives (Alert Fatigue), and engineers fear security patches might break existing business logic or wipe uncommitted changes.
* **User Prompt**: *"對我們的既有後端服務做安全審查，優先驗證哪些是真實漏洞，修復時絕不能讓現有測試壞掉。"* or *"這是資安團隊給的 `semgrep.sarif` 報告，幫我驗證哪些是假警報並把真的修掉。"*
* **Grounded Defense**:
  1. Incremental scan (`cm find . --diff-only`) or SAST ingestion (`cm report import -f semgrep.sarif`).
  2. Grounded PoC sandbox execution (`cm verify`) to eliminate 80% false positives.
  3. **Non-Destructive VCS Guardrail**: Checks `git status` and creates an automatic stash/backup before running `cm fix` or `cm vcs reset`, preventing accidental loss of uncommitted work.
  4. Domain-guided patch generation respecting existing architecture (`cm fix -c "..."`).
  5. **Double-Guarantee Closed Loop**: Automatically compiles and executes `build.command` (`npm test` / `pytest`) AND re-runs the PoC exploit (Re-Attack) to confirm the vulnerability is eliminated.
  6. **Atomic Remediation Loop**: Fixes vulnerabilities one-by-one with dedicated commits to prevent AST drift.
  7. Export standard OASIS SARIF 2.1.0 report for CI/CD and GitHub Code Scanning.

---

## 🛡️ Stateless On-the-Fly Scoping (Workspace Scoping)

In multi-project agent environments, running `cm` against global `~/.codemender/` can cause configuration collisions, prompt blocking (`Overwrite? [y/N]`), and test command conflicts.

This plugin enforces the **Stateless On-the-Fly Pattern**:

```bash
REAL_HOME="${HOME}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"

# Invoked per-command without mutating the persistent parent shell environment:
HOME="${PROJECT_ROOT}" GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" cm <command> [args...]
```

* **Outcome**: Every project maintains its own isolated `${PROJECT_ROOT}/.codemender/` state database and configuration, without mutating the developer's shell environment or losing Google Cloud ADC authentication.

---

## 📂 Repository Structure

```text
codemender-security/
├── plugin.json                     # agent-plugins.org v1.0.0 specification
├── gemini-extension.json           # Gemini CLI & Google Antigravity manifest
├── CLAUDE.md                       # Anthropic Claude Code operational guidelines
├── .claude-plugin/
│   └── plugin.json                 # Anthropic Claude Code plugin manifest
├── .codex-plugin/
│   └── plugin.json                 # OpenAI Codex plugin manifest
├── rules/
│   └── codemender-safety.md        # Cross-agent guardrails (Non-destructive VCS, Test degradation, Sandbox)
├── SKILL.md                        # Master Skill (Self-contained for Google Antigravity & Gemini CLI)
├── skills/
│   ├── codemender-audit/           # Modular Skill 1: Discovery, diff scan, SAST import, and PoC verification
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── cli_reference.md    # CLI commands, sandboxing, and session matrix
│   │       └── finding_format.md   # .exploit/ artifact breakdown (info.yaml, REPORT.md, poc.js)
│   └── codemender-remediate/       # Modular Skill 2: Context-aware fix, regression tests, Re-Attack, and VCS
│       ├── SKILL.md
│       └── references/
│           ├── config_schema.md    # .codemender/config.yaml parameters
│           └── vibe_coding_pitfalls.md # Top GenAI & Vibe Coding security vulnerability patterns
├── scripts/
│   └── install_cm.sh               # Official cross-platform installer (gcloud & curl)
└── README.md                       # Comprehensive documentation and developer guides
```

---

## 🚀 Installation

### 1. In Google Antigravity
Clone to your global skills directory:
```bash
git clone https://github.com/edwardc-gcp/codemender-security.git ~/.gemini/config/skills/codemender-security
```

### 2. In Anthropic Claude Code
```bash
claude plugin add https://github.com/edwardc-gcp/codemender-security.git
```

### 3. In OpenAI Codex
Place the repository in your configured Codex plugin path or reference it in your workspace `.codex-plugin/`.

### 4. Prerequisites
1. **Google Cloud ADC**: Authenticate with Application Default Credentials:
   ```bash
   gcloud auth application-default login
   ```
2. **CodeMender CLI (`cm`)**: Install via the bundled script:
   ```bash
   bash scripts/install_cm.sh
   ```

---

## 📄 License
Licensed under the [Apache License, Version 2.0](LICENSE).
