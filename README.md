# CodeMender Autonomous Security Skill (`/codemender-security`)

[![Skill: Antigravity](https://img.shields.io/badge/Antigravity-Skill-4285F4?style=flat&logo=google)](https://github.com/topics/antigravity-skill)
[![CLI: CodeMender](https://img.shields.io/badge/CodeMender_CLI-cm-34A853?style=flat)](https://cloud.google.com)
[![Platform: Google Cloud](https://img.shields.io/badge/Platform-Gemini_Enterprise-EA4335?style=flat&logo=googlecloud)](https://cloud.google.com)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

An autonomous AI Security Co-developer skill for **Google Antigravity** and the **Gemini Enterprise Agent Platform**, powered by the **CodeMender CLI (`cm`)**.

This skill equips Antigravity agents to autonomously discover AST and taint security vulnerabilities, synthesize and execute live exploit Proof-of-Concepts (PoCs), perform Root Cause Analysis (RCA), synthesize context-aware remediation patches validated against local test suites, and generate enterprise compliance reports in SARIF and HTML formats.

---

> [!NOTE]
> **Access Allowlist & Availability**: CodeMender is currently available to a limited set of customers in **Public Preview** (Pre-GA) and requires Google Cloud project allowlisting. Contact your Google Cloud sales or account team to request access to the CodeMender CLI artifact repository and backend APIs.

> [!WARNING]
> **Pre-GA & Public Preview Notice**: Pre-GA products are in various stages of internal testing and review. As such, customers should closely supervise the use of CodeMender, and not use CodeMender in situations where serious errors cannot be corrected. This product is made available solely for limited testing and evaluation, and may not be used for commercial or production purposes.

> [!CAUTION]
> **Safety Filters & Human Confirmation Notice**: When disabling human confirmation of write and tool execution actions (as configured in `~/.codemender/config.yaml` or non-interactive CLI flags like `-y` and `--bypass-warning`), Customer is responsible for such modification under Section 20(j) (*"Modifying, Disregarding, or Disabling Safety Filters"*) of the Google Cloud Service Specific Terms. Customers agree not to automatically bypass or circumvent other responses requiring human confirmation.

---

## ⚡ Key Capabilities & Workflow

CodeMender operates through an autonomous four-phase closed-loop workflow:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        CodeMender Workflow Loop                        │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│ 1. DISCOVER     │ 2. VERIFY (PoC) │ 3. REMEDIATE     │ 4. REPORT       │
│ cm find .       │ cm verify <id>  │ cm fix <id>      │ cm report       │
│ (AST & Taint)   │ (Live Exploit)  │ (Patch & Test)   │ (SARIF / HTML)  │
└─────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

1. **AST & Taint Discovery (`cm find`)**: Headless full-codebase AST and data-flow taint analysis with automated severity prioritization (Critical and High first).
2. **Autonomous Exploit Verification (`cm verify`)**: Synthesizes and executes dynamic PoC exploit payloads under `.exploit/` (e.g., `poc.js`, `exploit.py`, `REPORT.md`) to eliminate false positives.
3. **Patch Synthesis & Regression Testing (`cm fix`)**: Synthesizes language-aware patches and automatically executes configured test suites (`npm test`, `pytest`, `cargo test`) to ensure zero behavioral regression.
4. **Enterprise SARIF & HTML Reporting (`cm report`)**: Exports standard OASIS SARIF v2.1.0 reports for GitHub Advanced Security / CI/CD pipelines, or interactive standalone HTML audit dashboards.

---

## 📂 Repository Structure

```
.
├── SKILL.md                          # Primary agent skill definition and rules of engagement
├── README.md                         # Repository documentation, disclaimers, and setup guide
├── LICENSE                           # Apache 2.0 open-source license
├── .gitignore                        # Ignore rules for OS, cache, and temporary exploit files
├── references/                       # Deep reference documentation
│   ├── cli_reference.md              # Advanced command catalog, session lifecycle, and error matrix
│   ├── config_schema.md              # Complete schema reference for .codemender/config.yaml
│   └── vibe_coding_pitfalls.md       # Top GenAI & Vibe Coding security vulnerability patterns
└── scripts/
    └── install_cm.sh                 # Cross-platform automated installer for the cm CLI binary
```

---

## 🚀 Installation & Setup

### Option 1: Install via Antigravity Prompt (Recommended)

You can ask Antigravity directly inside your IDE or `agy` CLI session:

> *"Install the CodeMender security skill from `https://github.com/edwardc-gcp/codemender-security`"*

Antigravity will automatically clone the repository into your global skills directory (`~/.gemini/config/skills/codemender-security`) and index the skill immediately.

---

### Option 2: Install via Command Line

#### Global Installation (Available across all workspaces)
```bash
git clone https://github.com/edwardc-gcp/codemender-security.git ~/.gemini/config/skills/codemender-security
```

#### Workspace / Project-Specific Installation
```bash
# Clone directly into project customization directory
git clone https://github.com/edwardc-gcp/codemender-security.git .agents/skills/codemender-security

# Or add as a Git Submodule for team collaboration
git submodule add https://github.com/edwardc-gcp/codemender-security.git .agents/skills/codemender-security
```

---

### 2. Prerequisites & CLI Installation

1. **Google Cloud Authentication**: Ensure your environment has Application Default Credentials (ADC) configured and the Vertex AI API enabled:
   ```bash
   gcloud auth application-default login
   gcloud services enable aiplatform.googleapis.com
   ```

2. **Install the CodeMender CLI (`cm`)**:
   > [!IMPORTANT]
   > Downloading the binary requires project allowlisting on the Google Cloud Artifact Registry repository.

   ```bash
   bash scripts/install_cm.sh
   export PATH="$HOME/bin:$PATH"
   ```

3. **Verify Environment Setup**:
   ```bash
   cm --version
   gcloud auth application-default print-access-token >/dev/null && echo "GCP ADC: OK"
   ```

---

## 🛠️ Usage Cheat Sheet

| Operation | Command | Description |
| :--- | :--- | :--- |
| **Full Codebase Scan** | `cm find . -y --unrestricted --model gemini-3.5-flash` | Scans entire repository for AST/taint vulnerabilities. |
| **Scan PR / Diff Only** | `cm find . -y --diff-only --unrestricted` | Analyzes only modified files or uncommitted Git diffs. |
| **Severity Filter** | `cm find . -y --severity CRITICAL,HIGH --unrestricted` | Filters discovery to high-impact findings only. |
| **Verify Finding (PoC)** | `cm verify <finding-id> --unrestricted --bypass-warning -y` | Generates and executes live exploit PoC under `.exploit/`. |
| **Guided Remediation** | `cm fix <finding-id> -c "<guidance>" --unrestricted -y` | Generates patch guided by context (e.g., `-c "Use Secret Manager"`). |
| **Inspect Patch Diff** | `cm vcs diff` | Displays unified diff synthesized by the remediation agent. |
| **Rollback Patch** | `cm vcs revert` | Reverts patch changes if test validation fails. |
| **Export SARIF for CI/CD** | `cm report -f sarif > results.sarif` | Outputs OASIS SARIF v2.1.0 for GitHub Code Scanning / CI. |
| **Interactive HTML Report**| `cm report -f html > report.html` | Generates self-contained HTML vulnerability dashboard. |

---

## ⚙️ Workspace Configuration (`.codemender/config.yaml`)

CodeMender can be customized on a per-project basis via `.codemender/config.yaml`:

```yaml
version: 1
team_id: "secops-team"
model: gemini-3.5-flash

scan:
  extensions:
    include: [".py", ".java", ".go", ".js", ".ts", ".c", ".cc", ".cpp", ".rs"]
    exclude: ["node_modules", ".git", "dist", "build", "*.min.js"]
  max_file_size_kb: 500
  incremental: true

build:
  # Executed automatically by `cm fix` to verify zero regressions before applying patches
  command: "npm test" # Alternatives: "pytest", "go test ./...", "cargo test"

tools:
  confirm_commands: false
  confirm_writes: false

vcs:
  type: "git"
```

For full details on configuration options, see the [Configuration Schema Reference](references/config_schema.md).

---

## 📚 Deep Dive References

- [CLI Advanced Reference & Troubleshooting](references/cli_reference.md): Detailed parameter specifications, session resume lifecycle, and error matrix.
- [Configuration Schema](references/config_schema.md): Complete specification for `.codemender/config.yaml`.
- [GenAI & Vibe Coding Pitfalls](references/vibe_coding_pitfalls.md): Top 5 vulnerability patterns in LLM-generated code and remediation strategies.

---

## 🛡️ License

Distributed under the Apache 2.0 License. See [LICENSE](LICENSE) for details.
